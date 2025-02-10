Feature:
  Scenario: Without VIEW_PORTFOLIO Permissions The User Cannot Log In
    Given the user "test-user0_PERMS" tries to log in to DependencyTrack
    Then the user receives login error toast

  Scenario: With VIEW_PORTFOLIO Permissions The User Tries To Log In With Wrong Credentials
    Given the user "test-user_VP_PERMS" tries to log in to DependencyTrack with password "wrongPassword"
    When the user receives login credentials error toast
    Then the user sees wrong log in credentials modal content popup

  Scenario: With VIEW_PORTFOLIO Permissions The User Verifies Access
    Given the user "test-user_VP_PERMS" tries to log in to DependencyTrack
    When the "dashboardTab" tab should be visible and active
    Then the user navigates to "projectsTab" page and verifies
    Then the user navigates to "componentsTab" page and verifies
    Then the user navigates to "vulnerabilitiesTab" page and verifies
    Then the user navigates to "licencesTab" page and verifies
    Then the user navigates to "tagsTab" page and verifies
    And the "vulnerabilityAuditTab" tab should not be visible
    And the "policyViolationAuditTab" tab should not be visible
    And the "policyManagementTab" tab should not be visible
    And the "administrationTab" tab should not be visible
