/* eslint-disable */
import { Then } from '../fixtures/fixtures';
import { DataTable } from 'playwright-bdd';
import {expect} from "@playwright/test";

Then('the user creates the following test policies', async ({ page, policyPage, notificationToast }, dataTable: DataTable) => {
    for(const row of dataTable.hashes()) {
        await policyPage.clickOnCreatePolicy();
        await policyPage.createPolicy(row.policyName);
        await notificationToast.verifySuccessfulPolicyCreatedToast();
        await page.waitForTimeout(1000);
    }
});

Then('the user updates a policy with the following values', async ({ page, policyPage, notificationToast }, dataTable: DataTable) => {
    for(const row of dataTable.hashes()) {
        await policyPage.fillSearchFieldInput(row.policyName);
        await policyPage.togglePolicyDetailView(row.policyName);

        await policyPage.updatePolicyName(row.newPolicyName);
        await policyPage.updatePolicyOperator(row.operator);
        await policyPage.updatePolicyViolationState(row.violationState);
        await notificationToast.verifySuccessfulUpdatedToast();
        // Playwright .selectOption inside updatePolicyOperator() and updatePolicyViolationState() doesn't get recognized by DTrack so the Toast is only displayed once

        await policyPage.togglePolicyDetailView(row.policyName);
        await page.waitForTimeout(1000);
    }
});

Then('the user adds conditions to {string} with the following values', async ({ page, policyPage, notificationToast }, policyName: string, dataTable: DataTable) => {
    for(const row of dataTable.hashes()) {
        await policyPage.fillSearchFieldInput(policyName);
        await policyPage.togglePolicyDetailView(policyName);

        await policyPage.addConditionToPolicy(row.conditionSubject, row.conditionOperator, row.conditionInputValue);
        await notificationToast.verifySuccessfulUpdatedToast();
        await page.waitForTimeout(1000);
    }
    await policyPage.togglePolicyDetailView(policyName);
});

Then('the user deletes the following test policies if they exist', async ({ page, policyPage, notificationToast }, dataTable: DataTable) => {
    const count = await page.locator('tbody tr').count();
    if(count === 0) {
        return;
    }

    for(const row of dataTable.hashes()) {
        await policyPage.fillSearchFieldInput(row.policyName);

        const policyDoesntExist = await page.locator('.no-records-found').first().isVisible();
        if(policyDoesntExist) {
            console.warn(`Couldn't find project with name ${row.policyName}. Moving on.`);
            continue;
        }

        await policyPage.togglePolicyDetailView(row.policyName);
        await policyPage.deletePolicy();
        await notificationToast.verifySuccessfulPolicyDeletedToast();
        await page.waitForTimeout(1000);
    }
});

Then('the create-policy button should be visible', async ({ policyPage }) => {
    await expect(policyPage.createPolicyButton).toBeVisible();
});

Then('the policy {string} is visible', async ({ policyPage }, policyName: string) => {
    await expect(policyPage.policyList).toContainText(policyName);
});

Then('the user navigates to policyManagement {string} tab', async ({ policyPage }, tabName: string) => {
    await policyPage.clickOnTab(tabName);
});

Then('the create-licence-group button should be visible', async ({ licenceGroupPage }) => {
    await expect(licenceGroupPage.createLicenceGroupButton).toBeVisible();
});

Then('the licence-group {string} is visible', async ({ licenceGroupPage }, licenceGroupName: string) => {
    await expect(licenceGroupPage.licenceGroupList).toContainText(licenceGroupName);
});
