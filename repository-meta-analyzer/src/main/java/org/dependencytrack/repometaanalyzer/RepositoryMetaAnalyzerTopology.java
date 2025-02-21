/*
 * This file is part of Dependency-Track.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) OWASP Foundation. All Rights Reserved.
 */
package org.dependencytrack.repometaanalyzer;

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
import org.dependencytrack.common.KafkaTopic;
import org.dependencytrack.proto.KafkaProtobufSerde;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisCommand;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisResult;
import org.dependencytrack.repometaanalyzer.processor.MetaAnalyzerProcessorSupplier;
import org.dependencytrack.repometaanalyzer.repositories.RepositoryAnalyzerFactory;
import org.dependencytrack.repometaanalyzer.serde.KafkaPurlSerde;
import org.dependencytrack.repometaanalyzer.util.PurlUtil;

import static org.dependencytrack.kstreams.util.KafkaStreamsUtil.processorNameConsume;
import static org.dependencytrack.kstreams.util.KafkaStreamsUtil.processorNameProduce;

public class RepositoryMetaAnalyzerTopology {

    @Produces
    @SuppressWarnings({"resource", "java:S2095"}) // Ignore linter warnings about Serdes having to be closed
    public Topology topology(final RepositoryAnalyzerFactory analyzerFactory,
                             final MetaAnalyzerProcessorSupplier analyzerProcessorSupplier) {
        final var streamsBuilder = new StreamsBuilder();

        final var purlSerde = new KafkaPurlSerde();
        final var analysisCommandSerde = new KafkaProtobufSerde<>(AnalysisCommand.parser());
        final var scanResultSerde = new KafkaProtobufSerde<>(AnalysisResult.parser());

        final KStream<PackageURL, AnalysisCommand> commandStream = streamsBuilder
                .stream(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), Consumed
                        .with(Serdes.String(), analysisCommandSerde) // Key can be in arbitrary format
                        .withName(processorNameConsume(KafkaTopic.REPO_META_ANALYSIS_COMMAND)))
                .filter((key, scanCommand) -> scanCommand.hasComponent() && isValidPurl(scanCommand.getComponent().getPurl()),
                        Named.as("filter_components_with_valid_purl"))
                // TODO: This repartition is no longer required as of API server 5.6.0.
                //  Remove this in Hyades v0.7.0 and consume from REPO_META_ANALYSIS_COMMAND directly instead.
                // Re-key to PURL coordinates WITHOUT VERSION. As we are fetching data for packages,
                // but not specific package versions, including the version here would make our caching
                // largely ineffective. We want events for the same package to be sent to the same partition.
                //
                // Because we can't enforce this format on the keys of the input topic without causing
                // serialization exceptions, we're left with this mandatory key change.
                .selectKey((key, command) -> PurlUtil.parsePurlCoordinatesWithoutVersion(command.getComponent().getPurl()),
                        Named.as("re-key_to_purl_coordinates"))
                // Force a repartition to ensure that the ordering guarantees we want, based on the
                // previous re-keying operation, are effective.
                .repartition(Repartitioned
                        .with(purlSerde, analysisCommandSerde)
                        .withName("command-by-purl-coordinates"));

        commandStream
                .split(Named.as("applicable_analyzer"))
                .branch((purl, command) -> analyzerFactory.hasApplicableAnalyzer(purl), Branched
                        .<PackageURL, AnalysisCommand>withConsumer(stream -> stream
                                .processValues(analyzerProcessorSupplier, Named.as("analyze_component"))
                                .to(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), Produced
                                        .with(purlSerde, scanResultSerde)
                                        .withName(processorNameProduce(KafkaTopic.REPO_META_ANALYSIS_RESULT, "analysis_result"))))
                        .withName("-found"))
                .defaultBranch(Branched
                        .<PackageURL, AnalysisCommand>withConsumer(stream -> stream
                                .mapValues((purl, command) -> AnalysisResult.newBuilder().setComponent(command.getComponent()).build(),
                                        Named.as("map_unmatched_component_to_empty_result"))
                                .to(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), Produced
                                        .with(purlSerde, scanResultSerde)
                                        .withName(processorNameProduce(KafkaTopic.REPO_META_ANALYSIS_RESULT, "empty_result"))))
                        .withName("-not-found"));

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
}
