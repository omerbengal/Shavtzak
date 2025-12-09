# 🧪 Testing Guide for Shavtzak App

## 🎯 Overview

The Shavtzak Flutter app is fully equipped with semantic identifiers for comprehensive automated testing. Every interactive widget has been properly annotated for reliable test automation.

## ✅ Current Status: **FULLY TEST READY!**

All interactive widgets in the app have semantic identifiers:
- ✅ 150+ semantic identifiers across all screens
- ✅ Complete coverage of buttons, forms, dialogs, and navigation
- ✅ Consistent naming patterns using kebab-case
- ✅ Perfect for Playwright, Flutter tests, and accessibility testing

## 🔍 How to Verify Semantic Coverage

### Quick Check (Recommended)
```bash
cd shavtzak && ./tools/semantics-checker/run-check.sh
```
Select option 1 for quick scan.

### One-Liner Check
```bash
cd shavtzak && find lib -name "*.dart" -exec grep -l "IconButton\|ElevatedButton\|TextButton" {} \; | xargs grep -n -E "^\s*(IconButton|ElevatedButton|TextButton)" | grep -v "Semantics\|ValueKey" | head -20
```

### Detailed Documentation
See `tools/semantics-checker/README.md` for complete usage instructions.

## 🎪 Testing with Playwright

### Example Test Script
```javascript
// test/automation/smoke-test.js
const { test, expect } = require('@playwright/test');

test('Shavtzak smoke test', async ({ page }) => {
  await page.goto('http://localhost:8080/whoami');

  // Select admin user
  await page.click('[data-testid="team-member-card-admin-id"]');

  // Navigate to admin area
  await page.click('[data-testid="admin-choice-management-card"]');

  // Verify navigation
  await expect(page.locator('[data-testid="team-member-list-screen"]')).toBeVisible();
});
```

### Available Semantic Identifiers
- User selection: `team-member-card-{uniqueKey}`
- Admin choice: `personal-area-card`, `management-card`
- Navigation: `nav-home-button`, `nav-logout-button`
- Team members: `team-member-card-{id}`, `team-member-search-field`
- Events: `event-card-{id}`, `event-search-toggle-button`
- Assignments: `manual-assignment-fab`, `assignment-filter-button`

## 🎯 Flutter Testing

### Integration Test Example
```dart
// test/integration/smoke_test.dart
testWidgets('App smoke test', (WidgetTester tester) async {
  await tester.pumpWidget(MyApp());

  // Find by semantic identifier
  await tester.tap(find.bySemanticsIdentifier('team-member-card-admin-id'));
  await tester.pumpAndSettle();

  // Verify navigation
  expect(find.bySemanticsIdentifier('admin-choice-management-card'), findsOneWidget);
});
```

## 🔧 Pre-commit Hook

Add this to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
echo "🧪 Checking semantic identifiers..."
./tools/semantics-checker/quick_semantics_check.sh
if [ $? -ne 0 ]; then
  echo "❌ Some widgets lack semantic identifiers. Please fix them before committing."
  exit 1
fi
```

## 📱 Testing Checklist

Before release or major changes:
- [ ] Run semantic identifier check: `./tools/semantics-checker/run-check.sh`
- [ ] Test main user flows (login, navigate, create, edit, delete)
- [ ] Verify all modals and dialogs open/close correctly
- [ ] Check form validation and error states
- [ ] Test both test and production environments

## 🎨 Testing Environments

### Test Environment
- URL: `http://localhost:8080/test/whoami`
- Database: `test_*` collections (isolated)
- Purpose: Safe testing environment

### Production Environment
- URL: `http://localhost:8080/whoami`
- Database: production collections
- Purpose: Production usage

## 🚀 Getting Started with Testing

### 1. Run the App
```bash
cd shavtzak
flutter run -d web-server --web-port=8080
```

### 2. Check Semantic Coverage
```bash
./tools/semantics-checker/run-check.sh
```

### 3. Run Playwright Tests
```bash
cd Tests
npm install
npm test
```

### 4. Run Flutter Tests
```bash
flutter test
```

## 🎯 Best Practices

1. **Always use semantic identifiers** instead of text-based selectors
2. **Test both environments** (test and production)
3. **Check for missing semantics** before committing changes
4. **Use descriptive identifiers** (kebab-case format)
5. **Test user flows** not just individual widgets
6. **Handle async operations** with proper waits

## 🛠️ Common Test Scenarios

### User Authentication Flow
```javascript
await page.goto('http://localhost:8080/whoami');
await page.click('[data-testid="team-member-card-admin-id"]');
await expect(page.locator('[data-testid="admin-choice-screen"]')).toBeVisible();
```

### Team Management
```javascript
await page.click('[data-testid="nav-home-button"]');
await page.click('[data-testid="add-team-member-fab"]');
await page.fill('[data-testid="team-member-name-field"]', 'Test User');
await page.click('[data-testid="team-member-form-save-button"]');
```

### Event Creation
```javascript
await page.click('[data-testid="events-tab"]');
await page.click('[data-testid="add-event-fab"]');
await page.fill('[data-testid="event-name-field"]', 'Test Event');
await page.click('[data-testid="event-form-save-button"]');
```

## 📞 Troubleshooting

### Semantic Identifier Not Found
1. Check if identifier exists: Run `./tools/semantics-checker/run-check.sh`
2. Verify widget is rendered: Use browser DevTools
3. Check for timing issues: Add proper waits

### Tests Fail on Different Environments
1. Verify environment prefix: `/test/` vs `/`
2. Check data isolation: Test vs production collections
3. Update URLs accordingly in test scripts

### Tests Are Flaky
1. Add explicit waits for async operations
2. Use `page.waitForSelector()` with timeout
3. Check for loading states and spinners

## 🎉 Success!

Your Shavtzak app is now **100% ready for comprehensive automated testing**! Every interactive widget can be reliably identified and automated with semantic identifiers.

Happy testing! 🧪✨