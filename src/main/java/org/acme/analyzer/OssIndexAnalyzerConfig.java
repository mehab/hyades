package org.acme.analyzer;

import io.micrometer.core.instrument.binder.cache.JCacheMetrics;
import io.micrometer.prometheus.PrometheusMeterRegistry;
import org.acme.client.ossindex.ComponentReport;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import javax.cache.Cache;
import javax.cache.CacheManager;
import javax.cache.configuration.MutableConfiguration;
import javax.cache.expiry.CreatedExpiryPolicy;
import javax.enterprise.context.Dependent;
import javax.enterprise.inject.Produces;
import javax.inject.Named;
import java.time.Duration;
import java.util.concurrent.TimeUnit;

@Dependent
class OssIndexAnalyzerConfig {

    @Produces
    @Named("ossIndexCache")
    Cache<String, ComponentReport> cache(final CacheManager cacheManager,
                                         @ConfigProperty(name = "scanner.ossindex.cache.validity.period") final Duration validityPeriod,
                                         final PrometheusMeterRegistry meterRegistry) {
        final var configuration = new MutableConfiguration<String, ComponentReport>()
                .setStatisticsEnabled(true)
                .setTypes(String.class, ComponentReport.class)
                .setExpiryPolicyFactory(() ->
                        new CreatedExpiryPolicy(new javax.cache.expiry.Duration(TimeUnit.SECONDS, validityPeriod.toSeconds())));

        final Cache<String, ComponentReport> cache = cacheManager.createCache("ossindex", configuration);
        JCacheMetrics.monitor(meterRegistry, cache);
        return cache;
    }

}
