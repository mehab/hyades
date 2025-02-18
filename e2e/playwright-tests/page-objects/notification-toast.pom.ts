/* eslint-disable */
import {Page, Locator, expect} from '@playwright/test';
import { getValue } from "../utilities/utils";

export class NotificationToast {
    page: Page;
    successToast: Locator;
    warnToast: Locator;
    errorToast: Locator;
    toastTitle: Locator;
    toastMessage: Locator;

    constructor(page: Page) {
        this.page = page;
        this.successToast = page.locator('div.toast-success');
        this.warnToast = page.locator('div.toast-warning');
        this.errorToast = page.locator('div.toast-error');

        this.toastTitle = page.locator('div.toast-title');
        this.toastMessage = page.locator('div.toast-message');
    }

    async verifySuccessfulPasswordChangeToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "password_change_success"));
        await this.successToast.click();
    }

    async verifySuccessfulUserCreatedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("admin", "user_created"));
        await this.successToast.click();
    }

    async verifySuccessfulUserDeletedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("admin", "user_deleted"));
        await this.successToast.click();
    }

    async verifySuccessfulUpdatedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "updated"));
        await this.successToast.click();
    }

    async verifySuccessfulProjectUpdatedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "project_updated"));
        await this.successToast.click();
    }

    async verifySuccessfulProjectCreatedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "project_created"));
        await this.successToast.click();
    }

    async verifySuccessfulProjectDeletedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "project_deleted"));
        await this.successToast.click();
    }

    async verifySuccessfulBomUploadedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "bom_uploaded"));
        await this.successToast.click();
    }

    async verifySuccessfulPolicyCreatedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "policy_created"));
        await this.successToast.click();
    }

    async verifySuccessfulPolicyDeletedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "policy_deleted"));
        await this.successToast.click();
    }

    async verifySuccessfulConditionDeletedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "condition_deleted"));
        await this.successToast.click();
    }

    async verifyFailedProjectCreatedToasts() {
        await expect(this.errorToast).toBeVisible();
        await expect(this.errorToast).toContainText(getValue("condition", "http_request_error"));
        await expect(this.errorToast).toContainText(/Conflict \(409\)/i);
        await this.errorToast.click();
        await expect(this.warnToast).toBeVisible();
        await expect(this.warnToast).toContainText(getValue("condition", "unsuccessful_action"));
        await this.warnToast.click();
    }

    async verifyFailedLogInAttemptToast() {
        await expect(this.errorToast).toBeVisible();
        await expect(this.errorToast).toContainText(getValue("condition", "forbidden"));
        await this.errorToast.click();
    }

    async verifyFailedLogInAttemptWrongCredentialsToast() {
        await expect(this.errorToast).toBeVisible();
        await expect(this.errorToast).toContainText(/Unauthorized \(401\)/i);
        await this.errorToast.click();
    }

    async verifySuccessfulVulnerabilityCreatedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "vulnerability_created"));
        await this.successToast.click();
    }

    async verifySuccessfulVulnerabilityDeletedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "vulnerability_deleted"));
        await this.successToast.click();
    }

    async verifySuccessfulComponentCreatedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "component_created"));
        await this.successToast.click();
    }

    async verifySuccessfulComponentDeletedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "component_deleted"));
        await this.successToast.click();
    }

    async verifySuccessfulVexUploadedToast() {
        await expect(this.successToast).toBeVisible();
        await expect(this.successToast).toContainText(getValue("message", "vex_uploaded"));
        await this.successToast.click();
    }
}