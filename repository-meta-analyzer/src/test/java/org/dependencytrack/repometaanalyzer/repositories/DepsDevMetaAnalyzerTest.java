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
package org.dependencytrack.repometaanalyzer.repositories;

import org.apache.http.impl.client.HttpClients;
import org.dependencytrack.persistence.model.Component;
import org.dependencytrack.repometaanalyzer.model.MetaModel;
import org.junit.Assert;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;

class DepsDevMetaAnalyzerTest {
    private static IMetaAnalyzer analyzer;

    @BeforeEach
    void beforeEach() {
        analyzer = new DepsDevMetaAnalyzer();
        analyzer.setHttpClient(HttpClients.createDefault());
    }
    
    @Test
    void testRepoFound() {
        Component component = new Component();
        component.setPurl("pkg:maven/com.googlecode.owasp-java-html-sanitizer/java10-shim@20240325.1");

        Assert.assertTrue(analyzer.isApplicable(component));
        Assert.assertNull(analyzer.supportedRepositoryType());
        MetaModel metaModel = analyzer.analyze(component);
        Assert.assertEquals("https://github.com/OWASP/java-html-sanitizer", metaModel.getSourceRepository());
    }

    @Test
    void testRepoNotFound() {
        Component component = new Component();
        component.setPurl("pkg:maven/org.apache.httpcomponents/httpclient@4.5.14");

        Assert.assertTrue(analyzer.isApplicable(component));
        Assert.assertNull(analyzer.supportedRepositoryType());
        MetaModel metaModel = analyzer.analyze(component);
        Assert.assertNull(metaModel.getSourceRepository());
    }
}
