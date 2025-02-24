Feature: VIEW_PORTFOLIO
  Scenario: Without VIEW_PORTFOLIO Permission The User Cannot Log In
    Given the user "test-user0_PERMS" tries to log in to DependencyTrack
    Then the user receives login error toast

  Scenario: With VIEW_PORTFOLIO Permissions The User Tries To Log In With Wrong Credentials
    Given the user "test-user_VP_PERMS" tries to log in to DependencyTrack with password "wrongPassword"
    When the user receives login credentials error toast
    Then the user sees wrong log in credentials modal content popup and closes it

  Scenario: With VIEW_PORTFOLIO Permission The User Verifies Access
    Given the user "test-user_VP_PERMS" logs in to DependencyTrack and verifies
    Then the user navigates to "projects" page and verifies
    Then the user navigates to "components" page and verifies
    Then the user navigates to "vulnerabilities" page and verifies
    Then the user navigates to "licences" page and verifies
    Then the user navigates to "tags" page and verifies
    And the "vulnerabilityAudit" tab should not be visible
    And the "policyViolationAudit" tab should not be visible
    And the "policyManagement" tab should not be visible
    And the "administration" tab should not be visible
