/* eslint-disable */
import { Then } from '../fixtures/fixtures';
import {expect} from "@playwright/test";
import {DataTable} from "playwright-bdd";

Then('the create-vulnerability button should not be visible', async ({ vulnerabilitiesPage }) => {
    await expect(vulnerabilitiesPage.createVulnerabilityButton).not.toBeVisible();
});

Then('the create-vulnerability button should be visible', async ({ vulnerabilitiesPage }) => {
    await expect(vulnerabilitiesPage.createVulnerabilityButton).toBeVisible();
});

Then('the user creates the following test vulnerabilities', async ({ page, navBarPage, vulnerabilitiesPage, notificationToast }, dataTable: DataTable) => {
    for(const row of dataTable.hashes()) {
        await vulnerabilitiesPage.clickOnCreateVulnerability();
        await vulnerabilitiesPage.createVulnerability(
            row.vulnerabilityName,
            row.severity,
            row.title || undefined,
            row.cvssSeverity || undefined,
            row.owaspRiskRating || undefined,
            row.cwe || undefined,
            row.description || undefined,
            row.affectedComponent || undefined
        );
        await notificationToast.verifySuccessfulVulnerabilityCreatedToast();
        await page.waitForTimeout(1000);
        await navBarPage.clickOnNavTab('vulnerabilities');
    }
});

Then('the user deletes the following test vulnerabilities if they exist', async ({ page, vulnerabilitiesPage, selectedVulnerabilitiesPage, notificationToast }, dataTable: DataTable) => {
    const count = await page.locator('tbody tr').count();
    if(count === 0) {
        return;
    }

    for(const row of dataTable.hashes()) {
        await vulnerabilitiesPage.fillSearchFieldInput(row.vulnerabilityName);

        const projectDoesntExist = await page.locator('.no-records-found').isVisible();
        if(projectDoesntExist) {
            console.warn(`Couldn't find vulnerability with name ${row.vulnerabilityName}. Moving on.`);
            continue;
        }
        try {
            await vulnerabilitiesPage.clickOnSpecificVulnerability(row.vulnerabilityName, row.isInternal ? row.isInternal === "true" : undefined);
            await selectedVulnerabilitiesPage.clickOnDetails();
            await selectedVulnerabilitiesPage.deleteVulnerability();

            await notificationToast.verifySuccessfulVulnerabilityDeletedToast();
        } catch (e) {
            console.warn(`Couldn't find vulnerability with name ${row.vulnerabilityName}. Moving on.`);
            continue;
        }
        await page.waitForTimeout(1000);
    }
});