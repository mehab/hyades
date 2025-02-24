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
package org.dependencytrack.repometaanalyzer.processor;

import com.github.packageurl.PackageURL;
import com.google.protobuf.util.Timestamps;
import io.quarkus.cache.Cache;
import io.quarkus.narayana.jta.QuarkusTransaction;
import org.apache.kafka.streams.processor.api.ContextualFixedKeyProcessor;
import org.apache.kafka.streams.processor.api.FixedKeyRecord;
import org.dependencytrack.common.SecretDecryptor;
import org.dependencytrack.persistence.model.Repository;
import org.dependencytrack.persistence.model.RepositoryType;
import org.dependencytrack.persistence.repository.RepoEntityRepository;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisCommand;
import org.dependencytrack.proto.repometaanalysis.v1.AnalysisResult;
import org.dependencytrack.proto.repometaanalysis.v1.Component;
import org.dependencytrack.repometaanalyzer.model.IntegrityMeta;
import org.dependencytrack.repometaanalyzer.model.MetaAnalyzerCacheKey;
import org.dependencytrack.repometaanalyzer.model.MetaModel;
import org.dependencytrack.repometaanalyzer.repositories.IMetaAnalyzer;
import org.dependencytrack.repometaanalyzer.repositories.RepositoryAnalyzerFactory;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;

import java.util.List;
import java.util.NoSuchElementException;
import java.util.Optional;

import static org.dependencytrack.repometaanalyzer.util.PurlUtil.parsePurl;
import static org.dependencytrack.repometaanalyzer.util.PurlUtil.parsePurlCoordinatesWithoutVersion;

class MetaAnalyzerProcessor extends ContextualFixedKeyProcessor<PackageURL, AnalysisCommand, AnalysisResult> {

    private static final Logger LOGGER = LoggerFactory.getLogger(MetaAnalyzerProcessor.class);

    private static final String MDC_COMPONENT_PURL = "componentPurl";
    private static final String MDC_REPOSITORY = "repository";

    private final RepoEntityRepository repoEntityRepository;
    private final RepositoryAnalyzerFactory analyzerFactory;
    private final SecretDecryptor secretDecryptor;
    private final Cache cache;

    MetaAnalyzerProcessor(
            final RepoEntityRepository repoEntityRepository,
            final RepositoryAnalyzerFactory analyzerFactory,
            final SecretDecryptor secretDecryptor,
            final Cache cache
    ) {
        this.repoEntityRepository = repoEntityRepository;
        this.analyzerFactory = analyzerFactory;
        this.secretDecryptor = secretDecryptor;
        this.cache = cache;
    }

    @Override
    public void process(final FixedKeyRecord<PackageURL, AnalysisCommand> record) {
        final AnalysisCommand analysisCommand = record.value();
        final Component component = analysisCommand.getComponent();
        final PackageURL purl = parsePurl(component.getPurl());

        final Optional<IMetaAnalyzer> analyzer = analyzerFactory.createAnalyzer(purl);
        if (analyzer.isEmpty()) {
            if (LOGGER.isDebugEnabled()) {
                LOGGER.debug("No analyzer is capable of analyzing {}", purl);
            }

            context().forward(record
                    .withValue(AnalysisResult.newBuilder().setComponent(component).build())
                    .withTimestamp(context().currentSystemTimeMs()));
            return;
        }

        final AnalysisResult result;
        try (var ignoredMdcComponentPurl = MDC.putCloseable(MDC_COMPONENT_PURL, component.getPurl())) {
            result = analyzeComponent(analyzer.get(), component);
        }

        context().forward(record.withValue(result).withTimestamp(context().currentSystemTimeMs()));
    }

    private AnalysisResult analyzeComponent(final IMetaAnalyzer analyzer, final Component component) {
        final List<Repository> applicableRepositories = getApplicableRepositories(analyzer.supportedRepositoryType());
        final Optional<MetaModel> optionalRepoMeta = performRepoMetaAnalysis(applicableRepositories, analyzer, component);
        final Optional<IntegrityMeta> optionalIntegrityMeta = performIntegrityMetaAnalysis(applicableRepositories, analyzer, component);

        final AnalysisResult.Builder resultBuilder = AnalysisResult.newBuilder()
                .setComponent(component);

        if (optionalRepoMeta.isPresent()) {
            final MetaModel repoMeta = optionalRepoMeta.get();
            resultBuilder.setLatestVersion(repoMeta.getLatestVersion());
            resultBuilder.setFetchedAt(Timestamps.fromDate(repoMeta.getFetchedAt()));
            Optional.ofNullable(repoMeta.getRepositoryIdentifier()).ifPresent(resultBuilder::setRepository);
            Optional.ofNullable(repoMeta.getPublishedTimestamp())
                    .map(Timestamps::fromDate)
                    .ifPresent(resultBuilder::setPublished);
        } else if (LOGGER.isDebugEnabled()) {
            LOGGER.debug("No repository metadata found");
        }

        if (optionalIntegrityMeta.isPresent()) {
            final IntegrityMeta integrityMeta = optionalIntegrityMeta.get();
            resultBuilder.setIntegrityMeta(convert(integrityMeta));
        } else if (LOGGER.isDebugEnabled()) {
            LOGGER.debug("No integrity meta found");
        }

        return resultBuilder.build();
    }

    private List<Repository> getApplicableRepositories(final RepositoryType repositoryType) {
        // Hibernate requires an active transaction to perform any sort of interaction
        // with the database. Because processors can't be CDI beans, we cannot use
        // @Transactional and the like. Falling back to manual transaction management.
        //
        // NOTE: The result of this query can potentially be cached for at least a few minutes.
        // Executing it for every single component feels excessive.
        // Quarkus has Hibernate L2 cache enabled by default, we just need to opt in to using
        // it for this query: https://quarkus.io/guides/hibernate-orm#caching-of-queries
        // Should be tested whether throughput can be improved this way.
        return QuarkusTransaction.joiningExisting()
                .call(() -> repoEntityRepository.findEnabledRepositoriesByType(repositoryType));
    }

    private IntegrityMeta fetchIntegrityMeta(
            final IMetaAnalyzer analyzer,
            final Repository repository,
            final Component component
    ) {
        configureAnalyzer(analyzer, repository);

        // Analyzers still work with "legacy" data models,
        // allowing us to avoid major refactorings of the original code.
        final var metaComponent = new org.dependencytrack.persistence.model.Component();
        metaComponent.setPurl(component.getPurl());

        try {
            return analyzer.getIntegrityMeta(metaComponent);
        } catch (UnsupportedOperationException e) {
            LOGGER.debug("Package type is not supported");
            return null;
        } catch (Exception e) {
            LOGGER.error("Failed to fetch integrity metadata", e);
            return null;
        }
    }

    private MetaModel fetchRepoMeta(
            final IMetaAnalyzer analyzer,
            final Repository repository,
            final Component component
    ) {
        configureAnalyzer(analyzer, repository);

        // Analyzers still work with "legacy" data models,
        // allowing us to avoid major refactorings of the original code.
        final var metaComponent = new org.dependencytrack.persistence.model.Component();
        metaComponent.setPurl(component.getPurl());

        try {
            return analyzer.analyze(metaComponent);
        } catch (Exception e) {
            LOGGER.error("Failed to fetch repository metadata", e);
            return null;
        }
    }

    private void configureAnalyzer(final IMetaAnalyzer analyzer, final Repository repository) {
        analyzer.setRepositoryBaseUrl(repository.getUrl());
        boolean isAuthenticationRequired = Optional.ofNullable(repository.isAuthenticationRequired()).orElse(false);
        if (isAuthenticationRequired) {
            try {
                analyzer.setRepositoryUsernameAndPassword(repository.getUsername(), secretDecryptor.decryptAsString(repository.getPassword()));
            } catch (Exception e) {
                LOGGER.error("Failed to decrypt password", e);
            }
        }
    }

    private Optional<MetaModel> performRepoMetaAnalysis(
            final List<Repository> applicableRepositories,
            final IMetaAnalyzer analyzer,
            final Component component
    ) {
        for (final Repository repository : applicableRepositories) {
            try (var ignoredMdcRepository = MDC.putCloseable(MDC_REPOSITORY, repository.getIdentifier())) {
                final Optional<MetaModel> optionalResult =
                        performRepoMetaAnalysisForRepository(analyzer, component, repository);
                if (optionalResult.isPresent()) {
                    return optionalResult;
                }
            }
        }

        return Optional.empty();
    }

    private Optional<MetaModel> performRepoMetaAnalysisForRepository(
            final IMetaAnalyzer analyzer,
            final Component component,
            final Repository repository
    ) {
        if ((repository.isInternal() && !component.getInternal())
                || (!repository.isInternal() && component.getInternal())) {
            // Internal components should only be analyzed using internal repositories.
            // Non-internal components should only be analyzed with non-internal repositories.
            // We do not want non-internal components being analyzed with internal repositories as
            // internal repositories are not the source of truth for these components, even if the
            // repository acts as a proxy to the source of truth. This cannot be assumed.
            LOGGER.debug("Skipping component with purl {} ", component.getPurl());
            return Optional.empty();
        }

        // NB: Cache key should only include type, namespace and name parts of the PURL,
        // since latest version information will differ based on the input PURLs version
        // or qualifiers.
        //
        // For example: pkg:maven/foo/bar@1.2.3?type=jar
        // would have the same latest version as: pkg:maven/foo/bar@3.2.1?type=pom
        final String purlCoordinatesWithoutVersion = parsePurlCoordinatesWithoutVersion(component.getPurl()).canonicalize();
        final var cacheKey = new MetaAnalyzerCacheKey(analyzer.getName(), purlCoordinatesWithoutVersion, repository.getUrl());

        final Optional<Optional<MetaModel>> cacheEntry = getCachedResult(cacheKey);
        if (cacheEntry.isPresent()) {
            return cacheEntry.get();
        }

        final MetaModel repoMeta = fetchRepoMeta(analyzer, repository, component);
        if (repoMeta == null || repoMeta.getLatestVersion() == null || repoMeta.getLatestVersion().isBlank()) {
            cacheResult(cacheKey, null);
            return Optional.empty();
        }

        repoMeta.setRepositoryIdentifier(repository.getIdentifier());
        cacheResult(cacheKey, repoMeta);
        return Optional.of(repoMeta);
    }

    private Optional<IntegrityMeta> performIntegrityMetaAnalysis(
            final List<Repository> applicableRepositories,
            final IMetaAnalyzer analyzer,
            final Component component
    ) {
        for (final Repository repository : applicableRepositories) {
            try (var ignoredMdcRepository = MDC.putCloseable(MDC_REPOSITORY, repository.getIdentifier())) {
                final Optional<IntegrityMeta> optionalResult =
                        performIntegrityMetaAnalysisForRepository(analyzer, component, repository);
                if (optionalResult.isPresent()) {
                    return optionalResult;
                }
            }
        }

        return Optional.empty();
    }

    private Optional<IntegrityMeta> performIntegrityMetaAnalysisForRepository(
            final IMetaAnalyzer analyzer,
            final Component component,
            final Repository repository
    ) {
        if ((repository.isInternal() && !component.getInternal())
                || (!repository.isInternal() && component.getInternal())) {
            return Optional.empty();
        }

        // NB: Cache key should include the entire PURL (including version and qualifiers),
        // since integrity data can vary depending on certain qualifiers.
        //
        // For example: pkg:maven/foo/bar@1.2.3?type=jar
        // refers to a different artifact than: pkg:maven/foo/bar@1.2.3?type=pom
        // and thus will have different hashes, too.
        final var cacheKey = new MetaAnalyzerCacheKey(analyzer.getName(), component.getPurl(), repository.getUrl());
        final Optional<Optional<IntegrityMeta>> cacheEntry = getCachedResult(cacheKey);
        if (cacheEntry.isPresent()) {
            return cacheEntry.get();
        }

        final IntegrityMeta integrityMeta = fetchIntegrityMeta(analyzer, repository, component);
        if (integrityMeta == null) {
            cacheResult(cacheKey, null);
            return Optional.empty();
        }

        cacheResult(cacheKey, integrityMeta);
        return Optional.of(integrityMeta);
    }

    private <T> Optional<Optional<T>> getCachedResult(final MetaAnalyzerCacheKey cacheKey) {
        try {
            final T cachedValue = cache.<MetaAnalyzerCacheKey, T>get(cacheKey,
                    key -> {
                        // null values would be cached, so throw an exception instead.
                        // See https://quarkus.io/guides/cache#let-exceptions-bubble-up
                        throw new NoSuchElementException();
                    }).await().indefinitely();
            if (LOGGER.isDebugEnabled()) {
                LOGGER.debug("Cache hit for {}", cachedValue);
            }

            // cachedValue may be null.
            final Optional<T> optionalValue = Optional.ofNullable(cachedValue);

            return Optional.of(optionalValue);
        } catch (Exception e) {
            if (LOGGER.isDebugEnabled()) {
                LOGGER.debug("Cache miss for {}", cacheKey);
            }

            return Optional.empty();
        }
    }

    private <T> void cacheResult(final MetaAnalyzerCacheKey cacheKey, final T result) {
        cache.get(cacheKey, key -> result).await().indefinitely();
    }

    private static org.dependencytrack.proto.repometaanalysis.v1.IntegrityMeta convert(final IntegrityMeta integrityMeta) {
        final var builder = org.dependencytrack.proto.repometaanalysis.v1.IntegrityMeta.newBuilder();
        builder.setFetchedAt(Timestamps.fromDate(integrityMeta.getFetchedAt()));
        Optional.ofNullable(integrityMeta.getMd5()).ifPresent(builder::setMd5);
        Optional.ofNullable(integrityMeta.getSha1()).ifPresent(builder::setSha1);
        Optional.ofNullable(integrityMeta.getSha256()).ifPresent(builder::setSha256);
        Optional.ofNullable(integrityMeta.getSha512()).ifPresent(builder::setSha512);
        Optional.ofNullable(integrityMeta.getMetaSourceUrl()).ifPresent(builder::setMetaSourceUrl);
        Optional.ofNullable(integrityMeta.getCurrentVersionLastModified())
                .map(Timestamps::fromDate)
                .ifPresent(builder::setCurrentVersionLastModified);
        return builder.build();
    }

}