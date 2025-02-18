Feature: Suppress Violation Against Policy
  Scenario: The Admin User Suppresses A Policy Violation
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    And the user opens the project with the name "test-project02"
    And the user navigates to project "policyViolations" tab and verifies
    Then the user opens the policy violation of Component "JUnitParams"
    Then the user comments the current policy violation with "this is a comment"
    And the audit trail should contain "this is a comment"
    And the user sets the analysis to "Rejected"
    And the audit trail should contain "NOT_SET → REJECTED"
    Then the user suppresses the current policy violation
    And the audit trail should contain "SUPPRESSED"
    And the policy violation of the component "JUnitParams" will not appear in search result