Feature: Try Creating Existing Project
  Scenario: The Admin User Suppresses A Policy Violation
    Given the user "admin" is already authenticated for DependencyTrack
    When the user navigates to "projects" page and verifies
    Then the user tries to create a project with name "test-project01" and classifier "APPLICATION"
    Then the user receives project creation error and warn toast
