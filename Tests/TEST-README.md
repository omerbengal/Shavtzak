# Shavtzak UI Testing with Playwright

This directory contains UI automation tests for the Shavtzak web application using Playwright.

## Prerequisites

1. **Install Playwright**:
   ```bash
   npm run install:playwright
   ```
   Or directly:
   ```bash
   npm install playwright
   ```

2. **Install Playwright browsers** (first time only):
   ```bash
   npx playwright install
   ```

## Running the Tests

### Step 1: Start the Flutter App

Make sure the Flutter web app is running on port 8080:

```bash
cd shavtzak
flutter run -d web-server --web-port=8080
```

The app will be available at http://localhost:8080

### Step 2: Run the UI Test

In a separate terminal, run:

```bash
# Run with visible browser (default)
npm test
# or
node test-ui.js

# Run in headless mode (no browser UI)
npm run test:headless
# or
HEADLESS=true node test-ui.js
```

## Test Script Features

The `test-ui.js` script performs the following automated tests:

1. **App Loading**: Verifies the app loads and displays the user selection screen
2. **Admin Login**: Automatically logs in as the admin user ("a admin")
3. **Navigation**: Navigates to the personal area ("איזור אישי")
4. **Verification**: Confirms successful navigation to the user assignments page
5. **Screenshots**: Takes screenshots for visual confirmation and debugging

## Test Results

- Success screenshots are saved to: `test-results/personal-area.png`
- Failure screenshots are saved to: `test-results/test-failure.png`

## Customization

You can modify the test script in `test-ui.js` to:

- Test different users (change the user selection)
- Add more test scenarios (create events, assignments, etc.)
- Change the port (update the URL in multiple places)
- Adjust timeout values
- Add more assertions and validations

## Troubleshooting

1. **"App is not running" error**:
   - Make sure the Flutter app is running on port 8080
   - Check if another app is using the port

2. **Playwright not found**:
   - Run `npm install playwright` to install dependencies
   - Run `npx playwright install` to install browser binaries

3. **Timeout errors**:
   - Increase the timeout values in the `waitForSelector` calls
   - Check if the app is loading slowly due to network or Firebase issues

4. **Element not found errors**:
   - The UI text might have changed - update the selectors in the script
   - Check the app language (tests expect Hebrew text)

## Extending the Tests

To add more test scenarios:

1. Open `test-ui.js`
2. Add new functions following the existing pattern
3. Use Playwright's [API documentation](https://playwright.dev/docs/api/class-page)
4. Test different user flows like:
   - Creating events
   - Managing team members
   - Creating assignments
   - Testing constraint/availability features