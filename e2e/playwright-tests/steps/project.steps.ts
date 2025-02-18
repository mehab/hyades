/* eslint-disable */
import { Then } from '../fixtures/fixtures';
import { DataTable } from 'playwright-bdd';
import {expect} from "@playwright/test";

Then('the user creates projects with the following values', async ({ page, projectPage, notificationToast }, dataTable: DataTable) => {
    for(const row of dataTable.hashes()) {
        await projectPage.clickOnCreateProject();
        await projectPage.createProject(
            row.projectName,
            row.classifier,
            row.version || undefined,
            row.isLastVersion ? row.isLastVersion === "true" : undefined,
            row.team || undefined,
            row.parent || undefined,
            row.description || undefined,
            row.tag || undefined
        );
        await notificationToast.verifySuccessfulProjectCreatedToast();
        await page.waitForTimeout(1000);
    }
});

Then('the user tries to create a project with name {string} and classifier {string}', async ({ page, projectPage, notificationToast }, projectName: string, classifier: string) => {
    await projectPage.clickOnCreateProject();
    await projectPage.createProject(
        projectName,
        classifier,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined
    );
    await page.waitForTimeout(1000);
});

Then('the user deletes the following test projects if they exist', async ({ page, projectPage, notificationToast }, dataTable: DataTable) => {
    await projectPage.showInactiveProjects();
    const count = await page.locator('tbody tr').count();
    if(count === 0) {
        return;
    }

    for(const row of dataTable.hashes()) {
        await projectPage.fillSearchFieldInput(row.projectName);

        const projectDoesntExist = await page.locator('.no-records-found').isVisible();
        if(projectDoesntExist) {
            console.warn(`Couldn't find project with name ${row.projectName}. Moving on.`);
            continue;
        }

        await projectPage.deleteProject(row.projectName);
        await notificationToast.verifySuccessfulProjectDeletedToast();
        await page.waitForTimeout(1000);
    }
    await projectPage.hideInactiveProjects();
});

Then('the user deletes the following test projects', async ({ page, projectPage, notificationToast }, dataTable: DataTable) => {
    for(const row of dataTable.hashes()) {
        await projectPage.fillSearchFieldInput(row.projectName);

        const projectDoesntExist = await page.locator('.no-records-found').isVisible();
        if(projectDoesntExist) {
            throw new Error(`Couldn't find project with name ${row.projectName}. This shouldn't happen.`);
        }

        await projectPage.deleteProject(row.projectName);
        await notificationToast.verifySuccessfulProjectDeletedToast();
        await page.waitForTimeout(1000);
    }
});

Then('the user opens the project with the name {string}', async ({ projectPage }, projectName: string) => {
    await projectPage.clickOnProject(projectName);
});

Then('the user navigates to project {string} tab and verifies', async ({ selectedProjectPage }, projectTab: string) => {
    await selectedProjectPage.clickOnTab(projectTab);
});

Then('the user opens project details', async ({ selectedProjectPage }) => {
    await selectedProjectPage.openProjectDetails();
});

const projectShouldNotBeVisible = Then('the project {string} should not be visible in the list', async ({ projectPage }, projectName: string) => {
    await expect(projectPage.projectList).not.toContainText(projectName);
});

Then('the user makes inactive projects visible in the list', async ({ projectPage }) => {
    await projectPage.showInactiveProjects();
});

const projectShouldBeVisible = Then('the project {string} should be visible in the list', async ({ projectPage }, projectName: string) => {
    await expect(projectPage.projectList).toContainText(projectName);
});

Then('the user sets the current project to inactive and verifies', async ({ selectedProjectPage, notificationToast }) => {
    await selectedProjectPage.makeProjectInactive();
    await selectedProjectPage.clickOnUpdateButton();
    await notificationToast.verifySuccessfulProjectUpdatedToast();
    const inactiveTag = (await selectedProjectPage.getProjectCard(0)).locator('.badge.badge-tab-warn');
    await expect(inactiveTag).toContainText(/INACTIVE/);
});

Then('the user uploads default BOM', async ({ projectComponentsPage, notificationToast }) => {
    await projectComponentsPage.uploadBom();
    await notificationToast.verifySuccessfulBomUploadedToast();
});

Then('the user verifies {string} with the badge number of {int} on current project', async ({ selectedProjectPage }, tabName: string, expectedTotalBadge: number) => {
    const actualTotalBadge = await selectedProjectPage.getTotalTabBadgeValue(tabName);
    expect(actualTotalBadge).toEqual(expectedTotalBadge);
});

Then('the user verifies Audit Vulnerabilities with the badge number of {int} excluding and {int} including aliases on current project',
  async ({ selectedProjectPage }, expectedTotalBadge: number, expectedInfoBadge: number) => {
    const tabName = "auditVulnerabilities";
    const actualExcludingAlias = await selectedProjectPage.getTotalTabBadgeValue(tabName);
    const actualIncludingAlias = await selectedProjectPage.getInfoTabBadgeValue(tabName);

    expect(actualExcludingAlias).toEqual(expectedTotalBadge);
    expect(actualIncludingAlias).toEqual(expectedInfoBadge);
});

Then('the user verifies Policy Violations with the badge number of {int} total {int} info {int} warn {int} fail violations on current project',
  async ({ selectedProjectPage }, totalBadge: number, infoBadge: number, warnBadge: number, failBadge: number) => {
    const tabName = "policyViolations";
    const actualTotalBadge = await selectedProjectPage.getTotalTabBadgeValue(tabName);
    const actualInfoBadge = await selectedProjectPage.getInfoTabBadgeValue(tabName);
    const actualWarnBadge = await selectedProjectPage.getWarnTabBadgeValue(tabName);
    const actualFailBadge = await selectedProjectPage.getFailTabBadgeValue(tabName);

    expect(actualTotalBadge).toEqual(totalBadge);
    expect(actualInfoBadge).toEqual(infoBadge);
    expect(actualWarnBadge).toEqual(warnBadge);
    expect(actualFailBadge).toEqual(failBadge);
});

Then('the table on the respective projects tab is visible and contains entries', async ({ page }) => {
    const tabPanelListLocator = page.locator('.tab-pane.active');

    await expect(tabPanelListLocator).toBeVisible();
    expect(await tabPanelListLocator.locator('tbody tr').count()).toBeGreaterThan(0);
});

Then('the dependency graph tab is visible and contains a node with child entries', async ({ projectDependencyGraphPage }) => {
    await projectDependencyGraphPage.toggleTreeNodeExpansion();

    await expect(projectDependencyGraphPage.tabPanel).toBeVisible();
    expect(await projectDependencyGraphPage.treeNodeChild.count()).toBeGreaterThan(0);

    await projectDependencyGraphPage.toggleTreeNodeExpansion();
});

Then('the user opens the policy violation of Component {string}', async ({ projectPolicyViolationsPage }, component: string) => {
    await projectPolicyViolationsPage.fillSearchFieldInput(component);
    await projectPolicyViolationsPage.toggleDetailViewOnSpecificViolation(component);
});

Then('the user comments the current policy violation with {string}', async ({ projectPolicyViolationsPage, notificationToast }, comment: string) => {
    await projectPolicyViolationsPage.fillDetailViewCommentField(comment);
    await projectPolicyViolationsPage.clickOnDetailViewAddCommentButton();
    await notificationToast.verifySuccessfulUpdatedToast();
});

Then('the user sets the analysis to {string}', async ({ projectPolicyViolationsPage, notificationToast }, option: string) => {
    await projectPolicyViolationsPage.setDetailViewAnalysisSelect(option);
    await notificationToast.verifySuccessfulUpdatedToast();
});

Then('the user suppresses the current policy violation', async ({ projectPolicyViolationsPage, notificationToast }) => {
    await projectPolicyViolationsPage.clickDetailViewSuppressToggle();
    await notificationToast.verifySuccessfulUpdatedToast();
});

Then('the audit trail should contain {string}', async ({ projectPolicyViolationsPage }, content: string) => {
    const regex = new RegExp(content, "i");
    await expect(projectPolicyViolationsPage.detailViewAuditTrailField).toHaveValue(regex);
});

Then('the policy violation of the component {string} will not appear in search result', async ({ projectPolicyViolationsPage }, component: string) => {
    await projectPolicyViolationsPage.fillSearchFieldInput(component);
    await projectPolicyViolationsPage.clearSearchFieldInput();
    await projectPolicyViolationsPage.fillSearchFieldInput(component);
    await expect(projectPolicyViolationsPage.tableList).toContainText(/No matching records found/);
});

Then('the project {string} should be a parent project and contain {string} as child project', async ({ projectPage }, parent: string, child: string) => {
    const parentRow = await projectPage.getProjectTableRow(parent);

    await expect(parentRow).toHaveClass(/treegrid-collapsed/);
    await projectShouldNotBeVisible({projectPage}, child);
    await expect(projectPage.projectList).not.toContainText(child);

    await parentRow.locator('.treegrid-expander').click();
    await projectShouldBeVisible({projectPage}, child);
});

Then('the upload-bom button is invisible', async ({ projectComponentsPage }) => {
    await expect(projectComponentsPage.uploadBomButton).not.toBeVisible();
});

Then('the upload-bom button should be visible', async ({ projectComponentsPage }) => {
    await expect(projectComponentsPage.uploadBomButton).toBeVisible();
});

Then('the project {string} tab should not be visible', async ({ selectedProjectPage }, projectTab: string) => {
    const tabLocator = await selectedProjectPage.getTabLocator(projectTab);
    await expect(tabLocator).not.toBeVisible();
});

Then('the project {string} tab should be visible', async ({ selectedProjectPage }, projectTab: string) => {
    const tabLocator = await selectedProjectPage.getTabLocator(projectTab)
    await expect(tabLocator).toBeVisible();
});

Then('the create-project button should not visible', async ({ projectPage }) => {
    await expect(projectPage.createProjectButton).not.toBeVisible();
});

Then('the create-project button should be visible', async ({ projectPage }) => {
    await expect(projectPage.createProjectButton).toBeVisible();
});

Then('the add-component button should not be visible', async ({ projectComponentsPage }) => {
    await expect(projectComponentsPage.addComponentButton).not.toBeVisible();
});

Then('the remove-component button should not be visible', async ({ projectComponentsPage }) => {
    await expect(projectComponentsPage.removeComponentButton).not.toBeVisible();
});

Then('the add-component button should be visible', async ({ projectComponentsPage }) => {
    await expect(projectComponentsPage.addComponentButton).toBeVisible();
});

Then('the remove-component button should be visible', async ({ projectComponentsPage }) => {
    await expect(projectComponentsPage.removeComponentButton).toBeVisible();
});

Then('the delete-project button in project details should not be visible', async ({ selectedProjectPage }) => {
    await expect(selectedProjectPage.projectDetailsDeleteButton).not.toBeVisible();
});

Then('the project-properties button in project details should not be visible', async ({ selectedProjectPage }) => {
    await expect(selectedProjectPage.projectDetailsPropertiesButton).not.toBeVisible();
});

Then('the add-version button in project details should not be visible', async ({ selectedProjectPage }) => {
    await expect(selectedProjectPage.projectDetailsAddVersionButton).not.toBeVisible();
});

Then('the update-project button in project details should not be visible', async ({ selectedProjectPage }) => {
    await expect(selectedProjectPage.projectDetailsUpdateButton).not.toBeVisible();
});

Then('the delete-project button in project details should be visible', async ({ selectedProjectPage }) => {
    await expect(selectedProjectPage.projectDetailsDeleteButton).toBeVisible();
});

Then('the project-properties button in project details should be visible', async ({ selectedProjectPage }) => {
    await expect(selectedProjectPage.projectDetailsPropertiesButton).toBeVisible();
});

Then('the add-version button in project details should be visible', async ({ selectedProjectPage }) => {
    await expect(selectedProjectPage.projectDetailsAddVersionButton).toBeVisible();
});

Then('the update-project button in project details should be visible', async ({ selectedProjectPage }) => {
    await expect(selectedProjectPage.projectDetailsUpdateButton).toBeVisible();
});

Then('the user verifies read access on the vulnerability audit view on audit Vulnerability project tab', async ({ projectAuditVulnerabilitiesPage }) => {
    await expect(projectAuditVulnerabilitiesPage.detailViewTitleField).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewDescriptionField).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewAuditTrailField).toBeVisible();

    await expect(projectAuditVulnerabilitiesPage.detailViewCommentField).not.toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewAddCommentButton).not.toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewAnalysisSelect).not.toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewSuppressToggle).not.toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewJustificationSelect).not.toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewVendorResponseSelect).not.toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewAnalysisDetailsField).not.toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewUpdateAnalysisDetailsButton).not.toBeVisible();
});

Then('the user verifies write access on the vulnerability audit view on audit Vulnerability project tab', async ({ projectAuditVulnerabilitiesPage }) => {
    await expect(projectAuditVulnerabilitiesPage.detailViewTitleField).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewDescriptionField).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewAuditTrailField).toBeVisible();

    await expect(projectAuditVulnerabilitiesPage.detailViewCommentField).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewAddCommentButton).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewAnalysisSelect).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewSuppressToggle).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewJustificationSelect).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewVendorResponseSelect).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewAnalysisDetailsField).toBeVisible();
    await expect(projectAuditVulnerabilitiesPage.detailViewUpdateAnalysisDetailsButton).toBeVisible();
});

Then('the user verifies read access on the policy violation audit view on policy violations project tab', async ({ projectPolicyViolationsPage }) => {
    await expect(projectPolicyViolationsPage.detailViewFailedConditionField).toBeVisible();
    await expect(projectPolicyViolationsPage.detailViewAuditTrailField).toBeVisible();

    await expect(projectPolicyViolationsPage.detailViewSuppressToggle).not.toBeVisible();
    await expect(projectPolicyViolationsPage.detailViewCommentField).not.toBeVisible();
    await expect(projectPolicyViolationsPage.detailViewAddCommentButton).not.toBeVisible();
    await expect(projectPolicyViolationsPage.detailViewAnalysisSelect).not.toBeVisible();
});

Then('the user verifies write access on the policy violation audit view on policy violations project tab', async ({ projectPolicyViolationsPage }) => {
    await expect(projectPolicyViolationsPage.detailViewFailedConditionField).toBeVisible();
    await expect(projectPolicyViolationsPage.detailViewAuditTrailField).toBeVisible();

    await expect(projectPolicyViolationsPage.detailViewSuppressToggle).toBeVisible();
    await expect(projectPolicyViolationsPage.detailViewCommentField).toBeVisible();
    await expect(projectPolicyViolationsPage.detailViewAddCommentButton).toBeVisible();
    await expect(projectPolicyViolationsPage.detailViewAnalysisSelect).toBeVisible();
});

Then('the user adds a custom component on projects component page with the following values', async ({ page, projectComponentsPage, notificationToast }, dataTable: DataTable) => {
    for(const row of dataTable.hashes()) {
        await projectComponentsPage.clickOnAddComponent();
        await projectComponentsPage.addComponent(row.componentName, row.componentVersion, row.componentPURL);
        await notificationToast.verifySuccessfulComponentCreatedToast();
        await page.waitForTimeout(1000);
    }
});

Then('the user deletes the custom component {string} on projects component page', async ({ page, projectComponentsPage, selectedComponentsPage, notificationToast }, componentName: string) => {
    await projectComponentsPage.fillSearchFieldInput(componentName);
    await projectComponentsPage.clickOnSpecificComponent(componentName);
    await selectedComponentsPage.clickOnViewDetails();
    await selectedComponentsPage.deleteComponent();
    await notificationToast.verifySuccessfulComponentDeletedToast();
    await page.waitForTimeout(1000);
});

Then('the user applies default VEX for current project', async ({ page, projectAuditVulnerabilitiesPage, notificationToast }) => {
    await projectAuditVulnerabilitiesPage.applyVex();
    await notificationToast.verifySuccessfulVexUploadedToast();
    await page.waitForTimeout(1000);
});

Then('the user verifies default VEX application for current project with the following values', async ({ page, projectAuditVulnerabilitiesPage }, dataTable: DataTable) => {
    await projectAuditVulnerabilitiesPage.showSuppressedVulnerabilities();
    for(const row of dataTable.hashes()) {
        await projectAuditVulnerabilitiesPage.fillSearchFieldInput(row.componentName);
        await projectAuditVulnerabilitiesPage.toggleDetailViewOnSpecificVulnerability(row.componentName);

        await projectAuditVulnerabilitiesPage.detailView.scrollIntoViewIfNeeded();

        await expect(projectAuditVulnerabilitiesPage.detailViewAnalysisSelect).toHaveValue(new RegExp(row.analysisState, 'i'));
        await expect(projectAuditVulnerabilitiesPage.detailViewJustificationSelect).toHaveValue(new RegExp(row.justification, 'i'));
        await expect(projectAuditVulnerabilitiesPage.detailViewVendorResponseSelect).toHaveValue(new RegExp(row.response, 'i'));

        await expect(projectAuditVulnerabilitiesPage.detailViewAnalysisDetailsField).toHaveValue(new RegExp(row.details, 'i'));

        await projectAuditVulnerabilitiesPage.toggleDetailViewOnSpecificVulnerability(row.componentName);
        await page.waitForTimeout(1000);
    }
    await projectAuditVulnerabilitiesPage.hideSuppressedVulnerabilities();
});

Then('the user expands the violation {string} on policy violation project tab', async ({ projectPolicyViolationsPage }, violationName: string) => {
    await projectPolicyViolationsPage.fillSearchFieldInput(violationName);
    await projectPolicyViolationsPage.toggleDetailViewOnSpecificViolation(violationName);
});

Then('the user expands the vulnerability {string} on audit vulnerability project tab', async ({ projectAuditVulnerabilitiesPage }, violationName: string) => {
    await projectAuditVulnerabilitiesPage.fillSearchFieldInput(violationName);
    await projectAuditVulnerabilitiesPage.toggleDetailViewOnSpecificVulnerability(violationName);
});