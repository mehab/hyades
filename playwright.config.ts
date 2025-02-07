import { defineConfig, devices } from '@playwright/test';
import * as os from "node:os";
import { defineBddConfig } from "playwright-bdd";

/**
 * Read environment variables from file.
 * https://github.com/motdotla/dotenv
 */
// import dotenv from 'dotenv';
// import path from 'path';
// dotenv.config({ path: path.resolve(__dirname, '.env') });

const playwrightTestDir = "./e2e/playwright-tests";
const defOutDir = "./playwright-test-results";
const setupDir = "./e2e/playwright-tests/setup";

const gherkinTestDir = defineBddConfig({
  tags: '@test and not @todo',
  features: playwrightTestDir + '/features/*.test.feature',
  steps: [playwrightTestDir + '/steps/*.steps.ts', playwrightTestDir + '/fixtures/fixtures.ts'],
  outputDir: playwrightTestDir + '/.features-gen/tests',
});

const gherkinSetupDir = defineBddConfig({
  tags: 'not @todo',
  features: playwrightTestDir + '/features/*.setup.feature',
  steps: [playwrightTestDir + '/steps/*.steps.ts', playwrightTestDir + '/fixtures/fixtures.ts'],
  outputDir: playwrightTestDir + '/.features-gen/setup',
});

// https://vitalets.github.io/playwright-bdd/#/blog/whats-new-in-v8?id=improved-configuration-options

/**
 * See https://playwright.dev/docs/test-configuration.
 */
export default defineConfig({
  // Folder for the tests. Defaulting to this if not explicitly mentioned in projects
  testDir: gherkinTestDir,
  // Folder for test artifacts such as screenshots, videos, traces, etc.
  outputDir: defOutDir,
  /* Run tests in files in parallel */
  fullyParallel: false,
  /* If the tests in total exceed a certain timeout */
  globalTimeout: 15 * 60 * 1000, // 15 min
  /* Set the timeout each test has in ms (also one Gherkin-Scenario is treated as one test) */
  timeout: 5 * 60 * 1000, // 3 mins
  /* Set the timeout for each executed expect-line in ms */
  expect: {
    timeout: 5 * 1000, // 15 sec
  },
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry on CI only */
  retries: process.env.CI ? 1 : 0,
  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : 1,
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: process.env.CI ? [["list"], ["github"],
    ["allure-playwright",
      {
        resultsDir: defOutDir + "/allure-results",
        detail: true,
        suiteTitle: true,
        environmentInfo: {
          os_platform: os.platform(),
          os_release: os.release(),
          os_version: os.version(),
          node_version: process.version,
        },
      },
    ],
  ]: [["list"], ["html"],
        ["allure-playwright",
          {
            resultsDir: defOutDir + "/allure-results",
            detail: true,
            suiteTitle: true,
            environmentInfo: {
              os_platform: os.platform(),
              os_release: os.release(),
              os_version: os.version(),
              node_version: process.version,
            },
          },
        ],
      ],

  // globalSetup for: Locale Determination
  globalSetup: require.resolve(setupDir + "/global-setup.ts"),

  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: 'http://localhost:8081',

    // Capture screenshot after each test failure. 'off', 'on' and 'only-on-failure'
    screenshot: 'only-on-failure',

    // Record trace only when retrying a test for the first time. 'off', 'on', 'retain-on-failure' and 'on-first-retry'
    trace: 'on-first-retry',

    // Record video only when retrying a test for the first time. 'off', 'on', 'retain-on-failure' and 'on-first-retry'
    video: {
      mode: "retain-on-failure",
      size: { width: 1600, height: 1080 }
    },

    /* low level timeouts in ms */
    // e.g. locator.click()
    actionTimeout: 5 * 1000, // 5 sec
    // e.g. page.goto()
    navigationTimeout: 5 * 1000, // 5 sec
  },

  /* Configure projects for major browsers */
  projects: [
    {
      name: 'setup_initial',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1600, height: 1080 },
      },
      testDir: playwrightTestDir + '/setup/',
      testMatch: /.*initial-setup.ts/,
      retries: 0,
    },
    // todo at the moment admin_authentication doesnt possible to use sessionStorage with dependencyTrack. FOr some reason it wont work
    {
      name: 'setup_admin_authentication',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1600, height: 1080 },
      },
      testDir: playwrightTestDir + '/setup',
      testMatch: /.*auth-setup.ts/,
      retries: 0,
      dependencies: process.env.CI ? ['setup_initial'] : [],
    },
    {
      name: 'setup_provisioning',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1600, height: 1080 },
        // storageState: playwrightTestDir + '/.auth/admin.json',
      },
      testDir: gherkinSetupDir,
      dependencies: ['setup_admin_authentication'],
    },

    // ONLY THE FOLLOWING PROJECTS CAN BE USED FOR TESTING
    {
      name: 'chromium_test_workflow',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1600, height: 1080 },
        //storageState: playwrightTestDir + '/.auth/admin.json',
      },
      testDir: gherkinTestDir,
      dependencies: ['setup_provisioning'],
    },

    {
      name: 'firefox_test_workflow',
      use: {
        ...devices['Desktop Firefox'],
        viewport: { width: 1600, height: 1080 },
        //storageState: playwrightTestDir + '/.auth/admin.json',
      },
      testDir: gherkinTestDir,
      dependencies: ['setup_provisioning'],
    },

    {
      name: 'webkit_test_workflow',
      use: {
        ...devices['Desktop Safari'],
        viewport: { width: 1600, height: 1080 },
        //storageState: playwrightTestDir + '/.auth/admin.json',
      },
      testDir: gherkinTestDir,
      dependencies: ['setup_provisioning'],
    },

    {
      name: 'chromium_test_only_workflow',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1600, height: 1080 },
        //storageState: playwrightTestDir + '/.auth/admin.json',
      },
      testDir: gherkinTestDir,
    },
/* different permissions for each user -> work with custom fixtures or tags (because test.use doesnt work)
https://vitalets.github.io/playwright-bdd/#/faq?id=can-i-manually-apply-testuse-in-a-generated-file
    {
      name: 'permissions',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1600, height: 1080 },
      },
      dependencies: ['preconditions'],
    },
*/

    /*
    {
      name: 'firefox',
      use: {
        ...devices['Desktop Firefox'],
        viewport: { width: 1600, height: 1080 },
      },
      dependencies: ['preconditions'],
    },

    {
      name: 'webkit',
      use: {
        ...devices['Desktop Safari'],
        viewport: { width: 1600, height: 1080 },
      },
      dependencies: ['preconditions'],
    },
    */

    /* Test against mobile viewports. */
    // {
    //   name: 'Mobile Chrome',
    //   use: { ...devices['Pixel 5'] },
    // },
    // {
    //   name: 'Mobile Safari',
    //   use: { ...devices['iPhone 12'] },
    // },

    /* Test against branded browsers. */
    // {
    //   name: 'Microsoft Edge',
    //   use: { ...devices['Desktop Edge'], channel: 'msedge' },
    // },
    // {
    //   name: 'Google Chrome',
    //   use: { ...devices['Desktop Chrome'], channel: 'chrome' },
    // },
  ],

  /* Run your local dev server before starting the tests */
  // webServer: {
  //   command: 'npm run start',
  //   url: 'http://127.0.0.1:3000',
  //   reuseExistingServer: !process.env.CI,
  // },
});
