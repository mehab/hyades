Feature: Create Parent Project
  Scenario: The Admin User Creates A Parent And A Child Project
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    Then the user creates projects with the following values
      | projectName      | classifier  | version | isLastVersion | team | parent           | description | tag |
      | parent-project01 | APPLICATION |         |               |      |                  |             |     |
      | child-project01  | APPLICATION |         |               |      | parent-project01 |             |     |
    Then the project "parent-project01" should be a parent project and contain "child-project01" as child project

  Scenario: The Admin User Deletes Respective Projects
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    Then the user deletes the following test projects
      | projectName      |
      | parent-project01 |
