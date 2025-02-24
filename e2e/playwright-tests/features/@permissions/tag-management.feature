@Todo # Tags are still WIP
Feature: VIEW_PORTFOLIO x TAG_MANAGEMENT
  Scenario: Without TAG_MANAGEMENT Permission The User Cannot See The Tag Management Tab
    Given the user "test-user_VP_PERMS" logs in to DependencyTrack and verifies
    Then the user navigates to "tags" page and verifies
    Then the delete-tag button is not visible

  Scenario: With TAG_MANAGEMENT Permission The User Can See The Tag Management Tab
    Given the user "test-user_VP_TM_PERMS" logs in to DependencyTrack and verifies
    Then the user navigates to "tags" page and verifies
    Then the delete-tag button should be visible
