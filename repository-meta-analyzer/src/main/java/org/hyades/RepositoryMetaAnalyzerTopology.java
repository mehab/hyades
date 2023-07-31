package org.hyades;

import com.github.packageurl.MalformedPackageURLException;
import com.github.packageurl.PackageURL;
import jakarta.enterprise.inject.Produces;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Branched;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KStream;
import org.apache.kafka.streams.kstream.Named;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.kstream.Repartitioned;
import org.hyades.common.KafkaTopic;
import org.hyades.processor.IntegrityAnalyzerProcessorSupplier;
import org.hyades.processor.MetaAnalyzerProcessorSupplier;
import org.hyades.proto.KafkaProtobufSerde;
import org.hyades.proto.repometaanalysis.v1.AnalysisCommand;
import org.hyades.proto.repometaanalysis.v1.AnalysisResult;
import org.hyades.proto.repometaanalysis.v1.Component;
import org.hyades.proto.repometaanalysis.v1.IntegrityResult;
import org.hyades.repositories.IntegrityAnalyzerFactory;
import org.hyades.repositories.RepositoryAnalyzerFactory;
import org.hyades.serde.KafkaPurlSerde;

import java.util.TreeMap;

import static org.hyades.commonutil.KafkaStreamsUtil.processorNameConsume;
import static org.hyades.commonutil.KafkaStreamsUtil.processorNameProduce;

public class RepositoryMetaAnalyzerTopology {

    @Produces
    @SuppressWarnings({"resource", "java:S2095"}) // Ignore linter warnings about Serdes having to be closed
    public Topology topology(final RepositoryAnalyzerFactory analyzerFactory,
                             final MetaAnalyzerProcessorSupplier analyzerProcessorSupplier,
                             final IntegrityAnalyzerFactory integrityAnalyzerFactory,
                             final IntegrityAnalyzerProcessorSupplier integrityAnalyzerProcessorSupplier) {
        final var streamsBuilder = new StreamsBuilder();

        final var purlSerde = new KafkaPurlSerde();
        final var analysisCommandSerde = new KafkaProtobufSerde<>(AnalysisCommand.parser());
        final var scanResultSerde = new KafkaProtobufSerde<>(AnalysisResult.parser());

        //repo meta analysis command stream start
        final KStream<PackageURL, AnalysisCommand> commandStream = streamsBuilder
                .stream(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), Consumed
                        .with(Serdes.String(), analysisCommandSerde) // Key can be in arbitrary format
                        .withName(processorNameConsume(KafkaTopic.REPO_META_ANALYSIS_COMMAND)))
                .filter((key, scanCommand) -> scanCommand.hasComponent() && isValidPurl(scanCommand.getComponent().getPurl()),
                        Named.as("filter_components_with_valid_purl"))
                // Re-key to PURL coordinates WITHOUT VERSION. As we are fetching data for packages,
                // but not specific package versions, including the version here would make our caching
                // largely ineffective. We want events for the same package to be sent to the same partition.
                //
                // Because we can't enforce this format on the keys of the input topic without causing
                // serialization exceptions, we're left with this mandatory key change.
                .selectKey((key, command) -> mustParsePurlCoordinatesWithoutVersion(command.getComponent().getPurl()),
                        Named.as("re-key_to_purl_coordinates"))
                // Force a repartition to ensure that the ordering guarantees we want, based on the
                // previous re-keying operation, are effective.
                .repartition(Repartitioned
                        .with(purlSerde, analysisCommandSerde)
                        .withName("command-by-purl-coordinates"));

        commandStream
                .mapValues((purl, command) -> command.getComponent(),
                        Named.as("map_to_component"))
                .split(Named.as("applicable_analyzer"))
                .branch((purl, component) -> analyzerFactory.hasApplicableAnalyzer(purl), Branched
                        .<PackageURL, Component>withConsumer(stream -> stream
                                .processValues(analyzerProcessorSupplier, Named.as("analyze_component"))
                                .to(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), Produced
                                        .with(purlSerde, scanResultSerde)
                                        .withName(processorNameProduce(KafkaTopic.REPO_META_ANALYSIS_RESULT, "analysis_result"))))
                        .withName("-found"))
                .defaultBranch(Branched
                        .<PackageURL, Component>withConsumer(stream -> stream
                                .mapValues((purl, component) -> AnalysisResult.newBuilder().setComponent(component).build(),
                                        Named.as("map_unmatched_component_to_empty_result"))
                                .to(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), Produced
                                        .with(purlSerde, scanResultSerde)
                                        .withName(processorNameProduce(KafkaTopic.REPO_META_ANALYSIS_RESULT, "empty_result"))))
                        .withName("-not-found"));
        // repo meta analysis stream end

        // integrity check stresam start
        final var integrityResultSerde = new KafkaProtobufSerde<>(IntegrityResult.parser());
        final KStream<String, AnalysisCommand> integrityCheckCommandStream = streamsBuilder
                .stream(KafkaTopic.INTEGRITY_ANALYSIS_COMMAND.getName(), Consumed
                        .with(Serdes.String(), analysisCommandSerde)
                        .withName(processorNameConsume(KafkaTopic.INTEGRITY_ANALYSIS_COMMAND))).
                filter((key, scanCommand) -> scanCommand.hasComponent() && isValidPurl(scanCommand.getComponent().getPurl()),
                        Named.as("filter_components_with_valid_purl_ic"))
                .selectKey((key, command) -> mustParsePurlCoordinates(key),
                        Named.as("re-key_to_purl_coordinates_for_ic"))
                .repartition(Repartitioned
                        .with(Serdes.String(), analysisCommandSerde)
                        .withName("integrity-check-by-purl-coordinates"));

        integrityCheckCommandStream.mapValues((componentAndPurl, command) -> command.getComponent(), Named.as("map_to_integrity_check_for_component"))
                .split(Named.as("applicable_integrity_checker"))
                .branch((componentAndPurl, component) -> {
                            try {
                                return integrityAnalyzerFactory.hasApplicableAnalyzer(new PackageURL(componentAndPurl.split("_")[1]));
                            } catch (MalformedPackageURLException e) {
                                throw new RuntimeException(e);
                            }
                        },
                        Branched.withConsumer(stream -> stream
                                .processValues(integrityAnalyzerProcessorSupplier, Named.as("check_integrity_of_component"))
                                .to(KafkaTopic.INTEGRITY_ANALYSIS_RESULT.getName(),
                                        Produced.with(Serdes.String(), integrityResultSerde)
                                                .withName(processorNameProduce(KafkaTopic.INTEGRITY_ANALYSIS_RESULT, "integrity_check_result")))));

        //integrity check stream end
        return streamsBuilder.build();
    }

    private boolean isValidPurl(final String purl) {
        try {
            new PackageURL(purl);
            return true;
        } catch (MalformedPackageURLException e) {
            return false;
        }
    }

    private PackageURL mustParsePurlCoordinatesWithoutVersion(final String purl) {
        try {
            final var parsedPurl = new PackageURL(purl);
            return new PackageURL(parsedPurl.getType(), parsedPurl.getNamespace(),
                    parsedPurl.getName(), null, null, null);
        } catch (MalformedPackageURLException e) {
            throw new IllegalStateException("""
                    The provided PURL is invalid, even though it should have been
                    validated in a previous processing step
                    """, e);
        }
    }

    private String mustParsePurlCoordinates(final String componentIdAndpurl) {
        try {
            String purl = componentIdAndpurl.split("_")[1];
            final var parsedPurl = new PackageURL(purl);
            new PackageURL(parsedPurl.getType(), parsedPurl.getNamespace(),
                    parsedPurl.getName(), parsedPurl.getVersion(), (TreeMap<String, String>) parsedPurl.getQualifiers(), null);
            return componentIdAndpurl;
        } catch (MalformedPackageURLException e) {
            throw new IllegalStateException("""
                    The provided PURL is invalid, even though it should have been
                    validated in a previous processing step
                    """, e);
        }
    }

}
