Feature: VIEW_PORTFOLIO x BOM_UPLOAD
  Scenario: Without BOM_UPLOAD Permission The User Cannot See The BOM Upload Button
    Given the user "test-user_VP_PERMS" logs in to DependencyTrack and verifies
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project01"
    Then the user navigates to project "components" tab and verifies
    And the upload-bom button is invisible

  Scenario: With BOM_UPLOAD Permission The User Can See The BOM Upload Button
    Given the user "test-user_VP_BU_PERMS" logs in to DependencyTrack and verifies
    When the user navigates to "projects" page and verifies
    Then the user opens the project with the name "test-project01"
    Then the user navigates to project "components" tab and verifies
    And the upload-bom button should be visible
    # Upload could be tested here as well
