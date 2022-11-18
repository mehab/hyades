package org.acme.client.snyk;

import org.acme.model.Cwe;
import org.acme.model.Severity;
import org.acme.model.Vulnerability;
import org.acme.model.VulnerabilityAlias;
import org.acme.parser.common.resolver.CweResolver;
import org.acme.util.JsonUtil;

import java.math.BigDecimal;
import java.time.chrono.ChronoZonedDateTime;
import java.util.Date;
import java.util.Objects;
import java.util.Optional;
import java.util.stream.Collectors;

public final class ModelConverter {

    private ModelConverter() {
    }

    public static Vulnerability convert(final CweResolver cweResolver, final SeveritySource severitySource, final Issue issue) {
        final var vuln = new Vulnerability();
        vuln.setVulnId(issue.key());
        vuln.setSource(Vulnerability.Source.SNYK);
        vuln.setTitle(issue.title());
        vuln.setDescription(issue.description());
        Optional.ofNullable(issue.createdAt())
                .map(JsonUtil::jsonStringToTimestamp)
                .map(ChronoZonedDateTime::toInstant)
                .map(Date::from)
                .ifPresent(vuln::setCreated);
        Optional.ofNullable(issue.updatedAt())
                .map(JsonUtil::jsonStringToTimestamp)
                .map(ChronoZonedDateTime::toInstant)
                .map(Date::from)
                .ifPresent(vuln::setUpdated);
        if (issue.problems() != null) {
            vuln.setAliases(issue.problems().stream()
                    .map(problem -> convert(vuln.getVulnId(), problem))
                    .filter(Objects::nonNull)
                    .toList());
            issue.problems().stream()
                    .map(problem -> convert(cweResolver, problem))
                    .filter(Objects::nonNull)
                    .forEach(vuln::addCwe);
        }
        if (issue.severities() != null) {
            issue.severities().stream()
                    .filter(severity -> severitySource.equals(severity.source()))
                    .filter(severity -> severity.score() != null && !severity.vector().isBlank())
                    .findFirst()
                    .ifPresent(severity -> {
                        vuln.setSeverity(switch (severity.level()) {
                            case "CRITICAL" -> Severity.CRITICAL;
                            case "HIGH" -> Severity.HIGH;
                            case "MEDIUM" -> Severity.MEDIUM;
                            case "LOW" -> Severity.LOW;
                            default -> Severity.UNASSIGNED;
                        });
                        vuln.setCvssV3BaseScore(BigDecimal.valueOf(severity.score()));
                        vuln.setCvssV3Vector(severity.vector());
                    });
        }
        if (issue.slots() != null && issue.slots().references() != null) {
            vuln.setReferences(issue.slots().references().stream()
                    .map(reference -> "* [%s](%s)".formatted(reference.title(), reference.url()))
                    .collect(Collectors.joining("\n")));
        }
        return vuln;
    }

    private static Cwe convert(final CweResolver cweResolver, final Problem problem) {
        if ("CWE".equals(problem.source())) {
            return cweResolver.resolve(problem.id());
        }
        return null;
    }

    private static VulnerabilityAlias convert(final String vulnId, final Problem problem) {
        return switch (problem.source()) {
            case "CVE" -> {
                final var alias = new VulnerabilityAlias();
                alias.setSnykId(vulnId);
                alias.setCveId(problem.id());
                yield alias;
            }
            case "GHSA" -> {
                final var alias = new VulnerabilityAlias();
                alias.setSnykId(vulnId);
                alias.setGhsaId(problem.id());
                yield alias;
            }
            default -> null;
        };
    }

}
