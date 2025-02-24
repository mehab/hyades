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
package org.dependencytrack.e2e;

import org.apache.commons.io.IOUtils;
import org.dependencytrack.apiserver.model.BomUploadRequest;
import org.dependencytrack.apiserver.model.EventProcessingResponse;
import org.dependencytrack.apiserver.model.WorkflowTokenResponse;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.Container.ExecResult;
import org.testcontainers.containers.GenericContainer;

import java.time.Duration;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

class BomUploadProcessingWithLocalStorageE2ET extends AbstractE2ET {

    @Override
    protected void customizeApiServerContainer(final GenericContainer<?> container) {
        container
                // Ensure other storage extensions are disabled.
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_DATABASE_ENABLED", "false")
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_S3_ENABLED", "false")
                // Enable and configure local storage extension.
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_LOCAL_ENABLED", "true")
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_LOCAL_DIRECTORY", "/tmp/bom-uploads");
    }

    @Override
    protected void customizeVulnAnalyzerContainer(final GenericContainer<?> container) {
        // We don't test analysis here, so don't waste any quota with the OSS Index API.
        container.withEnv("SCANNER_OSSINDEX_ENABLED", "false");
    }

    @Test
    void test() throws Exception {
        // Parse and base64 encode a BOM.
        final byte[] bomBytes = IOUtils.resourceToByteArray("/dtrack-apiserver-4.5.0.bom.json");
        final String bomBase64 = Base64.getEncoder().encodeToString(bomBytes);

        // Upload the BOM.
        final WorkflowTokenResponse response = apiServerClient.uploadBom(new BomUploadRequest("foo", "bar", true, bomBase64));
        assertThat(response.token()).isNotEmpty();

        // Wait up to 15sec for the BOM processing to complete.
        await("BOM processing")
                .atMost(Duration.ofSeconds(15))
                .pollDelay(Duration.ofMillis(250))
                .untilAsserted(() -> {
                    final EventProcessingResponse processingResponse = apiServerClient.isEventBeingProcessed(response.token());
                    assertThat(processingResponse.processing()).isFalse();
                });

        verifyBomDeleted();
    }

    private void verifyBomDeleted() throws Exception {
        final ExecResult dirExistsResult = apiServerContainer.execInContainer("test", "-d", "/tmp/bom-uploads");
        assertThat(dirExistsResult.getExitCode()).withFailMessage("Storage directory was not created").isZero();

        final ExecResult dirEmptyResult = apiServerContainer.execInContainer("ls", "/tmp/bom-uploads");
        assertThat(dirEmptyResult.getStdout()).withFailMessage("BOM was not deleted after processing").isBlank();
    }

}
