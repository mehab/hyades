/* eslint-disable */
import { request } from '@playwright/test';
import * as fs from 'fs';
import * as path from "node:path";

// WILL NOT BE TRACKED IN TEST REPORT
async function globalSetup() {
    const locale = 'en'

    if (!process.env.CI) {
        const localAuthJson = fs.readFileSync(__dirname + '/../resources/local-auth.json', 'utf-8');
        const json = JSON.parse(localAuthJson);

        process.env.RANDOM_PASSWORD = json.password;
        // process.env.RANDOM_PASSWORD is set via uuidgen inside workflow
    }
    const filePath = await findMatchingLocaleFileOnGithub(locale, '/../resources/locales/');
    process.env.LOCALE_JSON = fs.readFileSync(filePath, 'utf-8');
}

/**
 * Finds the corresponding locale file from the _i18n_ directory on @link [DependencyTrack Frontend Project](https://github.com/DependencyTrack/frontend/tree/master/src/i18n/locales)
 * @param locale which is being searched in that repository
 * @param localeDir where it should be stored at
 */
async function findMatchingLocaleFileOnGithub(locale: string, localeDir = './locales') {
    let filePath: fs.PathOrFileDescriptor;
    console.info(`Will try to download ${locale} Locale`);

    const context = await request.newContext({
        baseURL: 'https://api.github.com',
        extraHTTPHeaders: {
            'Accept': 'application/vnd.github.v3+json',
        },
    });

    const apiResponse = await context.get("https://api.github.com/repos/DependencyTrack/frontend/contents/src/i18n/locales");

    if (apiResponse.ok()) {
        const data = await apiResponse.json();

        const matchingItem = data.find(item => item.name.startsWith(`${locale}.json`));

        if (matchingItem) {
            const fileUrl = matchingItem.download_url;
            const fileResponse = await context.get(fileUrl);

            if (fileResponse.ok()) {
                const fileContent = await fileResponse.body();

                filePath = path.join(__dirname, localeDir, matchingItem.name);

                fs.mkdirSync(path.dirname(filePath), { recursive: true });

                fs.writeFileSync(filePath, fileContent);

                console.info(`Downloaded: ${matchingItem.name}`);
            } else {
                throw new Error(`Failed to download ${matchingItem.name}: ${fileResponse.status()}`);
            }
        } else {
            throw new Error(`Locale file for ${locale} not found.`);
        }
    } else {
        throw new Error(`Failed to fetch directory contents: ${apiResponse.status()} ${apiResponse.statusText()}`);
    }

    await context.dispose();

    return filePath;
}

export default globalSetup;