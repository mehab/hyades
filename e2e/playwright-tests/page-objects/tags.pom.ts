/* eslint-disable */
import {Page, Locator } from '@playwright/test';

export class TagsPage {
    page: Page;
    toolbar: Locator;
    searchFieldInput: Locator;
    deleteButton: Locator;
    tagsList: Locator;

    constructor(page: Page) {
        this.page = page;
        this.toolbar = page.locator('.fixed-table-toolbar');

        this.deleteButton = this.toolbar.locator('.fa-trash');
        this.searchFieldInput = this.toolbar.locator('.search-input');

        this.tagsList = page.locator('tbody');
    }

    async fillSearchFieldInput(search: string) {
        await this.searchFieldInput.clear();
        await this.searchFieldInput.pressSequentially(search);
        await this.page.waitForTimeout(1000);
    }

    async ClearSearchFieldInput() {
        await this.searchFieldInput.clear();
    }
}