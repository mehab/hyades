/* eslint-disable */
import {Page, Locator, expect} from '@playwright/test';
import { getValue } from "../utilities/utils";

export class DashboardPage {
    page: Page;
    breadCrumb: Locator;
    dashBoardContainer: Locator;

    constructor(page: Page) {
        this.page = page;
        this.breadCrumb = page.locator('.breadcrumb');
        this.dashBoardContainer = page.locator('.container-fluid');
    }

    async pageShouldBeVisible() {
        await expect(this.breadCrumb).toContainText(getValue("message", "dashboard"));
        await expect(this.dashBoardContainer).toBeVisible();
    }
}