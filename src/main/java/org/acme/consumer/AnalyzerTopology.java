package org.acme.consumer;

import com.fasterxml.jackson.core.type.TypeReference;
import com.github.packageurl.MalformedPackageURLException;
import com.github.packageurl.PackageURL;
import io.quarkus.kafka.client.serialization.ObjectMapperDeserializer;
import io.quarkus.kafka.client.serialization.ObjectMapperSerde;
import io.quarkus.kafka.client.serialization.ObjectMapperSerializer;
import org.acme.analyzer.OssIndexAnalyzer;
import org.acme.analyzer.SnykAnalyzer;
import org.acme.model.Component;
import org.acme.model.VulnerabilityResult;
import org.acme.notification.NotificationRouter;
import org.acme.processor.BatchProcessor;
import org.acme.processor.PartitionIdReKeyProcessor;
import org.apache.commons.lang3.StringUtils;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Branched;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KStream;
import org.apache.kafka.streams.kstream.Named;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.processor.WallclockTimestampExtractor;
import org.apache.kafka.streams.state.Stores;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.enterprise.context.ApplicationScoped;
import javax.enterprise.inject.Produces;
import javax.inject.Inject;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@ApplicationScoped
public class AnalyzerTopology {

    private static final Logger LOGGER = LoggerFactory.getLogger(AnalyzerTopology.class);

    private final OssIndexAnalyzer ossIndexAnalyzer;
    private final SnykAnalyzer snykAnalyzer;
    private final NotificationRouter notificationRouter;

    @Inject
    public AnalyzerTopology(final OssIndexAnalyzer ossIndexAnalyzer,
                            final SnykAnalyzer snykAnalyzer,
                            final NotificationRouter notificationRouter) {
        this.ossIndexAnalyzer = ossIndexAnalyzer;
        this.snykAnalyzer = snykAnalyzer;
        this.notificationRouter = notificationRouter;
    }

    @Produces
    public Topology topology() {
        final var streamsBuilder = new StreamsBuilder();

        final var componentSerde = new ObjectMapperSerde<>(Component.class);
        final var componentsSerde = Serdes.serdeFrom(new ObjectMapperSerializer<>(),
                new ObjectMapperDeserializer<List<Component>>(new TypeReference<>() {
                }));
        final var vulnResultSerde = new ObjectMapperSerde<>(VulnerabilityResult.class);

        // Flat-Map incoming components from the API server, and re-key the stream from UUIDs to CPEs, PURLs, and SWID Tag IDs.
        // Every component from component-analysis can thus produce up to three new events.
        final KStream<String, Component> componentStream = streamsBuilder
                .stream("component-analysis", Consumed
                        .with(Serdes.UUID(), componentSerde)
                        .withName("consume_component-analysis_topic"))
                .peek((uuid, component) -> LOGGER.info("Received component: {}", component),
                        Named.as("log_components"))
                .flatMap((uuid, component) -> {
                    final var components = new ArrayList<KeyValue<String, Component>>();
                    if (component.getCpe() != null) {
                        // TODO: Canonicalize the CPE used as key, so that CPEs describing the same component end up in the same partition.
                        components.add(KeyValue.pair(component.getCpe(), component));
                    }
                    if (component.getPurl() != null) {
                        components.add(KeyValue.pair(component.getPurl().getCoordinates(), component));
                    }
                    if (component.getSwidTagId() != null) {
                        // NOTE: Barely any components have a SWID Tag ID yet, and no scanner supports it
                        components.add(KeyValue.pair(component.getSwidTagId(), component));
                    }
                    if (component.getCpe() == null && component.getPurl() == null && component.getSwidTagId() == null) {
                        components.add(KeyValue.pair("no-identifier", component));
                    }
                    return components;
                }, Named.as("re-key_components_from_uuid_to_identifiers"))
                .peek((identifier, component) -> LOGGER.info("Re-keyed component: {} -> {}", component.getUuid(), identifier),
                        Named.as("log_re-keyed_components"));

        final Map<String, KStream<String, Component>> branches = componentStream
                .split(Named.as("component-with-identifier-type"))
                .branch((identifier, component) -> isCpe(identifier), Branched.as("-cpe"))
                .branch((identifier, component) -> isPurl(identifier), Branched.as("-purl"))
                .branch((identifier, component) -> isSwidTagId(identifier), Branched.as("-swid"))
                .defaultBranch(Branched.as("-unknown"));
        branches.get("component-with-identifier-type-cpe").to("component-analysis-cpe", Produced
                .with(Serdes.String(), componentSerde)
                .withName("produce_to_component-analysis-cpe_topic"));
        branches.get("component-with-identifier-type-purl").to("component-analysis-purl", Produced
                .with(Serdes.String(), componentSerde)
                .withName("produce_to_component-analysis-purl_topic"));
        branches.get("component-with-identifier-type-swid").to("component-analysis-swid", Produced
                .with(Serdes.String(), componentSerde)
                .withName("produce_to_component-analysis-swid_topic"));
        branches.get("component-with-identifier-type-unknown")
                // The component does not have an identifier that we can work with,
                // but we still want to produce a result.
                // TODO: Instead of reporting "no vulnerability", report "not applicable" or so
                .map((identifier, component) -> {
                    final var result = new VulnerabilityResult();
                    result.setComponent(component);
                    result.setIdentity(null);
                    result.setVulnerability(null);
                    return KeyValue.pair(component.getUuid(), result);
                }, Named.as("map_to_empty_vuln_result"))
                .to("component-vuln-analysis-result", Produced
                        .with(Serdes.UUID(), vulnResultSerde)
                        .withName("produce_empty_result_to_component-vuln-analysis-result_topic"));

        final KStream<String, Component> purlComponentStream = streamsBuilder
                .stream("component-analysis-purl", Consumed
                        .with(Serdes.String(), componentSerde)
                        .withName("consume_from_component-analysis-purl_topic")
                        // For the windowed aggregation of PURLs we need the event timestamp to
                        // not be "stream time", otherwise we'll drop event when one stream task
                        // is consuming from multiple partitions.
                        .withTimestampExtractor(new WallclockTimestampExtractor()));

        streamsBuilder.addStateStore(Stores.keyValueStoreBuilder(
                Stores.persistentKeyValueStore("purl_component_batches"), Serdes.Integer(), componentsSerde));

        // Aggregate components with PURLs in batches of up to 128.
        // TODO: Repeat this for CPE and SWID Tag ID
        final KStream<Integer, List<Component>> purlAggregateStream = purlComponentStream
                // Batching requires records to have the same key.
                // Because most records will have different identifiers as key, we re-key
                // the stream to the partition ID the records are in.
                // This allows us to aggregate all records within the partition(s) we're consuming from.
                .process(PartitionIdReKeyProcessor::new, Named.as("re-key_components_from_purl_to_partition_id"))
                .process(() -> new BatchProcessor<>("purl_component_batches", Duration.ofSeconds(3), 128),
                        Named.as("batch_components"), "purl_component_batches");

        if (ossIndexAnalyzer.isEnabled()) {
            purlAggregateStream
                    .flatMap((window, components) -> analyzeOssIndex(components),
                            Named.as("analyze_with_ossindex"))
                    .to("component-analysis-vuln", Produced
                            .with(Serdes.String(), vulnResultSerde)
                            .withName("produce_ossindex_results_to_component-analysis-vuln_topic"));
        }
        if (snykAnalyzer.isEnabled()) {
            purlAggregateStream
                    .flatMap((window, components) -> analyzeSnyk(components),
                            Named.as("analyze_with_snyk"))
                    .to("component-analysis-vuln", Produced
                            .with(Serdes.String(), vulnResultSerde)
                            .withName("produce_snyk_results_to_component-analysis-vuln_topic"));
        }

        // Consume from the topic where analyzers write their results to,
        // and re-key them from CPE/PURL/SWID back to component UUIDs.
        streamsBuilder
                .stream("component-analysis-vuln", Consumed
                        .with(Serdes.String(), vulnResultSerde)
                        .withName("consume_component-analysis-vuln_topic"))
                .peek((identifier, vulnResult) -> LOGGER.info("Re-keying result: {} -> {}", identifier, vulnResult.getComponent().getUuid()),
                        Named.as("log_vuln_results_re-keying"))
                .map((identifier, vulnResult) -> KeyValue.pair(vulnResult.getComponent().getUuid(), vulnResult),
                        Named.as("re-key_vuln_results_from_identifier_to_component_uuid"))
                .to("component-vuln-analysis-result", Produced
                        .with(Serdes.UUID(), vulnResultSerde)
                        .withName("produce_to_component-vuln-analysis-result_topic"));

        // FIXME: Modularize the application, move the notification topology to it's own Quarkus app
        NotificationTopologyBuilder.buildTopology(streamsBuilder, notificationRouter);

        return streamsBuilder.build();
    }

    private boolean isPurl(final String purl) {
        try {
            new PackageURL(purl);
            return true;
        } catch (MalformedPackageURLException e) {
            return false;
        }
    }

    private boolean isCpe(final String cpe) {
        return StringUtils.startsWith(cpe, "cpe:");
    }

    private boolean isSwidTagId(final String swidTagId) {
        return false;
    }

    private List<KeyValue<String, VulnerabilityResult>> analyzeOssIndex(final List<Component> components) {
        LOGGER.info("Performing OSS Index analysis for {} components: {}", components.size(), components);
        return ossIndexAnalyzer.analyze(components).stream() // TODO: Handle exceptions
                .map(vulnResult -> KeyValue.pair(vulnResult.getComponent().getPurl().getCoordinates(), vulnResult))
                .toList();
    }

    private List<KeyValue<String, VulnerabilityResult>> analyzeSnyk(final List<Component> component) {
        LOGGER.info("Performing Snyk analysis for component: {}", component);
        return snykAnalyzer.analyze(component).stream() // TODO: Handle exceptions
                .map(vulnResult -> KeyValue.pair(vulnResult.getComponent().getPurl().getCoordinates(), vulnResult))
                .toList();
    }

}
