/* eslint-disable */
import { test as setup } from '@playwright/test';
import { LoginPage, PasswordChangePage } from "../page-objects/login.pom";
import { NotificationToast } from "../page-objects/notification-toast.pom";

setup('Change Initial Password As Admin', async ({ page }) => {
    const loginPage = new LoginPage(page);
    const initialPasswordChangePage = new PasswordChangePage(page);
    const notificationToast = new NotificationToast(page);

    await page.goto('/');
    await loginPage.login("admin", "admin");

    await initialPasswordChangePage.isPasswordChangePageVisible();
    await initialPasswordChangePage.doPasswordChangeFlow("admin", "admin", process.env.RANDOM_PASSWORD);
    await notificationToast.verifySuccessfulPasswordChangeToast();

    await page.waitForTimeout(5000);
});
