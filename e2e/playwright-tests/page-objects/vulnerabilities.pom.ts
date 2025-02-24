/* eslint-disable */
import {Page, Locator, expect} from '@playwright/test';
import { getValue } from "../utilities/utils";

class CreateVulnerabilityModal {
    page: Page;
    modalContent: Locator;

    activeTabPanel: Locator;
    tabNavigation: Locator;

    modalTabs: Record<string, Locator>;

    vulnerabilityIdInput: Locator;
    titleInput: Locator;
    severitySelect: Locator;
    cvssSeveritySelect: Locator;
    owaspRiskRatingSeveritySelect: Locator;
    cweButton: Locator;
    descriptionField: Locator;

    modalFooter: Locator;
    closeButton: Locator;
    createButton: Locator;

    constructor(page: Page) {
        this.modalContent = page.locator('.modal-content');
        this.activeTabPanel = this.modalContent.locator('.tab-pane.active');
        this.tabNavigation = this.modalContent.locator('.nav-tabs');

        this.modalTabs = {
            general: this.tabNavigation.getByRole('tab', { name: getValue("message", "general") }),
            extended: this.tabNavigation.getByRole('tab', { name: getValue("message", "extended") }),
            cvssV2: this.tabNavigation.getByRole('tab', { name: getValue("message", "cvss_v2") }),
            cvssV3: this.tabNavigation.getByRole('tab', { name: getValue("message", "cvss_v3") }),
            owaspRiskRating: this.tabNavigation.getByRole('tab', { name: getValue("message", "owasp_rr") }),
            affectedComponents: this.tabNavigation.getByRole('tab', { name: getValue("message", "affected_components") }),
            dates: this.tabNavigation.getByRole('tab', { name: getValue("message", "dates") })
        };

        this.vulnerabilityIdInput = this.activeTabPanel.locator('#vulnerability-id-input-input');
        this.titleInput = this.activeTabPanel.locator('#vulnerability-title-input-input');
        this.severitySelect = this.activeTabPanel.locator('#undefined-input').nth(0);
        this.cvssSeveritySelect = this.activeTabPanel.locator('#undefined-input').nth(1);
        this.owaspRiskRatingSeveritySelect = this.activeTabPanel.locator('#undefined-input').nth(2);
        this.cweButton = this.activeTabPanel.locator('.fa-plus-square');
        this.descriptionField = this.activeTabPanel.locator('#vulnerability-description-description');

        this.modalFooter = this.modalContent.locator('.modal-footer');
        this.closeButton = this.modalFooter.getByRole('button', { name: getValue("message", "close") });
        this.createButton = this.modalFooter.getByRole('button', { name: getValue("message", "create") });
    }

    async clickOnTab(tabName: string) {
        const tab = this.modalTabs[tabName];
        if (!tab) {
            throw new Error(`Tab '${tabName}' does not exist.`);
        }
        await tab.click();
        await this.page.waitForTimeout(1000);
        await expect(tab).toHaveClass(/active/);
    }

    async createVulnerability(vulnerabilityId: string, severity: string, title?: string, cvssSeverity?: string, owaspRiskRating?: string, cwe?: string, description?: string, affectedComponent?: string) {
        await expect(this.modalContent).toBeVisible();

        await this.vulnerabilityIdInput.fill(vulnerabilityId);
        await this.severitySelect.selectOption(severity);

        if(title) {
            await this.titleInput.fill(title);
        }
        if(cvssSeverity) {
            await this.cvssSeveritySelect.selectOption(cvssSeverity);
        }
        if(owaspRiskRating) {
            await this.owaspRiskRatingSeveritySelect.selectOption(owaspRiskRating);
        }
        if(cwe) {
            await this.cweButton.click();
            const cweModal = this.page.locator('#selectCweModal');
            await cweModal.locator('.search-input').pressSequentially(cwe);
            await this.page.waitForTimeout(1000);
            await cweModal.locator('tbody').locator('.bs-checkbox ').getByRole('checkbox').check();
            await cweModal.locator('.btn-primary').click();
        }
        if(description) {
            await this.descriptionField.fill(description);
        }
        if(affectedComponent) {
            const page = new AffectedComponentsPage(this.page);

            await this.clickOnTab('affectedComponents');
            await page.addNewAffectedComponent(affectedComponent);
        }
        await this.createButton.click();
    }
}

export class VulnerabilitiesPage extends CreateVulnerabilityModal {
    page: Page;
    toolbar: Locator;
    createVulnerabilityButton: Locator;
    searchFieldInput: Locator;
    table: Locator;
    tableList: Locator;

    constructor(page: Page) {
        super(page);

        this.page = page;
        this.toolbar = page.locator('.fixed-table-toolbar');
        this.createVulnerabilityButton = this.toolbar.getByRole('button', { name: getValue("message", "create_vulnerability") });
        this.searchFieldInput = this.toolbar.locator('.search-input');
        this.table = this.page.locator('tbody');
        this.tableList = this.table.locator('tr');
    }

    async fillSearchFieldInput(search: string) {
        await this.searchFieldInput.clear();
        await this.searchFieldInput.pressSequentially(search);
        await this.page.waitForTimeout(1000);
    }

    async ClearSearchFieldInput() {
        await this.searchFieldInput.clear();
    }

    async clickOnCreateVulnerability() {
        await this.createVulnerabilityButton.click();
    }

    async clickOnSpecificVulnerability(vulnerabilityName: string, isInternal?: boolean) {
        let vulnerabilityLocator: Locator;
        if(isInternal) {
            vulnerabilityLocator = this.tableList.filter({ hasText: /INTERNAL/ });
        } else {
            vulnerabilityLocator = this.tableList.filter({ hasNotText: /INTERNAL/ });
        }
        await vulnerabilityLocator.getByRole('link', { name: vulnerabilityName }).click();
    }
}

class DetailsViewModal {
    page: Page;
    modalContent: Locator;

    detailsViewTitleInput: Locator;

    detailsViewSeveritySelect: Locator;

    detailsViewDeleteButton: Locator;
    detailsViewCloseButton: Locator;
    detailsViewUpdateButton: Locator;

    constructor(page: Page) {
        this.page = page;

        this.modalContent = page.locator('.modal-content');

        this.detailsViewTitleInput = this.modalContent.locator('#vulnerability-title-input-input');
        this.detailsViewSeveritySelect = this.modalContent.locator('#undefined-input').first();

        this.detailsViewDeleteButton = this.modalContent.getByRole('button', { name: getValue("message", "delete") });
        this.detailsViewCloseButton = this.modalContent.getByRole('button', { name: getValue("message", "close") });
        this.detailsViewUpdateButton = this.modalContent.getByRole('button', { name: getValue("message", "update") });
    }

    async deleteVulnerability() {
        await expect(this.modalContent).toBeVisible();
        await this.detailsViewDeleteButton.click();
    }
}

export class SelectedVulnerabilitiesPage extends DetailsViewModal{
    page: Page;
    viewDetails: Locator;

    constructor(page: Page) {
        super(page);

        this.page = page;
        this.viewDetails = page.locator('#vulnerability-info-footer').getByText(getValue("message", "view_details"));
    }

    async clickOnDetails() {
        await this.viewDetails.click();
        await this.page.waitForTimeout(500);
    }
}

class AffectedComponentsPage {
    page: Page;

    addNewAffectedComponentButton: Locator;

    affectedComponentsModalContent: Locator;

    affectedComponentsIdentifierTypeSelect: Locator;
    affectedComponentsIdentifierInput: Locator;
    affectedComponentsVersionTypeSelect: Locator;

    affectedComponentsCancelButton: Locator;
    affectedComponentsAddButton: Locator;

    constructor(page: Page) {
        this.page = page;

        this.addNewAffectedComponentButton = this.page.locator('.tab-pane.active').locator('.fa-plus-square');

        this.affectedComponentsModalContent = this.page.locator('#addAffectedComponentModal');

        this.affectedComponentsIdentifierTypeSelect = this.affectedComponentsModalContent.locator('#undefined-input').nth(0);
        this.affectedComponentsIdentifierInput = this.affectedComponentsModalContent.locator('#undefined-input').nth(1);
        this.affectedComponentsVersionTypeSelect = this.affectedComponentsModalContent.locator('#undefined-input').nth(2);

        this.affectedComponentsCancelButton = this.affectedComponentsModalContent.getByRole('button', { name: getValue("message", "cancel") });
        this.affectedComponentsAddButton = this.affectedComponentsModalContent.getByRole('button', { name: getValue("message", "add") });
    }

    async addNewAffectedComponent(identifier: string, identifierType?: string, versionType?: string) {
        await this.addNewAffectedComponentButton.click();
        await expect(this.affectedComponentsModalContent).toBeVisible();

        await this.affectedComponentsIdentifierInput.fill(identifier);

        if(identifierType) {
            await this.affectedComponentsIdentifierTypeSelect.selectOption(identifierType);
        }
        if(versionType) {
            await this.affectedComponentsVersionTypeSelect.selectOption(versionType);
        }

        await this.affectedComponentsAddButton.click();
    }
}