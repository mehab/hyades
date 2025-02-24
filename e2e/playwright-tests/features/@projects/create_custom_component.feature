Feature: Create Custom Component
  Scenario: The Admin User Creates A Custom Component Inside A Test Project
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project04"
    And the user navigates to project "components" tab and verifies
    Then the user adds a custom component on projects component page with the following values
      | componentName  | componentVersion | componentPURL                              |
      | test-component | 1.0.0            | pkg:maven/org.testOrg/test-component@1.0.0 |

  Scenario: The Admin User Deletes A Custom Component Inside A Test Project
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project04"
    And the user navigates to project "components" tab and verifies
    Then the user deletes the custom component "test-component" on projects component page