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
package org.dependencytrack.notification.config;

import io.github.resilience4j.core.IntervalFunction;
import jakarta.validation.constraints.Positive;

import java.time.Duration;
import java.util.OptionalDouble;

public interface RetryConfig {

    Duration initialDelay();

    @Positive
    int multiplier();

    OptionalDouble randomizationFactor();

    Duration maxDuration();

    static IntervalFunction toIntervalFunction(final RetryConfig config) {
        if (config.randomizationFactor().isPresent()) {
            return IntervalFunction.ofExponentialRandomBackoff(
                    config.initialDelay(),
                    config.multiplier(),
                    config.randomizationFactor().getAsDouble(),
                    config.maxDuration()
            );
        }

        return IntervalFunction.ofExponentialBackoff(
                config.initialDelay(),
                config.multiplier(),
                config.maxDuration()
        );
    }

}
