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

import com.github.packageurl.PackageURL;
import io.quarkus.cache.Cache;
import io.quarkus.cache.CacheName;
import io.quarkus.cache.CaffeineCache;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.TestInputTopic;
import org.apache.kafka.streams.TestOutputTopic;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.TopologyTestDriver;
import org.dependencytrack.common.KafkaTopic;
import org.dependencytrack.persistence.model.Repository;
import org.dependencytrack.persistence.repository.RepoEntityRepository;
import org.dependencytrack.proto.KafkaProtobufDeserializer;
import org.dependencytrack.proto.KafkaProtobufSerializer;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisCommand;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisResult;
import org.dependencytrack.repometaanalyzer.model.IntegrityMeta;
import org.dependencytrack.repometaanalyzer.model.MetaAnalyzerCacheKey;
import org.dependencytrack.repometaanalyzer.model.MetaModel;
import org.dependencytrack.repometaanalyzer.repositories.IMetaAnalyzer;
import org.dependencytrack.repometaanalyzer.repositories.RepositoryAnalyzerFactory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static java.util.concurrent.CompletableFuture.completedFuture;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@QuarkusTest
public class RepositoryMetaAnalyzerTopologyTest {

    @Inject
    Topology topology;

    @InjectMock
    RepositoryAnalyzerFactory analyzerFactoryMock;

    @InjectMock
    RepoEntityRepository repoEntityRepositoryMock;

    @Inject
    @CacheName("metaAnalyzer")
    Cache cache;

    private TopologyTestDriver testDriver;
    private TestInputTopic<String, AnalysisCommand> inputTopic;
    private TestOutputTopic<String, AnalysisResult> outputTopic;
    private IMetaAnalyzer analyzerMock;

    @BeforeEach
    void beforeEach() {
        testDriver = new TopologyTestDriver(topology);
        inputTopic = testDriver.createInputTopic(
                KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(),
                new StringSerializer(), new KafkaProtobufSerializer<>());
        outputTopic = testDriver.createOutputTopic(
                KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(),
                new StringDeserializer(), new KafkaProtobufDeserializer<>(AnalysisResult.parser()));

        analyzerMock = mock(IMetaAnalyzer.class);

        when(analyzerFactoryMock.hasApplicableAnalyzer(any(PackageURL.class)))
                .thenReturn(true);
        when(analyzerFactoryMock.createAnalyzer(any(PackageURL.class)))
                .thenReturn(Optional.of(analyzerMock));
    }

    @AfterEach
    void afterEach() {
        testDriver.close();
        cache.invalidateAll().await().indefinitely();
    }

    @Test
    void testAnalyzerCacheMiss() throws Exception {
        final var command = AnalysisCommand.newBuilder()
                .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                        .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2")
                        .build())
                .build();

        // mock repository data
        Repository repository = new Repository();
        repository.setIdentifier("testRepository");
        repository.setInternal(false);
        repository.setAuthenticationRequired(false);
        repository.setUrl("https://repo1.maven.org/maven2/");
        when(repoEntityRepositoryMock.findEnabledRepositoriesByType(any()))
                .thenReturn(List.of(repository));

        // mock maven analyzer analyze method
        final var outputMetaModel = new MetaModel();
        outputMetaModel.setLatestVersion("test");
        when(analyzerMock.analyze(any())).thenReturn(outputMetaModel);
        when(analyzerMock.getName()).thenReturn("testAnalyzer");

        // mock maven analyzer fetch integrity meta method
        final var integrityMeta = new IntegrityMeta();
        integrityMeta.setSha256("sha256");
        when(analyzerMock.getIntegrityMeta(any())).thenReturn(integrityMeta);

        inputTopic.pipeInput("foo", command);

        final var cacheKeyWithoutVersion = new MetaAnalyzerCacheKey("testAnalyzer",
                "pkg:maven/com.fasterxml.jackson.core/jackson-databind",
                "https://repo1.maven.org/maven2/");
        Assertions.assertNotNull(cache.as(CaffeineCache.class).getIfPresent(cacheKeyWithoutVersion).get());
        final var cacheKeyWithVersion = new MetaAnalyzerCacheKey("testAnalyzer",
                "pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2",
                "https://repo1.maven.org/maven2/");
        Assertions.assertNotNull(cache.as(CaffeineCache.class).getIfPresent(cacheKeyWithVersion).get());
    }

    @Test
    void testAnalyzerCacheHitRepoMeta() {
        final var command = AnalysisCommand.newBuilder()
                .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                        .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2"))
                .build();

        // mock repository data
        Repository repository = new Repository();
        repository.setIdentifier("testRepository");
        repository.setInternal(false);
        repository.setAuthenticationRequired(false);
        repository.setUrl("https://repo1.maven.org/maven2/");
        when(repoEntityRepositoryMock.findEnabledRepositoriesByType(any()))
                .thenReturn(List.of(repository));

        final var cachedRepoMeta = new MetaModel();
        cachedRepoMeta.setRepositoryIdentifier("testRepository");
        cachedRepoMeta.setLatestVersion("test");
        when(analyzerMock.getName()).thenReturn("testAnalyzer");

        // populate the cache to hit the match
        final var cacheKey = new MetaAnalyzerCacheKey("testAnalyzer",
                "pkg:maven/com.fasterxml.jackson.core/jackson-databind",
                "https://repo1.maven.org/maven2/");
        cache.as(CaffeineCache.class).put(cacheKey, completedFuture(cachedRepoMeta));

        inputTopic.pipeInput("foo", command);
        final KeyValue<String, AnalysisResult> record = outputTopic.readKeyValue();
        Assertions.assertEquals("pkg:maven/com.fasterxml.jackson.core/jackson-databind", record.key);
        Assertions.assertEquals("test", record.value.getLatestVersion());
    }

    @Test
    void testAnalyzerCacheHitIntegrityMeta() {
        UUID uuid = UUID.randomUUID();
        final var command = AnalysisCommand.newBuilder()
                .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                        .setUuid(uuid.toString())
                        .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2"))
                .build();

        // mock repository data
        Repository repository = new Repository();
        repository.setIdentifier("testRepository");
        repository.setInternal(false);
        repository.setAuthenticationRequired(false);
        repository.setUrl("https://repo1.maven.org/maven2/");
        when(repoEntityRepositoryMock.findEnabledRepositoriesByType(any()))
                .thenReturn(List.of(repository));

        final var cachedIntegrityMeta = new IntegrityMeta();
        cachedIntegrityMeta.setSha1("sha1");

        when(analyzerMock.getName()).thenReturn("testAnalyzer");

        // populate the cache to hit the match
        final var cacheKey = new MetaAnalyzerCacheKey("testAnalyzer",
                "pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2",
                "https://repo1.maven.org/maven2/");
        cache.as(CaffeineCache.class).put(cacheKey, completedFuture(cachedIntegrityMeta));

        inputTopic.pipeInput("foo", command);
        final KeyValue<String, AnalysisResult> record = outputTopic.readKeyValue();
        Assertions.assertEquals("pkg:maven/com.fasterxml.jackson.core/jackson-databind", record.key);
        Assertions.assertEquals("sha1", record.value.getIntegrityMeta().getSha1());
        Assertions.assertEquals(uuid.toString(), record.value.getComponent().getUuid());
    }


    @Test
    void testPerformMetaAnalysis() {
        final var command = AnalysisCommand.newBuilder()
                .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                        .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2"))
                .build();

        inputTopic.pipeInput("foo", command);

        Assertions.assertEquals(1, outputTopic.getQueueSize());
    }


    @Test
    void testNoPurlComponent() {
        final var command = AnalysisCommand.newBuilder()
                .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder())
                .build();

        inputTopic.pipeInput("foo", command);

        Assertions.assertEquals(0, outputTopic.getQueueSize());
    }

    @Test
    void testMetaOutput() {
        final var command = AnalysisCommand.newBuilder()
                .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                        .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2"))
                .build();

        inputTopic.pipeInput("foo", command);

        Assertions.assertEquals(1, outputTopic.getQueueSize());
        final KeyValue<String, AnalysisResult> record = outputTopic.readKeyValue();
        Assertions.assertEquals("pkg:maven/com.fasterxml.jackson.core/jackson-databind", record.key);
        Assertions.assertEquals("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2", record.value.getComponent().getPurl());
        Assertions.assertFalse(record.value.hasLatestVersion());
        Assertions.assertFalse(record.value.hasIntegrityMeta());
    }

}

