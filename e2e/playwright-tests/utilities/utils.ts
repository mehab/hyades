/* eslint-disable */
import * as fs from 'fs';
import * as path from 'path';

/**
 * Get the corresponding value from locale.json stored inside process.env.LOCALE_JSON
 * @param parentKey
 * @param childKey
 */
export function getValue(parentKey: string, childKey: string): any {
    const json = JSON.parse(process.env.LOCALE_JSON);

    return findValue(json, parentKey, childKey);
}

function findValue(obj: any, searchParentKey: string, searchChildKey: string): any {
    if (obj === null || typeof obj !== 'object') {
        return null;
    }

    if (obj.hasOwnProperty(searchParentKey)) {
        const parentObj = obj[searchParentKey];
        if (parentObj && typeof parentObj === 'object' && parentObj.hasOwnProperty(searchChildKey)) {
            return parentObj[searchChildKey];
        }
    }

    for (const value of Object.values(obj)) {
        const found = findValue(value, searchParentKey, searchChildKey);
        if (found !== null) {
            return found;
        }
    }

    throw new Error(`Unable to find value in locale.json - ${searchParentKey}:${searchChildKey}`);
}

/**
 * Updates the process.env.LOCALE_JSON variable based on the provided locale.
 * @param locale - The locale string (e.g., 'en', 'de', 'fr').
 */
export function updateLocale(locale: string) {
    const localesPath = path.resolve(__dirname, '/../resources/locales');
    const localeFilePath = path.join(localesPath, `${locale}.json`);

    if (fs.existsSync(localeFilePath)) {
        process.env.LOCALE_JSON = fs.readFileSync(localeFilePath, 'utf-8');
    } else {
        console.warn(`Locale file not found for: ${locale}`);
    }
}
