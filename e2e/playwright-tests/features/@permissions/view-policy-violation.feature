Feature: VIEW_PORTFOLIO x VIEW_POLICY_VIOLATION
  Scenario: Without VIEW_POLICY_VIOLATION Permission The User Cannot See The Policy Violations On Project Page
    Given the user "test-user_VP_PERMS" logs in to DependencyTrack and verifies
    Then the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project01"
    Then the project "policyViolations" tab should not be visible

  Scenario: With VIEW_POLICY_VIOLATION Permission The User Can See Audit View On Policy Violations Project Page
    Given the user "test-user_VP_VPV_PERMS" logs in to DependencyTrack and verifies
    Then the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project01"
    Then the project "policyViolations" tab should be visible
    And the user navigates to project "policyViolations" tab and verifies
    Then the user expands the violation "json-smart" on policy violation project tab
    Then the user verifies read access on the policy violation audit view on policy violations project tab
