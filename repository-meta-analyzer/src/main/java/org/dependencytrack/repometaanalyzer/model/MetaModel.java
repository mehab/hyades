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
package org.dependencytrack.repometaanalyzer.model;

import org.dependencytrack.persistence.model.Component;

import java.io.Serializable;
import java.util.Date;

public class MetaModel implements Serializable {

    private Component component;
    private String latestVersion;
    private Date publishedTimestamp;
    private String sourceRepository;

    public MetaModel(){
    }
    public MetaModel(final Component component) {
        this.component = component;
    }

    public Component getComponent() {
        return component;
    }

    public String getLatestVersion() {
        return latestVersion;
    }

    public void setLatestVersion(final String latestVersion) {
        this.latestVersion = latestVersion;
    }

    public Date getPublishedTimestamp() {
        return publishedTimestamp;
    }

    public void setPublishedTimestamp(final Date publishedTimestamp) {
        this.publishedTimestamp = publishedTimestamp;
    }

    public String getSourceRepository() {
        return sourceRepository;
    }
    public void setSourceRepository(String sourceRepository) {
        this.sourceRepository = sourceRepository;
    }
}
