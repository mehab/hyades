Feature: Validate BOM Upload
  Scenario: The Admin User Validates A Test Project With A Recently Uploaded BOM
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project01"
    And the user verifies "components" with the badge number of 238 on current project
    And the user verifies "services" with the badge number of 19 on current project
    And the user verifies "dependencyGraph" with the badge number of 1 on current project
    And the user verifies Audit Vulnerabilities with the badge number of 5 excluding and 5 including aliases on current project
    And the user verifies "exploitPredictions" with the badge number of 5 on current project
    And the user verifies Policy Violations with the badge number of 238 total 0 info 0 warn 238 fail violations on current project
    Then the user navigates to project "components" tab and verifies
    And the table on the respective projects tab is visible and contains entries
    Then the user navigates to project "services" tab and verifies
    And the table on the respective projects tab is visible and contains entries
    Then the user navigates to project "dependencyGraph" tab and verifies
    Then the dependency graph tab is visible and contains a node with child entries
    Then the user navigates to project "auditVulnerabilities" tab and verifies
    And the table on the respective projects tab is visible and contains entries
    Then the user navigates to project "exploitPredictions" tab and verifies
    And the table on the respective projects tab is visible and contains entries
    Then the user navigates to project "policyViolations" tab and verifies
    And the table on the respective projects tab is visible and contains entries
