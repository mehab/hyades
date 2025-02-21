/* eslint-disable */
import {Page, Locator, expect} from '@playwright/test';
import { getValue } from "../utilities/utils";

export class ProjectModal {
    modalContent: Locator;

    projectNameInput: Locator;
    projectVersionInput: Locator;
    projectIsLastVersionSlider: Locator;
    projectTeamSelect: Locator;
    projectClassifierSelect: Locator;
    projectParentField: Locator;
    projectDescriptionField: Locator;
    projectTag: Locator;
    projectCloseButton: Locator;
    projectActiveSlider: Locator;
    projectCreationButton: Locator;

    projectDetailsDeleteButton: Locator;
    projectDetailsPropertiesButton: Locator;
    projectDetailsAddVersionButton: Locator;
    projectDetailsUpdateButton: Locator;

    constructor(page: Page, isProjectCreation: boolean) {
        this.modalContent = page.locator('.modal-content');
        this.projectNameInput = this.modalContent.locator('#project-name-input-input');
        this.projectVersionInput = this.modalContent.locator('#project-version-input-input');
        this.projectIsLastVersionSlider = this.modalContent.locator('#project-create-islatest .switch-slider'); // #project-create-islatest-input
        this.projectClassifierSelect = this.modalContent.locator('#v-classifier-input-input');
        this.projectTeamSelect = this.modalContent.locator('#v-team-input-input');
        this.projectParentField = this.modalContent.locator('#multiselect');
        this.projectDescriptionField = this.modalContent.locator('#project-description-description');
        this.projectTag = this.modalContent.locator('.ti-new-tag-input');

        // Either Create or Update
        this.projectCloseButton = this.modalContent.getByRole('button', { name: getValue("message", "close") });

        if(isProjectCreation) {
            this.projectCreationButton = this.modalContent.getByRole('button', { name: getValue("message", "create") });
        } else {
            this.projectDetailsDeleteButton = this.modalContent.getByRole('button', { name: getValue("message", "delete") });
            this.projectDetailsPropertiesButton = this.modalContent.getByRole('button', { name: getValue("message", "properties") });
            this.projectDetailsAddVersionButton = this.modalContent.getByRole('button', { name: getValue("message", "add_version") });
            this.projectDetailsUpdateButton = this.modalContent.getByRole('button', { name: getValue("message", "update") });
        }

        // Project Details Active Inactive Button
        this.projectActiveSlider = this.modalContent.locator('#project-details-active .switch-slider');
    }
}

export class ProjectPage extends ProjectModal {
    page: Page;
    toolBar: Locator;
    createProjectButton: Locator;
    inactiveProjectSlider: Locator;
    flatProjectSlider: Locator;
    searchFieldInput: Locator;
    projectList: Locator;

    constructor(page: Page) {
        super(page, true);
        this.page = page;

        this.toolBar = page.locator('#projectsToolbar');

        this.createProjectButton = this.toolBar.getByRole('button', { name: getValue("message", "create_project")});
        this.inactiveProjectSlider = this.toolBar.locator('.switch').filter({ has: page.locator('#showInactiveProjects')}).locator('.switch-slider');
        this.flatProjectSlider = this.toolBar.locator('.switch').filter({ has: page.locator('#showFlatView')}).locator('.switch-slider');
        this.searchFieldInput = page.locator('.search-input');
        this.projectList = page.locator('tbody');
    }

    async clickOnCreateProject() {
        await this.createProjectButton.click();
        await expect(this.modalContent).toBeVisible();
    }

    async createProject(projectName: string, projectClassifier: string, version?: string, isLastVersion?: boolean, team?: string, parent?: string, description?: string, tag?: string) {
        await expect(this.modalContent).toBeVisible();
        await this.projectNameInput.fill(projectName);
        await this.projectClassifierSelect.selectOption(projectClassifier);

        if(version) {
            await this.projectVersionInput.fill(version);
        }
        if(isLastVersion) {
            await this.projectIsLastVersionSlider.check();
        }
        if(team) {
            await this.projectTeamSelect.selectOption(team);
        }
        if(parent) {
            await this.projectParentField.pressSequentially(parent);
            await this.modalContent.locator('#listbox-multiselect').locator('#multiselect-0').click();
        }
        if(description) {
            await this.projectDescriptionField.fill(description);
        }
        if(tag) {
            await this.projectTag.fill(tag);
        }

        await this.projectCreationButton.click();
    }

    async getProjectTableRow(projectName: string) {
        return this.projectList.locator('tr').filter({ hasText: projectName });
    }

    async deleteProject(projectName: string) {
        const selectedProjectPage = new SelectedProjectPage(this.page);

        await this.clickOnProject(projectName);

        await selectedProjectPage.openProjectDetails();
        await selectedProjectPage.deleteProjectInProjectDetails();
    }

    async clickOnProject(projectName: string) {
        await this.page.getByRole('link', { name: projectName, exact: true }).first().click();
        await this.page.waitForTimeout(1500);
        await expect(this.page.locator('.container-fluid')).toBeVisible();
        await expect(this.page.locator('.text-nowrap.col-md-auto')).toContainText(projectName);
    }

    async fillSearchFieldInput(search: string) {
        await this.searchFieldInput.clear();
        await this.searchFieldInput.pressSequentially(search);
        await this.page.waitForTimeout(1000);
    }
    async clearSearchFieldInput() {
        await this.searchFieldInput.clear();
        await this.page.waitForTimeout(1000);
    }

    async showInactiveProjects() {
        await this.inactiveProjectSlider.check();
    }
    async hideInactiveProjects() {
        await this.inactiveProjectSlider.uncheck();
    }
    async showFlatProjectView() {
        await this.flatProjectSlider.check();
    }
    async hideFlatProjectView() {
        await this.flatProjectSlider.uncheck();
    }
}

export class SelectedProjectPage extends ProjectModal {
    page: Page;
    projectCards: Locator;
    projectDetails: Locator;
    projectTabs: Locator;
    projectTabList: Record<string, Locator>;

    constructor(page: Page) {
        super(page, false);
        this.page = page;

        this.projectCards = page.locator('.card');
        this.projectDetails = page.getByRole('link', { name: getValue("message", "view_details") });

        this.projectTabs = page.getByRole('tablist');
        this.projectTabList = {
            overview: this.projectTabs.getByText(getValue("message", "overview")),
            components: this.projectTabs.getByText(getValue("message", "components")),
            services: this.projectTabs.getByText(getValue("message", "services")),
            dependencyGraph: this.projectTabs.getByText(getValue("message", "dependency_graph")),
            auditVulnerabilities: this.projectTabs.getByText(getValue("message", "audit_vulnerabilities")),
            exploitPredictions: this.projectTabs.getByText(getValue("message", "exploit_predictions")),
            policyViolations: this.projectTabs.getByText(getValue("message", "policy_violations")),
        };
    }

    async getProjectCard(cardNumber: number) {
        return this.projectCards.nth(cardNumber);
    }

    async getTabLocator(tabName: string) {
        const tab = this.projectTabList[tabName];
        if (!tab) {
            throw new Error(`Tab '${tabName}' does not exist.`);
        }
        return tab;
    }

    async clickOnTab(tabName: string) {
        const tab = this.projectTabList[tabName];
        if (!tab) {
            throw new Error(`Tab '${tabName}' does not exist.`);
        }
        await tab.click();
        await this.page.waitForTimeout(1000);
        await expect(tab).toHaveClass(/active/);
    }

    async getTotalTabBadgeValue(tabName: string) {
        const tab = this.projectTabList[tabName];
        if (!tab) {
            throw new Error(`Tab '${tabName}' does not exist.`);
        }
        const name = await tab.textContent();
        const regex = new RegExp(name.split("\n")[0].trim());

        const textContent = await this.projectTabs.getByRole('tab', { name: regex }).locator('span.badge.badge-tab-total').textContent();
        return parseInt(textContent, 10);
    }

    async getInfoTabBadgeValue(tabName: string) {
        const tab = this.projectTabList[tabName];
        if (!tab) {
            throw new Error(`Tab '${tabName}' does not exist.`);
        }
        const name = await tab.textContent();
        const regex = new RegExp(name.split("\n")[0].trim());

        const textContent = await this.projectTabs.getByRole('tab', { name: regex }).locator('span.badge.badge-tab-info').textContent();
        return parseInt(textContent, 10);
    }

    async getWarnTabBadgeValue(tabName: string) {
        const tab = this.projectTabList[tabName];
        if (!tab) {
            throw new Error(`Tab '${tabName}' does not exist.`);
        }
        const name = await tab.textContent();
        const regex = new RegExp(name.split("\n")[0].trim());

        const textContent = await this.projectTabs.getByRole('tab', { name: regex }).locator('span.badge.badge-tab-warn').textContent();
        return parseInt(textContent, 10);
    }

    async getFailTabBadgeValue(tabName: string) {
        const tab = this.projectTabList[tabName];
        if (!tab) {
            throw new Error(`Tab '${tabName}' does not exist.`);
        }
        const name = await tab.textContent();
        const regex = new RegExp(name.split("\n")[0].trim());

        const textContent = await this.projectTabs.getByRole('tab', { name: regex }).locator('span.badge.badge-tab-fail').textContent();
        return parseInt(textContent, 10);
    }

    async openProjectDetails() {
        await this.projectDetails.click();
        await expect(this.modalContent).toBeVisible();
        await expect(this.modalContent).toContainText(getValue("message", "project_details"));
    }

    async clickOnUpdateButton() {
        await this.projectDetailsUpdateButton.click();
    }

    async deleteProjectInProjectDetails() {
        await this.projectDetailsDeleteButton.click();

        await this.page.waitForTimeout(1000);

        await expect(this.modalContent).toBeVisible();
        await expect(this.modalContent).toContainText(getValue("message", "project_delete_title"));

        await this.modalContent.getByRole('button', { name: "OK" }).click();
    }

    async openPropertiesInProjectDetails() {
        await this.projectDetailsPropertiesButton.click();

        await this.page.waitForTimeout(1000);

        await expect(this.modalContent).toBeVisible();
        await expect(this.modalContent).toContainText(getValue("message", "project_properties"));
    }

    async addVersionInProjectDetails(version: string, isLatestVersion: boolean) {
        await this.projectDetailsAddVersionButton.click();

        await this.page.waitForTimeout(1000);

        await expect(this.modalContent).toBeVisible();
        await expect(this.modalContent).toContainText(getValue("message", "add_version"));

        await this.modalContent.locator('#input-1').fill(version);

        if(isLatestVersion) {
            await this.modalContent.locator('#project-details-islatest-input').check();
        }

        await this.modalContent.getByRole('button', { name: getValue("message", "create") }).click();
    }

    async makeProjectActive() {
        await this.projectActiveSlider.check();
    }

    async makeProjectInactive() {
        await this.projectActiveSlider.uncheck();
    }
}

class AddComponentModal {
    addComponentModal: Locator;

    componentNameInput: Locator;
    componentVersionInput: Locator;
    componentPackageURLInput: Locator;

    createComponentButton: Locator;
    closeComponentButton: Locator;

    constructor(page: Page) {
        this.addComponentModal = page.locator('.modal-content');

        this.componentNameInput = this.addComponentModal.locator('#component-name-input-input');
        this.componentVersionInput = this.addComponentModal.locator('#component-version-input-input');
        this.componentPackageURLInput = this.addComponentModal.locator('#component-purl-input-input');

        this.createComponentButton = this.addComponentModal.getByRole('button', { name: getValue("message", "create") });
        this.closeComponentButton = this.addComponentModal.getByRole('button', { name: getValue("message", "close") });
    }
}

export class ProjectComponentsPage extends AddComponentModal {
    readonly page: Page;
    tabPanel: Locator;

    addComponentButton: Locator;
    removeComponentButton: Locator;
    uploadBomButton: Locator;
    downloadBomButton: Locator;
    downloadComponentsButton: Locator;

    searchFieldInput: Locator;

    tableList: Locator;

    uploadBomModal: Locator;

    bomUploadBrowseButton: Locator;
    bomUploadCancelButton: Locator;
    bomUploadResetButton: Locator;
    bomUploadConfirmButton: Locator;

    downloadBomInventoryButton: Locator;
    downloadBomInventoryWithVulnerabilitiesButton: Locator;

    downloadComponentsCSVButton: Locator;

    constructor(page: Page) {
        super(page);

        this.page = page;
        this.tabPanel = page.locator('.tab-pane.active');

        this.addComponentButton = this.tabPanel.getByRole('button', { name: getValue("message", "add_component") });
        this.removeComponentButton = this.tabPanel.getByRole('button', { name: getValue("message", "remove_component") });
        this.uploadBomButton = this.tabPanel.locator('#upload-button');
        this.downloadBomButton = this.tabPanel.getByRole('button', { name: getValue("message", "download_bom") });
        this.downloadComponentsButton = this.tabPanel.getByRole('button', { name: getValue("message", "download_component") });
        this.searchFieldInput = this.tabPanel.locator('.search-input');

        this.tableList = this.tabPanel.locator('tbody tr');

        this.uploadBomModal = page.locator('.modal-content');

        // BOM Upload
        this.bomUploadBrowseButton = this.uploadBomModal.locator('.custom-file-label');
        this.bomUploadCancelButton = this.uploadBomModal.getByRole('button', { name: getValue("message", "cancel") });
        this.bomUploadResetButton = this.uploadBomModal.getByRole('button', { name: getValue("message", "reset") });
        this.bomUploadConfirmButton = this.uploadBomModal.getByRole('button', { name: getValue("message", "upload") });

        // BOM Download
        this.downloadBomInventoryButton = this.tabPanel.locator('.dropdown-menu.show').getByRole('menuitem', { name: getValue("message", "inventory") });
        this.downloadBomInventoryWithVulnerabilitiesButton = this.tabPanel.locator('.dropdown-menu.show').getByRole('menuitem', { name: getValue("message", "inventory_with_vulnerabilities") });

        // Components Download
        this.downloadComponentsCSVButton = this.tabPanel.locator('.dropdown-menu.show').getByRole('menuitem', { name: getValue("message", "csv_filetype") });
    }

    async fillSearchFieldInput(search: string) {
        await this.searchFieldInput.clear();
        await this.searchFieldInput.pressSequentially(search);
        await this.page.waitForTimeout(1000);
    }

    async clearSearchFieldInput() {
        await this.searchFieldInput.clear();
        await this.page.waitForTimeout(1000);
    }

    async uploadBom(filePathFromProjectRoot?: string) {
        filePathFromProjectRoot ??= "e2e/playwright-tests/resources/dtrack-5.6.0-sbom.json";

        await this.uploadBomButton.click();
        await this.page.waitForTimeout(1000);

        await expect(this.uploadBomModal).toBeVisible();
        await expect(this.uploadBomModal).toContainText(getValue("message", "upload_bom"));

        const fileChooserPromise = this.page.waitForEvent('filechooser');
        await this.bomUploadBrowseButton.click();
        const fileChooser = await fileChooserPromise;

        await fileChooser.setFiles(filePathFromProjectRoot);

        await this.bomUploadConfirmButton.click();
    }

    async clickOnAddComponent() {
        await this.addComponentButton.click();
    }

    async addComponent(componentName: string, componentVersion: string, componentPURL: string) {
        await expect(this.addComponentModal).toBeVisible();

        await this.componentNameInput.fill(componentName);
        await this.componentVersionInput.fill(componentVersion);
        await this.componentPackageURLInput.fill(componentPURL);

        await this.createComponentButton.click();
    }

    async clickOnSpecificComponent(componentName: string) {
        await this.tableList.getByRole('link', { name: componentName }).click();
    }
}

export class ProjectServicesPage {
    readonly page: Page;
    tabPanel: Locator;
    searchFieldInput: Locator;
    tableList: Locator;

    constructor(page: Page) {
        this.page = page;
        this.tabPanel = page.locator('.tab-pane.active');
        this.searchFieldInput = this.tabPanel.locator('.search-input');
        this.tableList = this.tabPanel.locator('tbody tr');
    }

    async fillSearchFieldInput(search: string) {
        await this.searchFieldInput.clear();
        await this.searchFieldInput.pressSequentially(search);
        await this.page.waitForTimeout(1000);
    }
}

export class ProjectDependencyGraphPage {
    readonly page: Page;
    tabPanel: Locator;

    treeNode: Locator;
    isExpanded: boolean;
    treeNodeChildrenList: Locator;
    treeNodeChild: Locator;
    treeNodeExpandButton: Locator;
    treeNodeExpandedButton: Locator;

    constructor(page: Page) {
        this.page = page;
        this.tabPanel = page.locator('.tab-pane.active');

        this.treeNode = this.tabPanel.locator('.org-tree-container');
        this.isExpanded = false;
        this.treeNodeChildrenList = this.tabPanel.locator('.org-tree-node-children');
        this.treeNodeChild = this.treeNodeChildrenList.locator('.org-tree-node');
        this.treeNodeExpandButton = this.treeNode.locator('.org-tree-node-btn');
        this.treeNodeExpandedButton = this.treeNode.locator('.org-tree-node-btn.expanded');
    }

    async toggleTreeNodeExpansion() {
        if(this.isExpanded) {
            await this.treeNodeExpandedButton.click();
            this.isExpanded = false;
        } else {
            await this.treeNodeExpandButton.click();
            this.isExpanded = true;
        }
        await this.page.waitForTimeout(1000);
    }
}

export class ProjectAuditVulnerabilitiesPage {
    readonly page: Page;
    tabPanel: Locator;
    toolbar: Locator;
    searchFieldInput: Locator;
    applyVexButton: Locator;
    exportVexButton: Locator;
    exportVdrButton: Locator;
    reanalyzeButton: Locator;
    suppressedFindingsSlider: Locator;

    applyVexModal: Locator;
    applyVexBrowseButton: Locator;
    applyVexCancelButton: Locator;
    applyVexResetButton: Locator;
    applyVexUploadButton: Locator;

    tableList: Locator;

    detailView: Locator;

    detailViewTitleField: Locator;
    detailViewDescriptionField: Locator;
    detailViewCommentField: Locator;
    detailViewAuditTrailField: Locator;
    detailViewAddCommentButton: Locator;
    detailViewAnalysisSelect: Locator;
    detailViewSuppressToggle: Locator;
    detailViewJustificationSelect: Locator;
    detailViewVendorResponseSelect: Locator;
    detailViewAnalysisDetailsField: Locator;
    detailViewUpdateAnalysisDetailsButton: Locator;

    constructor(page: Page) {
        this.page = page;
        this.tabPanel = page.locator('.tab-pane.active');
        this.toolbar = this.tabPanel.locator('.fixed-table-toolbar');

        this.searchFieldInput = this.toolbar.locator('.search-input');
        this.applyVexButton = this.toolbar.locator('#apply-vex-button');
        this.exportVexButton = this.toolbar.locator('#export-vex-button');
        this.exportVdrButton = this.toolbar.locator('#export-vdr-button');
        this.reanalyzeButton = this.toolbar.locator('#reanalyze-button');
        this.suppressedFindingsSlider = this.toolbar.locator('.switch-slider');

        this.applyVexModal = this.page.locator('.modal-content');
        this.applyVexBrowseButton = this.page.locator('.custom-file-label');
        this.applyVexCancelButton = this.page.getByRole("button", { name: getValue("message", "cancel") });
        this.applyVexResetButton = this.page.getByRole("button", { name: getValue("message", "reset") });
        this.applyVexUploadButton = this.page.getByRole("button", { name: getValue("message", "upload") });

        this.tableList = this.tabPanel.locator('tbody tr');

        this.detailView = this.tabPanel.locator('.detail-view');
        this.detailViewTitleField = this.detailView.locator('#input-1');
        this.detailViewDescriptionField = this.detailView.locator('#input-3');
        this.detailViewCommentField = this.detailView.locator('#input-8');
        this.detailViewAuditTrailField = this.detailView.locator('#auditTrailField');
        this.detailViewAddCommentButton = this.detailView.getByRole('button', { name: getValue("message", "add_comment") });
        this.detailViewAnalysisSelect = this.detailView.locator('#input-9').locator('.custom-select');
        this.detailViewSuppressToggle = this.detailView.locator('.toggle.btn');
        this.detailViewJustificationSelect = this.detailView.locator('#input-10').locator('.custom-select');
        this.detailViewVendorResponseSelect = this.detailView.locator('#input-11').locator('.custom-select');
        this.detailViewAnalysisDetailsField = this.detailView.locator('#analysisDetailsField');
        this.detailViewUpdateAnalysisDetailsButton = this.detailView.getByRole('button', { name: getValue("message", "update_details") });
    }

    async fillSearchFieldInput(search: string) {
        await this.searchFieldInput.clear();
        await this.searchFieldInput.pressSequentially(search);
        await this.page.waitForTimeout(1000);
    }

    async clearSearchFieldInput() {
        await this.searchFieldInput.clear();
        await this.page.waitForTimeout(1000);
    }

    async clickOnSpecificVulnerability(violation: string) {
        await this.tableList.getByRole('link', { name: violation }).click();
        await this.page.waitForTimeout(1000);
    }

    async toggleDetailViewOnSpecificVulnerability(violation: string) {
        await this.tableList.filter({ hasText: violation }).locator('td').first().click();
        await this.page.waitForTimeout(1000);
    }

    async showSuppressedVulnerabilities() {
        await this.suppressedFindingsSlider.check();
    }

    async hideSuppressedVulnerabilities() {
        await this.suppressedFindingsSlider.uncheck();
    }

    async applyVex(filePathFromProjectRoot?: string) {
        filePathFromProjectRoot ??= "e2e/playwright-tests/resources/dtrack-4.8.0.vex.cdx.json";
        await this.applyVexButton.click();
        await this.page.waitForTimeout(1000);

        await expect(this.applyVexModal).toBeVisible();
        await expect(this.applyVexModal).toContainText(getValue("message", "upload_vex"));

        const fileChooserPromise = this.page.waitForEvent('filechooser');
        await this.applyVexBrowseButton.click();
        const fileChooser = await fileChooserPromise;

        await fileChooser.setFiles(filePathFromProjectRoot);

        await this.applyVexUploadButton.click();
    }
}

export class ProjectExploitPredictionsPage {
    readonly page: Page;
    tabPanel: Locator;
    searchFieldInput: Locator;
    tableList: Locator;

    constructor(page: Page) {
        this.page = page;
        this.tabPanel = page.locator('.tab-pane.active');
        this.searchFieldInput = this.tabPanel.locator('.search-input');
        this.tableList = this.tabPanel.locator('tbody tr');
    }

    async fillSearchFieldInput(search: string) {
        await this.searchFieldInput.clear();
        await this.searchFieldInput.pressSequentially(search);
        await this.page.waitForTimeout(1000);
    }
}

export class ProjectPolicyViolationsPage {
    readonly page: Page;
    tabPanel: Locator;
    searchFieldInput: Locator;
    table: Locator;
    tableList: Locator;

    suppressSlider: Locator;

    detailView: Locator;

    detailViewFailedConditionField: Locator;
    detailViewAuditTrailField: Locator;
    detailViewCommentField: Locator;
    detailViewAddCommentButton: Locator;
    detailViewAnalysisSelect: Locator;
    detailViewSuppressToggle: Locator;
    lastDetailViewAnalysisSelect: string;

    constructor(page: Page) {
        this.page = page;
        this.tabPanel = page.locator('.tab-pane.active');

        this.suppressSlider = this.tabPanel.locator('.switch-slider');

        this.searchFieldInput = this.tabPanel.locator('.search-input');
        this.table = this.tabPanel.locator('tbody');
        this.tableList = this.table.locator('tr');
        this.detailView = this.tabPanel.locator('.detail-view');

        this.detailViewFailedConditionField = this.detailView.locator('#failedCondition-input');
        this.detailViewAuditTrailField = this.detailView.locator('#auditTrailField');
        this.detailViewCommentField = this.detailView.locator('#input-8');
        this.detailViewAddCommentButton = this.detailView.getByRole('button', { name: getValue("message", "add_comment") });
        this.detailViewAnalysisSelect = this.detailView.locator('.custom-select');
        this.detailViewSuppressToggle = this.detailView.locator('.toggle.btn');
        this.lastDetailViewAnalysisSelect = "NOT_SET"
    }

    async clearSearchFieldInput() {
        await this.searchFieldInput.clear();
        await this.page.waitForTimeout(1000);
    }

    async fillSearchFieldInput(search: string) {
        await this.searchFieldInput.clear();
        await this.searchFieldInput.pressSequentially(search);
        await this.page.waitForTimeout(1000);
    }

    async toggleDetailViewOnSpecificViolation(violation: string) {
        await this.tableList.filter({ hasText: violation }).locator('td').first().click();
        await this.page.waitForTimeout(1000);
    }

    async fillDetailViewCommentField(input: string) {
        await this.detailViewCommentField.fill(input);
    }

    async clickOnDetailViewAddCommentButton() {
        await this.detailViewAddCommentButton.click();
    }

    async setDetailViewAnalysisSelect(option: string) {
        await this.detailViewAnalysisSelect.selectOption(option);
        this.lastDetailViewAnalysisSelect = await this.detailViewAnalysisSelect.getByRole('option', { name: option }).getAttribute('value');
    }

    async clickDetailViewSuppressToggle() {
        await this.detailViewSuppressToggle.click();
    }

    async toggleSuppressedViolations() {
        await this.suppressSlider.click();
    }
}