Feature: VIEW_PORTFOLIO x SYSTEM_CONFIGURATION
  Scenario: Without SYSTEM_CONFIGURATION Permission The User Cannot See Administration Tab
    Given the user "test-user_VP_PERMS" logs in to DependencyTrack and verifies
    Then the "administration" tab should not be visible

  Scenario: With SYSTEM_CONFIGURATION Permission The User Can See Administration Tab
    Given the user "test-user_VP_SC_PERMS" logs in to DependencyTrack and verifies
    When the user navigates to "administration" page and verifies
