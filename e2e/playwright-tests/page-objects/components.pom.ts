/* eslint-disable */
import {Page, Locator, expect} from '@playwright/test';
import { getValue } from "../utilities/utils";

export class ComponentsPage {
    page: Page;

    componentSearchToolbar: Locator;
    componentsSubjectSelect: Locator;
    componentsSearchField: Locator;
    componentsSearchButton: Locator;

    tableList: Locator;

    constructor(page: Page) {
        this.page = page;

        this.componentSearchToolbar = page.locator('#componentSearchToolbar');
        this.componentsSubjectSelect = this.componentSearchToolbar.locator('#input-subject-input');
        this.componentsSearchField = this.componentSearchToolbar.locator('#input-value-input');
        this.componentsSearchButton = this.componentSearchToolbar.getByRole('button', { name: getValue("message", "search") });

        this.tableList = page.locator('tbody tr');
    }
}

class ComponentDetailsModal {
    page: Page;

    modalContent: Locator;

    detailsViewComponentNameInput: Locator;
    detailsViewComponentVersionInput: Locator;
    detailsViewComponentNamespaceInput: Locator;
    detailsViewComponentAuthorInput: Locator;
    detailsViewComponentPURLInput: Locator;
    detailsViewComponentCPEInput: Locator;
    detailsViewComponentSWIDTagIDInput: Locator;
    detailsViewComponentObjectIdentifierInput: Locator;

    modalFooter: Locator;
    detailsViewDeleteButton: Locator;
    detailsViewPropertiesButton: Locator;
    detailsViewCloseButton: Locator;
    detailsViewUpdateButton: Locator;

    constructor(page: Page) {
        this.page = page;

        this.modalContent = page.locator('.modal-content');
        this.detailsViewComponentNameInput = this.modalContent.locator('#component-name-input-input');
        this.detailsViewComponentVersionInput = this.modalContent.locator('#component-version-input-input');
        this.detailsViewComponentNamespaceInput = this.modalContent.locator('#component-group-input-input');
        this.detailsViewComponentAuthorInput = this.modalContent.locator('#component-author-input-input');
        this.detailsViewComponentPURLInput = this.modalContent.locator('#component-purl-input-input');
        this.detailsViewComponentCPEInput = this.modalContent.locator('#component-cpe-input-input');
        this.detailsViewComponentSWIDTagIDInput = this.modalContent.locator('#component-swidTagId-input-input');
        this.detailsViewComponentObjectIdentifierInput = this.modalContent.locator('#component-uuid-input');

        this.modalFooter = this.modalContent.locator('.modal-footer');
        this.detailsViewDeleteButton = this.modalFooter.getByRole('button', { name: getValue("message", "delete") });
        this.detailsViewPropertiesButton = this.modalFooter.getByRole('button', { name: getValue("message", "properties") });
        this.detailsViewCloseButton = this.modalFooter.getByRole('button', { name: getValue("message", "close") });
        this.detailsViewUpdateButton = this.modalFooter.getByRole('button', { name: getValue("message", "update") });
    }
}

export class SelectedComponentsPage extends ComponentDetailsModal {
    page: Page;

    viewDetailsLink: Locator;

    constructor(page: Page) {
        super(page);

        this.page = page;

        this.viewDetailsLink = page.locator('#component-info-footer').getByRole('button', { name: getValue("message", "view_details") });
    }

    async clickOnViewDetails() {
        await this.viewDetailsLink.click();
    }

    async deleteComponent() {
        await expect(this.modalContent).toBeVisible();

        await this.detailsViewDeleteButton.click();
    }
}