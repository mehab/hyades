/* eslint-disable */
import { Then } from '../fixtures/fixtures';
import { DataTable } from 'playwright-bdd';
import {expect} from "@playwright/test";

Then('the user navigates to administration menu {string}', async ({ administrationPage }, adminMenu: string) => {
    await administrationPage.clickOnAdminMenu(adminMenu);
});

Then('the user clicks on access-management submenu {string}', async ({ accessManagementSubMenu }, adminSubMenu: string) => {
    await accessManagementSubMenu.clickOnMenuItem(adminSubMenu);
});

Then('the user creates the following test users', async ({ page, accessManagementSubMenu, notificationToast }, dataTable: DataTable) => {
    for(const row of dataTable.hashes()) {
        await accessManagementSubMenu.createUser(row.username, process.env.RANDOM_PASSWORD);
        await notificationToast.verifySuccessfulUserCreatedToast();
        await page.waitForTimeout(2000);
    }
});

Then('the user provides {string} with the following permissions', async ({ page, notificationToast, accessManagementSubMenu }, username: string, dataTable: DataTable) => {
    const arrayOfPermissions = [];

    for(const row of dataTable.hashes()) {
        arrayOfPermissions.push(row.permission);
    }
    await accessManagementSubMenu.fillSearchFieldInput(username);
    await accessManagementSubMenu.clickOnSpecificUser(username);
    await accessManagementSubMenu.addPermissionsToSelectedUser(username, arrayOfPermissions);
    await notificationToast.verifySuccessfulUpdatedToast();
    await accessManagementSubMenu.clickOnSpecificUser(username);
    await page.waitForTimeout(2000);
});

Then('the user deletes the following test users if they exist', async ({ page, accessManagementSubMenu, notificationToast }, dataTable: DataTable) => {
    if(await page.locator('tbody tr').count() === 1) {
        return;
    }

    for(const row of dataTable.hashes()) {
        await accessManagementSubMenu.fillSearchFieldInput(row.username);

        const userDoesntExist = await page.locator('.no-records-found').isVisible();
        if(userDoesntExist) {
            console.warn(`Couldn't find user with name ${row.username}. Moving on.`);
            continue;
        }

        await accessManagementSubMenu.deleteUser(row.username);
        await notificationToast.verifySuccessfulUserDeletedToast();
        await page.waitForTimeout(1000);
    }
});

Then('the {string} menu should be visible', async ({ administrationPage }, adminMenu: string) => {
    const menuLocator = await administrationPage.getNavTabLocator(adminMenu);
    await expect(menuLocator).toBeVisible();
});

Then('the {string} menu should not be visible', async ({ administrationPage }, adminMenu: string) => {
    const menuLocator = await administrationPage.getNavTabLocator(adminMenu);
    await expect(menuLocator).not.toBeVisible();
});

Then('the accessManagement submenu should be visible', async ({ administrationPage, accessManagementSubMenu }) => {
    await administrationPage.verifyMenuTabIsShown('accessManagement');
    await accessManagementSubMenu.verifySubMenuIsVisible();
});