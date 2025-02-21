Feature: VIEW_PORTFOLIO x VIEW_VULNERABILITY
  Scenario: Without VIEW_VULNERABILITY Permission The User Cannot See Management Buttons For Projects
    Given the user "test-user_VP_PERMS" logs in to DependencyTrack and verifies
    Then the "vulnerabilityAudit" tab should not be visible
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project01"
    And the project "auditVulnerabilities" tab should not be visible

  Scenario: With VIEW_VULNERABILITY Permission The User Can See Management Buttons For Projects
    Given the user "test-user_VP_VV_PERMS" logs in to DependencyTrack and verifies
    When the user navigates to "vulnerabilityAudit" page and verifies
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project01"
    And the user navigates to project "auditVulnerabilities" tab and verifies
    Then the user expands the vulnerability "json-smart" on audit vulnerability project tab
    And the user verifies read access on the vulnerability audit view on audit Vulnerability project tab
