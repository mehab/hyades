Feature: Make Project Inactive
  Scenario: The Admin User Sets A Test Project To Inactive
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project03"
    Then the user opens project details
    And the user sets the current project to inactive and verifies
    Then the user navigates to "projects" page and verifies
    And the project "test-project03" should not be visible in the list
    Then the user makes inactive projects visible in the list
    And the project "test-project03" should be visible in the list