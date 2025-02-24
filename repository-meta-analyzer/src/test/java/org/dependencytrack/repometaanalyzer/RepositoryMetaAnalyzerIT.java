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

import com.github.tomakehurst.wiremock.client.WireMock;
import com.github.tomakehurst.wiremock.http.Body;
import com.github.tomakehurst.wiremock.http.ContentTypeHeader;
import io.quarkiverse.wiremock.devservice.ConnectWireMock;
import io.quarkiverse.wiremock.devservice.WireMockConfigKey;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusIntegrationTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.kafka.InjectKafkaCompanion;
import io.quarkus.test.kafka.KafkaCompanionResource;
import io.smallrye.reactive.messaging.kafka.companion.KafkaCompanion;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.Serdes;
import org.dependencytrack.common.KafkaTopic;
import org.dependencytrack.proto.KafkaProtobufSerde;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisCommand;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisResult;
import org.eclipse.microprofile.config.ConfigProvider;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.platform.suite.api.SelectClasses;
import org.junit.platform.suite.api.Suite;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@Suite
@SelectClasses(value = {
        RepositoryMetaAnalyzerIT.WithValidPurlLatestVersionEnabled.class,
        RepositoryMetaAnalyzerIT.WithValidPurlWithIntegrityRepoUnsupported.class,
        RepositoryMetaAnalyzerIT.WithInvalidPurl.class,
        RepositoryMetaAnalyzerIT.NoCapableAnalyzer.class,
        RepositoryMetaAnalyzerIT.InternalAnalyzerNonInternalComponent.class,
        RepositoryMetaAnalyzerIT.WithValidPurlWithBothLatestVersionAndIntegrityEnabled.class,
        RepositoryMetaAnalyzerIT.WithValidPurlIntegrityMetaEnabled.class
})
class RepositoryMetaAnalyzerIT {

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @ConnectWireMock
    @TestProfile(WithValidPurlLatestVersionEnabled.TestProfile.class)
    static class WithValidPurlLatestVersionEnabled {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        WireMock wireMock;

        @BeforeEach
        void beforeEach() throws Exception {
            // Workaround for the fact that Quarkus < 2.17.0 does not support initializing the database container
            // with data. We can't use EntityManager etc. because the test is executed against an already built
            // artifact (JAR, container, or native image).
            // Can be replaced with quarkus.datasource.devservices.init-script-path after upgrading to Quarkus 2.17.0:
            // https://github.com/quarkusio/quarkus/pull/30455
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED")
                        VALUES ('true', 'test', false, NULL, 1, 'GO_MODULES', 'http://localhost:%d', false);
                        """.formatted(ConfigProvider.getConfig().getValue(WireMockConfigKey.PORT, Integer.class)));
                ps.execute();
            }

            wireMock.register(WireMock.get(WireMock.anyUrl())
                    .willReturn(WireMock.aResponse()
                            .withStatus(200)
                            .withResponseBody(Body.ofBinaryOrText("""
                                    {
                                        "Version": "v6.6.6",
                                        "Time": "2022-09-28T21:59:32Z",
                                        "Origin": {
                                            "VCS": "git",
                                            "URL": "https://github.com/acme/acme-lib",
                                            "Ref": "refs/tags/v6.6.6",
                                            "Hash": "39a1d8f8f69040a53114e1ea481e48f6d792c05e"
                                        }
                                    }
                                     """.getBytes(), new ContentTypeHeader("application/json"))
                            )));
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:golang/github.com/acme/acme-lib@9.1.1"))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), "foo", command));

            final List<ConsumerRecord<String, AnalysisResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(AnalysisResult.parser()))
                    .fromTopics(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();

            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:golang/github.com/acme/acme-lib");
                        assertThat(record.value()).isNotNull();
                        final AnalysisResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.hasRepository()).isTrue();
                        assertThat(result.getRepository()).isEqualTo("test");
                        assertThat(result.hasLatestVersion()).isTrue();
                        assertThat(result.getLatestVersion()).isEqualTo("v6.6.6");
                        assertThat(result.hasPublished()).isTrue();
                        assertThat(result.getPublished().getSeconds()).isEqualTo(1664402372);
                        assertThat(result.hasIntegrityMeta()).isFalse();
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @ConnectWireMock
    @TestProfile(WithValidPurlWithIntegrityRepoUnsupported.TestProfile.class)
    static class WithValidPurlWithIntegrityRepoUnsupported {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @BeforeEach
        void beforeEach() throws Exception {
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED")
                        VALUES ('true', 'test', false, NULL, 1, 'GO_MODULES', 'http://localhost:%d', false);
                        """.formatted(ConfigProvider.getConfig().getValue(WireMockConfigKey.PORT, Integer.class)));
                ps.execute();
            }
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:golang/github.com/acme/acme-lib@9.1.1"))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), "foo", command));

            final List<ConsumerRecord<String, AnalysisResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(AnalysisResult.parser()))
                    .fromTopics(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();

            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:golang/github.com/acme/acme-lib");
                        assertThat(record.value()).isNotNull();
                        final AnalysisResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.hasRepository()).isFalse();
                        assertThat(result.hasLatestVersion()).isFalse();
                        assertThat(result.hasPublished()).isFalse();
                        assertThat(result.hasIntegrityMeta()).isFalse();
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @ConnectWireMock
    @TestProfile(WithInvalidPurl.TestProfile.class)
    static class WithInvalidPurl {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @BeforeEach
        void beforeEach() throws Exception {
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED")
                        VALUES ('true', 'test', false, NULL, 2, 'NPM', 'http://localhost:%d', false);
                        """.formatted(ConfigProvider.getConfig().getValue(WireMockConfigKey.PORT, Integer.class)));
                ps.execute();
            }
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("invalid-purl"))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), "foo", command));

            final List<ConsumerRecord<String, AnalysisResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(AnalysisResult.parser()))
                    .fromTopics(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();

            assertThat(results).isEmpty();
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @ConnectWireMock
    @TestProfile(NoCapableAnalyzer.TestProfile.class)
    static class NoCapableAnalyzer {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @BeforeEach
        void beforeEach() throws Exception {
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED")
                        VALUES ('true', 'test', false, NULL, 2, 'CPAN', 'http://localhost:%d', false);
                        """.formatted(ConfigProvider.getConfig().getValue(WireMockConfigKey.PORT, Integer.class)));
                ps.execute();
            }
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:github/github.com/acme/acme-lib@9.1.1"))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), "foo", command));

            final List<ConsumerRecord<String, AnalysisResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(AnalysisResult.parser()))
                    .fromTopics(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();
            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:github/github.com/acme/acme-lib");
                        assertThat(record.value()).isNotNull();
                        final AnalysisResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.getComponent()).isEqualTo(command.getComponent());
                        assertThat(result.hasRepository()).isFalse();
                        assertThat(result.hasLatestVersion()).isFalse();
                        assertThat(result.hasPublished()).isFalse();
                        assertThat(result.hasIntegrityMeta()).isFalse();
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @ConnectWireMock
    @TestProfile(InternalAnalyzerNonInternalComponent.TestProfile.class)
    static class InternalAnalyzerNonInternalComponent {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @BeforeEach
        void beforeEach() throws Exception {
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED")
                        VALUES ('true', 'test', true, NULL, 2, 'MAVEN', 'http://localhost:%d', false);
                        """.formatted(ConfigProvider.getConfig().getValue(WireMockConfigKey.PORT, Integer.class)));
                ps.execute();
            }
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:golang/github.com/acme/acme-lib@9.1.1")
                            .setInternal(false))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), "foo", command));

            final List<ConsumerRecord<String, AnalysisResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(AnalysisResult.parser()))
                    .fromTopics(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();
            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:golang/github.com/acme/acme-lib");
                        assertThat(record.value()).isNotNull();
                        final AnalysisResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.getComponent()).isEqualTo(command.getComponent());
                        assertThat(result.hasRepository()).isFalse();
                        assertThat(result.hasLatestVersion()).isFalse();
                        assertThat(result.hasPublished()).isFalse();
                        assertThat(result.hasIntegrityMeta()).isFalse();
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @ConnectWireMock
    @TestProfile(WithValidPurlWithBothLatestVersionAndIntegrityEnabled.TestProfile.class)
    static class WithValidPurlWithBothLatestVersionAndIntegrityEnabled {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        WireMock wireMock;

        @BeforeEach
        void beforeEach() throws Exception {
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED")
                        VALUES ('true', 'test', false, NULL, 1, 'NPM', 'http://localhost:%d', false);
                        """.formatted(ConfigProvider.getConfig().getValue(WireMockConfigKey.PORT, Integer.class)));
                ps.execute();
            }

            wireMock.register(WireMock.get(WireMock.anyUrl())
                    .willReturn(WireMock.aResponse()
                            .withStatus(200)
                            .withResponseBody(Body.ofBinaryOrText("""
                                    {
                                        "latest": "v6.6.6"
                                    }
                                     """.getBytes(), new ContentTypeHeader("application/json"))
                            )));
            wireMock.register(WireMock.head(WireMock.anyUrl())
                    .willReturn(WireMock.aResponse()
                            .withStatus(200)
                            .withHeader("X-Checksum-MD5", "md5hash")
                            .withHeader("X-Checksum-SHA1", "sha1hash")
                            .withHeader("Last-Modified", "Wed, 06 Jul 2022 14:00:00 GMT")
                    ));
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:npm/amazon-s3-uri@0.0.1"))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), "foo", command));

            final List<ConsumerRecord<String, AnalysisResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(AnalysisResult.parser()))
                    .fromTopics(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();

            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:npm/amazon-s3-uri");
                        assertThat(record.value()).isNotNull();
                        final AnalysisResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.getRepository()).isEqualTo("test");
                        assertThat(result.getLatestVersion()).isEqualTo("v6.6.6");
                        assertThat(result.hasPublished()).isFalse();
                        assertThat(result.hasIntegrityMeta()).isTrue();
                        final var integrityMeta = result.getIntegrityMeta();
                        assertThat(integrityMeta).isNotNull();
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @ConnectWireMock
    @TestProfile(WithValidPurlIntegrityMetaEnabled.TestProfile.class)
    static class WithValidPurlIntegrityMetaEnabled {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        WireMock wireMock;

        @BeforeEach
        void beforeEach() throws Exception {
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED")
                        VALUES ('true', 'test', false, NULL, 1, 'NPM', 'http://localhost:%d', false);
                        """.formatted(ConfigProvider.getConfig().getValue(WireMockConfigKey.PORT, Integer.class)));
                ps.execute();
            }
            wireMock.register(WireMock.head(WireMock.anyUrl())
                    .willReturn(WireMock.aResponse()
                            .withStatus(200)
                            .withHeader("X-Checksum-MD5", "md5hash")
                            .withHeader("X-Checksum-SHA1", "sha1hash")
                            .withHeader("Last-Modified", "Wed, 06 Jul 2022 14:00:00 GMT")
                    ));
        }

        @Test
        void testIntegrityMetaOnly() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.dependencytrack.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:npm/amazon-s3-uri@0.0.1"))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), "foo", command));

            final List<ConsumerRecord<String, AnalysisResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(AnalysisResult.parser()))
                    .fromTopics(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();

            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:npm/amazon-s3-uri");
                        assertThat(record.value()).isNotNull();
                        final AnalysisResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.hasLatestVersion()).isFalse();
                        assertThat(result.hasPublished()).isFalse();
                        assertThat(result.hasIntegrityMeta()).isTrue();
                        final var integrityMeta = result.getIntegrityMeta();
                        assertThat(integrityMeta.getMd5()).isEqualTo("md5hash");
                        assertThat(integrityMeta.getSha1()).isEqualTo("sha1hash");
                        assertThat(integrityMeta.getCurrentVersionLastModified().getSeconds()).isEqualTo(1657116000);
                        assertThat(integrityMeta.getMetaSourceUrl()).contains("/amazon-s3-uri/-/amazon-s3-uri-0.0.1.tgz");
                    }
            );
        }
    }
}
