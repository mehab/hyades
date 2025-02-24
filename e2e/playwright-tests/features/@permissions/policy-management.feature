Feature: VIEW_PORTFOLIO x POLICY_MANAGEMENT
  Scenario: Without POLICY_MANAGEMENT Permission The User Cannot See The Policy Management Tab
    Given the user "test-user_VP_PERMS" logs in to DependencyTrack and verifies
    Then the "policyManagement" tab should not be visible

  Scenario: With POLICY_MANAGEMENT Permission The User Can See The Policy Management Tab
    Given the user "test-user_VP_PolicyM_PERMS" logs in to DependencyTrack and verifies
    When the user navigates to "policyManagement" page and verifies
    Then the create-policy button should be visible
    And the policy "test-policy01" is visible
    Then the user navigates to policyManagement "licenceGroup" tab
    Then the create-licence-group button should be visible
    And the licence-group "Copyleft" is visible
