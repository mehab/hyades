package org.acme.repositories;

import io.micrometer.core.instrument.binder.cache.JCacheMetrics;
import io.micrometer.prometheus.PrometheusMeterRegistry;
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
class MetaAnalyzerConfig {

    @Produces
    @Named("metaAnalyzerCache")
    Cache<String, MetaModel> cache(final CacheManager cacheManager,
                                         @ConfigProperty(name = "meta.analyzer.cache.validity.period") final Duration validityPeriod,
                                         final PrometheusMeterRegistry meterRegistry) {
        final var configuration = new MutableConfiguration<String, MetaModel>()
                .setStatisticsEnabled(true)
                .setTypes(String.class, MetaModel.class)
                .setExpiryPolicyFactory(() ->
                        new CreatedExpiryPolicy(new javax.cache.expiry.Duration(TimeUnit.SECONDS, validityPeriod.toSeconds())));

        final Cache<String, MetaModel> cache = cacheManager.createCache("metaAnalyzer", configuration);
        JCacheMetrics.monitor(meterRegistry, cache);
        return cache;
    }

}
