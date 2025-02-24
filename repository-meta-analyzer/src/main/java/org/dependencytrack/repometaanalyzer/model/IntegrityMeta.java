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

import java.io.Serializable;
import java.util.Date;

public class IntegrityMeta implements Serializable {

    private String md5;

    private String sha1;

    private String sha256;

    private String sha512;

    private Date currentVersionLastModified;

    private String metaSourceUrl;

    private final Date fetchedAt = new Date();

    public String getMd5() {
        return md5;
    }

    public void setMd5(String md5) {
        this.md5 = md5;
    }

    public String getSha1() {
        return sha1;
    }

    public void setSha1(String sha1) {
        this.sha1 = sha1;
    }

    public String getSha256() {
        return sha256;
    }

    public void setSha256(String sha256) {
        this.sha256 = sha256;
    }

    public Date getCurrentVersionLastModified() {
        return currentVersionLastModified;
    }

    public void setCurrentVersionLastModified(Date currentVersionLastModified) {
        this.currentVersionLastModified = currentVersionLastModified;
    }

    public void setSha512(String sha512) {
        this.sha512 = sha512;
    }

    public String getSha512() {
        return sha512;
    }

    public String getMetaSourceUrl() {
        return metaSourceUrl;
    }

    public void setMetaSourceUrl(String metaSourceUrl) {
        this.metaSourceUrl = metaSourceUrl;
    }

    public Date getFetchedAt() {
        return fetchedAt;
    }

}