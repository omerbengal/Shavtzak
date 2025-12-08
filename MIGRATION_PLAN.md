# Two-Branch Deployment with Build-Time Environment Detection

## Overview

Migrate from URL-based environment detection to build-time environment detection for a cleaner two-branch deployment system:
- **main branch** → Production deployment (root URL)
- **test-deploy branch** → Test deployment (/test subdirectory)

## Visual Summary

```
Current System:
┌─────────────────┐    ┌──────────────────┐
│   Single App    │    │  GitHub Pages    │
│ (URL-based env) │───▶│  gh-pages branch │
│  /test/* + /*   │    │  Both envs mixed │
└─────────────────┘    └──────────────────┘

Target System:
┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  main branch │───▶│   Production     │    │   Production     │
│  (build-time)│    │   Build          │    │   Deployment     │
│  ENV=prod    │    │  --dart-define   │    │  root URL        │
└──────────────┘    └──────────────────┘    └──────────────────┘
                                                   │
┌─────────────────┐    ┌──────────────────┐      │
│ test-deploy     │───▶│   Test Build     │      │
│ branch          │    │ --dart-define    │      │
│ ENV=test        │    │ ENV=test         │      │
└─────────────────┘    └──────────────────┘      │
                                                   ▼
                                          ┌──────────────────┐
                                          │   GitHub Pages   │
                                          │ gh-pages branch  │
                                          │  / (production)  │
                                          │  /test/ (test)   │
                                          └──────────────────┘
```

## Current State Analysis

### Issues with Current System
- URL-based environment detection (`/test/*` routes) creates duplicate route definitions
- Both test and production deployed together from single branch
- Complex route logic with prefix handling
- Runtime environment switching can be confusing

### Current Architecture
- Environment detection via `html.window.location.hash`
- Duplicate routes: `/admin/*` AND `/test/admin/*`
- EnvironmentSwitcherButton for runtime switching
- Data isolation via `test_` prefixed collections

## Target Architecture

### Environment Detection
**Build-time configuration using `--dart-define=ENVIRONMENT=test|production`**
- Production builds: `--dart-define=ENVIRONMENT=production`
- Test builds: `--dart-define=ENVIRONMENT=test`
- Local development: URL parameter override (`?test=true/false`) + toggle button in debug mode

### Branch Strategy
```
main (protected)           → Production deployment
├── test-deploy           → Test deployment
└── feature-branches      → Development
```

### URL Structure
```
Production: https://omerbengal.github.io/Shavtzak/
├── /whoami
├── /admin
└── /user/*

Test: https://omerbengal.github.io/Shavtzak/test/
├── /whoami
├── /admin
└── /user/*
```

## Implementation Plan

### Phase 0: Preparations

#### 0.1 Create Backup Branch
```bash
# Create a backup of current working system
git checkout main
git pull origin main

# Create backup branch pointing to current commit
git checkout -b backup/url-based-environment-system
git push origin backup/url-based-environment-system

# Add a tag for easy reference (optional but recommended)
git tag -a backup/pre-build-time-env -m "Backup before migrating to build-time environment detection"
git push origin backup/pre-build-time-env

# Return to main for development
git checkout main

# NOTE: If git says "nothing to commit, working tree clean" - that's perfect!
# It means main is already at a clean state and the backup branch will point to that exact commit.
# The backup preserves the current commit hash for easy rollback.
```

#### 0.2 Create Test Deployment Branch
```bash
# Create test-deploy branch from main
git checkout main
git checkout -b test-deploy
git push origin test-deploy
```

#### 0.3 Verify Current Environment
```bash
# Ensure local environment is clean
git status
flutter clean
flutter pub get
flutter run -d chrome  # Verify current system works
```

#### 0.4 Document Current State
- Take screenshots of current app functionality
- Document current URL structure (/test/* routes)
- Note any environment-specific behaviors
- Create checklist of features to verify later

### Phase 1: Update Environment Detection

#### 1.1 Modify EnvironmentService (`shavtzak/lib/core/services/environment_service.dart`)
**Key Changes:**
- Replace URL hash detection with build-time environment constant
- Add URL parameter override for local development
- Keep debug-mode environment switching

```dart
// Read build-time environment
const buildEnvironment = String.fromEnvironment('ENVIRONMENT', defaultValue: 'production');
_isTestMode = buildEnvironment == 'test';

// Local development URL override
if (kDebugMode) {
  final testParam = uri.queryParameters['test'];
  if (testParam == 'true') _isTestMode = true;
  if (testParam == 'false') _isTestMode = false;
}
```

#### 1.2 Update EnvironmentSwitcherButton (`shavtzak/lib/presentation/widgets/environment_switcher_button.dart`)
**Key Changes:**
- Only show in debug mode (`kDebugMode`)
- Maintain current toggle functionality for local development

### Phase 2: Simplify Router Structure

#### 2.1 Update Router (`shavtzak/lib/core/router/app_router.dart`)
**Key Changes:**
- Remove all `/test/*` route definitions
- Keep only production routes: `/whoami`, `/admin/*`, `/user/*`
- Update route helpers to remove `/test` prefix handling

**Routes to keep:**
- `/whoami`
- `/admin` → AdminChoiceScreen
- `/admin/team-members` → TeamListScreen
- `/admin/events` → EventListScreen
- `/admin/assignments` → AssignmentListScreen
- `/user/assignments` → UserAssignmentsScreen
- `/user/constraints` → ConstraintsScreen/AvailabilityScreen

### Phase 3: Update GitHub Actions Workflow

#### 3.1 Modify `.github/workflows/web.yml`
**Key Changes:**
- Add `test-deploy` branch trigger
- Environment-specific build flags
- Dual deployment to root and `/test` subdirectory
- Proper base href handling for subdirectory deployment

```yaml
on:
  push:
    branches:
      - main          # Production deployment
      - test-deploy   # Test environment deployment

# Build with environment flag
- name: Build for Test Environment
  if: github.ref == 'refs/heads/test-deploy'
  working-directory: shavtzak
  run: flutter build web --release --dart-define=ENVIRONMENT=test

- name: Build for Production
  if: github.ref == 'refs/heads/main'
  working-directory: shavtzak
  run: flutter build web --release --dart-define=ENVIRONMENT=production

# Deploy test to subdirectory with base href
- name: Deploy to Test Environment
  if: github.ref == 'refs/heads/test-deploy'
  uses: peaceiris/actions-gh-pages@v4
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./shavtzak/build/web
    destination_dir: test
```

### Phase 4: Documentation Updates

#### 4.1 Update `CLAUDE.md`
**Sections to update:**
- Development commands section
- Environment switching system
- Architecture patterns
- File organization
- Troubleshooting guide

#### 4.2 Update route documentation
- Remove `/test/*` route examples
- Update environment system description
- Add new branch strategy documentation

## Files to Modify

### Core Changes
1. **`shavtzak/lib/core/services/environment_service.dart`**
   - Replace URL detection with build-time constant
   - Add debug mode URL parameter override
   - Keep `collectionPrefix`, `cachePrefix` functionality

2. **`shavtzak/lib/core/router/app_router.dart`**
   - Remove duplicate `/test/*` routes
   - Remove route prefix handling logic
   - Keep all existing route protections

3. **`.github/workflows/web.yml`**
   - Add `test-deploy` branch trigger
   - Add environment-specific build steps
   - Configure dual deployment targets

4. **`shavtzak/lib/presentation/widgets/environment_switcher_button.dart`**
   - Add `kDebugMode` check
   - Keep existing toggle logic

### Documentation
5. **`CLAUDE.md`**
   - Update environment system description
   - Update development commands
   - Update architecture documentation

## Testing Strategy

### Local Testing
```bash
# Test production mode (default)
flutter run -d chrome

# Test with URL override
flutter run -d chrome
# Navigate to http://localhost:xxxxx/?test=true

# Test toggle functionality
flutter run -d chrome
# Use EnvironmentSwitcherButton (debug mode only)
```

### Deployment Testing
1. **Create test-deploy branch**
2. **Push to test-deploy** → Verify deployment to `/test/`
3. **Test environment behavior:**
   - Yellow banner shows automatically
   - Uses `test_` prefixed collections
   - All routes work without `/test` prefix
4. **Deploy production** → Verify deployment to root
5. **Regression test** all functionality in both environments

## Rollout Strategy

### Phase 1: Preparation
1. Create backup of current working system
2. Create `test-deploy` branch from current `main`
3. Ensure local environment is clean

### Phase 2: Implementation
1. Update EnvironmentService with build-time detection
2. Simplify router (remove /test routes)
3. Update GitHub Actions workflow
4. Test locally with both environment settings

### Phase 3: Deployment Migration
1. Push updated code to `test-deploy` branch
2. Verify test deployment works correctly at `/test/`
3. Merge changes to `main` branch
4. Verify production deployment works at root

### Phase 4: Cleanup
1. Update documentation
2. Remove any remaining references to old URL-based system
3. Update team on new workflow

## Safety Considerations

### Data Protection
- Test environment continues using `test_` prefixed collections
- Production collections remain unchanged
- Cache isolation maintained with environment prefixes

### Rollback Plan
- Keep current working system as backup
- Can revert by restoring previous EnvironmentService and router
- GitHub Actions rollback by reverting workflow changes

### Access Control
- Protect `main` branch to require PR approval
- `test-deploy` branch allows direct pushes for testing
- Team training on new branch workflow

## Benefits of New System

1. **Cleaner Architecture**: No duplicate route definitions
2. **True Environment Isolation**: Separate deployments, not just routes
3. **Simpler Development**: Easier to understand and maintain
4. **Safer Deployments**: Test features in isolated environment
5. **Better CI/CD**: Automated testing before production
6. **Team Collaboration**: Share test URL for QA

## Quick Reference - Step-by-Step Execution

### Pre-Implementation
```bash
# 1. Backup current system
git checkout main
git pull origin main
git checkout -b backup/url-based-environment-system
git push origin backup/url-based-environment-system
# Optional: git tag -a backup/pre-build-time-env -m "Backup before migration" && git push origin backup/pre-build-time-env
git checkout main

# 2. Create test-deploy branch
git checkout -b test-deploy
git push origin test-deploy

# 3. Verify current setup
cd shavtzak
flutter clean
flutter pub get
flutter run -d chrome
# Test: /whoami, /test/whoami, environment toggle works
```

### Implementation (Phase 1-3)
1. **Update EnvironmentService** - Replace URL detection with build-time
2. **Update Router** - Remove duplicate /test routes
3. **Update EnvironmentSwitcherButton** - Debug mode only
4. **Update GitHub Actions** - Add test-deploy branch support
5. **Update Documentation** - CLAUDE.md

### Testing & Deployment
```bash
# 1. Test locally both environments
flutter run -d chrome --dart-define=ENVIRONMENT=production
flutter run -d chrome --dart-define=ENVIRONMENT=test

# 2. Deploy test environment
git checkout test-deploy
git add .
git commit -m "Implement build-time environment detection"
git push origin test-deploy
# Verify: https://omerbengal.github.io/Shavtzak/test/

# 3. Deploy production
git checkout main
git merge test-deploy
git push origin main
# Verify: https://omerbengal.github.io/Shavtzak/

# 4. Cleanup (optional)
git branch -d backup/url-based-environment-system  # After everything works
git push origin --delete backup/url-based-environment-system  # Remove remote backup if desired
```

## Next Steps

1. ✅ Review and approve this plan
2. 🔄 Execute Phase 0: Preparations (backup + test-deploy branch)
3. 🔄 Begin Phase 1: Environment Detection implementation
4. 🔄 Test thoroughly at each phase
5. 🔄 Deploy following the step-by-step execution guide

---

**Created**: December 2025
**Purpose**: Migration from URL-based to build-time environment detection
**Status**: Planning phase - ready for implementation