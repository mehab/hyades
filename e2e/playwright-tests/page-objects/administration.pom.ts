/* eslint-disable */
import {Page, Locator, expect} from '@playwright/test';
import { getValue } from "../utilities/utils";

export class AdministrationPage {
    page: Page;
    adminMenuItems: Record<string, Locator>;

    constructor(page: Page) {
        this.page = page;

        const adminElement = page.locator('.card.admin-menu');
        this.adminMenuItems = {
            configuration: adminElement.filter({ hasText: getValue("admin", "configuration")}),
            analyzers: adminElement.filter({ hasText: getValue("admin", "analyzers")}),
            vulnerabilitySources: adminElement.filter({ hasText: getValue("admin", "vuln_sources")}),
            repositories: adminElement.filter({ hasText: getValue("admin", "repositories")}),
            notifications: adminElement.filter({ hasText: getValue("admin", "notifications")}),
            integrations: adminElement.filter({ hasText: getValue("admin", "integrations")}),
            accessManagement: adminElement.filter({ hasText: getValue("admin", "access_management")})
        };
    }

    async getNavTabLocator(menuName: string) {
        const menu = this.adminMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        return menu;
    }

    async verifyMenuTabIsShown(menuName: string) {
        const menu = this.adminMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        await expect(menu.locator('.not-collapsed')).toHaveClass('not-collapsed');
    }

    async clickOnAdminMenu(menuName: string) {
        const menu = this.adminMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        await menu.click();
        await this.page.waitForTimeout(1000);
    }
}

export class ConfigurationSubMenu {
    page: Page;
    configMenuItems: Record<string, Locator>;

    constructor(page: Page) {
        this.page = page;
        
        const configElement = page.locator('#configuration');
        const configElementURN = '/admin/configuration';
        this.configMenuItems = {
            general: configElement.locator(`a[href='${configElementURN}/general']`),
            bomFormats: configElement.locator(`a[href='${configElementURN}/bomFormats']`),
            email: configElement.locator(`a[href='${configElementURN}/email']`),
            welcomeMessage: configElement.locator(`a[href='{configElementURN}/welcomeMessage']`),
            internalComponents: configElement.locator(`a[href='${configElementURN}/internalComponents']`),
            maintenance: configElement.locator(`a[href='${configElementURN}/maintenance']`),
            taskScheduler: configElement.locator(`a[href='${configElementURN}/taskScheduler']`),
            search: configElement.locator(`a[href='${configElementURN}/search']`),
            riskScore: configElement.locator(`a[href='${configElementURN}/RiskScore']`),
            experimental: configElement.locator(`a[href='${configElementURN}/experimental']`),
        };
    }

    async clickOnMenuItem(menuName: string) {
        const menu = this.configMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        await menu.click();
        await this.page.waitForTimeout(1000);
    }
}

export class AnalyzersSubMenu {
    page: Page;
    analyzersMenuItems: Record<string, Locator>;

    constructor(page: Page) {
        this.page = page;
        
        const analyzersElement = page.locator('#analyzers');
        const analyzersElementURN = '/admin/analyzers';
        this.analyzersMenuItems = {
            internal: analyzersElement.locator(`a[href='${analyzersElementURN}/internal']`),
            oss: analyzersElement.locator(`a[href='${analyzersElementURN}/oss']`),
            vulnDB: analyzersElement.locator(`a[href='${analyzersElementURN}/vulnDB']`),
            snyk: analyzersElement.locator(`a[href='${analyzersElementURN}/snyk']`),
            trivy: analyzersElement.locator(`a[href='${analyzersElementURN}/trivy']`),
        };
    }

    async clickOnMenuItem(menuName: string) {
        const menu = this.analyzersMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        await menu.click();
        await this.page.waitForTimeout(1000);
    }
}

export class VulnerabilitySourcesSubMenu {
    page: Page;
    vulnerabilitySourcesMenuItems: Record<string, Locator>;

    constructor(page: Page) {
        this.page = page;
        
        const vulnerabilitySourcesElement = page.locator('#vulnerabilitysources');
        const vulnerabilitySourcesElementURN = '/admin/vulnerabilitySources';
        this.vulnerabilitySourcesMenuItems = {
            nvd: vulnerabilitySourcesElement.locator(`a[href='${vulnerabilitySourcesElementURN}/nvd']`),
            github: vulnerabilitySourcesElement.locator(`a[href='${vulnerabilitySourcesElementURN}/github']`),
            osv: vulnerabilitySourcesElement.locator(`a[href='${vulnerabilitySourcesElementURN}/osv']`),
        };
    }

    async clickOnMenuItem(menuName: string) {
        const menu = this.vulnerabilitySourcesMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        await menu.click();
        await this.page.waitForTimeout(1000);
    }
}

export class RepositoriesSubMenu {
    page: Page;
    repositoriesMenuItems: Record<string, Locator>;

    constructor(page: Page) {
        this.page = page;
        
        const repositoriesElement = page.locator('#repositories');
        const repositoriesElementURN = '/admin/repositories';
        this.repositoriesMenuItems = {
            cargo: repositoriesElement.locator(`a[href='${repositoriesElementURN}/cargo']`),
            composer: repositoriesElement.locator(`a[href='${repositoriesElementURN}/composer']`),
            cpan: repositoriesElement.locator(`a[href='${repositoriesElementURN}/cpan']`),
            gem: repositoriesElement.locator(`a[href='${repositoriesElementURN}/gem']`),
            github: repositoriesElement.locator(`a[href='${repositoriesElementURN}/github']`),
            go: repositoriesElement.locator(`a[href='${repositoriesElementURN}/goModules']`),
            hackage: repositoriesElement.locator(`a[href='${repositoriesElementURN}/hackage']`),
            hex: repositoriesElement.locator(`a[href='${repositoriesElementURN}/hex']`),
            maven: repositoriesElement.locator(`a[href='${repositoriesElementURN}/maven']`),
            nix: repositoriesElement.locator(`a[href='${repositoriesElementURN}/nixpkgs']`),
            npm: repositoriesElement.locator(`a[href='${repositoriesElementURN}/npm']`),
            nuget: repositoriesElement.locator(`a[href='${repositoriesElementURN}/nuget']`),
            python: repositoriesElement.locator(`a[href='${repositoriesElementURN}/python']`),
        };
    }

    async clickOnMenuItem(menuName: string) {
        const menu = this.repositoriesMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        await menu.click();
        await this.page.waitForTimeout(1000);
    }
}

export class NotificationsSubMenu {
    page: Page;
    notificationsMenuItems: Record<string, Locator>;

    constructor(page: Page) {
        this.page = page;
        
        const notificationsElement = page.locator('#notifications');
        const notificationsElementURN = '/admin/notifications';
        this.notificationsMenuItems = {
            alerts: notificationsElement.locator(`a[href='${notificationsElementURN}/alerts']`),
            templates: notificationsElement.locator(`a[href='${notificationsElementURN}/templates']`),
        };
    }

    async clickOnMenuItem(menuName: string) {
        const menu = this.notificationsMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        await menu.click();
        await this.page.waitForTimeout(1000);
    }
}

export class IntegrationsSubMenu {
    page: Page;
    integrationsMenuItems: Record<string, Locator>;

    constructor(page: Page) {
        this.page = page;

        const integrationsElement = page.locator('#integrations');
        const integrationsElementURN = '/admin/integrations';
        this.integrationsMenuItems = {
            defectDojo: integrationsElement.locator(`a[href='${integrationsElementURN}/defectDojo']`),
            fortifySSC: integrationsElement.locator(`a[href='${integrationsElementURN}/fortifySSC']`),
            jira: integrationsElement.locator(`a[href='${integrationsElementURN}/jira']`),
            kennaSecurity: integrationsElement.locator(`a[href='${integrationsElementURN}/kennaSecurity']`),
        };
    }

    async clickOnMenuItem(menuName: string) {
        const menu = this.integrationsMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        await menu.click();
        await this.page.waitForTimeout(1000);
    }
}

export class AccessManagementSubMenu {
    page: Page;
    accessManagementMenu: Locator;
    accessManagementMenuItems: Record<string, Locator>;

    createTeamButton: Locator;
    createUserButton: Locator;
    deleteUserButton: Locator;
    modalContent: Locator;
    searchFieldInput: Locator;
    userPaginationInfo: Locator;

    constructor(page: Page) {
        this.page = page;
        this.modalContent = page.locator('.modal-content');
        this.searchFieldInput = page.locator('.search-input');

        this.accessManagementMenu = page.locator('#accessmanagement');
        const accessManagementElementURN = '/admin/accessManagement';
        this.accessManagementMenuItems = {
            ldapUsers: this.accessManagementMenu.locator(`a[href='${accessManagementElementURN}/ldapUsers']`),
            managedUsers: this.accessManagementMenu.locator(`a[href='${accessManagementElementURN}/managedUsers']`),
            oidcUsers: this.accessManagementMenu.locator(`a[href='${accessManagementElementURN}/oidcUsers']`),
            oidcGroups: this.accessManagementMenu.locator(`a[href='${accessManagementElementURN}/oidcGroups']`),
            teams: this.accessManagementMenu.locator(`a[href='${accessManagementElementURN}/teams']`),
            permissions: this.accessManagementMenu.locator(`a[href='${accessManagementElementURN}/permissions']`),
            portfolioAccessControl: this.accessManagementMenu.locator(`a[href='${accessManagementElementURN}/portfolioAccessControl']`),
        };

        // TEAM
        this.createTeamButton = page.getByRole('button', { name: getValue("admin", "create_team") });

        // USER
        this.createUserButton = page.getByRole('button', { name: getValue("admin", "create_user") });
        this.deleteUserButton = page.getByRole('button', { name: getValue("admin", "delete_user") });
        this.userPaginationInfo = page.locator('.pagination-info');
    }

    async verifySubMenuIsVisible() {
        await expect(this.accessManagementMenu).toHaveClass(/show/);
    }

    async fillSearchFieldInput(search: string) {
        await this.searchFieldInput.clear();
        await this.searchFieldInput.pressSequentially(search);
        await this.page.waitForTimeout(1000);
    }
    async clearSearchFieldInput() {
        await this.searchFieldInput.clear();
        await this.page.waitForTimeout(1000);
    }

    async clickOnMenuItem(menuName: string) {
        const menu = this.accessManagementMenuItems[menuName];
        if (!menu) {
            throw new Error(`Menu '${menuName}' does not exist.`);
        }
        await menu.click();
        await this.page.waitForTimeout(1000);
    }

    async createTeam(teamName: string) {
        await this.createTeamButton.click();

        await this.modalContent.locator('#name-input-input').fill(teamName);

        await this.modalContent.getByRole('button', { name: getValue("message", "create") }).click();
    }

    async createUser(username: string, password: string) {
        await this.createUserButton.click();

        await this.modalContent.locator('#username-input-input').fill(username);
        await this.modalContent.locator('#fullname-input-input').fill(username);
        await this.modalContent.locator('#email-input-input').fill(username);
        await this.modalContent.locator('#password-input-input').fill(password);
        await this.modalContent.locator('#confirmPassword-input-input').fill(password);

        await this.modalContent.getByRole('button', { name: getValue("message", "create") }).click();
    }

    async deleteUser(username: string) {
        await this.clickOnSpecificUser(username);
        await this.deleteUserButton.click();
    }
    
    async clickOnSpecificUser(username: string) {
        await this.page.getByRole('row', { name: username }).click();
        await this.page.waitForTimeout(1000);
    }

    async addPermissionsToSelectedUser(username: string, permissions: string | string[]) {
        const permissionsArray = Array.isArray(permissions) ? permissions : [permissions];

        await this.page.locator('button.btn.pull-right').last().click();

        const modalsearchFieldInput = this.modalContent.locator('.search-input');
        for(const permission of permissionsArray) {
            await modalsearchFieldInput.pressSequentially(permission);
            await this.page.waitForTimeout(2000);

            const tableRow = this.modalContent.locator(`tbody tr`).filter({ hasText: permission }).first();
            await expect(tableRow).toBeVisible();
            await tableRow.getByRole('checkbox').click();
            await modalsearchFieldInput.clear();
        }

        await this.modalContent.getByRole('button', { name: getValue("message", "select") }).click();
    }
}
