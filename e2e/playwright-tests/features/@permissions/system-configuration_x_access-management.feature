Feature: VIEW_PORTFOLIO x SYSTEM_CONFIGURATION x ACCESS_MANAGEMENT
  Scenario: With SYSTEM_CONFIGURATION But Without ACCESS_MANAGEMENT Permission The User Cannot See Access Management Menu
    Given the user "test-user_VP_SC_PERMS" logs in to DependencyTrack and verifies
    When the user navigates to "administration" page and verifies
    Then the "accessManagement" menu should not be visible

  Scenario: With SYSTEM_CONFIGURATION x ACCESS_MANAGEMENT Permission The User Can See Administration Tab
    Given the user "test-user_VP_SC_AM_PERMS" logs in to DependencyTrack and verifies
    When the user navigates to "administration" page and verifies
    Then the "accessManagement" menu should be visible
    Then the user navigates to administration menu "accessManagement"
    And the accessManagement submenu should be visible
