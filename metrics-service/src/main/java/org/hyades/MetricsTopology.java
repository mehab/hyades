package org.hyades;

import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Aggregator;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Grouped;
import org.apache.kafka.streams.kstream.Initializer;
import org.apache.kafka.streams.kstream.KGroupedStream;
import org.apache.kafka.streams.kstream.KStream;
import org.apache.kafka.streams.kstream.KTable;
import org.apache.kafka.streams.kstream.Materialized;
import org.apache.kafka.streams.kstream.Named;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.state.KeyValueBytesStoreSupplier;
import org.hyades.common.KafkaTopic;
import org.hyades.metrics.processor.ComponentProcessorSupplier;
import org.hyades.metrics.processor.ProjectProcessorSupplier;
import org.hyades.proto.KafkaProtobufSerde;
import org.hyades.proto.metrics.v1.ComponentMetrics;
import org.hyades.proto.metrics.v1.PortfolioMetrics;
import org.hyades.proto.metrics.v1.ProjectMetrics;
import org.hyades.proto.metrics.v1.Status;

import javax.enterprise.context.ApplicationScoped;
import javax.enterprise.inject.Produces;
import javax.inject.Inject;

import static org.hyades.commonutil.KafkaStreamsUtil.processorNameConsume;
import static org.hyades.commonutil.KafkaStreamsUtil.processorNameProduce;
import static org.hyades.metrics.util.MetricsUtil.add;

@ApplicationScoped
public class MetricsTopology {

    private final ComponentProcessorSupplier componentProcessorSupplier;

    private final ProjectProcessorSupplier projectProcessorSupplier;

    private final KeyValueBytesStoreSupplier projectMetricsStoreSupplier;

    private final KeyValueBytesStoreSupplier portfolioMetricsStoreSupplier;


    @Inject
    public MetricsTopology(final ComponentProcessorSupplier componentProcessorSupplier,
                           final ProjectProcessorSupplier projectProcessorSupplier,
                           @javax.inject.Named("projectMetricsStoreSupplier") final KeyValueBytesStoreSupplier projectMetricsStoreSupplier,
                           @javax.inject.Named("portfolioMetricsStoreSupplier") final KeyValueBytesStoreSupplier portfolioMetricsStoreSupplier) {
        this.componentProcessorSupplier = componentProcessorSupplier;
        this.projectProcessorSupplier = projectProcessorSupplier;
        this.projectMetricsStoreSupplier = projectMetricsStoreSupplier;
        this.portfolioMetricsStoreSupplier = portfolioMetricsStoreSupplier;
    }

    @Produces
    public Topology metricsTopology() {
        final var streamsBuilder = new StreamsBuilder();

        var componentMetricsSerde = new KafkaProtobufSerde<>(ComponentMetrics.parser());
        var projectMetricsSerde = new KafkaProtobufSerde<>(ProjectMetrics.parser());
        var portfolioMetricsSerde = new KafkaProtobufSerde<>(PortfolioMetrics.parser());

        final KStream<String, ComponentMetrics> componentMetricsStream = streamsBuilder
                .stream(KafkaTopic.COMPONENT_METRICS.getName(), Consumed
                        .with(Serdes.String(), componentMetricsSerde)
                        .withName(processorNameConsume(KafkaTopic.COMPONENT_METRICS)))
                .process(componentProcessorSupplier, Named.as("process_with_component_delta_processor"));

        KGroupedStream<String, ComponentMetrics> kGroupedStream = componentMetricsStream
                .groupBy((key, value) -> value.getProjectUuid(), Grouped
                        .with(Serdes.String(), componentMetricsSerde)
                        .withName("group_metrics_by_project"));

        // The initial value of our aggregation will be a new Metrics instance
        Initializer<ProjectMetrics> projectMetricsInitializer = ProjectMetrics.newBuilder()::build;

        Aggregator<String, ComponentMetrics, ProjectMetrics> metricsAdder =
                (key, value, aggregate) -> add(aggregate, value);

        KTable<String, ProjectMetrics> projectMetricsTable =
                kGroupedStream.aggregate(
                        projectMetricsInitializer,
                        metricsAdder,
                        Named.as("aggregate-component-metrics-to-project-metrics"),
                        Materialized.<String, ProjectMetrics>as(projectMetricsStoreSupplier)
                                .withKeySerde(Serdes.String())
                                .withValueSerde(projectMetricsSerde));

        //stream projectMetricsTable to project metrics topic
        projectMetricsTable
                .toStream(Named.as("stream-project-metrics"))
                .filter((key, value) -> value.getStatus().equals(Status.STATUS_UPDATED))
                .to(KafkaTopic.PROJECT_METRICS.getName(), Produced
                        .with(Serdes.String(), projectMetricsSerde)
                        .withName(processorNameProduce(KafkaTopic.PROJECT_METRICS, "project_metric_event")));

        //aggregate project metrics to portfolio metrics
        final KStream<String, ProjectMetrics> projectMetricsKStream = streamsBuilder
                .stream(KafkaTopic.PROJECT_METRICS.getName(), Consumed
                        .with(Serdes.String(), projectMetricsSerde)
                        .withName(processorNameConsume(KafkaTopic.PROJECT_METRICS)))
                .process(projectProcessorSupplier, Named.as("process_with_project_delta_processor"));

        KGroupedStream<String, ProjectMetrics> kGroupedProjectStream = projectMetricsKStream
                .groupBy((key, value) -> "re-key", Grouped
                        .with(Serdes.String(), projectMetricsSerde)
                        .withName("group_metrics_by_portfolio"));

        Initializer<PortfolioMetrics> portfolioMetricsInitializer = PortfolioMetrics.newBuilder()::build;

        Aggregator<String, ProjectMetrics, PortfolioMetrics> portfolioMetricsAdder =
                (key, value, aggregate) -> add(aggregate, value);


        KTable<String, PortfolioMetrics> portfolioMetricsTable =
                kGroupedProjectStream.aggregate(
                        portfolioMetricsInitializer,
                        portfolioMetricsAdder,
                        Named.as("aggregate-project-metrics-to-portfolio-metrics"),
                        Materialized.<String, PortfolioMetrics>as(portfolioMetricsStoreSupplier)
                                .withKeySerde(Serdes.String())
                                .withValueSerde(portfolioMetricsSerde));

        //stream portfolioMetricsTable to portfolio metrics topic
        portfolioMetricsTable
                .toStream(Named.as("stream-portfolio-metrics"))
                .filter((key, value) -> value.getStatus().equals(Status.STATUS_UPDATED))
                .to(KafkaTopic.PORTFOLIO_METRICS.getName(), Produced
                        .with(Serdes.String(), portfolioMetricsSerde)
                        .withName(processorNameProduce(KafkaTopic.PORTFOLIO_METRICS, "portfolio_metrics_event")));

        return streamsBuilder.build();
    }
}
