/* eslint-disable */
import { Page, Locator, expect } from '@playwright/test';
import { getValue } from "../utilities/utils";

export class NavigationParPage {
    page: Page;

    navBarToggle: Locator;
    sideBarMinimizer: Locator;
    snapshotPopup: Locator;

    navBarItems: Record<string, Locator>;

    breadCrumb: Locator;

    accountDropDown: Locator;
    accountDropDownUpdatePassword: Locator;
    accountDropDownChangePassword: Locator;
    accountDropDownChangeLanguage: Locator;
    accountDropDownLogout: Locator;

    updateProfilePopup: Locator;
    updateProfilePopupUsernameInput: Locator;
    updateProfilePopupEmailInput: Locator;
    updateProfilePopupCloseButton: Locator;
    updateProfilePopupUpdateButton: Locator;

    constructor(page: Page) {
        this.page = page;

        this.navBarItems = {
            dashboard: page.getByRole('link', { name: getValue("message", "dashboard") }),
            projects: page.getByRole('link', { name: getValue("message", "projects") }),
            components: page.getByRole('link', { name: getValue("message", "components") }),
            vulnerabilities: page.getByRole('link', { name: getValue("message", "vulnerabilities") }),
            licences: page.getByRole('link', { name: getValue("message", "licenses") }),
            tags: page.getByRole('link', { name: getValue("message", "tags") }),
            vulnerabilityAudit: page.getByRole('link', { name: getValue("message", "vulnerability_audit") }),
            policyViolationAudit: page.getByRole('link', { name: getValue("message", "policy_violation_audit") }),
            policyManagement: page.getByRole('link', { name: getValue("message", "policy_management") }),
            administration: page.getByRole('link', { name: getValue("message", "administration") }),
        };

        this.breadCrumb = page.locator('.breadcrumb');

        this.navBarToggle = page.locator('button.d-md-down-none.navbar-toggler');
        this.sideBarMinimizer = page.locator('button.sidebar-minimizer');
        this.snapshotPopup = page.locator('.modal-content');

        // Account Dropdown top right
        this.accountDropDown = page.locator('li.dropdown');
        this.accountDropDownUpdatePassword = this.accountDropDown.getByText(getValue("message", "logout"));
        this.accountDropDownChangePassword = this.accountDropDown.locator('/change-password');
        this.accountDropDownChangeLanguage = this.accountDropDown.locator('#locale-picker-form').locator('.custom-select');
        this.accountDropDownLogout = this.accountDropDown.getByText(getValue("message", "profile_update"));

        // Update Profile Popup
        this.updateProfilePopup = page.locator('.modal-content');
        this.updateProfilePopupUsernameInput = this.updateProfilePopup.locator('#fullname-input-input');
        this.updateProfilePopupEmailInput = this.updateProfilePopup.locator('#email-input-input');
        this.updateProfilePopupCloseButton = this.updateProfilePopup.getByText(getValue("message", "close"));
        this.updateProfilePopupUpdateButton = this.updateProfilePopup.getByText(getValue("message", "update"));
    }

    async logout() {
        await this.clickOnAccountDropDown();
        await this.clickOnAccountDropDownLogout();
    }

    async getNavTabLocator(tabName: string) {
        const tab = this.navBarItems[tabName];
        if (!tab) {
            throw new Error(`Menu '${tabName}' does not exist.`);
        }
        return tab;
    }

    async verifyNavTabIsActive(tabName: string) {
        const tab = this.navBarItems[tabName];
        if (!tab) {
            throw new Error(`Menu '${tabName}' does not exist.`);
        }
        await expect(tab).toHaveClass('router-link-exact-active open active nav-link');
    }

    async clickOnNavTab(tabName: string) {
        const tab = this.navBarItems[tabName];
        if (!tab) {
            throw new Error(`Menu '${tabName}' does not exist.`);
        }
        await tab.first().click();
        await this.page.waitForTimeout(1000);
    }

    async clickOnNavBarToggler() {
        await this.navBarToggle.click();
    }

    async clickOnSideBarMinimizer() {
        await this.sideBarMinimizer.click();
    }

    async closeSnapshotPopupIfVisible() {
        const isVisible = await this.snapshotPopup.isVisible();

        if(isVisible) {
            await this.snapshotPopup.locator('button').click();
            await this.page.waitForTimeout(1000);
        }
    }

    async clickOnAccountDropDown() {
        await this.accountDropDown.click();
    }

    async clickOnAccountDropDownUpdatePassword() {
        await this.accountDropDownUpdatePassword.click();
    }

    async clickOnAccountDropDownChangePassword() {
        await this.accountDropDownChangePassword.click();
    }

    async clickOnAccountDropDownChangeLanguage() {
        await this.accountDropDownChangeLanguage.click();
    }

    async clickOnAccountDropDownLogout() {
        await this.accountDropDownLogout.click();
    }

    async fillUpdateProfilePopupUsernameInput(username: string) {
        await this.updateProfilePopupUsernameInput.fill(username);
    }

    async fillUpdateProfilePopupEmailInput(email: string) {
        await this.updateProfilePopupEmailInput.fill(email);
    }

    async clickUpdateProfilePopupCloseButton() {
        await this.updateProfilePopupCloseButton.click();
    }

    async clickUpdateProfilePopupUpdateButton() {
        await this.updateProfilePopupUpdateButton.click();
    }

    async expectUpdateProfilePopupToBeVisible() {
        await expect(this.updateProfilePopup).toBeVisible();
    }
}