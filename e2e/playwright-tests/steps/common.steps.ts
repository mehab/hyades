/* eslint-disable */
import { Given, Then } from '../fixtures/fixtures';
import * as fs from "node:fs";
import {expect} from "@playwright/test";

Given('the user {string} is already authenticated for DependencyTrack', async ({ page, navBarPage }, username: string) => {
    const sessionStorage = JSON.parse(fs.readFileSync(__dirname + `/../resources/.auth/${username}.json`, 'utf-8'));
    await page.context().addInitScript(storage => {
        for (const [key, value] of Object.entries(storage))
            if (typeof value === "string") {
                window.sessionStorage.setItem(key, value);
            }
    }, sessionStorage);
    await page.goto('/');
    await navBarPage.verifyNavTabIsActive('dashboard');
});

Given('the admin user logs in to DependencyTrack and verifies', async ({ loginPage, navBarPage }) => {
    await loginPage.goto();
    await loginPage.verifyVisibleLoginPage();
    await loginPage.login('admin', process.env.RANDOM_PASSWORD);
    await navBarPage.verifyNavTabIsActive('dashboard');
});

Given('the user {string} tries to log in to DependencyTrack', async ({ loginPage }, username: string) => {
    await loginPage.goto();
    await loginPage.verifyVisibleLoginPage();
    await loginPage.login(username, process.env.RANDOM_PASSWORD);
});

Given('the user {string} logs in to DependencyTrack and verifies', async ({ loginPage, navBarPage }, username: string) => {
    await loginPage.goto();
    await loginPage.login(username, process.env.RANDOM_PASSWORD);
    await navBarPage.verifyNavTabIsActive('dashboard');
});

Given('the user {string} tries to log in to DependencyTrack with password {string}', async ({ loginPage }, username: string, password: string) => {
    await loginPage.goto();
    await loginPage.verifyVisibleLoginPage();
    await loginPage.login(username, password);
});

Then('the user sees wrong log in credentials modal content popup and closes it', async ({ loginPage }) => {
    await loginPage.verifyLoginErrorPopup();
    await loginPage.closeLoginErrorPopup();
});

Then('the delete-tag button is not visible', async ({ tagsPage }) => {
    await expect(tagsPage.deleteButton).not.toBeVisible();
});

Then('the delete-tag button should be visible', async ({ tagsPage }) => {
    await expect(tagsPage.deleteButton).toBeVisible();
});