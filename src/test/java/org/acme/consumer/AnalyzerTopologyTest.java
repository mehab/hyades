package org.acme.consumer;

import io.quarkus.kafka.client.serialization.ObjectMapperDeserializer;
import io.quarkus.kafka.client.serialization.ObjectMapperSerializer;
import io.quarkus.test.junit.QuarkusMock;
import io.quarkus.test.junit.QuarkusTest;
import org.acme.analyzer.OssIndexAnalyzer;
import org.acme.analyzer.SnykAnalyzer;
import org.acme.model.Component;
import org.acme.model.VulnerabilityResult;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.UUIDDeserializer;
import org.apache.kafka.common.serialization.UUIDSerializer;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.TestInputTopic;
import org.apache.kafka.streams.TestOutputTopic;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.TopologyTestDriver;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import javax.inject.Inject;
import java.util.Collections;
import java.util.UUID;

@QuarkusTest
class AnalyzerTopologyTest {

    @Inject
    Topology topology;

    private TopologyTestDriver testDriver;
    private TestInputTopic<UUID, Component> inputTopic;
    private TestOutputTopic<UUID, VulnerabilityResult> outputTopic;
    private OssIndexAnalyzer ossIndexAnalyzerMock;
    private SnykAnalyzer snykAnalyzerMock;

    @BeforeEach
    void beforeEach() {
        ossIndexAnalyzerMock = Mockito.mock(OssIndexAnalyzer.class);
        QuarkusMock.installMockForType(ossIndexAnalyzerMock, OssIndexAnalyzer.class);

        snykAnalyzerMock = Mockito.mock(SnykAnalyzer.class);
        QuarkusMock.installMockForType(snykAnalyzerMock, SnykAnalyzer.class);

        testDriver = new TopologyTestDriver(topology);
        inputTopic = testDriver.createInputTopic("component-analysis", new UUIDSerializer(), new ObjectMapperSerializer<>());
        outputTopic = testDriver.createOutputTopic("component-vuln-analysis-result", new UUIDDeserializer(), new ObjectMapperDeserializer<>(VulnerabilityResult.class));
    }

    @Test
    void testIdentifierSplitting() {
        final TestOutputTopic<String, Component> componentsCpeTopic =
                testDriver.createOutputTopic("component-analysis-cpe", new StringDeserializer(), new ObjectMapperDeserializer<>(Component.class));
        final TestOutputTopic<String, Component> componentPurlTopic =
                testDriver.createOutputTopic("component-analysis-purl", new StringDeserializer(), new ObjectMapperDeserializer<>(Component.class));
        final TestOutputTopic<String, Component> componentSwidTopic =
                testDriver.createOutputTopic("component-analysis-swid", new StringDeserializer(), new ObjectMapperDeserializer<>(Component.class));

        final UUID uuid = UUID.randomUUID();
        final var component = new Component();
        component.setUuid(uuid);
        component.setCpe("cpe:/a:acme:application:9.1.1");
        component.setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2");
        component.setSwidTagId("PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiID8");

        inputTopic.pipeInput(uuid, component);

        Assertions.assertEquals(1, componentsCpeTopic.getQueueSize());
        Assertions.assertEquals(1, componentPurlTopic.getQueueSize());
        Assertions.assertEquals(0, componentSwidTopic.getQueueSize());
    }

    @Test
    void testNoVulnerabilities() {
        Mockito.when(ossIndexAnalyzerMock.analyze(Mockito.any())).thenReturn(Collections.emptyList());
        Mockito.when(snykAnalyzerMock.analyze(Mockito.any())).thenReturn(Collections.emptyList());

        final UUID uuid = UUID.randomUUID();
        final var component = new Component();
        component.setUuid(uuid);
        component.setPurl("pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.13.2");

        inputTopic.pipeInput(uuid, component);

        Assertions.assertTrue(outputTopic.isEmpty());
    }

    @Test
    void testUnknownIdentifier() {
        final UUID uuid = UUID.randomUUID();
        final var component = new Component();
        component.setUuid(uuid);

        inputTopic.pipeInput(uuid, component);

        Assertions.assertEquals(1, outputTopic.getQueueSize());

        final KeyValue<UUID, VulnerabilityResult> record = outputTopic.readKeyValue();
        Assertions.assertEquals(uuid, record.key);
        Assertions.assertEquals(uuid, record.value.getComponent().getUuid());
        Assertions.assertNull(record.value.getIdentity());
        Assertions.assertNull(record.value.getVulnerability());
    }

    @AfterEach
    void afterEach() {
        testDriver.close();
    }

}