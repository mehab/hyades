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

import io.minio.ListObjectsArgs;
import io.minio.MakeBucketArgs;
import io.minio.MinioClient;
import io.minio.Result;
import io.minio.messages.Item;
import org.apache.commons.io.IOUtils;
import org.dependencytrack.apiserver.model.BomUploadRequest;
import org.dependencytrack.apiserver.model.EventProcessingResponse;
import org.dependencytrack.apiserver.model.WorkflowTokenResponse;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.MinIOContainer;
import org.testcontainers.utility.DockerImageName;

import java.time.Duration;
import java.util.Base64;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

class BomUploadProcessingWithS3StorageE2ET extends AbstractE2ET {

    private static final String BOM_UPLOAD_BUCKET_NAME = "bom-upload";

    private MinIOContainer minioContainer;
    private MinioClient minioClient;

    @Override
    @BeforeEach
    void beforeEach() throws Exception {
        minioContainer = new MinIOContainer(DockerImageName.parse("minio/minio:RELEASE.2023-12-14T18-51-57Z"))
                .withNetworkAliases("minio")
                .withNetwork(internalNetwork);
        minioContainer.start();

        minioClient = MinioClient.builder()
                .endpoint(minioContainer.getS3URL())
                .credentials(minioContainer.getUserName(), minioContainer.getPassword())
                .build();
        createBucket();

        super.beforeEach();
    }

    @Override
    protected void customizeApiServerContainer(final GenericContainer<?> container) {
        container
                // Ensure other storage extensions are disabled.
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_DATABASE_ENABLED", "false")
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_LOCAL_ENABLED", "false")
                // Enable and configure S3 storage extension.
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_S3_ENABLED", "true")
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_S3_ENDPOINT", "http://minio:9000")
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_S3_BUCKET", BOM_UPLOAD_BUCKET_NAME)
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_S3_ACCESS_KEY", minioContainer.getUserName())
                .withEnv("BOM_UPLOAD_STORAGE_EXTENSION_S3_SECRET_KEY", minioContainer.getPassword());
    }

    @Override
    protected void customizeVulnAnalyzerContainer(final GenericContainer<?> container) {
        // We don't test analysis here, so don't waste any quota with the OSS Index API.
        container.withEnv("SCANNER_OSSINDEX_ENABLED", "false");
    }

    @Override
    @AfterEach
    void afterEach() throws Exception {
        if (minioClient != null) {
            minioClient.close();
        }
        Optional.ofNullable(minioContainer).ifPresent(GenericContainer::stop);

        super.afterEach();
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

    private void createBucket() throws Exception {
        minioClient.makeBucket(MakeBucketArgs.builder()
                .bucket(BOM_UPLOAD_BUCKET_NAME)
                .build());
    }

    private void verifyBomDeleted() {
        final Iterable<Result<Item>> results = minioClient.listObjects(ListObjectsArgs.builder()
                .bucket(BOM_UPLOAD_BUCKET_NAME)
                .recursive(true)
                .build());

        assertThat(results).isEmpty();
    }

}
