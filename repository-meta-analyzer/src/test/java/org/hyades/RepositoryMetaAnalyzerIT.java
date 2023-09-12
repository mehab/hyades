package org.hyades;

import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.client.WireMock;
import com.github.tomakehurst.wiremock.http.Body;
import com.github.tomakehurst.wiremock.http.ContentTypeHeader;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusIntegrationTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.kafka.InjectKafkaCompanion;
import io.quarkus.test.kafka.KafkaCompanionResource;
import io.smallrye.reactive.messaging.kafka.companion.KafkaCompanion;
import jakarta.ws.rs.core.MediaType;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.Serdes;
import org.eclipse.microprofile.config.ConfigProvider;
import org.hyades.common.KafkaTopic;
import org.hyades.proto.KafkaProtobufSerde;
import org.hyades.proto.repointegrityanalysis.v1.HashMatchStatus;
import org.hyades.proto.repointegrityanalysis.v1.IntegrityResult;
import org.hyades.proto.repometaanalysis.v1.AnalysisCommand;
import org.hyades.proto.repometaanalysis.v1.AnalysisResult;
import org.hyades.util.WireMockTestResource;
import org.hyades.util.WireMockTestResource.InjectWireMock;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.platform.suite.api.SelectClasses;
import org.junit.platform.suite.api.Suite;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.time.Duration;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@Suite
@SelectClasses(value = {
        RepositoryMetaAnalyzerIT.WithValidPurl.class,
        RepositoryMetaAnalyzerIT.WithInvalidPurl.class,
        RepositoryMetaAnalyzerIT.NoCapableAnalyzer.class,
        RepositoryMetaAnalyzerIT.InternalAnalyzerNonInternalComponent.class,
        RepositoryMetaAnalyzerIT.WithIntegrityCheckEnabledComponentMissingHash.class,
        RepositoryMetaAnalyzerIT.WithIntegrityCheckEnabledComponentHashMatch.class,
        RepositoryMetaAnalyzerIT.WithIntegrityCheckEnabledComponentHashMisMatch.class,
        RepositoryMetaAnalyzerIT.WithIntegrityCheckEnabledSourceMissingHash.class
})
class RepositoryMetaAnalyzerIT {

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @QuarkusTestResource(WireMockTestResource.class)
    @TestProfile(WithValidPurl.TestProfile.class)
    static class WithValidPurl {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @InjectWireMock
        WireMockServer wireMockServer;

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
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED", "INTEGRITY_CHECK_ENABLED")
                        VALUES ('true', 'test', false, NULL, 1, 'GO_MODULES', 'http://localhost:%d', false, false);
                        """.formatted(wireMockServer.port()));
                ps.execute();
            }

            wireMockServer.stubFor(WireMock.get(WireMock.anyUrl())
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
                                     """.getBytes(), new ContentTypeHeader(MediaType.APPLICATION_JSON))
                            )));
        }

        @AfterEach
        void afterEach() {
            kafkaCompanion.close();
            wireMockServer.shutdown();
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.hyades.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:golang/github.com/acme/acme-lib@9.1.1"))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.REPO_META_ANALYSIS_COMMAND.getName(), "foo", command));

            final List<ConsumerRecord<String, AnalysisResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(AnalysisResult.parser()))
                    .fromTopics(KafkaTopic.REPO_META_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(15))
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
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @QuarkusTestResource(WireMockTestResource.class)
    @TestProfile(WithIntegrityCheckEnabledComponentMissingHash.TestProfile.class)
    static class WithIntegrityCheckEnabledComponentMissingHash {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @InjectWireMock
        WireMockServer wireMockServer;

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
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED", "INTEGRITY_CHECK_ENABLED")
                        VALUES ('true', 'test', false, NULL, 1, 'MAVEN', 'http://localhost:%d', false, true);
                        """.formatted(wireMockServer.port()));
                ps.execute();
            }

            wireMockServer.stubFor(WireMock.get(WireMock.anyUrl())
                    .willReturn(WireMock.aResponse()
                            .withStatus(200)
                            .withResponseBody(Body.ofBinaryOrText("""
                                                                        
                                    """.getBytes(), new ContentTypeHeader(MediaType.APPLICATION_JSON))
                            )
                            .withHeader("X-Checksum-MD5", "098f6bcd4621d373cade4e832627b4f6")
                            .withHeader("X-Checksum-SHA1", "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3")
                            .withHeader("X-Checksum-SHA256", "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")));
        }


        @AfterEach
        void afterEach() {
            kafkaCompanion.close();
            wireMockServer.shutdown();
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.hyades.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2.2"))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.INTEGRITY_ANALYSIS_COMMAND.getName(), "pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2.2", command));

            final List<ConsumerRecord<String, IntegrityResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(IntegrityResult.parser()))
                    .fromTopics(KafkaTopic.INTEGRITY_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();

            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2.2");
                        assertThat(record.value()).isNotNull();
                        final IntegrityResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.getMd5HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_COMPONENT_MISSING_HASH.getNumber());
                        assertThat(result.getSha1HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_COMPONENT_MISSING_HASH.getNumber());
                        assertThat(result.getSha256HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_COMPONENT_MISSING_HASH.getNumber());
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @QuarkusTestResource(WireMockTestResource.class)

    @TestProfile(WithIntegrityCheckEnabledComponentHashMatch.TestProfile.class)
    static class WithIntegrityCheckEnabledComponentHashMatch {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @InjectWireMock
        WireMockServer wireMockServer;

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
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED", "INTEGRITY_CHECK_ENABLED")
                        VALUES ('true', 'test', false, NULL, 1, 'MAVEN', 'http://localhost:%d', false, true);
                        """.formatted(wireMockServer.port()));
                ps.execute();
            }

            wireMockServer.stubFor(WireMock.head(WireMock.anyUrl())
                    .willReturn(WireMock.aResponse()
                            .withStatus(200)
                            .withResponseBody(Body.ofBinaryOrText("""
                                                                        
                                    """.getBytes(), new ContentTypeHeader(MediaType.APPLICATION_JSON))
                            )
                            .withHeader("X-Checksum-MD5", "098f6bcd4621d373cade4e832627b4f6")
                            .withHeader("X-Checksum-SHA1", "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3")
                            .withHeader("X-Checksum-SHA256", "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")));
        }

        @AfterEach
        void afterEach() {
            kafkaCompanion.close();
            wireMockServer.shutdown();
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.hyades.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2.2?type=jar")
                            .setMd5Hash("098f6bcd4621d373cade4e832627b4f6")
                            .setSha1Hash("a94a8fe5ccb19ba61c4c0873d391e987982fbbd3")
                            .setSha256Hash("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
                            .setUuid(UUID.randomUUID().toString()))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.INTEGRITY_ANALYSIS_COMMAND.getName(), "pkg:maven/com.fasterxml.jackson.core/jackson-databind", command));

            final List<ConsumerRecord<String, IntegrityResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(IntegrityResult.parser()))
                    .fromTopics(KafkaTopic.INTEGRITY_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(10))
                    .awaitCompletion()
                    .getRecords();

            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:maven/com.fasterxml.jackson.core/jackson-databind");
                        assertThat(record.value()).isNotNull();
                        final IntegrityResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.getMd5HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_PASS.getNumber());
                        assertThat(result.getSha1HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_PASS.getNumber());
                        assertThat(result.getSha256HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_PASS.getNumber());
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @QuarkusTestResource(WireMockTestResource.class)
    @TestProfile(WithIntegrityCheckEnabledComponentHashMisMatch.TestProfile.class)
    static class WithIntegrityCheckEnabledComponentHashMisMatch {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @InjectWireMock
        WireMockServer wireMockServer;

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
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED", "INTEGRITY_CHECK_ENABLED")
                        VALUES ('true', 'test', false, NULL, 1, 'MAVEN', 'http://localhost:%d', false, true);
                        """.formatted(wireMockServer.port()));
                ps.execute();
            }

            wireMockServer.stubFor(WireMock.head(WireMock.anyUrl())
                    .willReturn(WireMock.aResponse()
                            .withStatus(200)
                            .withResponseBody(Body.ofBinaryOrText("""
                                                                        
                                    """.getBytes(), new ContentTypeHeader(MediaType.APPLICATION_JSON))
                            )
                            .withHeader("X-Checksum-MD5", "098f6bcd4621d373cade4e83262744f6")
                            .withHeader("X-Checksum-SHA1", "a94a8fe5ccb19ba61c4c0873d391e987982fbbd2")
                            .withHeader("X-Checksum-SHA256", "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a68")));
        }

        @AfterEach
        void afterEach() {
            kafkaCompanion.close();
            wireMockServer.shutdown();
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.hyades.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2.2?type=jar")
                            .setMd5Hash("098f6bcd4621d373cade4e832627b4f6")
                            .setSha1Hash("a94a8fe5ccb19ba61c4c0873d391e987982fbbd3")
                            .setSha256Hash("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
                            .setUuid(UUID.randomUUID().toString()))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.INTEGRITY_ANALYSIS_COMMAND.getName(), "pkg:maven/com.fasterxml.jackson.core/jackson-databind", command));

            final List<ConsumerRecord<String, IntegrityResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(IntegrityResult.parser()))
                    .fromTopics(KafkaTopic.INTEGRITY_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();

            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:maven/com.fasterxml.jackson.core/jackson-databind");
                        assertThat(record.value()).isNotNull();
                        final IntegrityResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.getMd5HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_FAIL.getNumber());
                        assertThat(result.getSha1HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_FAIL.getNumber());
                        assertThat(result.getSha256HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_FAIL.getNumber());
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @QuarkusTestResource(WireMockTestResource.class)
    @TestProfile(WithIntegrityCheckEnabledSourceMissingHash.TestProfile.class)
    static class WithIntegrityCheckEnabledSourceMissingHash {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @InjectWireMock
        WireMockServer wireMockServer;

        @AfterEach
        void afterEach() {
            kafkaCompanion.close();
            wireMockServer.shutdown();
        }

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
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED", "INTEGRITY_CHECK_ENABLED")
                        VALUES ('true', 'test', false, NULL, 1, 'MAVEN', 'http://localhost:%d', false, true);
                        """.formatted(wireMockServer.port()));
                ps.execute();
            }

            wireMockServer.stubFor(WireMock.head(WireMock.anyUrl())
                    .willReturn(WireMock.aResponse()
                            .withStatus(200)
                            .withResponseBody(Body.ofBinaryOrText("""
                                                                        
                                    """.getBytes(), new ContentTypeHeader(MediaType.APPLICATION_JSON))
                            )));
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.hyades.proto.repometaanalysis.v1.Component.newBuilder()
                            .setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2.2?type=jar")
                            .setMd5Hash("098f6bcd4621d373cade4e832627b4f6")
                            .setSha1Hash("a94a8fe5ccb19ba61c4c0873d391e987982fbbd3")
                            .setSha256Hash("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
                            .setUuid(UUID.randomUUID().toString()))
                    .build();

            kafkaCompanion
                    .produce(Serdes.String(), new KafkaProtobufSerde<>(AnalysisCommand.parser()))
                    .fromRecords(new ProducerRecord<>(KafkaTopic.INTEGRITY_ANALYSIS_COMMAND.getName(), "pkg:maven/com.fasterxml.jackson.core/jackson-databind", command));

            final List<ConsumerRecord<String, IntegrityResult>> results = kafkaCompanion
                    .consume(Serdes.String(), new KafkaProtobufSerde<>(IntegrityResult.parser()))
                    .fromTopics(KafkaTopic.INTEGRITY_ANALYSIS_RESULT.getName(), 1, Duration.ofSeconds(5))
                    .awaitCompletion()
                    .getRecords();

            assertThat(results).satisfiesExactly(
                    record -> {
                        assertThat(record.key()).isEqualTo("pkg:maven/com.fasterxml.jackson.core/jackson-databind");
                        assertThat(record.value()).isNotNull();
                        final IntegrityResult result = record.value();
                        assertThat(result.hasComponent()).isTrue();
                        assertThat(result.getMd5HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_UNKNOWN.getNumber());
                        assertThat(result.getSha1HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_UNKNOWN.getNumber());
                        assertThat(result.getSha256HashMatchValue()).isEqualTo(HashMatchStatus.HASH_MATCH_STATUS_UNKNOWN.getNumber());
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @QuarkusTestResource(WireMockTestResource.class)
    static class WithInvalidPurl {

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @InjectWireMock
        WireMockServer wireMockServer;

        @BeforeEach
        void beforeEach() throws Exception {
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED", "INTEGRITY_CHECK_ENABLED")
                        VALUES ('true', 'test', false, NULL, 2, 'NPM', 'http://localhost:%d', false, false);
                        """.formatted(wireMockServer.port()));
                ps.execute();
            }
        }

        @AfterEach
        void afterEach() {
            kafkaCompanion.close();
            wireMockServer.shutdown();
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.hyades.proto.repometaanalysis.v1.Component.newBuilder()
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
    @QuarkusTestResource(WireMockTestResource.class)
    @TestProfile(NoCapableAnalyzer.TestProfile.class)
    static class NoCapableAnalyzer {

        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @InjectWireMock
        WireMockServer wireMockServer;

        @BeforeEach
        void beforeEach() throws Exception {
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        <<<<<<< HEAD
                                                INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED", "INTEGRITY_CHECK_ENABLED")
                                                VALUES ('true', 'test', false, NULL, 2, 'CPAN', 'http://localhost:%d', false, false);
                        =======
                                                INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED")
                                                VALUES ('true', 'test', false, NULL, 2, 'CPAN', 'http://localhost:%d', false);
                        >>>>>>> 7e7d0f0c7922b1a526123a937642cfdc2d45f7d9
                                                """.formatted(wireMockServer.port()));
                ps.execute();
            }
        }

        @AfterEach
        void afterEach() {
            kafkaCompanion.close();
            wireMockServer.shutdown();
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.hyades.proto.repometaanalysis.v1.Component.newBuilder()
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
                    }
            );
        }
    }

    @QuarkusIntegrationTest
    @QuarkusTestResource(KafkaCompanionResource.class)
    @QuarkusTestResource(WireMockTestResource.class)
    @TestProfile(InternalAnalyzerNonInternalComponent.TestProfile.class)
    static class InternalAnalyzerNonInternalComponent {


        public static class TestProfile implements QuarkusTestProfile {
        }

        @InjectKafkaCompanion
        KafkaCompanion kafkaCompanion;

        @InjectWireMock
        WireMockServer wireMockServer;

        @AfterEach
        void afterEach() {
            kafkaCompanion.close();
            wireMockServer.shutdown();
        }

        @BeforeEach
        void beforeEach() throws Exception {
            try (final Connection connection = DriverManager.getConnection(
                    ConfigProvider.getConfig().getValue("quarkus.datasource.jdbc.url", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class),
                    ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class))) {
                final PreparedStatement ps = connection.prepareStatement("""
                        INSERT INTO "REPOSITORY" ("ENABLED", "IDENTIFIER", "INTERNAL", "PASSWORD", "RESOLUTION_ORDER", "TYPE", "URL", "AUTHENTICATIONREQUIRED", "INTEGRITY_CHECK_ENABLED")
                        VALUES ('true', 'test', true, NULL, 2, 'MAVEN', 'http://localhost:%d', false, false);
                        """.formatted(wireMockServer.port()));
                ps.execute();
            }
        }

        @Test
        void test() {
            final var command = AnalysisCommand.newBuilder()
                    .setComponent(org.hyades.proto.repometaanalysis.v1.Component.newBuilder()
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
                    }
            );
        }
    }
}
