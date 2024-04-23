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
package org.dependencytrack.config;

import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.IvParameterSpec;
import java.util.Base64;

class PskSecretKeysHandler implements io.smallrye.config.SecretKeysHandler {

    static final String NAME = "dtrack-psk";

    private final SecretKey secretKey;

    PskSecretKeysHandler(final SecretKey secretKey) {
        this.secretKey = secretKey;
    }

    @Override
    public String decode(final String secret) {
        try {
            return decryptAsString(secret);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public String getName() {
        return NAME;
    }

    /**
     * Decrypts the specified bytes using AES-256.
     * <p>
     * Ported from Alpine's {@code DataEncryption} class.
     *
     * @param encryptedIvTextBytes the text to decrypt
     * @return the decrypted bytes
     * @throws Exception a number of exceptions may be thrown
     * @see <a href="https://github.com/stevespringett/Alpine/blob/alpine-parent-2.2.0/alpine-infra/src/main/java/alpine/security/crypto/DataEncryption.java">Alpine DataEncryption</a>
     */
    public byte[] decryptAsBytes(final byte[] encryptedIvTextBytes) throws Exception {
        // NB(nscuro): Added null and length checks to prevent encountering low-level
        // exceptions later on (i.e. out-of-bounds exceptions during array copying).
        if (encryptedIvTextBytes == null) {
            throw new IllegalArgumentException("Encrypted value must not be null");
        }
        if (encryptedIvTextBytes.length % 16 != 0) {
            throw new IllegalArgumentException("Length of encrypted value must be a multiple of 16, but was %d"
                    .formatted(encryptedIvTextBytes.length));
        }

        int ivSize = 16;

        // Extract IV
        final byte[] iv = new byte[ivSize];
        System.arraycopy(encryptedIvTextBytes, 0, iv, 0, iv.length);
        final IvParameterSpec ivParameterSpec = new IvParameterSpec(iv);

        // Extract encrypted bytes
        final int encryptedSize = encryptedIvTextBytes.length - ivSize;
        final byte[] encryptedBytes = new byte[encryptedSize];
        System.arraycopy(encryptedIvTextBytes, ivSize, encryptedBytes, 0, encryptedSize);

        // Decrypt
        final Cipher cipherDecrypt = Cipher.getInstance("AES/CBC/PKCS5Padding");
        cipherDecrypt.init(Cipher.DECRYPT_MODE, secretKey, ivParameterSpec);
        return cipherDecrypt.doFinal(encryptedBytes);
    }

    /**
     * Decrypts the specified string using AES-256. The encryptedText is
     * expected to be the Base64 encoded representation of the encrypted bytes.
     * <p>
     * Ported from Alpine's {@code DataEncryption} class.
     *
     * @param encryptedText the text to decrypt
     * @return the decrypted string
     * @throws Exception a number of exceptions may be thrown
     * @see <a href="https://github.com/stevespringett/Alpine/blob/alpine-parent-2.2.0/alpine-infra/src/main/java/alpine/security/crypto/DataEncryption.java">Alpine DataEncryption</a>
     */
    public String decryptAsString(final String encryptedText) throws Exception {
        return new String(decryptAsBytes(Base64.getDecoder().decode(encryptedText)));
    }

}
