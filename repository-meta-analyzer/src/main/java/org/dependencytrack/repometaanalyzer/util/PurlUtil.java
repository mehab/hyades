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
package org.dependencytrack.repometaanalyzer.util;

import com.github.packageurl.MalformedPackageURLException;
import com.github.packageurl.PackageURL;

public final class PurlUtil {

    private PurlUtil() {
    }

    /**
     * @param purl the purl string to parse
     * @return a PackageURL object
     */
    public static PackageURL parsePurl(final String purl) {
        try {
            return new PackageURL(purl);
        } catch (MalformedPackageURLException e) {
            throw new IllegalStateException("""
                    The provided PURL is invalid, even though it should have been \
                    validated in a previous processing step""", e);
        }
    }

    /**
     * @param purl the purl string to parse
     * @return a PackageURL object
     */
    public static PackageURL parsePurlCoordinatesWithoutVersion(final String purl) {
        try {
            final var parsedPurl = new PackageURL(purl);
            return new PackageURL(parsedPurl.getType(), parsedPurl.getNamespace(),
                    parsedPurl.getName(), null, null, null);
        } catch (MalformedPackageURLException e) {
            throw new IllegalStateException("""
                    The provided PURL is invalid, even though it should have been \
                    validated in a previous processing step""", e);
        }
    }
}
