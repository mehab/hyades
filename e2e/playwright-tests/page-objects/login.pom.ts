/* eslint-disable */
import { Page, Locator, expect } from '@playwright/test';
import { getValue } from "../utilities/utils";

export class LoginPage {
    page: Page;
    heading: Locator;
    username: Locator;
    password: Locator;
    submitButton: Locator;
    loginDescription: Locator;
    loginErrorPopup: Locator;

    constructor(page: Page) {
        this.page = page;
        this.heading = page.getByRole('heading', { name: getValue("message", "login") });
        this.username = page.getByPlaceholder(getValue("message","username"));
        this.password = page.getByPlaceholder(getValue("message","password"));
        this.submitButton = page.getByRole('button', { name: getValue("message", "login") });
        this.loginDescription = page.locator('.text-muted');
        this.loginErrorPopup = page.locator('.modal-content');
    }

    async goto() {
        await this.page.goto('/');
        await this.verifyVisibleLoginPage();
    }

    async login(username: string, password: string) {
        await this.username.fill(username);
        await this.password.fill(password);
        await this.submitButton.click();
        await this.page.waitForTimeout(2000);
    }
    async verifyVisibleLoginPage() {
        await expect(this.page).toHaveTitle(/Login/);
        await expect(this.heading).toBeVisible();
    }
    async getLoginDescription() {
        return await this.loginDescription.innerText();
    }
    async verifyLoginErrorPopup() {
        await expect(this.loginErrorPopup).toBeVisible();
        await expect(this.loginErrorPopup).toContainText(getValue("message", "login_unauthorized"));
    }
    async closeLoginErrorPopup() {
        await this.loginErrorPopup.locator('button').click();
    }
}

export class PasswordChangePage {
    // http request error
    // unauthorized (401)
    page: Page;
    heading: Locator;
    username: Locator;
    currentPassword: Locator;
    newPassword: Locator;
    confirmNewPassword: Locator;
    submitButton: Locator;
    loginDescription: Locator;
    loginErrorPopup: Locator;

    constructor(page: Page) {
        this.page = page;
        this.heading = page.getByRole('heading', { name: getValue("message", "password_force_change") });
        this.username = page.locator('#username-input');
        this.currentPassword = page.locator('#current-password-input');
        this.newPassword = page.locator('#new-password-input');
        this.confirmNewPassword = page.locator('#confirm-password-input');

        this.submitButton = page.getByRole('button', { name: getValue("message", "password_change") });
        this.loginDescription = page.locator('.text-muted');
        this.loginErrorPopup = page.locator('.modal-content'); //login_unauthorized
    }

    async isPasswordChangePageVisible() {
        await expect(this.page).toHaveTitle(/Change Password/);
        await expect(this.heading).toBeVisible();
    }

    async doPasswordChangeFlow(username: string, currentPassword: string, newPassword: string) {
        await this.username.fill(username);
        await this.currentPassword.fill(currentPassword);
        await this.newPassword.fill(newPassword);
        await this.confirmNewPassword.fill(newPassword);
        await this.submitButton.click();
    }
}
