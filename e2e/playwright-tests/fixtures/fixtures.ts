/* eslint-disable */
// Note: import base from playwright-bdd, not from @playwright/test!
import { test as base, createBdd } from 'playwright-bdd';
import {
    AdministrationPage,
    ConfigurationSubMenu,
    AnalyzersSubMenu,
    VulnerabilitySourcesSubMenu,
    RepositoriesSubMenu,
    NotificationsSubMenu,
    IntegrationsSubMenu,
    AccessManagementSubMenu
} from "../page-objects/administration.pom";
import {
    LoginPage
} from "../page-objects/login.pom";
import {
    NavigationParPage
} from "../page-objects/navigation-bar.pom";
import {
    NotificationToast
} from "../page-objects/notification-toast.pom";
import {
    DashboardPage
} from "../page-objects/dashboard.pom";
import {
    ProjectAuditVulnerabilitiesPage,
    ProjectComponentsPage, ProjectDependencyGraphPage, ProjectExploitPredictionsPage,
    ProjectPage, ProjectPolicyViolationsPage, ProjectServicesPage, SelectedProjectPage
} from "../page-objects/project.pom";
import {
    LicenceGroupPage,
    PolicyPage
} from "../page-objects/policy-management.pom";
import {
    TagsPage
} from "../page-objects/tags.pom";
import {
    SelectedVulnerabilitiesPage,
    VulnerabilitiesPage
} from "../page-objects/vulnerabilities.pom";
import {ComponentsPage, SelectedComponentsPage} from "../page-objects/components.pom";

// export custom test fixtures
export const test = base.extend<
    {
        administrationPage: AdministrationPage;
        configurationSubMenu: ConfigurationSubMenu;
        analyzersSubMenu: AnalyzersSubMenu;
        vulnerabilitySourcesSubMenu: VulnerabilitySourcesSubMenu;
        repositoriesSubMenu: RepositoriesSubMenu;
        notificationsSubMenu: NotificationsSubMenu;
        integrationsSubMenu: IntegrationsSubMenu;
        accessManagementSubMenu: AccessManagementSubMenu;
        projectPage: ProjectPage;
        selectedProjectPage: SelectedProjectPage;
        projectComponentsPage: ProjectComponentsPage;
        projectServicesPage: ProjectServicesPage;
        projectDependencyGraphPage: ProjectDependencyGraphPage;
        projectAuditVulnerabilitiesPage: ProjectAuditVulnerabilitiesPage;
        projectExploitPredictionsPage: ProjectExploitPredictionsPage;
        projectPolicyViolationsPage: ProjectPolicyViolationsPage;
        loginPage: LoginPage;
        dashboardPage: DashboardPage;
        navBarPage: NavigationParPage;
        notificationToast: NotificationToast;
        policyPage: PolicyPage;
        licenceGroupPage: LicenceGroupPage;
        tagsPage: TagsPage;
        vulnerabilitiesPage: VulnerabilitiesPage;
        selectedVulnerabilitiesPage: SelectedVulnerabilitiesPage;
        componentsPage: ComponentsPage;
        selectedComponentsPage: SelectedComponentsPage;
    }>({
    administrationPage: async ({ page }, use) => {
        await use(new AdministrationPage(page));
    },
    configurationSubMenu: async ({ page }, use) => {
        await use(new ConfigurationSubMenu(page));
    },
    analyzersSubMenu: async ({ page }, use) => {
        await use(new AnalyzersSubMenu(page));
    },
    vulnerabilitySourcesSubMenu: async ({ page }, use) => {
        await use(new VulnerabilitySourcesSubMenu(page));
    },
    repositoriesSubMenu: async ({ page }, use) => {
        await use(new RepositoriesSubMenu(page));
    },
    notificationsSubMenu: async ({ page }, use) => {
        await use(new NotificationsSubMenu(page));
    },
    integrationsSubMenu: async ({ page }, use) => {
        await use(new IntegrationsSubMenu(page));
    },
    accessManagementSubMenu: async ({ page }, use) => {
        await use(new AccessManagementSubMenu(page));
    },
    projectPage: async ({ page }, use) => {
        await use(new ProjectPage(page));
    },
    selectedProjectPage: async ({ page }, use) => {
        await use(new SelectedProjectPage(page));
    },
    projectComponentsPage: async ({ page }, use) => {
        await use(new ProjectComponentsPage(page));
    },
    projectServicesPage: async ({ page }, use) => {
        await use(new ProjectServicesPage(page));
    },
    projectDependencyGraphPage: async ({ page }, use) => {
        await use(new ProjectDependencyGraphPage(page));
    },
    projectAuditVulnerabilitiesPage: async ({ page }, use) => {
        await use(new ProjectAuditVulnerabilitiesPage(page));
    },
    projectExploitPredictionsPage: async ({ page }, use) => {
        await use(new ProjectExploitPredictionsPage(page));
    },
    projectPolicyViolationsPage: async ({ page }, use) => {
        await use(new ProjectPolicyViolationsPage(page));
    },
    loginPage: async ({ page }, use) => {
        await use(new LoginPage(page));
    },
    dashboardPage: async ({ page }, use) => {
        await use(new DashboardPage(page));
    },
    navBarPage: async ({ page }, use) => {
        await use(new NavigationParPage(page));
    },
    notificationToast: async ({ page }, use) => {
        await use(new NotificationToast(page));
    },
    policyPage: async ({ page }, use) => {
        await use(new PolicyPage(page));
    },
    licenceGroupPage: async ({ page }, use) => {
        await use(new LicenceGroupPage(page));
    },
    tagsPage: async ({ page }, use) => {
        await use(new TagsPage(page));
    },
    vulnerabilitiesPage: async ({ page }, use) => {
        await use(new VulnerabilitiesPage(page));
    },
    selectedVulnerabilitiesPage: async ({ page }, use) => {
        await use(new SelectedVulnerabilitiesPage(page));
    },
    componentsPage: async ({ page }, use) => {
        await use(new ComponentsPage(page));
    },
    selectedComponentsPage: async ({ page }, use) => {
        await use(new SelectedComponentsPage(page));
    },
});

// export changes
export const { Given, When, Then } = createBdd(test);
