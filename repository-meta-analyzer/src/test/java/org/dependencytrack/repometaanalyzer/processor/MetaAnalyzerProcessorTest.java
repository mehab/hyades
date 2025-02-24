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
package org.dependencytrack.repometaanalyzer.processor;

import com.github.packageurl.MalformedPackageURLException;
import com.github.packageurl.PackageURL;
import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.http.Body;
import com.github.tomakehurst.wiremock.http.ContentTypeHeader;
import io.quarkus.cache.Cache;
import io.quarkus.cache.CacheName;
import io.quarkus.test.TestTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import org.apache.http.HttpHeaders;
import org.apache.http.HttpStatus;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.TestInputTopic;
import org.apache.kafka.streams.TestOutputTopic;
import org.apache.kafka.streams.TopologyTestDriver;
import org.apache.kafka.streams.errors.StreamsException;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.test.TestRecord;
import org.dependencytrack.common.SecretDecryptor;
import org.dependencytrack.persistence.model.RepositoryType;
import org.dependencytrack.persistence.repository.RepoEntityRepository;
import org.dependencytrack.proto.KafkaProtobufSerde;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisCommand;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisResult;
import org.dependencytrack.proto.repometaanalysis.v1.Component;
import org.dependencytrack.repometaanalyzer.repositories.RepositoryAnalyzerFactory;
import org.dependencytrack.repometaanalyzer.serde.KafkaPurlSerde;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import java.util.Map;
import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.head;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static org.assertj.core.api.Assertions.assertThat;

@QuarkusTest
@TestProfile(MetaAnalyzerProcessorTest.TestProfile.class)
class MetaAnalyzerProcessorTest {

    public static class TestProfile implements QuarkusTestProfile {
        @Override
        public Map<String, String> getConfigOverrides() {
            return Map.of(
                    "quarkus.kafka.snappy.enabled", "false"
            );
        }
    }

    private static WireMockServer wireMockServer1;
    private static WireMockServer wireMockServer2;
    private static final String TEST_PURL_JACKSON_BIND = "pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.4";

    private TopologyTestDriver testDriver;
    private TestInputTopic<PackageURL, AnalysisCommand> inputTopic;
    private TestOutputTopic<PackageURL, AnalysisResult> outputTopic;
    @Inject
    RepoEntityRepository repoEntityRepository;

    @Inject
    RepositoryAnalyzerFactory analyzerFactory;

    @Inject
    EntityManager entityManager;

    @Inject
    @CacheName("metaAnalyzer")
    Cache cache;

    @Inject
    SecretDecryptor secretDecryptor;

    @BeforeEach
    void beforeEach() {
        final var processorSupplier = new MetaAnalyzerProcessorSupplier(repoEntityRepository, analyzerFactory, secretDecryptor, cache);

        final var valueSerde = new KafkaProtobufSerde<>(AnalysisCommand.parser());
        final var purlSerde = new KafkaPurlSerde();
        final var valueSerdeResult = new KafkaProtobufSerde<>(AnalysisResult.parser());

        final var streamsBuilder = new StreamsBuilder();
        streamsBuilder
                .stream("input-topic", Consumed.with(purlSerde, valueSerde))
                .processValues(processorSupplier)
                .to("output-topic", Produced.with(purlSerde, valueSerdeResult));

        testDriver = new TopologyTestDriver(streamsBuilder.build());
        inputTopic = testDriver.createInputTopic("input-topic", purlSerde.serializer(), valueSerde.serializer());
        outputTopic = testDriver.createOutputTopic("output-topic", purlSerde.deserializer(), valueSerdeResult.deserializer());

        wireMockServer1 = new WireMockServer(1080);
        wireMockServer1.start();
        wireMockServer2 = new WireMockServer(2080);
        wireMockServer2.start();
    }

    @AfterEach
    void afterEach() {
        wireMockServer1.stop();
        wireMockServer1.resetAll();
        wireMockServer2.stop();
        wireMockServer2.resetAll();
        testDriver.close();
        cache.invalidateAll().await().indefinitely();
    }


    @Test
    void testWithNoSupportedRepositoryTypes() throws Exception {
        final TestRecord<PackageURL, AnalysisCommand> inputRecord = new TestRecord<>(new PackageURL(TEST_PURL_JACKSON_BIND), AnalysisCommand.newBuilder().setComponent(Component.newBuilder()
                .setPurl(TEST_PURL_JACKSON_BIND)).build());
        inputTopic.pipeInput(inputRecord);
        assertThat(outputTopic.getQueueSize()).isEqualTo(1);
        assertThat(outputTopic.readRecordsToList()).satisfiesExactly(
                record -> {
                    assertThat(record.key().getType()).isEqualTo(RepositoryType.MAVEN.toString().toLowerCase());
                });
    }

    @Test
    void testMalformedPurl() throws Exception {
        final TestRecord<PackageURL, AnalysisCommand> inputRecord = new TestRecord<>(new PackageURL(TEST_PURL_JACKSON_BIND), AnalysisCommand.newBuilder().setComponent(Component.newBuilder()
                .setPurl("invalid purl")).build());
        Assertions.assertThrows(StreamsException.class, () -> {
            inputTopic.pipeInput(inputRecord);
        }, "no exception thrown");

    }

    @Test
    void testNoAnalyzerApplicable() throws Exception {
        final TestRecord<PackageURL, AnalysisCommand> inputRecord = new TestRecord<>(new PackageURL("pkg:test/com.fasterxml.jackson.core/jackson-databind@2.13.4"), AnalysisCommand.newBuilder().setComponent(Component.newBuilder()
                .setPurl("pkg:test/com.fasterxml.jackson.core/jackson-databind@2.13.4")).build());
        inputTopic.pipeInput(inputRecord);
        assertThat(outputTopic.getQueueSize()).isEqualTo(1);
        assertThat(outputTopic.readRecordsToList()).satisfiesExactly(
                record -> {
                    assertThat(record.key().getType()).isEqualTo("test");
                });

    }

    @Test
    @TestTransaction
    void testInternalRepositoryExternalComponent() throws MalformedPackageURLException {
        entityManager.createNativeQuery("""
                INSERT INTO "REPOSITORY" ("TYPE", "ENABLED","IDENTIFIER", "INTERNAL", "URL", "AUTHENTICATIONREQUIRED", "RESOLUTION_ORDER") VALUES
                                    ('MAVEN',true, 'central', true, 'test.com', false,1);
                """).executeUpdate();

        final TestRecord<PackageURL, AnalysisCommand> inputRecord = new TestRecord<>(new PackageURL("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.4"), AnalysisCommand.newBuilder().setComponent(Component.newBuilder()
                .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.4").setInternal(false)).build());
        inputTopic.pipeInput(inputRecord);
        assertThat(outputTopic.getQueueSize()).isEqualTo(1);
        assertThat(outputTopic.readRecordsToList()).satisfiesExactly(
                record -> {
                    assertThat(record.key().getType()).isEqualTo(RepositoryType.MAVEN.toString().toLowerCase());
                });

    }

    @Test
    @TestTransaction
    void testExternalRepositoryInternalComponent() throws MalformedPackageURLException {
        entityManager.createNativeQuery("""
                INSERT INTO "REPOSITORY" ("TYPE", "ENABLED","IDENTIFIER", "INTERNAL", "URL", "AUTHENTICATIONREQUIRED", "RESOLUTION_ORDER") VALUES
                                    ('MAVEN',true, 'central', false, 'test.com', false,1);
                """).executeUpdate();

        final TestRecord<PackageURL, AnalysisCommand> inputRecord = new TestRecord<>(new PackageURL("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.4"), AnalysisCommand.newBuilder().setComponent(Component.newBuilder()
                .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.4").setInternal(true)).build());
        inputTopic.pipeInput(inputRecord);
        assertThat(outputTopic.getQueueSize()).isEqualTo(1);
        assertThat(outputTopic.readRecordsToList()).satisfiesExactly(
                record -> {
                    assertThat(record.key().getType()).isEqualTo(RepositoryType.MAVEN.toString().toLowerCase());
                });

    }

    @Test
    @TestTransaction
    void testRepoMetaWithIntegrityMetaWithAuth() throws Exception {
        entityManager.createNativeQuery("""
                        INSERT INTO "REPOSITORY" ("TYPE", "ENABLED","IDENTIFIER", "INTERNAL", "URL", "AUTHENTICATIONREQUIRED", "RESOLUTION_ORDER", "USERNAME", "PASSWORD") VALUES
                                            ('NPM', true, 'central', true, :url, true, 1, 'username', :encryptedPassword);
                        """)
                .setParameter("encryptedPassword", secretDecryptor.encryptAsString("password"))
                .setParameter("url", String.format("http://localhost:%d", wireMockServer1.port()))
                .executeUpdate();
        wireMockServer1.stubFor(get(urlPathEqualTo("/-/package/%40apollo%2Ffederation/dist-tags"))
                .willReturn(aResponse().withHeader(HttpHeaders.CONTENT_TYPE, "application/json")
                        .withResponseBody(Body.ofBinaryOrText("""
                                        {
                                            "latest": "v6.6.6"
                                        }
                                        """.getBytes(),
                                new ContentTypeHeader("application/json"))).withStatus(HttpStatus.SC_OK)));

        wireMockServer1.stubFor(head(urlPathEqualTo("/@apollo/federation/-/@apollo/federation-0.19.1.tgz"))
                .willReturn(aResponse().withHeader(HttpHeaders.CONTENT_TYPE, "application/json")
                        .withResponseBody(Body.ofBinaryOrText("".getBytes(),
                                new ContentTypeHeader("application/json")))
                        .withHeader("X-Checksum-MD5", "md5hash").withStatus(HttpStatus.SC_OK)));

        UUID uuid = UUID.randomUUID();
        final TestRecord<PackageURL, AnalysisCommand> inputRecord = new TestRecord<>(new PackageURL("pkg:npm/@apollo/federation@0.19.1"),
                AnalysisCommand.newBuilder()
                        .setComponent(Component.newBuilder()
                                .setPurl("pkg:npm/@apollo/federation@0.19.1")
                                .setUuid(uuid.toString())
                                .setInternal(true))
                        .build());

        inputTopic.pipeInput(inputRecord);
        assertThat(outputTopic.getQueueSize()).isEqualTo(1);
        assertThat(outputTopic.readRecordsToList()).satisfiesExactly(
                record -> {
                    assertThat(record.key().getType()).isEqualTo(RepositoryType.NPM.toString().toLowerCase());
                    assertThat(record.value()).isNotNull();
                    final AnalysisResult result = record.value();
                    assertThat(result.hasComponent()).isTrue();
                    assertThat(result.getComponent().getUuid()).isEqualTo(uuid.toString());
                    assertThat(result.getRepository()).isEqualTo("central");
                    assertThat(result.getLatestVersion()).isEqualTo("v6.6.6");
                    assertThat(result.hasPublished()).isFalse();
                    assertThat(result.hasIntegrityMeta()).isTrue();
                    final var integrityMeta = result.getIntegrityMeta();
                    assertThat(integrityMeta.getMd5()).isEqualTo("md5hash");
                    assertThat(integrityMeta.getMetaSourceUrl()).contains("/@apollo/federation/-/@apollo/federation-0.19.1.tgz");
                });

    }

    @Test
    @TestTransaction
    void testDifferentSourcesForRepoAndIntegrityMeta() throws Exception {
        entityManager.createNativeQuery("""
                        INSERT INTO "REPOSITORY" ("TYPE", "ENABLED","IDENTIFIER", "INTERNAL", "URL", "AUTHENTICATIONREQUIRED", "RESOLUTION_ORDER") VALUES
                                            ('NPM', true, 'central', true, :url1, false, 1),
                                            ('NPM', true, 'internal', true, :url2, false, 2);
                        """)
                .setParameter("url1", String.format("http://localhost:%d", wireMockServer1.port()))
                .setParameter("url2", String.format("http://localhost:%d", wireMockServer2.port()))
                .executeUpdate();
        wireMockServer1.stubFor(get(urlPathEqualTo("/-/package/%40apollo%2Ffederation/dist-tags"))
                .willReturn(aResponse().withHeader(HttpHeaders.CONTENT_TYPE, "application/json")
                        .withResponseBody(Body.ofBinaryOrText("""
                                        {
                                        }
                                        """.getBytes(),
                                new ContentTypeHeader("application/json")))
                        .withStatus(HttpStatus.SC_OK)));

        wireMockServer1.stubFor(head(urlPathEqualTo("/@apollo/federation/-/@apollo/federation-0.19.1.tgz"))
                .willReturn(aResponse().withHeader(HttpHeaders.CONTENT_TYPE, "application/json")
                        .withResponseBody(Body.ofBinaryOrText("".getBytes(),
                                new ContentTypeHeader("application/json"))).withHeader("X-Checksum-MD5", "md5hash")
                        .withStatus(HttpStatus.SC_OK)));
        wireMockServer2.stubFor(get(urlPathEqualTo("/-/package/%40apollo%2Ffederation/dist-tags"))
                .willReturn(aResponse().withHeader(HttpHeaders.CONTENT_TYPE, "application/json")
                        .withResponseBody(Body.ofBinaryOrText("""
                                        {
                                            "latest": "v6.6.6"
                                        }
                                        """.getBytes(),
                                new ContentTypeHeader("application/json")))
                        .withStatus(HttpStatus.SC_OK)));
        UUID uuid = UUID.randomUUID();
        final TestRecord<PackageURL, AnalysisCommand> inputRecord = new TestRecord<>(new PackageURL("pkg:npm/@apollo/federation@0.19.1"),
                AnalysisCommand.newBuilder()
                        .setComponent(Component.newBuilder()
                                .setPurl("pkg:npm/@apollo/federation@0.19.1")
                                .setUuid(uuid.toString())
                                .setInternal(true))
                        .build());

        inputTopic.pipeInput(inputRecord);
        assertThat(outputTopic.getQueueSize()).isEqualTo(1);
        assertThat(outputTopic.readRecordsToList()).satisfiesExactly(
                record -> {
                    assertThat(record.key().getType()).isEqualTo(RepositoryType.NPM.toString().toLowerCase());
                    assertThat(record.value()).isNotNull();
                    final AnalysisResult result = record.value();
                    assertThat(result.hasComponent()).isTrue();
                    assertThat(result.getComponent().getUuid()).isEqualTo(uuid.toString());
                    assertThat(result.getRepository()).isEqualTo("internal");
                    assertThat(result.getLatestVersion()).isEqualTo("v6.6.6");
                    assertThat(result.hasPublished()).isFalse();
                    assertThat(result.hasIntegrityMeta()).isTrue();
                    final var integrityMeta = result.getIntegrityMeta();
                    assertThat(integrityMeta.getMd5()).isEqualTo("md5hash");
                    assertThat(integrityMeta.getMetaSourceUrl()).isEqualTo("http://localhost:1080/@apollo/federation/-/@apollo/federation-0.19.1.tgz");
                });
    }
}