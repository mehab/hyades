
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';

CREATE FUNCTION public."CALC_RISK_SCORE"(critical integer, high integer, medium integer, low integer, unassigned integer) RETURNS numeric
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
WITH "CUSTOM_SCORES" AS (
  SELECT "PROPERTYVALUE"::INT AS "value"
       , "PROPERTYNAME" AS "name"
    FROM "CONFIGPROPERTY"
   WHERE "GROUPNAME" = 'risk-score'
     AND "PROPERTYTYPE" = 'INTEGER'
)
SELECT (
  ("critical" * (SELECT "value" FROM "CUSTOM_SCORES" WHERE "name" = 'weight.critical'))
  + ("high" * (SELECT "value" FROM "CUSTOM_SCORES" WHERE "name" = 'weight.high'))
  + ("medium" * (SELECT "value" FROM "CUSTOM_SCORES" WHERE "name" = 'weight.medium'))
  + ("low" * (SELECT "value" FROM "CUSTOM_SCORES" WHERE "name" = 'weight.low'))
  + ("unassigned" * (SELECT "value" FROM "CUSTOM_SCORES" WHERE "name" = 'weight.unassigned'))
)::NUMERIC;
$$;

CREATE PROCEDURE public."UPDATE_COMPONENT_METRICS"(component_uuid uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
  "v_component"                               RECORD; -- The component to update metrics for
  "v_vulnerability"                           RECORD; -- Loop variable for iterating over vulnerabilities the component is affected by
  "v_alias"                                   RECORD; -- Loop variable for iterating over aliases of a vulnerability
  "v_aliases_seen"                            TEXT[]; -- Array of aliases encountered while iterating over vulnerabilities
  "v_policy_violation"                        RECORD; -- Loop variable for iterating over policy violations assigned to the component
  "v_vulnerabilities"                         INT     := 0; -- Total number of vulnerabilities
  "v_critical"                                INT     := 0; -- Number of vulnerabilities with critical severity
  "v_high"                                    INT     := 0; -- Number of vulnerabilities with high severity
  "v_medium"                                  INT     := 0; -- Number of vulnerabilities with medium severity
  "v_low"                                     INT     := 0; -- Number of vulnerabilities with low severity
  "v_unassigned"                              INT     := 0; -- Number of vulnerabilities with unassigned severity
  "v_risk_score"                              NUMERIC := 0; -- Inherited risk score
  "v_findings_total"                          INT     := 0; -- Total number of findings
  "v_findings_audited"                        INT     := 0; -- Number of audited findings
  "v_findings_unaudited"                      INT     := 0; -- Number of unaudited findings
  "v_findings_suppressed"                     INT     := 0; -- Number of suppressed findings
  "v_policy_violations_total"                 INT     := 0; -- Total number of policy violations
  "v_policy_violations_fail"                  INT     := 0; -- Number of policy violations with level fail
  "v_policy_violations_warn"                  INT     := 0; -- Number of policy violations with level warn
  "v_policy_violations_info"                  INT     := 0; -- Number of policy violations with level info
  "v_policy_violations_audited"               INT     := 0; -- Number of audited policy violations
  "v_policy_violations_unaudited"             INT     := 0; -- Number of unaudited policy violations
  "v_policy_violations_license_total"         INT     := 0; -- Total number of policy violations of type license
  "v_policy_violations_license_audited"       INT     := 0; -- Number of audited policy violations of type license
  "v_policy_violations_license_unaudited"     INT     := 0; -- Number of unaudited policy violations of type license
  "v_policy_violations_operational_total"     INT     := 0; -- Total number of policy violations of type operational
  "v_policy_violations_operational_audited"   INT     := 0; -- Number of audited policy violations of type operational
  "v_policy_violations_operational_unaudited" INT     := 0; -- Number of unaudited policy violations of type operational
  "v_policy_violations_security_total"        INT     := 0; -- Total number of policy violations of type security
  "v_policy_violations_security_audited"      INT     := 0; -- Number of audited policy violations of type security
  "v_policy_violations_security_unaudited"    INT     := 0; -- Number of unaudited policy violations of type security
  "v_existing_id"                             BIGINT; -- ID of the existing row that matches the data point calculated in this procedure
BEGIN
  SELECT "ID", "PROJECT_ID" INTO "v_component" FROM "COMPONENT" WHERE "UUID" = "component_uuid";
  IF "v_component" IS NULL THEN
    RAISE EXCEPTION 'Component with UUID % does not exist', "component_uuid";
  END IF;

  FOR "v_vulnerability" IN SELECT "VULNID", "SOURCE", "V"."SEVERITY", "A"."SEVERITY" AS "SEVERITY_OVERRIDE", "CVSSV2BASESCORE", "CVSSV3BASESCORE"
                           FROM "VULNERABILITY" AS "V"
                                  INNER JOIN "COMPONENTS_VULNERABILITIES" AS "CV"
                                             ON "CV"."COMPONENT_ID" = "v_component"."ID"
                                               AND "CV"."VULNERABILITY_ID" = "V"."ID"
                                  LEFT OUTER JOIN "ANALYSIS" AS "A"
                                        ON "A"."COMPONENT_ID" = "v_component"."ID"
                                            AND "A"."COMPONENT_ID" = "CV"."COMPONENT_ID"
                                            AND "A"."VULNERABILITY_ID" = "V"."ID"
                                        WHERE "A"."SUPPRESSED" != TRUE OR "A"."SUPPRESSED" IS NULL
    LOOP
      CONTINUE WHEN ("v_vulnerability"."SOURCE" || '|' || "v_vulnerability"."VULNID") = ANY ("v_aliases_seen");

      FOR "v_alias" IN SELECT *
                       FROM "VULNERABILITYALIAS" AS "VA"
                       WHERE ("v_vulnerability"."SOURCE" = 'GITHUB' AND
                              "VA"."GHSA_ID" = "v_vulnerability"."VULNID")
                         OR ("v_vulnerability"."SOURCE" = 'INTERNAL' AND
                             "VA"."INTERNAL_ID" = "v_vulnerability"."VULNID")
                         OR ("v_vulnerability"."SOURCE" = 'NVD' AND
                             "VA"."CVE_ID" = "v_vulnerability"."VULNID")
                         OR ("v_vulnerability"."SOURCE" = 'OSSINDEX' AND
                             "VA"."SONATYPE_ID" = "v_vulnerability"."VULNID")
                         OR ("v_vulnerability"."SOURCE" = 'OSV' AND
                             "VA"."OSV_ID" = "v_vulnerability"."VULNID")
                         OR ("v_vulnerability"."SOURCE" = 'SNYK' AND
                             "VA"."SNYK_ID" = "v_vulnerability"."VULNID")
                         OR ("v_vulnerability"."SOURCE" = 'VULNDB' AND
                             "VA"."VULNDB_ID" = "v_vulnerability"."VULNID")
        LOOP
          IF "v_alias"."GHSA_ID" IS NOT NULL THEN
            "v_aliases_seen" = array_append("v_aliases_seen", 'GITHUB|' || "v_alias"."GHSA_ID");
          END IF;
          IF "v_alias"."INTERNAL_ID" IS NOT NULL THEN
            "v_aliases_seen" = array_append("v_aliases_seen", 'INTERNAL|' || "v_alias"."INTERNAL_ID");
          END IF;
          IF "v_alias"."CVE_ID" IS NOT NULL THEN
            "v_aliases_seen" = array_append("v_aliases_seen", 'NVD|' || "v_alias"."CVE_ID");
          END IF;
          IF "v_alias"."SONATYPE_ID" IS NOT NULL THEN
            "v_aliases_seen" = array_append("v_aliases_seen", 'OSSINDEX|' || "v_alias"."SONATYPE_ID");
          END IF;
          IF "v_alias"."OSV_ID" IS NOT NULL THEN
            "v_aliases_seen" = array_append("v_aliases_seen", 'OSV|' || "v_alias"."OSV_ID");
          END IF;
          IF "v_alias"."SNYK_ID" IS NOT NULL THEN
            "v_aliases_seen" = array_append("v_aliases_seen", 'SNYK|' || "v_alias"."SNYK_ID");
          END IF;
          IF "v_alias"."VULNDB_ID" IS NOT NULL THEN
            "v_aliases_seen" = array_append("v_aliases_seen", 'VULNDB|' || "v_alias"."VULNDB_ID");
          END IF;
        END LOOP;

      "v_vulnerabilities" := "v_vulnerabilities" + 1;

      IF COALESCE("v_vulnerability"."SEVERITY_OVERRIDE", "v_vulnerability"."SEVERITY") = 'CRITICAL' THEN
        "v_critical" := "v_critical" + 1;
      ELSEIF COALESCE("v_vulnerability"."SEVERITY_OVERRIDE", "v_vulnerability"."SEVERITY") = 'HIGH' THEN
        "v_high" := "v_high" + 1;
      ELSEIF COALESCE("v_vulnerability"."SEVERITY_OVERRIDE", "v_vulnerability"."SEVERITY") = 'MEDIUM' THEN
        "v_medium" := "v_medium" + 1;
      ELSEIF COALESCE("v_vulnerability"."SEVERITY_OVERRIDE", "v_vulnerability"."SEVERITY") = 'LOW' THEN
        "v_low" := "v_low" + 1;
      ELSE
        "v_unassigned" := "v_unassigned" + 1;
      END IF;

    END LOOP;

  "v_risk_score" = "CALC_RISK_SCORE"("v_critical", "v_high", "v_medium", "v_low", "v_unassigned");

  SELECT COUNT(*)
  FROM "ANALYSIS" AS "A"
  WHERE "A"."COMPONENT_ID" = "v_component"."ID"
    AND "A"."SUPPRESSED" = FALSE
    AND "A"."STATE" != 'NOT_SET'
    AND "A"."STATE" != 'IN_TRIAGE'
  INTO "v_findings_audited";

  "v_findings_total" = "v_vulnerabilities";
  "v_findings_unaudited" = "v_findings_total" - "v_findings_audited";

  SELECT COUNT(*)
  FROM "ANALYSIS" AS "A"
  WHERE "A"."COMPONENT_ID" = "v_component"."ID"
    AND "A"."SUPPRESSED" = TRUE
  INTO "v_findings_suppressed";

  FOR "v_policy_violation" IN SELECT "PV"."TYPE", "P"."VIOLATIONSTATE"
                              FROM "POLICYVIOLATION" AS "PV"
                                     INNER JOIN "POLICYCONDITION" AS "PC" ON "PV"."POLICYCONDITION_ID" = "PC"."ID"
                                     INNER JOIN "POLICY" AS "P" ON "PC"."POLICY_ID" = "P"."ID"
                                     LEFT JOIN "VIOLATIONANALYSIS" AS "VA"
                                               ON "VA"."COMPONENT_ID" = "v_component"."ID" AND
                                                  "VA"."POLICYVIOLATION_ID" = "PV"."ID"
                              WHERE "PV"."COMPONENT_ID" = "v_component"."ID"
                                AND ("VA" IS NULL OR "VA"."SUPPRESSED" = FALSE)
    LOOP
      "v_policy_violations_total" := "v_policy_violations_total" + 1;

      IF "v_policy_violation"."TYPE" = 'LICENSE' THEN
        "v_policy_violations_license_total" := "v_policy_violations_license_total" + 1;
      ELSEIF "v_policy_violation"."TYPE" = 'OPERATIONAL' THEN
        "v_policy_violations_operational_total" := "v_policy_violations_operational_total" + 1;
      ELSEIF "v_policy_violation"."TYPE" = 'SECURITY' THEN
        "v_policy_violations_security_total" := "v_policy_violations_security_total" + 1;
      ELSE
        RAISE EXCEPTION 'Encountered invalid policy violation type %', "v_policy_violation"."TYPE";
      END IF;

      IF "v_policy_violation"."VIOLATIONSTATE" = 'FAIL' THEN
        "v_policy_violations_fail" := "v_policy_violations_fail" + 1;
      ELSEIF "v_policy_violation"."VIOLATIONSTATE" = 'WARN' THEN
        "v_policy_violations_warn" := "v_policy_violations_warn" + 1;
      ELSEIF "v_policy_violation"."VIOLATIONSTATE" = 'INFO' THEN
        "v_policy_violations_info" := "v_policy_violations_info" + 1;
      ELSE
        RAISE EXCEPTION 'Encountered invalid violation state %', "v_policy_violation"."VIOLATIONSTATE";
      end if;
    END LOOP;

  SELECT COUNT(*)
  FROM "VIOLATIONANALYSIS" AS "VA"
         INNER JOIN "POLICYVIOLATION" AS "PV" ON "PV"."ID" = "VA"."POLICYVIOLATION_ID"
  WHERE "VA"."COMPONENT_ID" = "v_component"."ID"
    AND "PV"."TYPE" = 'LICENSE'
    AND "VA"."SUPPRESSED" = FALSE
    AND "VA"."STATE" != 'NOT_SET'
  INTO "v_policy_violations_license_audited";
  "v_policy_violations_license_unaudited" =
      "v_policy_violations_license_total" - "v_policy_violations_license_audited";

  SELECT COUNT(*)
  FROM "VIOLATIONANALYSIS" AS "VA"
         INNER JOIN "POLICYVIOLATION" AS "PV" ON "PV"."ID" = "VA"."POLICYVIOLATION_ID"
  WHERE "VA"."COMPONENT_ID" = "v_component"."ID"
    AND "PV"."TYPE" = 'OPERATIONAL'
    AND "VA"."SUPPRESSED" = FALSE
    AND "VA"."STATE" != 'NOT_SET'
  INTO "v_policy_violations_operational_audited";
  "v_policy_violations_operational_unaudited" =
      "v_policy_violations_operational_total" - "v_policy_violations_operational_audited";

  SELECT COUNT(*)
  FROM "VIOLATIONANALYSIS" AS "VA"
         INNER JOIN "POLICYVIOLATION" AS "PV" ON "PV"."ID" = "VA"."POLICYVIOLATION_ID"
  WHERE "VA"."COMPONENT_ID" = "v_component"."ID"
    AND "PV"."TYPE" = 'SECURITY'
    AND "VA"."SUPPRESSED" = FALSE
    AND "VA"."STATE" != 'NOT_SET'
  INTO "v_policy_violations_security_audited";
  "v_policy_violations_security_unaudited" =
      "v_policy_violations_security_total" - "v_policy_violations_security_audited";

  "v_policy_violations_audited" = "v_policy_violations_license_audited"
    + "v_policy_violations_operational_audited"
    + "v_policy_violations_security_audited";
  "v_policy_violations_unaudited" = "v_policy_violations_total" - "v_policy_violations_audited";

  WITH "CTE_LATEST_METRICS" AS (
    SELECT *
      FROM "DEPENDENCYMETRICS"
     WHERE "COMPONENT_ID" = "v_component"."ID"
     ORDER BY "LAST_OCCURRENCE" DESC
     LIMIT 1)
  SELECT "ID"
  FROM "CTE_LATEST_METRICS"
  WHERE "VULNERABILITIES" = "v_vulnerabilities"
    AND "CRITICAL" = "v_critical"
    AND "HIGH" = "v_high"
    AND "MEDIUM" = "v_medium"
    AND "LOW" = "v_low"
    AND "UNASSIGNED_SEVERITY" = "v_unassigned"
    AND "RISKSCORE" = "v_risk_score"
    AND "FINDINGS_TOTAL" = "v_findings_total"
    AND "FINDINGS_AUDITED" = "v_findings_audited"
    AND "FINDINGS_UNAUDITED" = "v_findings_unaudited"
    AND "SUPPRESSED" = "v_findings_suppressed"
    AND "POLICYVIOLATIONS_TOTAL" = "v_policy_violations_total"
    AND "POLICYVIOLATIONS_FAIL" = "v_policy_violations_fail"
    AND "POLICYVIOLATIONS_WARN" = "v_policy_violations_warn"
    AND "POLICYVIOLATIONS_INFO" = "v_policy_violations_info"
    AND "POLICYVIOLATIONS_AUDITED" = "v_policy_violations_audited"
    AND "POLICYVIOLATIONS_UNAUDITED" = "v_policy_violations_unaudited"
    AND "POLICYVIOLATIONS_LICENSE_TOTAL" = "v_policy_violations_license_total"
    AND "POLICYVIOLATIONS_LICENSE_AUDITED" = "v_policy_violations_license_audited"
    AND "POLICYVIOLATIONS_LICENSE_UNAUDITED" = "v_policy_violations_license_unaudited"
    AND "POLICYVIOLATIONS_OPERATIONAL_TOTAL" = "v_policy_violations_operational_total"
    AND "POLICYVIOLATIONS_OPERATIONAL_AUDITED" = "v_policy_violations_operational_audited"
    AND "POLICYVIOLATIONS_OPERATIONAL_UNAUDITED" = "v_policy_violations_operational_unaudited"
    AND "POLICYVIOLATIONS_SECURITY_TOTAL" = "v_policy_violations_security_total"
    AND "POLICYVIOLATIONS_SECURITY_AUDITED" = "v_policy_violations_security_audited"
    AND "POLICYVIOLATIONS_SECURITY_UNAUDITED" = "v_policy_violations_security_unaudited"
  LIMIT 1
  INTO "v_existing_id";

  IF "v_existing_id" IS NOT NULL THEN
    UPDATE "DEPENDENCYMETRICS" SET "LAST_OCCURRENCE" = NOW() WHERE "ID" = "v_existing_id";
  ELSE
    INSERT INTO "DEPENDENCYMETRICS" ("COMPONENT_ID",
                                     "PROJECT_ID",
                                     "VULNERABILITIES",
                                     "CRITICAL",
                                     "HIGH",
                                     "MEDIUM",
                                     "LOW",
                                     "UNASSIGNED_SEVERITY",
                                     "RISKSCORE",
                                     "FINDINGS_TOTAL",
                                     "FINDINGS_AUDITED",
                                     "FINDINGS_UNAUDITED",
                                     "SUPPRESSED",
                                     "POLICYVIOLATIONS_TOTAL",
                                     "POLICYVIOLATIONS_FAIL",
                                     "POLICYVIOLATIONS_WARN",
                                     "POLICYVIOLATIONS_INFO",
                                     "POLICYVIOLATIONS_AUDITED",
                                     "POLICYVIOLATIONS_UNAUDITED",
                                     "POLICYVIOLATIONS_LICENSE_TOTAL",
                                     "POLICYVIOLATIONS_LICENSE_AUDITED",
                                     "POLICYVIOLATIONS_LICENSE_UNAUDITED",
                                     "POLICYVIOLATIONS_OPERATIONAL_TOTAL",
                                     "POLICYVIOLATIONS_OPERATIONAL_AUDITED",
                                     "POLICYVIOLATIONS_OPERATIONAL_UNAUDITED",
                                     "POLICYVIOLATIONS_SECURITY_TOTAL",
                                     "POLICYVIOLATIONS_SECURITY_AUDITED",
                                     "POLICYVIOLATIONS_SECURITY_UNAUDITED",
                                     "FIRST_OCCURRENCE",
                                     "LAST_OCCURRENCE")
    VALUES ("v_component"."ID",
            "v_component"."PROJECT_ID",
            "v_vulnerabilities",
            "v_critical",
            "v_high",
            "v_medium",
            "v_low",
            "v_unassigned",
            "v_risk_score",
            "v_findings_total",
            "v_findings_audited",
            "v_findings_unaudited",
            "v_findings_suppressed",
            "v_policy_violations_total",
            "v_policy_violations_fail",
            "v_policy_violations_warn",
            "v_policy_violations_info",
            "v_policy_violations_audited",
            "v_policy_violations_unaudited",
            "v_policy_violations_license_total",
            "v_policy_violations_license_audited",
            "v_policy_violations_license_unaudited",
            "v_policy_violations_operational_total",
            "v_policy_violations_operational_audited",
            "v_policy_violations_operational_unaudited",
            "v_policy_violations_security_total",
            "v_policy_violations_security_audited",
            "v_policy_violations_security_unaudited",
            NOW(),
            NOW());

    UPDATE "COMPONENT" SET "LAST_RISKSCORE" = "v_risk_score" WHERE "ID" = "v_component"."ID";
  END IF;
END;
$$;

CREATE PROCEDURE public."UPDATE_PORTFOLIO_METRICS"()
    LANGUAGE plpgsql
    AS $$
DECLARE
  "v_projects"                                INT; -- Total number of projects in the portfolio
  "v_vulnerable_projects"                     INT; -- Number of vulnerable projects in the portfolio
  "v_components"                              INT; -- Total number of components in the portfolio
  "v_vulnerable_components"                   INT; -- Number of vulnerable components in the portfolio
  "v_vulnerabilities"                         INT; -- Total number of vulnerabilities
  "v_critical"                                INT; -- Number of vulnerabilities with critical severity
  "v_high"                                    INT; -- Number of vulnerabilities with high severity
  "v_medium"                                  INT; -- Number of vulnerabilities with medium severity
  "v_low"                                     INT; -- Number of vulnerabilities with low severity
  "v_unassigned"                              INT; -- Number of vulnerabilities with unassigned severity
  "v_risk_score"                              NUMERIC; -- Inherited risk score
  "v_findings_total"                          INT; -- Total number of findings
  "v_findings_audited"                        INT; -- Number of audited findings
  "v_findings_unaudited"                      INT; -- Number of unaudited findings
  "v_findings_suppressed"                     INT; -- Number of suppressed findings
  "v_policy_violations_total"                 INT; -- Total number of policy violations
  "v_policy_violations_fail"                  INT; -- Number of policy violations with level fail
  "v_policy_violations_warn"                  INT; -- Number of policy violations with level warn
  "v_policy_violations_info"                  INT; -- Number of policy violations with level info
  "v_policy_violations_audited"               INT; -- Number of audited policy violations
  "v_policy_violations_unaudited"             INT; -- Number of unaudited policy violations
  "v_policy_violations_license_total"         INT; -- Total number of policy violations of type license
  "v_policy_violations_license_audited"       INT; -- Number of audited policy violations of type license
  "v_policy_violations_license_unaudited"     INT; -- Number of unaudited policy violations of type license
  "v_policy_violations_operational_total"     INT; -- Total number of policy violations of type operational
  "v_policy_violations_operational_audited"   INT; -- Number of audited policy violations of type operational
  "v_policy_violations_operational_unaudited" INT; -- Number of unaudited policy violations of type operational
  "v_policy_violations_security_total"        INT; -- Total number of policy violations of type security
  "v_policy_violations_security_audited"      INT; -- Number of audited policy violations of type security
  "v_policy_violations_security_unaudited"    INT; -- Number of unaudited policy violations of type security
  "v_existing_id"                             BIGINT; -- ID of the existing row that matches the data point calculated in this procedure
BEGIN
  -- Aggregate over all most recent DEPENDENCYMETRICS.
  -- NOTE: SUM returns NULL when no rows match the query, but COUNT returns 0.
  -- For nullable result columns, use COALESCE(..., 0) to have a default value.
  SELECT COUNT(*)::INT,
    COALESCE(SUM(CASE WHEN "VULNERABILITIES" > 0 THEN 1 ELSE 0 END)::INT, 0),
    COALESCE(SUM("COMPONENTS")::INT, 0),
    COALESCE(SUM("VULNERABLECOMPONENTS")::INT, 0),
    COALESCE(SUM("VULNERABILITIES")::INT, 0),
    COALESCE(SUM("CRITICAL")::INT, 0),
    COALESCE(SUM("HIGH")::INT, 0),
    COALESCE(SUM("MEDIUM")::INT, 0),
    COALESCE(SUM("LOW")::INT, 0),
    COALESCE(SUM("UNASSIGNED_SEVERITY")::INT, 0),
    COALESCE(SUM("FINDINGS_TOTAL")::INT, 0),
    COALESCE(SUM("FINDINGS_AUDITED")::INT, 0),
    COALESCE(SUM("FINDINGS_UNAUDITED")::INT, 0),
    COALESCE(SUM("SUPPRESSED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_TOTAL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_FAIL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_WARN")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_INFO")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_AUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_UNAUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_LICENSE_TOTAL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_LICENSE_AUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_LICENSE_UNAUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_OPERATIONAL_TOTAL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_OPERATIONAL_AUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_OPERATIONAL_UNAUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_SECURITY_TOTAL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_SECURITY_AUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_SECURITY_UNAUDITED")::INT, 0)
  FROM (SELECT DISTINCT ON ("PM"."PROJECT_ID") *
        FROM "PROJECTMETRICS" AS "PM"
               INNER JOIN "PROJECT" AS "P" ON "P"."ID" = "PM"."PROJECT_ID"
        WHERE "P"."INACTIVE_SINCE" IS NULL  -- Only consider active projects
        ORDER BY "PM"."PROJECT_ID", "PM"."LAST_OCCURRENCE" DESC) AS "LATEST_PROJECT_METRICS"
  INTO
    "v_projects",
    "v_vulnerable_projects",
    "v_components",
    "v_vulnerable_components",
    "v_vulnerabilities",
    "v_critical",
    "v_high",
    "v_medium",
    "v_low",
    "v_unassigned",
    "v_findings_total",
    "v_findings_audited",
    "v_findings_unaudited",
    "v_findings_suppressed",
    "v_policy_violations_total",
    "v_policy_violations_fail",
    "v_policy_violations_warn",
    "v_policy_violations_info",
    "v_policy_violations_audited",
    "v_policy_violations_unaudited",
    "v_policy_violations_license_total",
    "v_policy_violations_license_audited",
    "v_policy_violations_license_unaudited",
    "v_policy_violations_operational_total",
    "v_policy_violations_operational_audited",
    "v_policy_violations_operational_unaudited",
    "v_policy_violations_security_total",
    "v_policy_violations_security_audited",
    "v_policy_violations_security_unaudited";

  "v_risk_score" = "CALC_RISK_SCORE"("v_critical", "v_high", "v_medium", "v_low", "v_unassigned");

  WITH "CTE_LATEST_METRICS" AS (
    SELECT *
      FROM "PORTFOLIOMETRICS"
     ORDER BY "LAST_OCCURRENCE" DESC
     LIMIT 1)
  SELECT "ID"
  FROM "CTE_LATEST_METRICS"
  WHERE "PROJECTS" = "v_projects"
    AND "VULNERABLEPROJECTS" = "v_vulnerable_projects"
    AND "COMPONENTS" = "v_components"
    AND "VULNERABLECOMPONENTS" = "v_vulnerable_components"
    AND "VULNERABILITIES" = "v_vulnerabilities"
    AND "CRITICAL" = "v_critical"
    AND "HIGH" = "v_high"
    AND "MEDIUM" = "v_medium"
    AND "LOW" = "v_low"
    AND "UNASSIGNED_SEVERITY" = "v_unassigned"
    AND "RISKSCORE" = "v_risk_score"
    AND "FINDINGS_TOTAL" = "v_findings_total"
    AND "FINDINGS_AUDITED" = "v_findings_audited"
    AND "FINDINGS_UNAUDITED" = "v_findings_unaudited"
    AND "SUPPRESSED" = "v_findings_suppressed"
    AND "POLICYVIOLATIONS_TOTAL" = "v_policy_violations_total"
    AND "POLICYVIOLATIONS_FAIL" = "v_policy_violations_fail"
    AND "POLICYVIOLATIONS_WARN" = "v_policy_violations_warn"
    AND "POLICYVIOLATIONS_INFO" = "v_policy_violations_info"
    AND "POLICYVIOLATIONS_AUDITED" = "v_policy_violations_audited"
    AND "POLICYVIOLATIONS_UNAUDITED" = "v_policy_violations_unaudited"
    AND "POLICYVIOLATIONS_LICENSE_TOTAL" = "v_policy_violations_license_total"
    AND "POLICYVIOLATIONS_LICENSE_AUDITED" = "v_policy_violations_license_audited"
    AND "POLICYVIOLATIONS_LICENSE_UNAUDITED" = "v_policy_violations_license_unaudited"
    AND "POLICYVIOLATIONS_OPERATIONAL_TOTAL" = "v_policy_violations_operational_total"
    AND "POLICYVIOLATIONS_OPERATIONAL_AUDITED" = "v_policy_violations_operational_audited"
    AND "POLICYVIOLATIONS_OPERATIONAL_UNAUDITED" = "v_policy_violations_operational_unaudited"
    AND "POLICYVIOLATIONS_SECURITY_TOTAL" = "v_policy_violations_security_total"
    AND "POLICYVIOLATIONS_SECURITY_AUDITED" = "v_policy_violations_security_audited"
    AND "POLICYVIOLATIONS_SECURITY_UNAUDITED" = "v_policy_violations_security_unaudited"
  LIMIT 1
  INTO "v_existing_id";

  IF "v_existing_id" IS NOT NULL THEN
    UPDATE "PORTFOLIOMETRICS" SET "LAST_OCCURRENCE" = NOW() WHERE "ID" = "v_existing_id";
  ELSE
    INSERT INTO "PORTFOLIOMETRICS" ("PROJECTS",
                                    "VULNERABLEPROJECTS",
                                    "COMPONENTS",
                                    "VULNERABLECOMPONENTS",
                                    "VULNERABILITIES",
                                    "CRITICAL",
                                    "HIGH",
                                    "MEDIUM",
                                    "LOW",
                                    "UNASSIGNED_SEVERITY",
                                    "RISKSCORE",
                                    "FINDINGS_TOTAL",
                                    "FINDINGS_AUDITED",
                                    "FINDINGS_UNAUDITED",
                                    "SUPPRESSED",
                                    "POLICYVIOLATIONS_TOTAL",
                                    "POLICYVIOLATIONS_FAIL",
                                    "POLICYVIOLATIONS_WARN",
                                    "POLICYVIOLATIONS_INFO",
                                    "POLICYVIOLATIONS_AUDITED",
                                    "POLICYVIOLATIONS_UNAUDITED",
                                    "POLICYVIOLATIONS_LICENSE_TOTAL",
                                    "POLICYVIOLATIONS_LICENSE_AUDITED",
                                    "POLICYVIOLATIONS_LICENSE_UNAUDITED",
                                    "POLICYVIOLATIONS_OPERATIONAL_TOTAL",
                                    "POLICYVIOLATIONS_OPERATIONAL_AUDITED",
                                    "POLICYVIOLATIONS_OPERATIONAL_UNAUDITED",
                                    "POLICYVIOLATIONS_SECURITY_TOTAL",
                                    "POLICYVIOLATIONS_SECURITY_AUDITED",
                                    "POLICYVIOLATIONS_SECURITY_UNAUDITED",
                                    "FIRST_OCCURRENCE",
                                    "LAST_OCCURRENCE")
    VALUES ("v_projects",
            "v_vulnerable_projects",
            "v_components",
            "v_vulnerable_components",
            "v_vulnerabilities",
            "v_critical",
            "v_high",
            "v_medium",
            "v_low",
            "v_unassigned",
            "v_risk_score",
            "v_findings_total",
            "v_findings_audited",
            "v_findings_unaudited",
            "v_findings_suppressed",
            "v_policy_violations_total",
            "v_policy_violations_fail",
            "v_policy_violations_warn",
            "v_policy_violations_info",
            "v_policy_violations_audited",
            "v_policy_violations_unaudited",
            "v_policy_violations_license_total",
            "v_policy_violations_license_audited",
            "v_policy_violations_license_unaudited",
            "v_policy_violations_operational_total",
            "v_policy_violations_operational_audited",
            "v_policy_violations_operational_unaudited",
            "v_policy_violations_security_total",
            "v_policy_violations_security_audited",
            "v_policy_violations_security_unaudited",
            NOW(),
            NOW());
  END IF;
END;
$$;

CREATE PROCEDURE public."UPDATE_PROJECT_METRICS"(project_uuid uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
  "v_project_id"                              BIGINT;
  "v_component_uuid"                          UUID;
  "v_components"                              INT; -- Total number of components in the project
  "v_vulnerable_components"                   INT; -- Number of vulnerable components in the project
  "v_vulnerabilities"                         INT; -- Total number of vulnerabilities
  "v_critical"                                INT; -- Number of vulnerabilities with critical severity
  "v_high"                                    INT; -- Number of vulnerabilities with high severity
  "v_medium"                                  INT; -- Number of vulnerabilities with medium severity
  "v_low"                                     INT; -- Number of vulnerabilities with low severity
  "v_unassigned"                              INT; -- Number of vulnerabilities with unassigned severity
  "v_risk_score"                              NUMERIC; -- Inherited risk score
  "v_findings_total"                          INT; -- Total number of findings
  "v_findings_audited"                        INT; -- Number of audited findings
  "v_findings_unaudited"                      INT; -- Number of unaudited findings
  "v_findings_suppressed"                     INT; -- Number of suppressed findings
  "v_policy_violations_total"                 INT; -- Total number of policy violations
  "v_policy_violations_fail"                  INT; -- Number of policy violations with level fail
  "v_policy_violations_warn"                  INT; -- Number of policy violations with level warn
  "v_policy_violations_info"                  INT; -- Number of policy violations with level info
  "v_policy_violations_audited"               INT; -- Number of audited policy violations
  "v_policy_violations_unaudited"             INT; -- Number of unaudited policy violations
  "v_policy_violations_license_total"         INT; -- Total number of policy violations of type license
  "v_policy_violations_license_audited"       INT; -- Number of audited policy violations of type license
  "v_policy_violations_license_unaudited"     INT; -- Number of unaudited policy violations of type license
  "v_policy_violations_operational_total"     INT; -- Total number of policy violations of type operational
  "v_policy_violations_operational_audited"   INT; -- Number of audited policy violations of type operational
  "v_policy_violations_operational_unaudited" INT; -- Number of unaudited policy violations of type operational
  "v_policy_violations_security_total"        INT; -- Total number of policy violations of type security
  "v_policy_violations_security_audited"      INT; -- Number of audited policy violations of type security
  "v_policy_violations_security_unaudited"    INT; -- Number of unaudited policy violations of type security
  "v_existing_id"                             BIGINT; -- ID of the existing row that matches the data point calculated in this procedure
BEGIN
  SELECT "ID" FROM "PROJECT" WHERE "UUID" = "project_uuid" INTO "v_project_id";
  IF "v_project_id" IS NULL THEN
    RAISE EXCEPTION 'Project with UUID % does not exist', "project_uuid";
  END IF;

  FOR "v_component_uuid" IN SELECT "UUID" FROM "COMPONENT" WHERE "PROJECT_ID" = "v_project_id"
  LOOP
    CALL "UPDATE_COMPONENT_METRICS"("v_component_uuid");
  END LOOP;

  -- Aggregate over all most recent DEPENDENCYMETRICS.
  -- NOTE: SUM returns NULL when no rows match the query, but COUNT returns 0.
  -- For nullable result columns, use COALESCE(..., 0) to have a default value.
  SELECT COUNT(*)::INT,
    COALESCE(SUM(CASE WHEN "VULNERABILITIES" > 0 THEN 1 ELSE 0 END)::INT, 0),
    COALESCE(SUM("VULNERABILITIES")::INT, 0),
    COALESCE(SUM("CRITICAL")::INT, 0),
    COALESCE(SUM("HIGH")::INT, 0),
    COALESCE(SUM("MEDIUM")::INT, 0),
    COALESCE(SUM("LOW")::INT, 0),
    COALESCE(SUM("UNASSIGNED_SEVERITY")::INT, 0),
    COALESCE(SUM("FINDINGS_TOTAL")::INT, 0),
    COALESCE(SUM("FINDINGS_AUDITED")::INT, 0),
    COALESCE(SUM("FINDINGS_UNAUDITED")::INT, 0),
    COALESCE(SUM("SUPPRESSED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_TOTAL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_FAIL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_WARN")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_INFO")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_AUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_UNAUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_LICENSE_TOTAL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_LICENSE_AUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_LICENSE_UNAUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_OPERATIONAL_TOTAL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_OPERATIONAL_AUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_OPERATIONAL_UNAUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_SECURITY_TOTAL")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_SECURITY_AUDITED")::INT, 0),
    COALESCE(SUM("POLICYVIOLATIONS_SECURITY_UNAUDITED")::INT, 0)
  FROM (SELECT DISTINCT ON ("DM"."COMPONENT_ID") *
        FROM "DEPENDENCYMETRICS" AS "DM"
        WHERE "PROJECT_ID" = "v_project_id"
        ORDER BY "DM"."COMPONENT_ID", "DM"."LAST_OCCURRENCE" DESC) AS "LATEST_COMPONENT_METRICS"
  INTO
    "v_components",
    "v_vulnerable_components",
    "v_vulnerabilities",
    "v_critical",
    "v_high",
    "v_medium",
    "v_low",
    "v_unassigned",
    "v_findings_total",
    "v_findings_audited",
    "v_findings_unaudited",
    "v_findings_suppressed",
    "v_policy_violations_total",
    "v_policy_violations_fail",
    "v_policy_violations_warn",
    "v_policy_violations_info",
    "v_policy_violations_audited",
    "v_policy_violations_unaudited",
    "v_policy_violations_license_total",
    "v_policy_violations_license_audited",
    "v_policy_violations_license_unaudited",
    "v_policy_violations_operational_total",
    "v_policy_violations_operational_audited",
    "v_policy_violations_operational_unaudited",
    "v_policy_violations_security_total",
    "v_policy_violations_security_audited",
    "v_policy_violations_security_unaudited";

  "v_risk_score" = "CALC_RISK_SCORE"("v_critical", "v_high", "v_medium", "v_low", "v_unassigned");

  WITH "CTE_LATEST_METRICS" AS (
    SELECT *
      FROM "PROJECTMETRICS"
     WHERE "PROJECT_ID" = "v_project_id"
     ORDER BY "LAST_OCCURRENCE" DESC
     LIMIT 1)
  SELECT "ID"
  FROM "CTE_LATEST_METRICS"
  WHERE "COMPONENTS" = "v_components"
    AND "VULNERABLECOMPONENTS" = "v_vulnerable_components"
    AND "VULNERABILITIES" = "v_vulnerabilities"
    AND "CRITICAL" = "v_critical"
    AND "HIGH" = "v_high"
    AND "MEDIUM" = "v_medium"
    AND "LOW" = "v_low"
    AND "UNASSIGNED_SEVERITY" = "v_unassigned"
    AND "RISKSCORE" = "v_risk_score"
    AND "FINDINGS_TOTAL" = "v_findings_total"
    AND "FINDINGS_AUDITED" = "v_findings_audited"
    AND "FINDINGS_UNAUDITED" = "v_findings_unaudited"
    AND "SUPPRESSED" = "v_findings_suppressed"
    AND "POLICYVIOLATIONS_TOTAL" = "v_policy_violations_total"
    AND "POLICYVIOLATIONS_FAIL" = "v_policy_violations_fail"
    AND "POLICYVIOLATIONS_WARN" = "v_policy_violations_warn"
    AND "POLICYVIOLATIONS_INFO" = "v_policy_violations_info"
    AND "POLICYVIOLATIONS_AUDITED" = "v_policy_violations_audited"
    AND "POLICYVIOLATIONS_UNAUDITED" = "v_policy_violations_unaudited"
    AND "POLICYVIOLATIONS_LICENSE_TOTAL" = "v_policy_violations_license_total"
    AND "POLICYVIOLATIONS_LICENSE_AUDITED" = "v_policy_violations_license_audited"
    AND "POLICYVIOLATIONS_LICENSE_UNAUDITED" = "v_policy_violations_license_unaudited"
    AND "POLICYVIOLATIONS_OPERATIONAL_TOTAL" = "v_policy_violations_operational_total"
    AND "POLICYVIOLATIONS_OPERATIONAL_AUDITED" = "v_policy_violations_operational_audited"
    AND "POLICYVIOLATIONS_OPERATIONAL_UNAUDITED" = "v_policy_violations_operational_unaudited"
    AND "POLICYVIOLATIONS_SECURITY_TOTAL" = "v_policy_violations_security_total"
    AND "POLICYVIOLATIONS_SECURITY_AUDITED" = "v_policy_violations_security_audited"
    AND "POLICYVIOLATIONS_SECURITY_UNAUDITED" = "v_policy_violations_security_unaudited"
  LIMIT 1
  INTO "v_existing_id";

  IF "v_existing_id" IS NOT NULL THEN
    UPDATE "PROJECTMETRICS" SET "LAST_OCCURRENCE" = NOW() WHERE "ID" = "v_existing_id";
  ELSE
    INSERT INTO "PROJECTMETRICS" ("PROJECT_ID",
                                  "COMPONENTS",
                                  "VULNERABLECOMPONENTS",
                                  "VULNERABILITIES",
                                  "CRITICAL",
                                  "HIGH",
                                  "MEDIUM",
                                  "LOW",
                                  "UNASSIGNED_SEVERITY",
                                  "RISKSCORE",
                                  "FINDINGS_TOTAL",
                                  "FINDINGS_AUDITED",
                                  "FINDINGS_UNAUDITED",
                                  "SUPPRESSED",
                                  "POLICYVIOLATIONS_TOTAL",
                                  "POLICYVIOLATIONS_FAIL",
                                  "POLICYVIOLATIONS_WARN",
                                  "POLICYVIOLATIONS_INFO",
                                  "POLICYVIOLATIONS_AUDITED",
                                  "POLICYVIOLATIONS_UNAUDITED",
                                  "POLICYVIOLATIONS_LICENSE_TOTAL",
                                  "POLICYVIOLATIONS_LICENSE_AUDITED",
                                  "POLICYVIOLATIONS_LICENSE_UNAUDITED",
                                  "POLICYVIOLATIONS_OPERATIONAL_TOTAL",
                                  "POLICYVIOLATIONS_OPERATIONAL_AUDITED",
                                  "POLICYVIOLATIONS_OPERATIONAL_UNAUDITED",
                                  "POLICYVIOLATIONS_SECURITY_TOTAL",
                                  "POLICYVIOLATIONS_SECURITY_AUDITED",
                                  "POLICYVIOLATIONS_SECURITY_UNAUDITED",
                                  "FIRST_OCCURRENCE",
                                  "LAST_OCCURRENCE")
    VALUES ("v_project_id",
            "v_components",
            "v_vulnerable_components",
            "v_vulnerabilities",
            "v_critical",
            "v_high",
            "v_medium",
            "v_low",
            "v_unassigned",
            "v_risk_score",
            "v_findings_total",
            "v_findings_audited",
            "v_findings_unaudited",
            "v_findings_suppressed",
            "v_policy_violations_total",
            "v_policy_violations_fail",
            "v_policy_violations_warn",
            "v_policy_violations_info",
            "v_policy_violations_audited",
            "v_policy_violations_unaudited",
            "v_policy_violations_license_total",
            "v_policy_violations_license_audited",
            "v_policy_violations_license_unaudited",
            "v_policy_violations_operational_total",
            "v_policy_violations_operational_audited",
            "v_policy_violations_operational_unaudited",
            "v_policy_violations_security_total",
            "v_policy_violations_security_audited",
            "v_policy_violations_security_unaudited",
            NOW(),
            NOW());

    UPDATE "PROJECT" SET "LAST_RISKSCORE" = "v_risk_score" WHERE "ID" = "v_project_id";
  END IF;
end;
$$;

CREATE FUNCTION public.jsonb_vuln_aliases(vuln_source text, vuln_id text) RETURNS jsonb
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
SELECT JSONB_AGG(DISTINCT JSONB_STRIP_NULLS(JSONB_BUILD_OBJECT(
         'cveId', "VA"."CVE_ID"
       , 'ghsaId', "VA"."GHSA_ID"
       , 'gsdId', "VA"."GSD_ID"
       , 'internalId', "VA"."INTERNAL_ID"
       , 'osvId', "VA"."OSV_ID"
       , 'sonatypeId', "VA"."SONATYPE_ID"
       , 'snykId', "VA"."SNYK_ID"
       , 'vulnDbId', "VA"."VULNDB_ID"
       )))
  FROM "VULNERABILITYALIAS" AS "VA"
 WHERE ("vuln_source" = 'NVD' AND "VA"."CVE_ID" = "vuln_id")
    OR ("vuln_source" = 'GITHUB' AND "VA"."GHSA_ID" = "vuln_id")
    OR ("vuln_source" = 'GSD' AND "VA"."GSD_ID" = "vuln_id")
    OR ("vuln_source" = 'INTERNAL' AND "VA"."INTERNAL_ID" = "vuln_id")
    OR ("vuln_source" = 'OSV' AND "VA"."OSV_ID" = "vuln_id")
    OR ("vuln_source" = 'SONATYPE' AND "VA"."SONATYPE_ID" = "vuln_id")
    OR ("vuln_source" = 'SNYK' AND "VA"."SNYK_ID" = "vuln_id")
    OR ("vuln_source" = 'VULNDB' AND "VA"."VULNDB_ID" = "vuln_id")
$$;

SET default_tablespace = '';

SET default_with_oids = false;

CREATE TABLE public."AFFECTEDVERSIONATTRIBUTION" (
    "ID" bigint NOT NULL,
    "FIRST_SEEN" timestamp with time zone NOT NULL,
    "LAST_SEEN" timestamp with time zone NOT NULL,
    "SOURCE" character varying(255) NOT NULL,
    "UUID" uuid NOT NULL,
    "VULNERABILITY" bigint NOT NULL,
    "VULNERABLE_SOFTWARE" bigint NOT NULL
);

ALTER TABLE public."AFFECTEDVERSIONATTRIBUTION" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."AFFECTEDVERSIONATTRIBUTION_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."ANALYSIS" (
    "ID" bigint NOT NULL,
    "DETAILS" text,
    "JUSTIFICATION" character varying(255),
    "RESPONSE" character varying(255),
    "STATE" character varying(255) NOT NULL,
    "COMPONENT_ID" bigint,
    "PROJECT_ID" bigint,
    "SUPPRESSED" boolean NOT NULL,
    "VULNERABILITY_ID" bigint NOT NULL,
    "CVSSV2VECTOR" character varying(255),
    "CVSSV3SCORE" numeric,
    "OWASPSCORE" numeric,
    "CVSSV2SCORE" numeric,
    "OWASPVECTOR" character varying(255),
    "CVSSV3VECTOR" character varying(255),
    "SEVERITY" character varying(255),
    "VULNERABILITY_POLICY_ID" bigint
);

CREATE TABLE public."ANALYSISCOMMENT" (
    "ID" bigint NOT NULL,
    "ANALYSIS_ID" bigint NOT NULL,
    "COMMENT" text NOT NULL,
    "COMMENTER" character varying(255),
    "TIMESTAMP" timestamp with time zone NOT NULL
);

ALTER TABLE public."ANALYSISCOMMENT" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."ANALYSISCOMMENT_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE public."ANALYSIS" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."ANALYSIS_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."APIKEY" (
    "ID" bigint NOT NULL,
    "APIKEY" character varying(255) NOT NULL,
    "COMMENT" character varying(255),
    "CREATED" timestamp with time zone,
    "LAST_USED" timestamp with time zone
);

CREATE TABLE public."APIKEYS_TEAMS" (
    "TEAM_ID" bigint NOT NULL,
    "APIKEY_ID" bigint NOT NULL
);

ALTER TABLE public."APIKEY" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."APIKEY_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."BOM" (
    "ID" bigint NOT NULL,
    "BOM_FORMAT" character varying(255),
    "BOM_VERSION" integer,
    "IMPORTED" timestamp with time zone NOT NULL,
    "PROJECT_ID" bigint NOT NULL,
    "SERIAL_NUMBER" character varying(255),
    "SPEC_VERSION" character varying(255),
    "UUID" uuid NOT NULL,
    "GENERATED" timestamp with time zone
);

ALTER TABLE public."BOM" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."BOM_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."BOM_UPLOAD" (
    "TOKEN" uuid NOT NULL,
    "UPLOADED_AT" timestamp with time zone NOT NULL,
    "BOM" bytea NOT NULL
);

CREATE TABLE public."COMPONENT" (
    "ID" bigint NOT NULL,
    "BLAKE2B_256" character varying(64),
    "BLAKE2B_384" character varying(96),
    "BLAKE2B_512" character varying(128),
    "BLAKE3" character varying(255),
    "CLASSIFIER" character varying(255),
    "COPYRIGHT" character varying(1024),
    "CPE" character varying(255),
    "DESCRIPTION" character varying(1024),
    "DIRECT_DEPENDENCIES" jsonb,
    "EXTENSION" character varying(255),
    "EXTERNAL_REFERENCES" bytea,
    "FILENAME" character varying(255),
    "GROUP" character varying(255),
    "INTERNAL" boolean,
    "LAST_RISKSCORE" double precision,
    "LICENSE" character varying(255),
    "LICENSE_EXPRESSION" text,
    "LICENSE_URL" character varying(255),
    "MD5" character varying(32),
    "NAME" character varying(255) NOT NULL,
    "TEXT" text,
    "PARENT_COMPONENT_ID" bigint,
    "PROJECT_ID" bigint NOT NULL,
    "PUBLISHER" character varying(255),
    "PURL" character varying(1024),
    "PURLCOORDINATES" character varying(255),
    "LICENSE_ID" bigint,
    "SHA1" character varying(40),
    "SHA_256" character varying(64),
    "SHA_384" character varying(96),
    "SHA3_256" character varying(64),
    "SHA3_384" character varying(96),
    "SHA3_512" character varying(128),
    "SHA_512" character varying(128),
    "SWIDTAGID" character varying(255),
    "UUID" uuid NOT NULL,
    "VERSION" character varying(255),
    "SUPPLIER" text,
    "AUTHORS" text,
    CONSTRAINT "COMPONENT_CLASSIFIER_check" CHECK ((("CLASSIFIER" IS NULL) OR (("CLASSIFIER")::text = ANY (ARRAY['APPLICATION'::text, 'CONTAINER'::text, 'DEVICE'::text, 'FILE'::text, 'FIRMWARE'::text, 'FRAMEWORK'::text, 'LIBRARY'::text, 'OPERATING_SYSTEM'::text]))))
);

CREATE TABLE public."COMPONENTS_VULNERABILITIES" (
    "COMPONENT_ID" bigint NOT NULL,
    "VULNERABILITY_ID" bigint NOT NULL
);

ALTER TABLE public."COMPONENT" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."COMPONENT_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."COMPONENT_PROPERTY" (
    "ID" bigint NOT NULL,
    "COMPONENT_ID" bigint NOT NULL,
    "GROUPNAME" character varying(255),
    "PROPERTYNAME" character varying(255) NOT NULL,
    "PROPERTYVALUE" character varying(1024),
    "PROPERTYTYPE" text NOT NULL,
    "DESCRIPTION" character varying(255),
    "UUID" uuid NOT NULL,
    CONSTRAINT "COMPONENT_PROPERTY_TYPE_check" CHECK ((("PROPERTYTYPE" IS NULL) OR ("PROPERTYTYPE" = ANY (ARRAY['BOOLEAN'::text, 'INTEGER'::text, 'NUMBER'::text, 'STRING'::text, 'ENCRYPTEDSTRING'::text, 'TIMESTAMP'::text, 'URL'::text, 'UUID'::text]))))
);

ALTER TABLE public."COMPONENT_PROPERTY" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."COMPONENT_PROPERTY_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."CONFIGPROPERTY" (
    "ID" bigint NOT NULL,
    "DESCRIPTION" character varying(255),
    "GROUPNAME" character varying(255) NOT NULL,
    "PROPERTYNAME" character varying(255) NOT NULL,
    "PROPERTYTYPE" character varying(255) NOT NULL,
    "PROPERTYVALUE" character varying(1024)
);

ALTER TABLE public."CONFIGPROPERTY" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."CONFIGPROPERTY_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."DEPENDENCYMETRICS" (
    "ID" bigint NOT NULL,
    "COMPONENT_ID" bigint NOT NULL,
    "CRITICAL" integer NOT NULL,
    "FINDINGS_AUDITED" integer,
    "FINDINGS_TOTAL" integer,
    "FINDINGS_UNAUDITED" integer,
    "FIRST_OCCURRENCE" timestamp with time zone NOT NULL,
    "HIGH" integer NOT NULL,
    "RISKSCORE" double precision NOT NULL,
    "LAST_OCCURRENCE" timestamp with time zone NOT NULL,
    "LOW" integer NOT NULL,
    "MEDIUM" integer NOT NULL,
    "POLICYVIOLATIONS_AUDITED" integer,
    "POLICYVIOLATIONS_FAIL" integer,
    "POLICYVIOLATIONS_INFO" integer,
    "POLICYVIOLATIONS_LICENSE_AUDITED" integer,
    "POLICYVIOLATIONS_LICENSE_TOTAL" integer,
    "POLICYVIOLATIONS_LICENSE_UNAUDITED" integer,
    "POLICYVIOLATIONS_OPERATIONAL_AUDITED" integer,
    "POLICYVIOLATIONS_OPERATIONAL_TOTAL" integer,
    "POLICYVIOLATIONS_OPERATIONAL_UNAUDITED" integer,
    "POLICYVIOLATIONS_SECURITY_AUDITED" integer,
    "POLICYVIOLATIONS_SECURITY_TOTAL" integer,
    "POLICYVIOLATIONS_SECURITY_UNAUDITED" integer,
    "POLICYVIOLATIONS_TOTAL" integer,
    "POLICYVIOLATIONS_UNAUDITED" integer,
    "POLICYVIOLATIONS_WARN" integer,
    "PROJECT_ID" bigint NOT NULL,
    "SUPPRESSED" integer NOT NULL,
    "UNASSIGNED_SEVERITY" integer,
    "VULNERABILITIES" integer NOT NULL
);

ALTER TABLE public."DEPENDENCYMETRICS" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."DEPENDENCYMETRICS_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."EPSS" (
    "ID" bigint NOT NULL,
    "CVE" text NOT NULL,
    "PERCENTILE" numeric,
    "SCORE" numeric
);

ALTER TABLE public."EPSS" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."EPSS_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."EVENTSERVICELOG" (
    "ID" bigint NOT NULL,
    "SUBSCRIBERCLASS" character varying(255) NOT NULL,
    "STARTED" timestamp with time zone,
    "COMPLETED" timestamp with time zone
);

ALTER TABLE public."EVENTSERVICELOG" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."EVENTSERVICELOG_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."FINDINGATTRIBUTION" (
    "ID" bigint NOT NULL,
    "ALT_ID" character varying(255),
    "ANALYZERIDENTITY" character varying(255) NOT NULL,
    "ATTRIBUTED_ON" timestamp with time zone NOT NULL,
    "COMPONENT_ID" bigint NOT NULL,
    "PROJECT_ID" bigint NOT NULL,
    "REFERENCE_URL" character varying(255),
    "UUID" uuid NOT NULL,
    "VULNERABILITY_ID" bigint NOT NULL
);

ALTER TABLE public."FINDINGATTRIBUTION" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."FINDINGATTRIBUTION_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."INSTALLEDUPGRADES" (
    "ID" bigint NOT NULL,
    "ENDTIME" timestamp with time zone,
    "STARTTIME" timestamp with time zone,
    "UPGRADECLASS" character varying(255)
);

ALTER TABLE public."INSTALLEDUPGRADES" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."INSTALLEDUPGRADES_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."INTEGRITY_ANALYSIS" (
    "ID" bigint NOT NULL,
    "COMPONENT_ID" bigint NOT NULL,
    "INTEGRITY_CHECK_STATUS" character varying(255) NOT NULL,
    "MD5_HASH_MATCH_STATUS" character varying(255) NOT NULL,
    "SHA1_HASH_MATCH_STATUS" character varying(255) NOT NULL,
    "SHA256_HASH_MATCH_STATUS" character varying(255) NOT NULL,
    "SHA512_HASH_MATCH_STATUS" character varying(255) NOT NULL,
    "UPDATED_AT" timestamp with time zone NOT NULL
);

ALTER TABLE public."INTEGRITY_ANALYSIS" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."INTEGRITY_ANALYSIS_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."INTEGRITY_META_COMPONENT" (
    "ID" bigint NOT NULL,
    "LAST_FETCH" timestamp with time zone,
    "MD5" character varying(32),
    "PUBLISHED_AT" timestamp with time zone,
    "PURL" character varying(1024) NOT NULL,
    "REPOSITORY_URL" character varying(1024),
    "SHA1" character varying(40),
    "SHA256" character varying(64),
    "SHA512" character varying(128),
    "STATUS" character varying(64),
    CONSTRAINT "INTEGRITY_META_COMPONENT_STATUS_check" CHECK ((("STATUS" IS NULL) OR (("STATUS")::text = ANY (ARRAY['IN_PROGRESS'::text, 'NOT_AVAILABLE'::text, 'PROCESSED'::text]))))
);

ALTER TABLE public."INTEGRITY_META_COMPONENT" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."INTEGRITY_META_COMPONENT_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."LDAPUSER" (
    "ID" bigint NOT NULL,
    "DN" character varying(255) NOT NULL,
    "EMAIL" character varying(255),
    "USERNAME" character varying(255)
);

CREATE TABLE public."LDAPUSERS_PERMISSIONS" (
    "LDAPUSER_ID" bigint NOT NULL,
    "PERMISSION_ID" bigint NOT NULL
);

CREATE TABLE public."LDAPUSERS_TEAMS" (
    "TEAM_ID" bigint NOT NULL,
    "LDAPUSER_ID" bigint NOT NULL
);

ALTER TABLE public."LDAPUSER" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."LDAPUSER_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."LICENSE" (
    "ID" bigint NOT NULL,
    "COMMENT" text,
    "ISCUSTOMLICENSE" boolean,
    "ISDEPRECATED" boolean NOT NULL,
    "FSFLIBRE" boolean,
    "HEADER" text,
    "LICENSEID" character varying(255),
    "NAME" character varying(255) NOT NULL,
    "ISOSIAPPROVED" boolean NOT NULL,
    "SEEALSO" bytea,
    "TEMPLATE" text,
    "TEXT" text,
    "UUID" uuid NOT NULL
);

CREATE TABLE public."LICENSEGROUP" (
    "ID" bigint NOT NULL,
    "NAME" character varying(255) NOT NULL,
    "RISKWEIGHT" integer NOT NULL,
    "UUID" uuid NOT NULL
);

ALTER TABLE public."LICENSEGROUP" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."LICENSEGROUP_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."LICENSEGROUP_LICENSE" (
    "LICENSEGROUP_ID" bigint NOT NULL,
    "LICENSE_ID" bigint NOT NULL
);

ALTER TABLE public."LICENSE" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."LICENSE_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."MANAGEDUSER" (
    "ID" bigint NOT NULL,
    "EMAIL" character varying(255),
    "FORCE_PASSWORD_CHANGE" boolean NOT NULL,
    "FULLNAME" character varying(255),
    "LAST_PASSWORD_CHANGE" timestamp with time zone NOT NULL,
    "NON_EXPIRY_PASSWORD" boolean NOT NULL,
    "PASSWORD" character varying(255) NOT NULL,
    "SUSPENDED" boolean NOT NULL,
    "USERNAME" character varying(255)
);

CREATE TABLE public."MANAGEDUSERS_PERMISSIONS" (
    "MANAGEDUSER_ID" bigint NOT NULL,
    "PERMISSION_ID" bigint NOT NULL
);

CREATE TABLE public."MANAGEDUSERS_TEAMS" (
    "TEAM_ID" bigint NOT NULL,
    "MANAGEDUSER_ID" bigint NOT NULL
);

ALTER TABLE public."MANAGEDUSER" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."MANAGEDUSER_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."MAPPEDLDAPGROUP" (
    "ID" bigint NOT NULL,
    "DN" character varying(1024) NOT NULL,
    "TEAM_ID" bigint NOT NULL,
    "UUID" character varying(36) NOT NULL
);

ALTER TABLE public."MAPPEDLDAPGROUP" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."MAPPEDLDAPGROUP_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."MAPPEDOIDCGROUP" (
    "ID" bigint NOT NULL,
    "GROUP_ID" bigint NOT NULL,
    "TEAM_ID" bigint NOT NULL,
    "UUID" character varying(36) NOT NULL
);

ALTER TABLE public."MAPPEDOIDCGROUP" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."MAPPEDOIDCGROUP_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."NOTIFICATIONPUBLISHER" (
    "ID" bigint NOT NULL,
    "DEFAULT_PUBLISHER" boolean NOT NULL,
    "DESCRIPTION" character varying(255),
    "NAME" character varying(255) NOT NULL,
    "PUBLISHER_CLASS" character varying(1024) NOT NULL,
    "TEMPLATE" text,
    "TEMPLATE_MIME_TYPE" character varying(255) NOT NULL,
    "UUID" uuid NOT NULL
);

ALTER TABLE public."NOTIFICATIONPUBLISHER" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."NOTIFICATIONPUBLISHER_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."NOTIFICATIONRULE" (
    "ID" bigint NOT NULL,
    "ENABLED" boolean NOT NULL,
    "MESSAGE" character varying(1024),
    "NAME" character varying(255) NOT NULL,
    "NOTIFICATION_LEVEL" character varying(255),
    "NOTIFY_CHILDREN" boolean,
    "NOTIFY_ON" character varying(1024),
    "PUBLISHER" bigint,
    "PUBLISHER_CONFIG" text,
    "SCOPE" character varying(255) NOT NULL,
    "UUID" uuid NOT NULL,
    "LOG_SUCCESSFUL_PUBLISH" boolean
);

ALTER TABLE public."NOTIFICATIONRULE" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."NOTIFICATIONRULE_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."NOTIFICATIONRULE_PROJECTS" (
    "NOTIFICATIONRULE_ID" bigint NOT NULL,
    "PROJECT_ID" bigint
);

CREATE TABLE public."NOTIFICATIONRULE_TAGS" (
    "NOTIFICATIONRULE_ID" bigint NOT NULL,
    "TAG_ID" bigint
);

CREATE TABLE public."NOTIFICATIONRULE_TEAMS" (
    "NOTIFICATIONRULE_ID" bigint NOT NULL,
    "TEAM_ID" bigint
);

CREATE TABLE public."OIDCGROUP" (
    "ID" bigint NOT NULL,
    "NAME" character varying(1024) NOT NULL,
    "UUID" character varying(36) NOT NULL
);

ALTER TABLE public."OIDCGROUP" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."OIDCGROUP_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."OIDCUSER" (
    "ID" bigint NOT NULL,
    "EMAIL" character varying(255),
    "SUBJECT_IDENTIFIER" character varying(255),
    "USERNAME" character varying(255) NOT NULL
);

CREATE TABLE public."OIDCUSERS_PERMISSIONS" (
    "PERMISSION_ID" bigint NOT NULL,
    "OIDCUSER_ID" bigint NOT NULL
);

CREATE TABLE public."OIDCUSERS_TEAMS" (
    "OIDCUSERS_ID" bigint NOT NULL,
    "TEAM_ID" bigint NOT NULL
);

ALTER TABLE public."OIDCUSER" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."OIDCUSER_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."PERMISSION" (
    "ID" bigint NOT NULL,
    "DESCRIPTION" text,
    "NAME" character varying(255) NOT NULL
);

ALTER TABLE public."PERMISSION" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."PERMISSION_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."POLICY" (
    "ID" bigint NOT NULL,
    "INCLUDE_CHILDREN" boolean,
    "NAME" character varying(255) NOT NULL,
    "OPERATOR" character varying(255) NOT NULL,
    "UUID" uuid NOT NULL,
    "VIOLATIONSTATE" character varying(255) NOT NULL,
    "ONLY_LATEST_PROJECT_VERSION" boolean DEFAULT false NOT NULL
);

CREATE TABLE public."POLICYCONDITION" (
    "ID" bigint NOT NULL,
    "OPERATOR" character varying(255) NOT NULL,
    "POLICY_ID" bigint NOT NULL,
    "SUBJECT" character varying(255) NOT NULL,
    "UUID" uuid NOT NULL,
    "VALUE" text NOT NULL,
    "VIOLATIONTYPE" character varying(255)
);

ALTER TABLE public."POLICYCONDITION" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."POLICYCONDITION_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."POLICYVIOLATION" (
    "ID" bigint NOT NULL,
    "COMPONENT_ID" bigint NOT NULL,
    "POLICYCONDITION_ID" bigint NOT NULL,
    "PROJECT_ID" bigint NOT NULL,
    "TEXT" character varying(255),
    "TIMESTAMP" timestamp with time zone NOT NULL,
    "TYPE" character varying(255) NOT NULL,
    "UUID" uuid NOT NULL
);

ALTER TABLE public."POLICYVIOLATION" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."POLICYVIOLATION_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE public."POLICY" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."POLICY_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."POLICY_PROJECTS" (
    "POLICY_ID" bigint NOT NULL,
    "PROJECT_ID" bigint
);

CREATE TABLE public."POLICY_TAGS" (
    "POLICY_ID" bigint NOT NULL,
    "TAG_ID" bigint
);

CREATE TABLE public."PORTFOLIOMETRICS" (
    "ID" bigint NOT NULL,
    "COMPONENTS" integer NOT NULL,
    "CRITICAL" integer NOT NULL,
    "FINDINGS_AUDITED" integer,
    "FINDINGS_TOTAL" integer,
    "FINDINGS_UNAUDITED" integer,
    "FIRST_OCCURRENCE" timestamp with time zone NOT NULL,
    "HIGH" integer NOT NULL,
    "RISKSCORE" double precision NOT NULL,
    "LAST_OCCURRENCE" timestamp with time zone NOT NULL,
    "LOW" integer NOT NULL,
    "MEDIUM" integer NOT NULL,
    "POLICYVIOLATIONS_AUDITED" integer,
    "POLICYVIOLATIONS_FAIL" integer,
    "POLICYVIOLATIONS_INFO" integer,
    "POLICYVIOLATIONS_LICENSE_AUDITED" integer,
    "POLICYVIOLATIONS_LICENSE_TOTAL" integer,
    "POLICYVIOLATIONS_LICENSE_UNAUDITED" integer,
    "POLICYVIOLATIONS_OPERATIONAL_AUDITED" integer,
    "POLICYVIOLATIONS_OPERATIONAL_TOTAL" integer,
    "POLICYVIOLATIONS_OPERATIONAL_UNAUDITED" integer,
    "POLICYVIOLATIONS_SECURITY_AUDITED" integer,
    "POLICYVIOLATIONS_SECURITY_TOTAL" integer,
    "POLICYVIOLATIONS_SECURITY_UNAUDITED" integer,
    "POLICYVIOLATIONS_TOTAL" integer,
    "POLICYVIOLATIONS_UNAUDITED" integer,
    "POLICYVIOLATIONS_WARN" integer,
    "PROJECTS" integer NOT NULL,
    "SUPPRESSED" integer NOT NULL,
    "UNASSIGNED_SEVERITY" integer,
    "VULNERABILITIES" integer NOT NULL,
    "VULNERABLECOMPONENTS" integer NOT NULL,
    "VULNERABLEPROJECTS" integer NOT NULL
);

ALTER TABLE public."PORTFOLIOMETRICS" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."PORTFOLIOMETRICS_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."PROJECT" (
    "ID" bigint NOT NULL,
    "CLASSIFIER" character varying(255),
    "CPE" character varying(255),
    "DESCRIPTION" character varying(255),
    "DIRECT_DEPENDENCIES" jsonb,
    "EXTERNAL_REFERENCES" bytea,
    "GROUP" character varying(255),
    "LAST_BOM_IMPORTED" timestamp with time zone,
    "LAST_BOM_IMPORTED_FORMAT" character varying(255),
    "LAST_RISKSCORE" double precision,
    "NAME" character varying(255) NOT NULL,
    "PARENT_PROJECT_ID" bigint,
    "PUBLISHER" character varying(255),
    "PURL" character varying(255),
    "SWIDTAGID" character varying(255),
    "UUID" uuid NOT NULL,
    "VERSION" character varying(255),
    "SUPPLIER" text,
    "MANUFACTURER" text,
    "AUTHORS" text,
    "IS_LATEST" boolean DEFAULT false NOT NULL,
    "INACTIVE_SINCE" timestamp with time zone,
    CONSTRAINT "PROJECT_CLASSIFIER_check" CHECK ((("CLASSIFIER" IS NULL) OR (("CLASSIFIER")::text = ANY (ARRAY['APPLICATION'::text, 'CONTAINER'::text, 'DEVICE'::text, 'FILE'::text, 'FIRMWARE'::text, 'FRAMEWORK'::text, 'LIBRARY'::text, 'OPERATING_SYSTEM'::text]))))
);

CREATE TABLE public."PROJECTMETRICS" (
    "ID" bigint NOT NULL,
    "COMPONENTS" integer NOT NULL,
    "CRITICAL" integer NOT NULL,
    "FINDINGS_AUDITED" integer,
    "FINDINGS_TOTAL" integer,
    "FINDINGS_UNAUDITED" integer,
    "FIRST_OCCURRENCE" timestamp with time zone NOT NULL,
    "HIGH" integer NOT NULL,
    "RISKSCORE" double precision NOT NULL,
    "LAST_OCCURRENCE" timestamp with time zone NOT NULL,
    "LOW" integer NOT NULL,
    "MEDIUM" integer NOT NULL,
    "POLICYVIOLATIONS_AUDITED" integer,
    "POLICYVIOLATIONS_FAIL" integer,
    "POLICYVIOLATIONS_INFO" integer,
    "POLICYVIOLATIONS_LICENSE_AUDITED" integer,
    "POLICYVIOLATIONS_LICENSE_TOTAL" integer,
    "POLICYVIOLATIONS_LICENSE_UNAUDITED" integer,
    "POLICYVIOLATIONS_OPERATIONAL_AUDITED" integer,
    "POLICYVIOLATIONS_OPERATIONAL_TOTAL" integer,
    "POLICYVIOLATIONS_OPERATIONAL_UNAUDITED" integer,
    "POLICYVIOLATIONS_SECURITY_AUDITED" integer,
    "POLICYVIOLATIONS_SECURITY_TOTAL" integer,
    "POLICYVIOLATIONS_SECURITY_UNAUDITED" integer,
    "POLICYVIOLATIONS_TOTAL" integer,
    "POLICYVIOLATIONS_UNAUDITED" integer,
    "POLICYVIOLATIONS_WARN" integer,
    "PROJECT_ID" bigint NOT NULL,
    "SUPPRESSED" integer NOT NULL,
    "UNASSIGNED_SEVERITY" integer,
    "VULNERABILITIES" integer NOT NULL,
    "VULNERABLECOMPONENTS" integer NOT NULL
);

ALTER TABLE public."PROJECTMETRICS" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."PROJECTMETRICS_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."PROJECTS_TAGS" (
    "TAG_ID" bigint NOT NULL,
    "PROJECT_ID" bigint NOT NULL
);

CREATE TABLE public."PROJECT_ACCESS_TEAMS" (
    "PROJECT_ID" bigint NOT NULL,
    "TEAM_ID" bigint
);

ALTER TABLE public."PROJECT" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."PROJECT_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."PROJECT_METADATA" (
    "ID" bigint NOT NULL,
    "PROJECT_ID" bigint NOT NULL,
    "SUPPLIER" text,
    "AUTHORS" text,
    "TOOLS" text
);

ALTER TABLE public."PROJECT_METADATA" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."PROJECT_METADATA_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."PROJECT_PROPERTY" (
    "ID" bigint NOT NULL,
    "DESCRIPTION" character varying(255),
    "GROUPNAME" character varying(255) NOT NULL,
    "PROJECT_ID" bigint NOT NULL,
    "PROPERTYNAME" character varying(255) NOT NULL,
    "PROPERTYTYPE" character varying(255) NOT NULL,
    "PROPERTYVALUE" character varying(1024)
);

ALTER TABLE public."PROJECT_PROPERTY" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."PROJECT_PROPERTY_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."REPOSITORY" (
    "ID" bigint NOT NULL,
    "AUTHENTICATIONREQUIRED" boolean,
    "ENABLED" boolean NOT NULL,
    "IDENTIFIER" character varying(255) NOT NULL,
    "INTERNAL" boolean,
    "PASSWORD" character varying(255),
    "RESOLUTION_ORDER" integer NOT NULL,
    "TYPE" character varying(255) NOT NULL,
    "URL" character varying(255),
    "USERNAME" character varying(255),
    "UUID" uuid
);

ALTER TABLE public."REPOSITORY" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."REPOSITORY_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."REPOSITORY_META_COMPONENT" (
    "ID" bigint NOT NULL,
    "LAST_CHECK" timestamp with time zone NOT NULL,
    "LATEST_VERSION" character varying(255) NOT NULL,
    "NAME" character varying(255) NOT NULL,
    "NAMESPACE" character varying(255),
    "PUBLISHED" timestamp with time zone,
    "REPOSITORY_TYPE" character varying(255) NOT NULL
);

ALTER TABLE public."REPOSITORY_META_COMPONENT" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."REPOSITORY_META_COMPONENT_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."SCHEMAVERSION" (
    "ID" bigint NOT NULL,
    "VERSION" character varying(255)
);

ALTER TABLE public."SCHEMAVERSION" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."SCHEMAVERSION_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."SERVICECOMPONENT" (
    "ID" bigint NOT NULL,
    "AUTHENTICATED" boolean,
    "X_TRUST_BOUNDARY" boolean,
    "DATA" bytea,
    "DESCRIPTION" character varying(1024),
    "ENDPOINTS" bytea,
    "EXTERNAL_REFERENCES" bytea,
    "GROUP" character varying(255),
    "LAST_RISKSCORE" double precision DEFAULT '0'::double precision NOT NULL,
    "NAME" character varying(255) NOT NULL,
    "TEXT" text,
    "PARENT_SERVICECOMPONENT_ID" bigint,
    "PROJECT_ID" bigint NOT NULL,
    "PROVIDER_ID" bytea,
    "UUID" uuid NOT NULL,
    "VERSION" character varying(255)
);

CREATE TABLE public."SERVICECOMPONENTS_VULNERABILITIES" (
    "VULNERABILITY_ID" bigint NOT NULL,
    "SERVICECOMPONENT_ID" bigint NOT NULL
);

ALTER TABLE public."SERVICECOMPONENT" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."SERVICECOMPONENT_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."TAG" (
    "ID" bigint NOT NULL,
    "NAME" character varying(255) NOT NULL
);

ALTER TABLE public."TAG" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."TAG_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."TEAM" (
    "ID" bigint NOT NULL,
    "NAME" character varying(255) NOT NULL,
    "UUID" character varying(36) NOT NULL
);

CREATE TABLE public."TEAMS_PERMISSIONS" (
    "TEAM_ID" bigint NOT NULL,
    "PERMISSION_ID" bigint NOT NULL
);

ALTER TABLE public."TEAM" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."TEAM_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."VEX" (
    "ID" bigint NOT NULL,
    "IMPORTED" timestamp with time zone NOT NULL,
    "PROJECT_ID" bigint NOT NULL,
    "SERIAL_NUMBER" character varying(255),
    "SPEC_VERSION" character varying(255),
    "UUID" uuid NOT NULL,
    "VEX_FORMAT" character varying(255),
    "VEX_VERSION" integer
);

ALTER TABLE public."VEX" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VEX_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."VIOLATIONANALYSIS" (
    "ID" bigint NOT NULL,
    "STATE" character varying(255) NOT NULL,
    "COMPONENT_ID" bigint,
    "POLICYVIOLATION_ID" bigint NOT NULL,
    "PROJECT_ID" bigint,
    "SUPPRESSED" boolean NOT NULL
);

CREATE TABLE public."VIOLATIONANALYSISCOMMENT" (
    "ID" bigint NOT NULL,
    "COMMENT" text NOT NULL,
    "COMMENTER" character varying(255),
    "TIMESTAMP" timestamp with time zone NOT NULL,
    "VIOLATIONANALYSIS_ID" bigint NOT NULL
);

ALTER TABLE public."VIOLATIONANALYSISCOMMENT" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VIOLATIONANALYSISCOMMENT_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE public."VIOLATIONANALYSIS" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VIOLATIONANALYSIS_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."VULNERABILITIES_TAGS" (
    "TAG_ID" bigint NOT NULL,
    "VULNERABILITY_ID" bigint NOT NULL
);

CREATE TABLE public."VULNERABILITY" (
    "ID" bigint NOT NULL,
    "CREATED" timestamp with time zone,
    "CREDITS" text,
    "CVSSV2BASESCORE" numeric,
    "CVSSV2EXPLOITSCORE" numeric,
    "CVSSV2IMPACTSCORE" numeric,
    "CVSSV2VECTOR" character varying(255),
    "CVSSV3BASESCORE" numeric,
    "CVSSV3EXPLOITSCORE" numeric,
    "CVSSV3IMPACTSCORE" numeric,
    "CVSSV3VECTOR" character varying(255),
    "CWES" character varying(255),
    "DESCRIPTION" text,
    "DETAIL" text,
    "FRIENDLYVULNID" character varying(255),
    "OWASPRRBUSINESSIMPACTSCORE" numeric,
    "OWASPRRLIKELIHOODSCORE" numeric,
    "OWASPRRTECHNICALIMPACTSCORE" numeric,
    "OWASPRRVECTOR" character varying(255),
    "PATCHEDVERSIONS" character varying(255),
    "PUBLISHED" timestamp with time zone,
    "RECOMMENDATION" text,
    "REFERENCES" text,
    "SEVERITY" character varying(255),
    "SOURCE" character varying(255) NOT NULL,
    "SUBTITLE" character varying(255),
    "TITLE" character varying(255),
    "UPDATED" timestamp with time zone,
    "UUID" uuid NOT NULL,
    "VULNID" character varying(255) NOT NULL,
    "VULNERABLEVERSIONS" character varying(255)
);

CREATE TABLE public."VULNERABILITYALIAS" (
    "ID" bigint NOT NULL,
    "CVE_ID" character varying(255),
    "GHSA_ID" character varying(255),
    "GSD_ID" character varying(255),
    "INTERNAL_ID" character varying(255),
    "OSV_ID" character varying(255),
    "SNYK_ID" character varying(255),
    "SONATYPE_ID" character varying(255),
    "UUID" uuid NOT NULL,
    "VULNDB_ID" character varying(255)
);

ALTER TABLE public."VULNERABILITYALIAS" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VULNERABILITYALIAS_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."VULNERABILITYMETRICS" (
    "ID" bigint NOT NULL,
    "COUNT" integer NOT NULL,
    "MEASURED_AT" timestamp with time zone NOT NULL,
    "MONTH" integer,
    "YEAR" integer NOT NULL
);

ALTER TABLE public."VULNERABILITYMETRICS" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VULNERABILITYMETRICS_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."VULNERABILITYSCAN" (
    "ID" bigint NOT NULL,
    "EXPECTED_RESULTS" integer NOT NULL,
    "FAILURE_THRESHOLD" double precision,
    "RECEIVED_RESULTS" integer NOT NULL,
    "SCAN_FAILED" bigint,
    "SCAN_TOTAL" bigint,
    "STARTED_AT" timestamp with time zone NOT NULL,
    "STATUS" character varying(255) NOT NULL,
    "TARGET_IDENTIFIER" uuid NOT NULL,
    "TARGET_TYPE" character varying(255) NOT NULL,
    "TOKEN" uuid NOT NULL,
    "UPDATED_AT" timestamp with time zone NOT NULL,
    "VERSION" bigint NOT NULL
);

ALTER TABLE public."VULNERABILITYSCAN" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VULNERABILITYSCAN_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE public."VULNERABILITY" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VULNERABILITY_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."VULNERABILITY_POLICY" (
    "ID" bigint NOT NULL,
    "ANALYSIS" jsonb NOT NULL,
    "AUTHOR" character varying(255),
    "CONDITIONS" text[] NOT NULL,
    "CREATED" timestamp with time zone,
    "DESCRIPTION" character varying(512),
    "NAME" character varying(255) NOT NULL,
    "RATINGS" jsonb,
    "UPDATED" timestamp with time zone,
    "VALID_FROM" timestamp with time zone,
    "VALID_UNTIL" timestamp with time zone,
    "OPERATION_MODE" character varying(255) DEFAULT 'APPLY'::character varying NOT NULL
);

CREATE TABLE public."VULNERABILITY_POLICY_BUNDLE" (
    "ID" bigint NOT NULL,
    "URL" character varying(2048) NOT NULL,
    "HASH" character varying(255),
    "LAST_SUCCESSFUL_SYNC" timestamp with time zone,
    "CREATED" timestamp with time zone,
    "UPDATED" timestamp with time zone
);

ALTER TABLE public."VULNERABILITY_POLICY_BUNDLE" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VULNERABILITY_POLICY_BUNDLE_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE public."VULNERABILITY_POLICY" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VULNERABILITY_POLICY_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."VULNERABLESOFTWARE" (
    "ID" bigint NOT NULL,
    "CPE22" character varying(255),
    "CPE23" character varying(255),
    "EDITION" character varying(255),
    "LANGUAGE" character varying(255),
    "OTHER" character varying(255),
    "PART" character varying(255),
    "PRODUCT" character varying(255),
    "PURL" character varying(255),
    "PURL_NAME" character varying(255),
    "PURL_NAMESPACE" character varying(255),
    "PURL_QUALIFIERS" character varying(255),
    "PURL_SUBPATH" character varying(255),
    "PURL_TYPE" character varying(255),
    "PURL_VERSION" character varying(255),
    "SWEDITION" character varying(255),
    "TARGETHW" character varying(255),
    "TARGETSW" character varying(255),
    "UPDATE" character varying(255),
    "UUID" uuid NOT NULL,
    "VENDOR" character varying(255),
    "VERSION" character varying(255),
    "VERSIONENDEXCLUDING" character varying(255),
    "VERSIONENDINCLUDING" character varying(255),
    "VERSIONSTARTEXCLUDING" character varying(255),
    "VERSIONSTARTINCLUDING" character varying(255),
    "VULNERABLE" boolean NOT NULL
);

ALTER TABLE public."VULNERABLESOFTWARE" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."VULNERABLESOFTWARE_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public."VULNERABLESOFTWARE_VULNERABILITIES" (
    "VULNERABILITY_ID" bigint NOT NULL,
    "VULNERABLESOFTWARE_ID" bigint NOT NULL
);

CREATE TABLE public."WORKFLOW_STATE" (
    "ID" bigint NOT NULL,
    "FAILURE_REASON" text,
    "PARENT_STEP_ID" bigint,
    "STARTED_AT" timestamp with time zone,
    "STATUS" character varying(64) NOT NULL,
    "STEP" character varying(64) NOT NULL,
    "TOKEN" uuid NOT NULL,
    "UPDATED_AT" timestamp with time zone NOT NULL,
    CONSTRAINT "WORKFLOW_STATE_STATUS_check" CHECK ((("STATUS")::text = ANY (ARRAY['CANCELLED'::text, 'COMPLETED'::text, 'FAILED'::text, 'NOT_APPLICABLE'::text, 'PENDING'::text, 'TIMED_OUT'::text]))),
    CONSTRAINT "WORKFLOW_STATE_STEP_check" CHECK ((("STEP")::text = ANY (ARRAY['BOM_CONSUMPTION'::text, 'BOM_PROCESSING'::text, 'METRICS_UPDATE'::text, 'POLICY_BUNDLE_SYNC'::text, 'POLICY_EVALUATION'::text, 'REPO_META_ANALYSIS'::text, 'VULN_ANALYSIS'::text, 'PROJECT_CLONE'::text])))
);

ALTER TABLE public."WORKFLOW_STATE" ALTER COLUMN "ID" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."WORKFLOW_STATE_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public.databasechangelog (
    id character varying(255) NOT NULL,
    author character varying(255) NOT NULL,
    filename character varying(255) NOT NULL,
    dateexecuted timestamp without time zone NOT NULL,
    orderexecuted integer NOT NULL,
    exectype character varying(10) NOT NULL,
    md5sum character varying(35),
    description character varying(255),
    comments character varying(255),
    tag character varying(255),
    liquibase character varying(20),
    contexts character varying(255),
    labels character varying(255),
    deployment_id character varying(10)
);

CREATE TABLE public.databasechangeloglock (
    id integer NOT NULL,
    locked boolean NOT NULL,
    lockgranted timestamp without time zone,
    lockedby character varying(255)
);

CREATE TABLE public.shedlock (
    name character varying(64) NOT NULL,
    lock_until timestamp without time zone NOT NULL,
    locked_at timestamp without time zone NOT NULL,
    locked_by character varying(255) NOT NULL
);

ALTER TABLE ONLY public."AFFECTEDVERSIONATTRIBUTION"
    ADD CONSTRAINT "AFFECTEDVERSIONATTRIBUTION_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."AFFECTEDVERSIONATTRIBUTION"
    ADD CONSTRAINT "AFFECTEDVERSIONATTRIBUTION_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."ANALYSISCOMMENT"
    ADD CONSTRAINT "ANALYSISCOMMENT_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."ANALYSIS"
    ADD CONSTRAINT "ANALYSIS_COMPOSITE_IDX" UNIQUE ("PROJECT_ID", "COMPONENT_ID", "VULNERABILITY_ID");

ALTER TABLE ONLY public."ANALYSIS"
    ADD CONSTRAINT "ANALYSIS_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."APIKEY"
    ADD CONSTRAINT "APIKEY_IDX" UNIQUE ("APIKEY");

ALTER TABLE ONLY public."APIKEY"
    ADD CONSTRAINT "APIKEY_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."BOM"
    ADD CONSTRAINT "BOM_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."BOM_UPLOAD"
    ADD CONSTRAINT "BOM_UPLOAD_PK" PRIMARY KEY ("TOKEN");

ALTER TABLE ONLY public."BOM"
    ADD CONSTRAINT "BOM_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."COMPONENT"
    ADD CONSTRAINT "COMPONENT_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."COMPONENT_PROPERTY"
    ADD CONSTRAINT "COMPONENT_PROPERTY_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."COMPONENT"
    ADD CONSTRAINT "COMPONENT_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."CONFIGPROPERTY"
    ADD CONSTRAINT "CONFIGPROPERTY_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."CONFIGPROPERTY"
    ADD CONSTRAINT "CONFIGPROPERTY_U1" UNIQUE ("GROUPNAME", "PROPERTYNAME");

ALTER TABLE ONLY public."DEPENDENCYMETRICS"
    ADD CONSTRAINT "DEPENDENCYMETRICS_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."EPSS"
    ADD CONSTRAINT "EPSS_CVE_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."EPSS"
    ADD CONSTRAINT "EPSS_CVE_key" UNIQUE ("CVE");

ALTER TABLE ONLY public."EVENTSERVICELOG"
    ADD CONSTRAINT "EVENTSERVICELOG_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."FINDINGATTRIBUTION"
    ADD CONSTRAINT "FINDINGATTRIBUTION_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."FINDINGATTRIBUTION"
    ADD CONSTRAINT "FINDINGATTRIBUTION_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."INSTALLEDUPGRADES"
    ADD CONSTRAINT "INSTALLEDUPGRADES_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."INTEGRITY_ANALYSIS"
    ADD CONSTRAINT "INTEGRITY_ANALYSIS_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."INTEGRITY_META_COMPONENT"
    ADD CONSTRAINT "INTEGRITY_META_COMPONENT_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."LDAPUSER"
    ADD CONSTRAINT "LDAPUSER_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."LDAPUSER"
    ADD CONSTRAINT "LDAPUSER_USERNAME_IDX" UNIQUE ("USERNAME");

ALTER TABLE ONLY public."LICENSEGROUP"
    ADD CONSTRAINT "LICENSEGROUP_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."LICENSEGROUP"
    ADD CONSTRAINT "LICENSEGROUP_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."LICENSE"
    ADD CONSTRAINT "LICENSE_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."LICENSE"
    ADD CONSTRAINT "LICENSE_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."MANAGEDUSER"
    ADD CONSTRAINT "MANAGEDUSER_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."MANAGEDUSER"
    ADD CONSTRAINT "MANAGEDUSER_USERNAME_IDX" UNIQUE ("USERNAME");

ALTER TABLE ONLY public."MAPPEDLDAPGROUP"
    ADD CONSTRAINT "MAPPEDLDAPGROUP_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."MAPPEDLDAPGROUP"
    ADD CONSTRAINT "MAPPEDLDAPGROUP_U1" UNIQUE ("TEAM_ID", "DN");

ALTER TABLE ONLY public."MAPPEDLDAPGROUP"
    ADD CONSTRAINT "MAPPEDLDAPGROUP_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."MAPPEDOIDCGROUP"
    ADD CONSTRAINT "MAPPEDOIDCGROUP_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."MAPPEDOIDCGROUP"
    ADD CONSTRAINT "MAPPEDOIDCGROUP_U1" UNIQUE ("TEAM_ID", "GROUP_ID");

ALTER TABLE ONLY public."MAPPEDOIDCGROUP"
    ADD CONSTRAINT "MAPPEDOIDCGROUP_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."NOTIFICATIONPUBLISHER"
    ADD CONSTRAINT "NOTIFICATIONPUBLISHER_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."NOTIFICATIONPUBLISHER"
    ADD CONSTRAINT "NOTIFICATIONPUBLISHER_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."NOTIFICATIONRULE"
    ADD CONSTRAINT "NOTIFICATIONRULE_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."NOTIFICATIONRULE"
    ADD CONSTRAINT "NOTIFICATIONRULE_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."OIDCGROUP"
    ADD CONSTRAINT "OIDCGROUP_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."OIDCGROUP"
    ADD CONSTRAINT "OIDCGROUP_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."OIDCUSER"
    ADD CONSTRAINT "OIDCUSER_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."OIDCUSER"
    ADD CONSTRAINT "OIDCUSER_USERNAME_IDX" UNIQUE ("USERNAME");

ALTER TABLE ONLY public."PERMISSION"
    ADD CONSTRAINT "PERMISSION_IDX" UNIQUE ("NAME");

ALTER TABLE ONLY public."PERMISSION"
    ADD CONSTRAINT "PERMISSION_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."POLICYCONDITION"
    ADD CONSTRAINT "POLICYCONDITION_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."POLICYCONDITION"
    ADD CONSTRAINT "POLICYCONDITION_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."POLICYVIOLATION"
    ADD CONSTRAINT "POLICYVIOLATION_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."POLICYVIOLATION"
    ADD CONSTRAINT "POLICYVIOLATION_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."POLICY"
    ADD CONSTRAINT "POLICY_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."POLICY"
    ADD CONSTRAINT "POLICY_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."PORTFOLIOMETRICS"
    ADD CONSTRAINT "PORTFOLIOMETRICS_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."PROJECTMETRICS"
    ADD CONSTRAINT "PROJECTMETRICS_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."PROJECT_METADATA"
    ADD CONSTRAINT "PROJECT_METADATA_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."PROJECT"
    ADD CONSTRAINT "PROJECT_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."PROJECT_PROPERTY"
    ADD CONSTRAINT "PROJECT_PROPERTY_KEYS_IDX" UNIQUE ("PROJECT_ID", "GROUPNAME", "PROPERTYNAME");

ALTER TABLE ONLY public."PROJECT_PROPERTY"
    ADD CONSTRAINT "PROJECT_PROPERTY_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."PROJECT"
    ADD CONSTRAINT "PROJECT_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."REPOSITORY"
    ADD CONSTRAINT "REPOSITORY_COMPOUND_IDX" UNIQUE ("TYPE", "IDENTIFIER");

ALTER TABLE ONLY public."REPOSITORY_META_COMPONENT"
    ADD CONSTRAINT "REPOSITORY_META_COMPONENT_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."REPOSITORY"
    ADD CONSTRAINT "REPOSITORY_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."SCHEMAVERSION"
    ADD CONSTRAINT "SCHEMAVERSION_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."SERVICECOMPONENT"
    ADD CONSTRAINT "SERVICECOMPONENT_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."SERVICECOMPONENT"
    ADD CONSTRAINT "SERVICECOMPONENT_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."TAG"
    ADD CONSTRAINT "TAG_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."TEAM"
    ADD CONSTRAINT "TEAM_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."TEAM"
    ADD CONSTRAINT "TEAM_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."VEX"
    ADD CONSTRAINT "VEX_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VEX"
    ADD CONSTRAINT "VEX_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."VIOLATIONANALYSISCOMMENT"
    ADD CONSTRAINT "VIOLATIONANALYSISCOMMENT_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VIOLATIONANALYSIS"
    ADD CONSTRAINT "VIOLATIONANALYSIS_COMPOSITE_IDX" UNIQUE ("PROJECT_ID", "COMPONENT_ID", "POLICYVIOLATION_ID");

ALTER TABLE ONLY public."VIOLATIONANALYSIS"
    ADD CONSTRAINT "VIOLATIONANALYSIS_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VULNERABILITYALIAS"
    ADD CONSTRAINT "VULNERABILITYALIAS_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VULNERABILITYALIAS"
    ADD CONSTRAINT "VULNERABILITYALIAS_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."VULNERABILITYMETRICS"
    ADD CONSTRAINT "VULNERABILITYMETRICS_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VULNERABILITY_POLICY"
    ADD CONSTRAINT "VULNERABILITYPOLICY_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VULNERABILITYSCAN"
    ADD CONSTRAINT "VULNERABILITYSCAN_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VULNERABILITY"
    ADD CONSTRAINT "VULNERABILITY_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VULNERABILITY_POLICY_BUNDLE"
    ADD CONSTRAINT "VULNERABILITY_POLICY_BUNDLE_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VULNERABILITYSCAN"
    ADD CONSTRAINT "VULNERABILITY_SCAN_TOKEN_IDX" UNIQUE ("TOKEN");

ALTER TABLE ONLY public."VULNERABILITY"
    ADD CONSTRAINT "VULNERABILITY_U1" UNIQUE ("VULNID", "SOURCE");

ALTER TABLE ONLY public."VULNERABILITY"
    ADD CONSTRAINT "VULNERABILITY_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."VULNERABLESOFTWARE"
    ADD CONSTRAINT "VULNERABLESOFTWARE_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public."VULNERABLESOFTWARE"
    ADD CONSTRAINT "VULNERABLESOFTWARE_UUID_IDX" UNIQUE ("UUID");

ALTER TABLE ONLY public."WORKFLOW_STATE"
    ADD CONSTRAINT "WORKFLOW_STATE_COMPOSITE_IDX" UNIQUE ("TOKEN", "STEP");

ALTER TABLE ONLY public."WORKFLOW_STATE"
    ADD CONSTRAINT "WORKFLOW_STATE_PK" PRIMARY KEY ("ID");

ALTER TABLE ONLY public.databasechangeloglock
    ADD CONSTRAINT databasechangeloglock_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.shedlock
    ADD CONSTRAINT shedlock_pk PRIMARY KEY (name);

CREATE INDEX "AFFECTEDVERSIONATTRIBUTION_KEYS_IDX" ON public."AFFECTEDVERSIONATTRIBUTION" USING btree ("VULNERABILITY", "VULNERABLE_SOFTWARE");

CREATE INDEX "ANALYSISCOMMENT_ANALYSIS_ID_IDX" ON public."ANALYSISCOMMENT" USING btree ("ANALYSIS_ID");

CREATE INDEX "ANALYSIS_COMPONENT_ID_IDX" ON public."ANALYSIS" USING btree ("COMPONENT_ID");

CREATE INDEX "ANALYSIS_VULNERABILITY_ID_IDX" ON public."ANALYSIS" USING btree ("VULNERABILITY_ID");

CREATE INDEX "APIKEYS_TEAMS_APIKEY_ID_IDX" ON public."APIKEYS_TEAMS" USING btree ("APIKEY_ID");

CREATE INDEX "APIKEYS_TEAMS_TEAM_ID_IDX" ON public."APIKEYS_TEAMS" USING btree ("TEAM_ID");

CREATE INDEX "BOM_PROJECT_ID_IDX" ON public."BOM" USING btree ("PROJECT_ID");

CREATE UNIQUE INDEX "COMPONENTS_VULNERABILITIES_COMPOSITE_IDX" ON public."COMPONENTS_VULNERABILITIES" USING btree ("COMPONENT_ID", "VULNERABILITY_ID");

CREATE INDEX "COMPONENTS_VULNERABILITIES_VULNERABILITY_ID_IDX" ON public."COMPONENTS_VULNERABILITIES" USING btree ("VULNERABILITY_ID");

CREATE INDEX "COMPONENT_BLAKE2B_256_IDX" ON public."COMPONENT" USING btree ("BLAKE2B_256") WHERE ("BLAKE2B_256" IS NOT NULL);

CREATE INDEX "COMPONENT_BLAKE2B_384_IDX" ON public."COMPONENT" USING btree ("BLAKE2B_384") WHERE ("BLAKE2B_384" IS NOT NULL);

CREATE INDEX "COMPONENT_BLAKE2B_512_IDX" ON public."COMPONENT" USING btree ("BLAKE2B_512") WHERE ("BLAKE2B_512" IS NOT NULL);

CREATE INDEX "COMPONENT_BLAKE3_IDX" ON public."COMPONENT" USING btree ("BLAKE3") WHERE ("BLAKE3" IS NOT NULL);

CREATE INDEX "COMPONENT_CLASSIFIER_IDX" ON public."COMPONENT" USING btree ("CLASSIFIER");

CREATE INDEX "COMPONENT_CPE_IDX" ON public."COMPONENT" USING btree ("CPE");

CREATE INDEX "COMPONENT_DIRECT_DEPENDENCIES_JSONB_IDX" ON public."COMPONENT" USING gin ("DIRECT_DEPENDENCIES" jsonb_path_ops);

CREATE INDEX "COMPONENT_GROUP_IDX" ON public."COMPONENT" USING btree ("GROUP");

CREATE INDEX "COMPONENT_LAST_RISKSCORE_IDX" ON public."COMPONENT" USING btree ("LAST_RISKSCORE");

CREATE INDEX "COMPONENT_LICENSE_ID_IDX" ON public."COMPONENT" USING btree ("LICENSE_ID");

CREATE INDEX "COMPONENT_MD5_IDX" ON public."COMPONENT" USING btree ("MD5") WHERE ("MD5" IS NOT NULL);

CREATE INDEX "COMPONENT_NAME_IDX" ON public."COMPONENT" USING btree ("NAME");

CREATE INDEX "COMPONENT_PARENT_COMPONENT_ID_IDX" ON public."COMPONENT" USING btree ("PARENT_COMPONENT_ID");

CREATE INDEX "COMPONENT_PROJECT_ID_IDX" ON public."COMPONENT" USING btree ("PROJECT_ID");

CREATE INDEX "COMPONENT_PROPERTY_COMPONENT_ID_IDX" ON public."COMPONENT_PROPERTY" USING btree ("COMPONENT_ID");

CREATE INDEX "COMPONENT_PURL_COORDINATES_IDX" ON public."COMPONENT" USING btree ("PURLCOORDINATES");

CREATE INDEX "COMPONENT_PURL_IDX" ON public."COMPONENT" USING btree ("PURL");

CREATE INDEX "COMPONENT_SHA1_IDX" ON public."COMPONENT" USING btree ("SHA1") WHERE ("SHA1" IS NOT NULL);

CREATE INDEX "COMPONENT_SHA3_256_IDX" ON public."COMPONENT" USING btree ("SHA3_256") WHERE ("SHA3_256" IS NOT NULL);

CREATE INDEX "COMPONENT_SHA3_384_IDX" ON public."COMPONENT" USING btree ("SHA3_384") WHERE ("SHA3_384" IS NOT NULL);

CREATE INDEX "COMPONENT_SHA3_512_IDX" ON public."COMPONENT" USING btree ("SHA3_512") WHERE ("SHA3_512" IS NOT NULL);

CREATE INDEX "COMPONENT_SHA_256_IDX" ON public."COMPONENT" USING btree ("SHA_256") WHERE ("SHA_256" IS NOT NULL);

CREATE INDEX "COMPONENT_SHA_384_IDX" ON public."COMPONENT" USING btree ("SHA_384") WHERE ("SHA_384" IS NOT NULL);

CREATE INDEX "COMPONENT_SHA_512_IDX" ON public."COMPONENT" USING btree ("SHA_512") WHERE ("SHA_512" IS NOT NULL);

CREATE INDEX "COMPONENT_SWID_TAGID_IDX" ON public."COMPONENT" USING btree ("SWIDTAGID");

CREATE INDEX "DEPENDENCYMETRICS_COMPONENT_ID_IDX" ON public."DEPENDENCYMETRICS" USING btree ("COMPONENT_ID");

CREATE INDEX "DEPENDENCYMETRICS_COMPOSITE_IDX" ON public."DEPENDENCYMETRICS" USING btree ("PROJECT_ID", "COMPONENT_ID");

CREATE INDEX "DEPENDENCYMETRICS_FIRST_OCCURRENCE_IDX" ON public."DEPENDENCYMETRICS" USING btree ("FIRST_OCCURRENCE");

CREATE INDEX "DEPENDENCYMETRICS_LAST_OCCURRENCE_IDX" ON public."DEPENDENCYMETRICS" USING btree ("LAST_OCCURRENCE");

CREATE UNIQUE INDEX "EPSS_CVE_IDX" ON public."EPSS" USING btree ("CVE");

CREATE UNIQUE INDEX "FINDINGATTRIBUTION_COMPOUND_IDX" ON public."FINDINGATTRIBUTION" USING btree ("COMPONENT_ID", "VULNERABILITY_ID");

CREATE INDEX "FINDINGATTRIBUTION_PROJECT_ID_IDX" ON public."FINDINGATTRIBUTION" USING btree ("PROJECT_ID");

CREATE INDEX "FINDINGATTRIBUTION_VULNERABILITY_ID_IDX" ON public."FINDINGATTRIBUTION" USING btree ("VULNERABILITY_ID");

CREATE INDEX "INTEGRITY_ANALYSIS_COMPONENT_ID_IDX" ON public."INTEGRITY_ANALYSIS" USING btree ("COMPONENT_ID");

CREATE UNIQUE INDEX "INTEGRITY_META_COMPONENT_PURL_IDX" ON public."INTEGRITY_META_COMPONENT" USING btree ("PURL");

CREATE INDEX "LAST_FETCH_IDX" ON public."INTEGRITY_META_COMPONENT" USING btree ("LAST_FETCH");

CREATE INDEX "LDAPUSERS_PERMISSIONS_LDAPUSER_ID_IDX" ON public."LDAPUSERS_PERMISSIONS" USING btree ("LDAPUSER_ID");

CREATE INDEX "LDAPUSERS_PERMISSIONS_PERMISSION_ID_IDX" ON public."LDAPUSERS_PERMISSIONS" USING btree ("PERMISSION_ID");

CREATE INDEX "LDAPUSERS_TEAMS_LDAPUSER_ID_IDX" ON public."LDAPUSERS_TEAMS" USING btree ("LDAPUSER_ID");

CREATE INDEX "LDAPUSERS_TEAMS_TEAM_ID_IDX" ON public."LDAPUSERS_TEAMS" USING btree ("TEAM_ID");

CREATE INDEX "LICENSEGROUP_LICENSE_LICENSEGROUP_ID_IDX" ON public."LICENSEGROUP_LICENSE" USING btree ("LICENSEGROUP_ID");

CREATE INDEX "LICENSEGROUP_LICENSE_LICENSE_ID_IDX" ON public."LICENSEGROUP_LICENSE" USING btree ("LICENSE_ID");

CREATE INDEX "LICENSEGROUP_NAME_IDX" ON public."LICENSEGROUP" USING btree ("NAME");

CREATE UNIQUE INDEX "LICENSE_LICENSEID_IDX" ON public."LICENSE" USING btree ("LICENSEID");

CREATE INDEX "LICENSE_NAME_IDX" ON public."LICENSE" USING btree ("NAME");

CREATE INDEX "MANAGEDUSERS_PERMISSIONS_MANAGEDUSER_ID_IDX" ON public."MANAGEDUSERS_PERMISSIONS" USING btree ("MANAGEDUSER_ID");

CREATE INDEX "MANAGEDUSERS_PERMISSIONS_PERMISSION_ID_IDX" ON public."MANAGEDUSERS_PERMISSIONS" USING btree ("PERMISSION_ID");

CREATE INDEX "MANAGEDUSERS_TEAMS_MANAGEDUSER_ID_IDX" ON public."MANAGEDUSERS_TEAMS" USING btree ("MANAGEDUSER_ID");

CREATE INDEX "MANAGEDUSERS_TEAMS_TEAM_ID_IDX" ON public."MANAGEDUSERS_TEAMS" USING btree ("TEAM_ID");

CREATE INDEX "MAPPEDOIDCGROUP_GROUP_ID_IDX" ON public."MAPPEDOIDCGROUP" USING btree ("GROUP_ID");

CREATE INDEX "NOTIFICATIONRULE_PROJECTS_NOTIFICATIONRULE_ID_IDX" ON public."NOTIFICATIONRULE_PROJECTS" USING btree ("NOTIFICATIONRULE_ID");

CREATE INDEX "NOTIFICATIONRULE_PROJECTS_PROJECT_ID_IDX" ON public."NOTIFICATIONRULE_PROJECTS" USING btree ("PROJECT_ID");

CREATE INDEX "NOTIFICATIONRULE_PUBLISHER_IDX" ON public."NOTIFICATIONRULE" USING btree ("PUBLISHER");

CREATE INDEX "NOTIFICATIONRULE_TAGS_NOTIFICATIONRULE_ID_IDX" ON public."NOTIFICATIONRULE_TAGS" USING btree ("NOTIFICATIONRULE_ID");

CREATE INDEX "NOTIFICATIONRULE_TAGS_TAG_ID_IDX" ON public."NOTIFICATIONRULE_TAGS" USING btree ("TAG_ID");

CREATE INDEX "NOTIFICATIONRULE_TEAMS_NOTIFICATIONRULE_ID_IDX" ON public."NOTIFICATIONRULE_TEAMS" USING btree ("NOTIFICATIONRULE_ID");

CREATE INDEX "NOTIFICATIONRULE_TEAMS_TEAM_ID_IDX" ON public."NOTIFICATIONRULE_TEAMS" USING btree ("TEAM_ID");

CREATE INDEX "OIDCUSERS_PERMISSIONS_OIDCUSER_ID_IDX" ON public."OIDCUSERS_PERMISSIONS" USING btree ("OIDCUSER_ID");

CREATE INDEX "OIDCUSERS_PERMISSIONS_PERMISSION_ID_IDX" ON public."OIDCUSERS_PERMISSIONS" USING btree ("PERMISSION_ID");

CREATE INDEX "OIDCUSERS_TEAMS_OIDCUSERS_ID_IDX" ON public."OIDCUSERS_TEAMS" USING btree ("OIDCUSERS_ID");

CREATE INDEX "OIDCUSERS_TEAMS_TEAM_ID_IDX" ON public."OIDCUSERS_TEAMS" USING btree ("TEAM_ID");

CREATE INDEX "POLICYCONDITION_POLICY_ID_IDX" ON public."POLICYCONDITION" USING btree ("POLICY_ID");

CREATE INDEX "POLICYVIOLATION_COMPONENT_IDX" ON public."POLICYVIOLATION" USING btree ("COMPONENT_ID");

CREATE INDEX "POLICYVIOLATION_POLICYCONDITION_ID_IDX" ON public."POLICYVIOLATION" USING btree ("POLICYCONDITION_ID");

CREATE INDEX "POLICYVIOLATION_PROJECT_IDX" ON public."POLICYVIOLATION" USING btree ("PROJECT_ID");

CREATE INDEX "POLICY_NAME_IDX" ON public."POLICY" USING btree ("NAME");

CREATE INDEX "POLICY_PROJECTS_POLICY_ID_IDX" ON public."POLICY_PROJECTS" USING btree ("POLICY_ID");

CREATE INDEX "POLICY_PROJECTS_PROJECT_ID_IDX" ON public."POLICY_PROJECTS" USING btree ("PROJECT_ID");

CREATE INDEX "POLICY_TAGS_POLICY_ID_IDX" ON public."POLICY_TAGS" USING btree ("POLICY_ID");

CREATE INDEX "POLICY_TAGS_TAG_ID_IDX" ON public."POLICY_TAGS" USING btree ("TAG_ID");

CREATE INDEX "PORTFOLIOMETRICS_FIRST_OCCURRENCE_IDX" ON public."PORTFOLIOMETRICS" USING btree ("FIRST_OCCURRENCE");

CREATE INDEX "PORTFOLIOMETRICS_LAST_OCCURRENCE_IDX" ON public."PORTFOLIOMETRICS" USING btree ("LAST_OCCURRENCE");

CREATE INDEX "PROJECTMETRICS_FIRST_OCCURRENCE_IDX" ON public."PROJECTMETRICS" USING btree ("FIRST_OCCURRENCE");

CREATE INDEX "PROJECTMETRICS_LAST_OCCURRENCE_IDX" ON public."PROJECTMETRICS" USING btree ("LAST_OCCURRENCE");

CREATE INDEX "PROJECTMETRICS_PROJECT_ID_IDX" ON public."PROJECTMETRICS" USING btree ("PROJECT_ID");

CREATE INDEX "PROJECTS_TAGS_PROJECT_ID_IDX" ON public."PROJECTS_TAGS" USING btree ("PROJECT_ID");

CREATE INDEX "PROJECTS_TAGS_TAG_ID_IDX" ON public."PROJECTS_TAGS" USING btree ("TAG_ID");

CREATE INDEX "PROJECT_ACCESS_TEAMS_PROJECT_ID_IDX" ON public."PROJECT_ACCESS_TEAMS" USING btree ("PROJECT_ID");

CREATE INDEX "PROJECT_ACCESS_TEAMS_TEAM_ID_IDX" ON public."PROJECT_ACCESS_TEAMS" USING btree ("TEAM_ID");

CREATE INDEX "PROJECT_CLASSIFIER_IDX" ON public."PROJECT" USING btree ("CLASSIFIER");

CREATE INDEX "PROJECT_CPE_IDX" ON public."PROJECT" USING btree ("CPE");

CREATE INDEX "PROJECT_GROUP_IDX" ON public."PROJECT" USING btree ("GROUP");

CREATE INDEX "PROJECT_IS_LATEST_IDX" ON public."PROJECT" USING btree ("IS_LATEST");

CREATE INDEX "PROJECT_LASTBOMIMPORT_FORMAT_IDX" ON public."PROJECT" USING btree ("LAST_BOM_IMPORTED_FORMAT");

CREATE INDEX "PROJECT_LASTBOMIMPORT_IDX" ON public."PROJECT" USING btree ("LAST_BOM_IMPORTED");

CREATE INDEX "PROJECT_LAST_RISKSCORE_IDX" ON public."PROJECT" USING btree ("LAST_RISKSCORE");

CREATE UNIQUE INDEX "PROJECT_METADATA_PROJECT_ID_IDX" ON public."PROJECT_METADATA" USING btree ("PROJECT_ID");

CREATE INDEX "PROJECT_NAME_IDX" ON public."PROJECT" USING btree ("NAME");

CREATE UNIQUE INDEX "PROJECT_NAME_VERSION_IDX" ON public."PROJECT" USING btree ("NAME", "VERSION") WHERE ("VERSION" IS NOT NULL);

CREATE UNIQUE INDEX "PROJECT_NAME_VERSION_NULL_IDX" ON public."PROJECT" USING btree ("NAME") WHERE ("VERSION" IS NULL);

CREATE INDEX "PROJECT_PARENT_PROJECT_ID_IDX" ON public."PROJECT" USING btree ("PARENT_PROJECT_ID");

CREATE INDEX "PROJECT_PURL_IDX" ON public."PROJECT" USING btree ("PURL");

CREATE INDEX "PROJECT_SWID_TAGID_IDX" ON public."PROJECT" USING btree ("SWIDTAGID");

CREATE INDEX "PROJECT_VERSION_IDX" ON public."PROJECT" USING btree ("VERSION");

CREATE UNIQUE INDEX "REPOSITORY_META_COMPONENT_COMPOUND_IDX" ON public."REPOSITORY_META_COMPONENT" USING btree ("REPOSITORY_TYPE", "NAMESPACE", "NAME");

CREATE INDEX "REPOSITORY_META_COMPONENT_LASTCHECK_IDX" ON public."REPOSITORY_META_COMPONENT" USING btree ("LAST_CHECK");

CREATE INDEX "REPOSITORY_UUID_IDX" ON public."REPOSITORY" USING btree ("UUID");

CREATE INDEX "SERVICECOMPONENTS_VULNERABILITIES_SERVICECOMPONENT_ID_IDX" ON public."SERVICECOMPONENTS_VULNERABILITIES" USING btree ("SERVICECOMPONENT_ID");

CREATE INDEX "SERVICECOMPONENTS_VULNERABILITIES_VULNERABILITY_ID_IDX" ON public."SERVICECOMPONENTS_VULNERABILITIES" USING btree ("VULNERABILITY_ID");

CREATE INDEX "SERVICECOMPONENT_LAST_RISKSCORE_IDX" ON public."SERVICECOMPONENT" USING btree ("LAST_RISKSCORE");

CREATE INDEX "SERVICECOMPONENT_PARENT_SERVICECOMPONENT_ID_IDX" ON public."SERVICECOMPONENT" USING btree ("PARENT_SERVICECOMPONENT_ID");

CREATE INDEX "SERVICECOMPONENT_PROJECT_ID_IDX" ON public."SERVICECOMPONENT" USING btree ("PROJECT_ID");

CREATE INDEX "SUBSCRIBERCLASS_IDX" ON public."EVENTSERVICELOG" USING btree ("SUBSCRIBERCLASS");

CREATE INDEX "TEAMS_PERMISSIONS_PERMISSION_ID_IDX" ON public."TEAMS_PERMISSIONS" USING btree ("PERMISSION_ID");

CREATE INDEX "TEAMS_PERMISSIONS_TEAM_ID_IDX" ON public."TEAMS_PERMISSIONS" USING btree ("TEAM_ID");

CREATE INDEX "VEX_PROJECT_ID_IDX" ON public."VEX" USING btree ("PROJECT_ID");

CREATE INDEX "VIOLATIONANALYSISCOMMENT_VIOLATIONANALYSIS_ID_IDX" ON public."VIOLATIONANALYSISCOMMENT" USING btree ("VIOLATIONANALYSIS_ID");

CREATE INDEX "VIOLATIONANALYSIS_COMPONENT_ID_IDX" ON public."VIOLATIONANALYSIS" USING btree ("COMPONENT_ID");

CREATE INDEX "VIOLATIONANALYSIS_POLICYVIOLATION_ID_IDX" ON public."VIOLATIONANALYSIS" USING btree ("POLICYVIOLATION_ID");

CREATE INDEX "VULNERABILITIES_TAGS_TAG_ID_IDX" ON public."VULNERABILITIES_TAGS" USING btree ("TAG_ID");

CREATE INDEX "VULNERABILITIES_TAGS_VULNERABILITY_ID_IDX" ON public."VULNERABILITIES_TAGS" USING btree ("VULNERABILITY_ID");

CREATE INDEX "VULNERABILITYALIAS_CVE_ID_IDX" ON public."VULNERABILITYALIAS" USING btree ("CVE_ID");

CREATE INDEX "VULNERABILITYALIAS_GHSA_ID_IDX" ON public."VULNERABILITYALIAS" USING btree ("GHSA_ID");

CREATE INDEX "VULNERABILITYALIAS_GSD_ID_IDX" ON public."VULNERABILITYALIAS" USING btree ("GSD_ID");

CREATE INDEX "VULNERABILITYALIAS_INTERNAL_ID_IDX" ON public."VULNERABILITYALIAS" USING btree ("INTERNAL_ID");

CREATE INDEX "VULNERABILITYALIAS_OSV_ID_IDX" ON public."VULNERABILITYALIAS" USING btree ("OSV_ID");

CREATE INDEX "VULNERABILITYALIAS_SNYK_ID_IDX" ON public."VULNERABILITYALIAS" USING btree ("SNYK_ID");

CREATE INDEX "VULNERABILITYALIAS_SONATYPE_ID_IDX" ON public."VULNERABILITYALIAS" USING btree ("SONATYPE_ID");

CREATE INDEX "VULNERABILITYALIAS_VULNDB_ID_IDX" ON public."VULNERABILITYALIAS" USING btree ("VULNDB_ID");

CREATE INDEX "VULNERABILITY_CREATED_IDX" ON public."VULNERABILITY" USING btree ("CREATED");

CREATE UNIQUE INDEX "VULNERABILITY_POLICY_NAME_IDX" ON public."VULNERABILITY_POLICY" USING btree ("NAME");

CREATE INDEX "VULNERABILITY_PUBLISHED_IDX" ON public."VULNERABILITY" USING btree ("PUBLISHED");

CREATE INDEX "VULNERABILITY_UPDATED_IDX" ON public."VULNERABILITY" USING btree ("UPDATED");

CREATE INDEX "VULNERABLESOFTWARE_CPE23_VERSION_RANGE_IDX" ON public."VULNERABLESOFTWARE" USING btree ("CPE23", "VERSIONENDEXCLUDING", "VERSIONENDINCLUDING", "VERSIONSTARTEXCLUDING", "VERSIONSTARTINCLUDING");

CREATE INDEX "VULNERABLESOFTWARE_CPE_PURL_PARTS_IDX" ON public."VULNERABLESOFTWARE" USING btree ("PART", "VENDOR", "PRODUCT", "PURL_TYPE", "PURL_NAMESPACE", "PURL_NAME");

CREATE INDEX "VULNERABLESOFTWARE_PURL_TYPE_NS_NAME_IDX" ON public."VULNERABLESOFTWARE" USING btree ("PURL_TYPE", "PURL_NAMESPACE", "PURL_NAME");

CREATE INDEX "VULNERABLESOFTWARE_PURL_VERSION_RANGE_IDX" ON public."VULNERABLESOFTWARE" USING btree ("PURL", "VERSIONENDEXCLUDING", "VERSIONENDINCLUDING", "VERSIONSTARTEXCLUDING", "VERSIONSTARTINCLUDING");

CREATE INDEX "VULNERABLESOFTWARE_VULNERABILITIES_VULNERABILITY_ID_IDX" ON public."VULNERABLESOFTWARE_VULNERABILITIES" USING btree ("VULNERABILITY_ID");

CREATE INDEX "VULNERABLESOFTWARE_VULNERABILITIES_VULNERABLESOFTWARE_ID_IDX" ON public."VULNERABLESOFTWARE_VULNERABILITIES" USING btree ("VULNERABLESOFTWARE_ID");

CREATE INDEX "WORKFLOW_STATE_PARENT_STEP_ID_IDX" ON public."WORKFLOW_STATE" USING btree ("PARENT_STEP_ID");

ALTER TABLE ONLY public."AFFECTEDVERSIONATTRIBUTION"
    ADD CONSTRAINT "AFFECTEDVERSIONATTRIBUTION_VULNERABILITY_FK" FOREIGN KEY ("VULNERABILITY") REFERENCES public."VULNERABILITY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."AFFECTEDVERSIONATTRIBUTION"
    ADD CONSTRAINT "AFFECTEDVERSIONATTRIBUTION_VULNERABLESOFTWARE_FK" FOREIGN KEY ("VULNERABLE_SOFTWARE") REFERENCES public."VULNERABLESOFTWARE"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."ANALYSISCOMMENT"
    ADD CONSTRAINT "ANALYSISCOMMENT_ANALYSIS_FK" FOREIGN KEY ("ANALYSIS_ID") REFERENCES public."ANALYSIS"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."ANALYSIS"
    ADD CONSTRAINT "ANALYSIS_COMPONENT_FK" FOREIGN KEY ("COMPONENT_ID") REFERENCES public."COMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."ANALYSIS"
    ADD CONSTRAINT "ANALYSIS_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."ANALYSIS"
    ADD CONSTRAINT "ANALYSIS_VULNERABILITY_FK" FOREIGN KEY ("VULNERABILITY_ID") REFERENCES public."VULNERABILITY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."ANALYSIS"
    ADD CONSTRAINT "ANALYSIS_VULNERABILITY_POLICY_ID_FK" FOREIGN KEY ("VULNERABILITY_POLICY_ID") REFERENCES public."VULNERABILITY_POLICY"("ID");

ALTER TABLE ONLY public."APIKEYS_TEAMS"
    ADD CONSTRAINT "APIKEYS_TEAMS_APIKEY_FK" FOREIGN KEY ("APIKEY_ID") REFERENCES public."APIKEY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."APIKEYS_TEAMS"
    ADD CONSTRAINT "APIKEYS_TEAMS_TEAM_FK" FOREIGN KEY ("TEAM_ID") REFERENCES public."TEAM"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."BOM"
    ADD CONSTRAINT "BOM_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."COMPONENTS_VULNERABILITIES"
    ADD CONSTRAINT "COMPONENTS_VULNERABILITIES_COMPONENT_FK" FOREIGN KEY ("COMPONENT_ID") REFERENCES public."COMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."COMPONENTS_VULNERABILITIES"
    ADD CONSTRAINT "COMPONENTS_VULNERABILITIES_VULNERABILITY_FK" FOREIGN KEY ("VULNERABILITY_ID") REFERENCES public."VULNERABILITY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."COMPONENT"
    ADD CONSTRAINT "COMPONENT_COMPONENT_FK" FOREIGN KEY ("PARENT_COMPONENT_ID") REFERENCES public."COMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."COMPONENT"
    ADD CONSTRAINT "COMPONENT_LICENSE_FK" FOREIGN KEY ("LICENSE_ID") REFERENCES public."LICENSE"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."COMPONENT"
    ADD CONSTRAINT "COMPONENT_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."COMPONENT_PROPERTY"
    ADD CONSTRAINT "COMPONENT_PROPERTY_COMPONENT_ID_FK" FOREIGN KEY ("COMPONENT_ID") REFERENCES public."COMPONENT"("ID") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."DEPENDENCYMETRICS"
    ADD CONSTRAINT "DEPENDENCYMETRICS_COMPONENT_FK" FOREIGN KEY ("COMPONENT_ID") REFERENCES public."COMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."DEPENDENCYMETRICS"
    ADD CONSTRAINT "DEPENDENCYMETRICS_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."FINDINGATTRIBUTION"
    ADD CONSTRAINT "FINDINGATTRIBUTION_COMPONENT_FK" FOREIGN KEY ("COMPONENT_ID") REFERENCES public."COMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."FINDINGATTRIBUTION"
    ADD CONSTRAINT "FINDINGATTRIBUTION_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."FINDINGATTRIBUTION"
    ADD CONSTRAINT "FINDINGATTRIBUTION_VULNERABILITY_FK" FOREIGN KEY ("VULNERABILITY_ID") REFERENCES public."VULNERABILITY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."INTEGRITY_ANALYSIS"
    ADD CONSTRAINT "INTEGRITY_ANALYSIS_COMPONENT_FK" FOREIGN KEY ("COMPONENT_ID") REFERENCES public."COMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."LDAPUSERS_PERMISSIONS"
    ADD CONSTRAINT "LDAPUSERS_PERMISSIONS_LDAPUSER_FK" FOREIGN KEY ("LDAPUSER_ID") REFERENCES public."LDAPUSER"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."LDAPUSERS_PERMISSIONS"
    ADD CONSTRAINT "LDAPUSERS_PERMISSIONS_PERMISSION_FK" FOREIGN KEY ("PERMISSION_ID") REFERENCES public."PERMISSION"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."LDAPUSERS_TEAMS"
    ADD CONSTRAINT "LDAPUSERS_TEAMS_LDAPUSER_FK" FOREIGN KEY ("LDAPUSER_ID") REFERENCES public."LDAPUSER"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."LDAPUSERS_TEAMS"
    ADD CONSTRAINT "LDAPUSERS_TEAMS_TEAM_FK" FOREIGN KEY ("TEAM_ID") REFERENCES public."TEAM"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."LICENSEGROUP_LICENSE"
    ADD CONSTRAINT "LICENSEGROUP_LICENSE_LICENSEGROUP_FK" FOREIGN KEY ("LICENSEGROUP_ID") REFERENCES public."LICENSEGROUP"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."LICENSEGROUP_LICENSE"
    ADD CONSTRAINT "LICENSEGROUP_LICENSE_LICENSE_FK" FOREIGN KEY ("LICENSE_ID") REFERENCES public."LICENSE"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."MANAGEDUSERS_PERMISSIONS"
    ADD CONSTRAINT "MANAGEDUSERS_PERMISSIONS_MANAGEDUSER_FK" FOREIGN KEY ("MANAGEDUSER_ID") REFERENCES public."MANAGEDUSER"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."MANAGEDUSERS_PERMISSIONS"
    ADD CONSTRAINT "MANAGEDUSERS_PERMISSIONS_PERMISSION_FK" FOREIGN KEY ("PERMISSION_ID") REFERENCES public."PERMISSION"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."MANAGEDUSERS_TEAMS"
    ADD CONSTRAINT "MANAGEDUSERS_TEAMS_MANAGEDUSER_FK" FOREIGN KEY ("MANAGEDUSER_ID") REFERENCES public."MANAGEDUSER"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."MANAGEDUSERS_TEAMS"
    ADD CONSTRAINT "MANAGEDUSERS_TEAMS_TEAM_FK" FOREIGN KEY ("TEAM_ID") REFERENCES public."TEAM"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."MAPPEDLDAPGROUP"
    ADD CONSTRAINT "MAPPEDLDAPGROUP_TEAM_FK" FOREIGN KEY ("TEAM_ID") REFERENCES public."TEAM"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."MAPPEDOIDCGROUP"
    ADD CONSTRAINT "MAPPEDOIDCGROUP_OIDCGROUP_FK" FOREIGN KEY ("GROUP_ID") REFERENCES public."OIDCGROUP"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."MAPPEDOIDCGROUP"
    ADD CONSTRAINT "MAPPEDOIDCGROUP_TEAM_FK" FOREIGN KEY ("TEAM_ID") REFERENCES public."TEAM"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."NOTIFICATIONRULE"
    ADD CONSTRAINT "NOTIFICATIONRULE_NOTIFICATIONPUBLISHER_FK" FOREIGN KEY ("PUBLISHER") REFERENCES public."NOTIFICATIONPUBLISHER"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."NOTIFICATIONRULE_PROJECTS"
    ADD CONSTRAINT "NOTIFICATIONRULE_PROJECTS_NOTIFICATIONRULE_FK" FOREIGN KEY ("NOTIFICATIONRULE_ID") REFERENCES public."NOTIFICATIONRULE"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."NOTIFICATIONRULE_PROJECTS"
    ADD CONSTRAINT "NOTIFICATIONRULE_PROJECTS_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."NOTIFICATIONRULE_TAGS"
    ADD CONSTRAINT "NOTIFICATIONRULE_TAGS_NOTIFICATIONRULE_FK" FOREIGN KEY ("NOTIFICATIONRULE_ID") REFERENCES public."NOTIFICATIONRULE"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."NOTIFICATIONRULE_TAGS"
    ADD CONSTRAINT "NOTIFICATIONRULE_TAGS_TAG_FK" FOREIGN KEY ("TAG_ID") REFERENCES public."TAG"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."NOTIFICATIONRULE_TEAMS"
    ADD CONSTRAINT "NOTIFICATIONRULE_TEAMS_NOTIFICATIONRULE_FK" FOREIGN KEY ("NOTIFICATIONRULE_ID") REFERENCES public."NOTIFICATIONRULE"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."NOTIFICATIONRULE_TEAMS"
    ADD CONSTRAINT "NOTIFICATIONRULE_TEAMS_TEAM_FK" FOREIGN KEY ("TEAM_ID") REFERENCES public."TEAM"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."OIDCUSERS_PERMISSIONS"
    ADD CONSTRAINT "OIDCUSERS_PERMISSIONS_OIDCUSER_FK" FOREIGN KEY ("OIDCUSER_ID") REFERENCES public."OIDCUSER"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."OIDCUSERS_PERMISSIONS"
    ADD CONSTRAINT "OIDCUSERS_PERMISSIONS_PERMISSION_FK" FOREIGN KEY ("PERMISSION_ID") REFERENCES public."PERMISSION"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."OIDCUSERS_TEAMS"
    ADD CONSTRAINT "OIDCUSERS_TEAMS_OIDCUSER_FK" FOREIGN KEY ("OIDCUSERS_ID") REFERENCES public."OIDCUSER"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."OIDCUSERS_TEAMS"
    ADD CONSTRAINT "OIDCUSERS_TEAMS_TEAM_FK" FOREIGN KEY ("TEAM_ID") REFERENCES public."TEAM"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."POLICYCONDITION"
    ADD CONSTRAINT "POLICYCONDITION_POLICY_FK" FOREIGN KEY ("POLICY_ID") REFERENCES public."POLICY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."POLICYVIOLATION"
    ADD CONSTRAINT "POLICYVIOLATION_COMPONENT_FK" FOREIGN KEY ("COMPONENT_ID") REFERENCES public."COMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."POLICYVIOLATION"
    ADD CONSTRAINT "POLICYVIOLATION_POLICYCONDITION_FK" FOREIGN KEY ("POLICYCONDITION_ID") REFERENCES public."POLICYCONDITION"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."POLICYVIOLATION"
    ADD CONSTRAINT "POLICYVIOLATION_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."POLICY_PROJECTS"
    ADD CONSTRAINT "POLICY_PROJECTS_POLICY_FK" FOREIGN KEY ("POLICY_ID") REFERENCES public."POLICY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."POLICY_PROJECTS"
    ADD CONSTRAINT "POLICY_PROJECTS_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."POLICY_TAGS"
    ADD CONSTRAINT "POLICY_TAGS_POLICY_FK" FOREIGN KEY ("POLICY_ID") REFERENCES public."POLICY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."POLICY_TAGS"
    ADD CONSTRAINT "POLICY_TAGS_TAG_FK" FOREIGN KEY ("TAG_ID") REFERENCES public."TAG"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."PROJECTMETRICS"
    ADD CONSTRAINT "PROJECTMETRICS_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."PROJECTS_TAGS"
    ADD CONSTRAINT "PROJECTS_TAGS_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."PROJECTS_TAGS"
    ADD CONSTRAINT "PROJECTS_TAGS_TAG_FK" FOREIGN KEY ("TAG_ID") REFERENCES public."TAG"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."PROJECT_ACCESS_TEAMS"
    ADD CONSTRAINT "PROJECT_ACCESS_TEAMS_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."PROJECT_ACCESS_TEAMS"
    ADD CONSTRAINT "PROJECT_ACCESS_TEAMS_TEAM_FK" FOREIGN KEY ("TEAM_ID") REFERENCES public."TEAM"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."PROJECT_METADATA"
    ADD CONSTRAINT "PROJECT_METADATA_PROJECT_ID_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."PROJECT"
    ADD CONSTRAINT "PROJECT_PROJECT_FK" FOREIGN KEY ("PARENT_PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."PROJECT_PROPERTY"
    ADD CONSTRAINT "PROJECT_PROPERTY_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."SERVICECOMPONENTS_VULNERABILITIES"
    ADD CONSTRAINT "SERVICECOMPONENTS_VULNERABILITIES_SERVICECOMPONENT_FK" FOREIGN KEY ("SERVICECOMPONENT_ID") REFERENCES public."SERVICECOMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."SERVICECOMPONENTS_VULNERABILITIES"
    ADD CONSTRAINT "SERVICECOMPONENTS_VULNERABILITIES_VULNERABILITY_FK" FOREIGN KEY ("VULNERABILITY_ID") REFERENCES public."VULNERABILITY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."SERVICECOMPONENT"
    ADD CONSTRAINT "SERVICECOMPONENT_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."SERVICECOMPONENT"
    ADD CONSTRAINT "SERVICECOMPONENT_SERVICECOMPONENT_FK" FOREIGN KEY ("PARENT_SERVICECOMPONENT_ID") REFERENCES public."SERVICECOMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."TEAMS_PERMISSIONS"
    ADD CONSTRAINT "TEAMS_PERMISSIONS_PERMISSION_FK" FOREIGN KEY ("PERMISSION_ID") REFERENCES public."PERMISSION"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."TEAMS_PERMISSIONS"
    ADD CONSTRAINT "TEAMS_PERMISSIONS_TEAM_FK" FOREIGN KEY ("TEAM_ID") REFERENCES public."TEAM"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."VEX"
    ADD CONSTRAINT "VEX_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."VIOLATIONANALYSISCOMMENT"
    ADD CONSTRAINT "VIOLATIONANALYSISCOMMENT_VIOLATIONANALYSIS_FK" FOREIGN KEY ("VIOLATIONANALYSIS_ID") REFERENCES public."VIOLATIONANALYSIS"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."VIOLATIONANALYSIS"
    ADD CONSTRAINT "VIOLATIONANALYSIS_COMPONENT_FK" FOREIGN KEY ("COMPONENT_ID") REFERENCES public."COMPONENT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."VIOLATIONANALYSIS"
    ADD CONSTRAINT "VIOLATIONANALYSIS_POLICYVIOLATION_FK" FOREIGN KEY ("POLICYVIOLATION_ID") REFERENCES public."POLICYVIOLATION"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."VIOLATIONANALYSIS"
    ADD CONSTRAINT "VIOLATIONANALYSIS_PROJECT_FK" FOREIGN KEY ("PROJECT_ID") REFERENCES public."PROJECT"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."VULNERABILITIES_TAGS"
    ADD CONSTRAINT "VULNERABILITIES_TAGS_TAG_FK" FOREIGN KEY ("TAG_ID") REFERENCES public."TAG"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."VULNERABILITIES_TAGS"
    ADD CONSTRAINT "VULNERABILITIES_TAGS_VULNERABILITY_FK" FOREIGN KEY ("VULNERABILITY_ID") REFERENCES public."VULNERABILITY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."VULNERABLESOFTWARE_VULNERABILITIES"
    ADD CONSTRAINT "VULNERABLESOFTWARE_VULNERABILITIES_VULNERABILITY_FK" FOREIGN KEY ("VULNERABILITY_ID") REFERENCES public."VULNERABILITY"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."VULNERABLESOFTWARE_VULNERABILITIES"
    ADD CONSTRAINT "VULNERABLESOFTWARE_VULNERABILITIES_VULNERABLESOFTWARE_FK" FOREIGN KEY ("VULNERABLESOFTWARE_ID") REFERENCES public."VULNERABLESOFTWARE"("ID") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY public."WORKFLOW_STATE"
    ADD CONSTRAINT "WORKFLOW_STATE_WORKFLOW_STATE_FK" FOREIGN KEY ("PARENT_STEP_ID") REFERENCES public."WORKFLOW_STATE"("ID") DEFERRABLE INITIALLY DEFERRED;

-- Required for tests
INSERT INTO public."CONFIGPROPERTY" ("GROUPNAME", "PROPERTYNAME", "PROPERTYVALUE", "PROPERTYTYPE", "DESCRIPTION")
VALUES ('internal', 'cluster.id', '53b94f78-6e2f-4015-961a-0965ff1807a9', 'STRING', NULL);