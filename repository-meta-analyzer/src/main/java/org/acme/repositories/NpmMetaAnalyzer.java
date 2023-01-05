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
 * Copyright (c) Steve Springett. All Rights Reserved.
 */
package org.acme.repositories;

import alpine.common.logging.Logger;
import com.github.packageurl.PackageURL;
import org.acme.common.ManagedHttpClient;
import org.acme.common.ManagedHttpClientFactory;
import org.acme.commonutil.HttpUtil;
import org.acme.model.Component;
import org.acme.model.MetaModel;
import org.acme.model.RepositoryType;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpUriRequest;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.util.EntityUtils;
import org.json.JSONObject;

import javax.enterprise.context.ApplicationScoped;
import javax.inject.Inject;
import java.io.IOException;

/**
 * An IMetaAnalyzer implementation that supports NPM.
 *
 * @author Steve Springett
 * @since 3.1.0
 */
@ApplicationScoped
public class NpmMetaAnalyzer extends AbstractMetaAnalyzer {

    private static final Logger LOGGER = Logger.getLogger(NpmMetaAnalyzer.class);
    private static final String DEFAULT_BASE_URL = "https://registry.npmjs.org";
    private static final String API_URL = "/-/package/%s/dist-tags";

    NpmMetaAnalyzer() {
        this.baseUrl = DEFAULT_BASE_URL;
    }

    @Inject
    ManagedHttpClientFactory managedHttpClientFactory;

    /**
     * {@inheritDoc}
     */
    public boolean isApplicable(final Component component) {
        return component.getPurl() != null && PackageURL.StandardTypes.NPM.equals(component.getPurl().getType());
    }

    /**
     * {@inheritDoc}
     */
    public RepositoryType supportedRepositoryType() {
        return RepositoryType.NPM;
    }

    /**
     * {@inheritDoc}
     */
    public MetaModel analyze(final Component component) {
        final MetaModel meta = new MetaModel(component);
        if (component.getPurl() != null) {

            final String packageName;
            if (component.getPurl().getNamespace() != null) {
                packageName = component.getPurl().getNamespace().replace("@", "%40") + "%2F" + component.getPurl().getName();
            } else {
                packageName = component.getPurl().getName();
            }

            final String url = String.format(baseUrl + API_URL, packageName);
            try {
                final HttpUriRequest request = new HttpGet(url);
                request.setHeader("accept", "application/json");
                if (username != null || password != null) {
                    request.setHeader("Authorization", HttpUtil.basicAuthHeaderValue(username, password));
                }
                final ManagedHttpClient pooledHttpClient = managedHttpClientFactory.newManagedHttpClient();
                CloseableHttpClient threadSafeClient = pooledHttpClient.getHttpClient();
                try (final CloseableHttpResponse response = threadSafeClient.execute(request)) {
                    if (response.getStatusLine().getStatusCode() == org.apache.http.HttpStatus.SC_OK) {
                        String responseString = EntityUtils.toString(response.getEntity());
                        JSONObject jsonResponse = new JSONObject(responseString);
                        if (responseString != null && jsonResponse != null) {
                            final String latest = jsonResponse.optString("latest");
                            if (latest != null) {
                                meta.setLatestVersion(latest);
                            }
                        }
                    } else {
                        handleUnexpectedHttpResponse(LOGGER, url, response.getStatusLine().getStatusCode(), response.getStatusLine().getReasonPhrase(), component);
                    }
                }

            } catch ( IOException e) {
                handleRequestException(LOGGER, e);
            }
        }
        return meta;
    }

    @Override
    public String getName() {
        return this.getClass().getSimpleName();
    }
}
