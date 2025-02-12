Feature:
  Scenario: Without PORTFOLIO_MANAGEMENT Permissions User Cannot See Management Buttons For Projects
    Given the user "test-user_VP_PERMS" logs in to DependencyTrack and verifies
    When the user navigates to "projectsTab" page and verifies
    Then the create-project button should not visible
    Then the user opens the project with the name "test-project01"
    And the user navigates to project "components" tab and verifies
    Then the add-component button should not be visible
    Then the remove-component button should not be visible
    And the user opens project details
    Then the delete-project button in project details should not be visible
    Then the project-properties button in project details should not be visible
    Then the add-version button in project details should not be visible
    Then the update-project button in project details should not be visible

  Scenario: With SYSTEM_CONFIGURATION Permissions User Can See Management Buttons For Projects
    Given the user "test-user_VP_PortfolioM_PERMS" logs in to DependencyTrack and verifies
    When the user navigates to "projectsTab" page and verifies
    Then the create-project button should be visible
    Then the user opens the project with the name "test-project01"
    And the user navigates to project "components" tab and verifies
    Then the add-component button should be visible
    Then the remove-component button should be visible
    And the user opens project details
    Then the delete-project button in project details should be visible
    Then the project-properties button in project details should be visible
    Then the add-version button in project details should be visible
    Then the update-project button in project details should be visible
