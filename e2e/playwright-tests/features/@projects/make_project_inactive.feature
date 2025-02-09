Feature:
  Scenario: The Admin User Sets A Test Project To Inactive
    Given the admin user logs in to DependencyTrack
    When the "dashboardTab" tab should be visible and active
    Then the user navigates to "projectsTab" page and verifies
    And the user opens the project with the name "test-project03"
    Then the user opens project details
    And the user sets the current project to inactive and verifies
    Then the user navigates to "projectsTab" page and verifies
    And the project "test-project03" should not be visible in the list
    Then the user makes inactive projects visible in the list
    And the project "test-project03" should be visible in the list