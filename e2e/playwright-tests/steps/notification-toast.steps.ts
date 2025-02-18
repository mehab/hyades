/* eslint-disable */
import { Then } from '../fixtures/fixtures';

Then('the user receives project creation error and warn toast', async ({ notificationToast }) => {
    await notificationToast.verifyFailedProjectCreatedToasts();
});

Then('the user receives login error toast', async ({ notificationToast }) => {
    await notificationToast.verifyFailedLogInAttemptToast();
});

Then('the user receives login credentials error toast',async ({ notificationToast }) => {
    await notificationToast.verifyFailedLogInAttemptWrongCredentialsToast();
});