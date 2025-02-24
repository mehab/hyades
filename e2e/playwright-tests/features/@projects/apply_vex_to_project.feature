Feature: Create Custom Component
  Scenario: The Admin User Applies Vex Inside A Test Project
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project05"
    And the user navigates to project "auditVulnerabilities" tab and verifies
    Then the user applies default VEX for current project

  Scenario: The Admin User Verifies Vex Application Inside A Test Project
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project05"
    And the user navigates to project "auditVulnerabilities" tab and verifies
    Then the user verifies default VEX application for current project with the following values
      | componentName | analysisState | justification      | vendorResponse | details                                          |
      | HdrHistogram  | not_affected  | code_not_reachable | will_not_fix   | The vulnerable backup functionality is not used. |
