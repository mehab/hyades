/* eslint-disable */
import {Then} from '../fixtures/fixtures';
import {expect} from "@playwright/test";

Then('the user navigates to {string} page and verifies', async ({ navBarPage }, navTab: string) => {
    await navBarPage.clickOnNavTab(navTab);
    await navBarPage.verifyNavTabIsActive(navTab);
});

Then('the {string} tab should not be visible', async ({ navBarPage }, navTab: string) => {
    const navTabLocator = await navBarPage.getNavTabLocator(navTab);
    await expect(navTabLocator).not.toBeVisible();
});