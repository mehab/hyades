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

import java.io.IOException;
import java.io.InputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Iterator;
import java.util.Optional;

import org.apache.http.HttpEntity;
import org.apache.http.HttpStatus;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.dependencytrack.persistence.model.Component;
import org.dependencytrack.persistence.model.RepositoryType;
import org.dependencytrack.repometaanalyzer.model.MetaModel;
import org.dependencytrack.repometaanalyzer.util.PurlUtil;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.github.packageurl.PackageURL;

public class DepsDevMetaAnalyzer extends AbstractMetaAnalyzer {
    private static final Logger LOGGER = LoggerFactory.getLogger(DepsDevMetaAnalyzer.class);
    private static final String DEFAULT_BASE_URL = "https://api.deps.dev/v3alpha";
    private static final String API_URL = "/purl/%s";
    private static final String SOURCE_REPO = "SOURCE_REPO";

    DepsDevMetaAnalyzer() {
        this.baseUrl = DEFAULT_BASE_URL;
    }

    @Override
    public boolean isApplicable(Component component) {
        return component.getPurl() != null;
    }

    /**
     * {@inheritDoc}
     */
    public RepositoryType supportedRepositoryType() {
        return null; // Supported values for type are cargo, golang, maven, npm, nuget and pypi. 
    }

    /**
     * {@inheritDoc}
     */
    public MetaModel analyze(final Component component) {
        final MetaModel meta = new MetaModel(component);
        final PackageURL purl = component.getPurl();
        if (purl != null) {
            PackageURL coords = PurlUtil.silentPurlCoordinatesOnly(purl);
            if (coords != null) {
                String encodedCoords = URLEncoder.encode(coords.canonicalize(), StandardCharsets.UTF_8);
                final String url = String.format(baseUrl + API_URL, encodedCoords);
                try (final CloseableHttpResponse response = processHttpRequest(url)) {
                    if (response.getStatusLine().getStatusCode() == HttpStatus.SC_OK &&
                        response.getEntity() != null) {
                        Optional<String> sourceRepo = extractSourceRepo(response.getEntity());
                        sourceRepo.ifPresent(meta::setSourceRepository);
                    }
                } catch (IOException | JSONException e) {
                    handleRequestException(LOGGER, e);
                }
            }
        }
        return meta;
    }

    private Optional<String> extractSourceRepo(HttpEntity entity) throws IOException, JSONException {
        try (InputStream in = entity.getContent()) {
            JSONObject version = new JSONObject(new JSONTokener(in)).getJSONObject("version");

            // Try to read the repo url from the links section
            JSONArray links = version.getJSONArray("links");
            if (links != null) {
                Iterator<Object> it = links.iterator();
                while(it.hasNext()) {
                    JSONObject link = (JSONObject)it.next();
                    if (SOURCE_REPO.equals(link.getString("label"))) {
                        return Optional.of(link.getString("url"));
                    }
                }
            }
        }
        return Optional.empty();
    }

    @Override
    public String getName() {
        return this.getClass().getSimpleName();
    }
    
}
