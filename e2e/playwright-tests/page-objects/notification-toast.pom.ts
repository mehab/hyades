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
        this.warnToast = page.locator('div.toast-warn');
        this.errorToast = page.locator('div.toast-error');
        this.toastTitle = page.locator('div.toast-title');
        this.toastMessage = page.locator('div.toast-message');

        // success
        // div.toast-success
        // div.toast-message bspw. updated

        // warn
        // div.toast-warn (GUESS)
        // div.toast-title (GUESS)
        // div.toast-message (GUESS)

        // error
        // div.toast-error
        // div.toast-title bspw. http request error
        // div.toast-message bspw. bad request (400)
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
}