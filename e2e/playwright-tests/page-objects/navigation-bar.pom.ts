import { Page, Locator, expect } from '@playwright/test';
import { getValue } from "../utilities/utils";

export class NavigationParPage {
    page: Page;
    dashboardTab: Locator;
    projectsTab: Locator;
    componentsTab: Locator;
    vulnerabilitiesTab: Locator;
    licencesTab: Locator;
    tagsTab: Locator;
    vulnerabilityAuditTab: Locator;
    policyManagementTab: Locator;
    administrationTab: Locator;
    navBarToggle: Locator;
    sideBarMinimizer: Locator;
    snapshotPopup: Locator;

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
        this.dashboardTab = page.getByRole('link', { name: getValue("message", "dashboard") }); //locator('a[href="/dashboard"]')
        this.projectsTab = page.getByRole('link', { name: getValue("message", "projects") }); //locator('a[href="/projects"]')
        this.componentsTab = page.getByRole('link', { name: getValue("message", "components") }); //locator('a[href="/components"]')
        this.vulnerabilitiesTab = page.getByRole('link', { name: getValue("message", "vulnerabilities") }); //locator('a[href="/vulnerabilities"]')
        this.licencesTab = page.getByRole('link', { name: getValue("message", "licenses") }); //locator('a[href="/licenses"]')
        this.tagsTab = page.getByRole('link', { name: getValue("message", "tags") }); //locator('a[href="/tags"]')
        this.vulnerabilityAuditTab = page.getByRole('link', { name: getValue("message", "vulnerability_audit") }); //locator('a[href="/vulnerabilityAudit"]')
        this.policyManagementTab = page.getByRole('link', { name: getValue("message", "policy_management") }); //locator('a[href="/policy"]')
        this.administrationTab = page.getByRole('link', { name: getValue("message", "administration") }); // locator('a[href="/admin"]')

        this.navBarToggle = page.locator('button.d-md-down-none.navbar-toggler');
        this.sideBarMinimizer = page.locator('button.sidebar-minimizer');
        this.snapshotPopup = page.locator('.modal-content');

        // Account Dropdown top right
        this.accountDropDown = page.locator('li.dropdown'); //todo if not working a.dropdown-toggle aber dann alle darunter anpassen
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
        await this.clickOnaccountDropDownLogout();
    }

    async clickOnDashboardTab() {
        await this.dashboardTab.click();
    }

    async clickOnProjectsTab() {
        await this.projectsTab.click();
    }

    async clickOnComponentsTab() {
        await this.componentsTab.click();
    }

    async clickOnVulnerabilitiesTab() {
        await this.vulnerabilitiesTab.click();
    }

    async clickOnLicencesTab() {
        await this.licencesTab.click();
    }

    async clickOnTagsTab() {
        await this.tagsTab.click();
    }

    async clickOnVulnerabilityAuditTab() {
        await this.vulnerabilityAuditTab.click();
    }

    async clickOnPolicyManagementTab() {
        await this.policyManagementTab.click();
    }

    async clickOnAdministrationTab() {
        await this.administrationTab.click();
    }

    async clickOnNavBarToggler() {
        await this.navBarToggle.click();
    }

    async clickOnSideBarMinimizer() {
        await this.sideBarMinimizer.click();
    }
    async closeSnapshotPopup() {
        await this.snapshotPopup.locator('button').click();
        await this.page.waitForTimeout(1000);
    }

    async clickOnAccountDropDown() {
        await this.accountDropDown.click();
    }

    async clickOnaccountDropDownUpdatePassword() {
        await this.accountDropDownUpdatePassword.click();
    }

    async clickOnaccountDropDownChangePassword() {
        await this.accountDropDownChangePassword.click();
    }

    async clickOnaccountDropDownChangeLanguage() {
        await this.accountDropDownChangeLanguage.click();
    }

    async clickOnaccountDropDownLogout() {
        await this.accountDropDownLogout.click();
    }

    async fillupdateProfilePopupUsernameInput(username: string) {
        await this.updateProfilePopupUsernameInput.fill(username);
    }

    async fillupdateProfilePopupEmailInput(email: string) {
        await this.updateProfilePopupEmailInput.fill(email);
    }

    async clickupdateProfilePopupCloseButton() {
        await this.updateProfilePopupCloseButton.click();
    }

    async clickupdateProfilePopupUpdateButton() {
        await this.updateProfilePopupUpdateButton.click();
    }

    async expectUpdateProfilePopupToBeVisible() {
        await expect(this.updateProfilePopup).toBeVisible();
    }
}