# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workflow Conventions (Claude Code — READ FIRST)

**Worktree-per-task.** These rules govern how Claude Code operates in this repo and override any default "work in place" behavior.

1. **Start clean on a worktree.** At the start of every new feature or investigation, create a fresh, isolated git worktree *before* making any changes — use the `EnterWorktree` tool (or `git worktree add` as a fallback). The base should be clean (branch from `origin/main`), and there must be **one worktree per feature/investigation** — never reuse a previous task's worktree.
2. **Announce the worktree.** As soon as it's created, tell the user that a worktree was created and state its **name and full path** (e.g. `.claude/worktrees/<name>`).
3. **Re-state the worktree whenever the user needs to act on it.** Any time the user needs to test something, run the app, or look at files, proactively re-mention which worktree we're on — **name and full path** — because the user works from other terminals and needs to `cd` into it. Don't assume they remember; repeat it each time.

## Project Overview

**Shavtzak** (שבצק) is a team management and event scheduling web application built with Flutter Web and Firebase. The app manages team members, events, and role-based assignments for events, primarily in Hebrew (RTL). It replaces a V1 system that used Google Sheets with Apps Script.

**Key Problem Solved**: V1 used positional spreadsheet data which caused sync issues when rows/columns changed. V2 uses explicit foreign key relationships (Assignment → Event, Assignment → TeamMember) to maintain data integrity.

**Platform**: This is a Flutter Web application. While Flutter supports multiple platforms, this project is primarily designed for web deployment.

## Development Commands

### Flutter Web Commands

**Run every Flutter command from the `shavtzak/` subdirectory, not the repo root** — `cd shavtzak` first. Otherwise the standard commands apply (`flutter pub get`, `flutter analyze`, `flutter test`, `flutter build web`).

### Firebase Configuration
- Firebase is initialized in `lib/main.dart`
- Firebase configuration is in `lib/firebase_options.dart` (auto-generated via FlutterFire CLI)
- To regenerate: `flutterfire configure`

## Architecture

### Clean Architecture Layers

The codebase follows Clean Architecture with clear separation:

1. **Domain Layer** (`lib/domain/`)
   - `entities/`: Pure business objects (TeamMember, Event, Assignment)
   - No dependencies on other layers or external frameworks
   - Rich domain logic (e.g., `TeamMember.isAvailableOn()`, `Assignment.hasConflicts`)

2. **Data Layer** (`lib/data/`)
   - `data_sources/`: Abstract database interface + Firestore implementation
   - `models/`: Data models that convert between entities and Firestore documents
   - `repositories/`: Repository implementations that use data sources
   - Key: `DatabaseInterface` makes the app backend-agnostic

3. **Presentation Layer** (`lib/presentation/`)
   - `screens/`: UI screens organized by feature (admin/, user/, team/, event/, assignment/, whoami/)
   - `bloc/`: BLoC state management for each feature
   - `widgets/`: Reusable UI components
   - All text is in Hebrew, all layouts use RTL (`TextDirection.rtl`)

4. **Core** (`lib/core/`)
   - `constants/`: Enums and constants (RoleType, EventStatus, AssignmentStatus, ConstraintStatus)
   - `router/`: GoRouter configuration with nested routes
   - `services/`: Cross-cutting services (EnvironmentService, UserCacheService)
   - `theme/`: App theme configuration
   - `utils/`: Helper utilities (validators, date_utils, event_assignment_status)

### State Management (BLoC Pattern)

Uses `flutter_bloc` with the BLoC (Business Logic Component) pattern:

- **TeamBloc**: Manages team members with real-time Firestore streams via `emit.forEach`, handles constraint requests
- **EventBloc**: Manages events with real-time updates, handles role quotas
- **AssignmentBloc**: Most complex - manages assignments with related Event and TeamMember data
- **UserSelectionBloc**: Manages user authentication, selection, and session persistence

Each BLoC follows the pattern:
```dart
Event (user action) → BLoC (business logic) → State (UI updates)
```

Real-time updates use `emit.forEach` with Firestore streams for live data synchronization.

### Database Architecture

**Backend-Agnostic Design**: `DatabaseInterface` abstract class defines all database operations. Currently implemented with Firestore (`FirestoreDatabase`), but can be swapped for Supabase, local SQLite, etc.

**Collections**:
- `teamMembers` - Team member records
- `events` - Event records
- `assignments` - Assignment records (junction table with foreign keys)

**Environment-Aware Collections**: In test mode, all collections are prefixed with `test_` (e.g., `test_teamMembers`, `test_events`, `test_assignments`) to completely isolate test data from production.

**Key Pattern - Relation Population**:
Assignments store only `eventId` and `teamMemberId` (foreign keys), but the repository populates full `Event` and `TeamMember` objects via `_populateAssignmentRelations()` for UI display. This prevents denormalization issues.

**Real-time Updates**:
Firestore implementation provides both async methods (getX) and stream methods (watchX) for real-time updates.

### Environment Switching System

The app supports **test** and **production** environments with complete data isolation:

**EnvironmentService** (`lib/core/services/environment_service.dart`):
- Singleton service extending ChangeNotifier
- Detects environment from URL path (`/test/*` routes = test mode)
- Properties:
  - `isTestMode`: Boolean flag
  - `collectionPrefix`: 'test_' or '' (empty string)
  - `cachePrefix`: 'test_' or ''
  - `routePrefix`: '/test' or ''

**Environment-Aware Architecture**:
The app provides two approaches for implementing test-only features:

1. **Simple UI Changes** (Current Approach):
   - Use `EnvironmentService.instance.isTestMode` directly
   - Wrap with `ListenableBuilder` for reactive UI updates
   - Perfect for: visibility changes, different icons, simple conditional logic
   - Example: FAB button showing smiley emoji in test mode

2. **Complex State Management** (Factory Pattern):
   - Use `EnvironmentAwareFactory` and `ServiceLocator` for advanced scenarios
   - Use when you need: different BLoC implementations, alternative repository behaviors, test-specific business logic
   - Infrastructure ready for future complex test-only features
   - Migration approach: start simple, upgrade to factory when complexity demands it

**How it works**:
1. On app initialization, EnvironmentService detects current mode from URL
2. FirestoreDatabase uses `collectionPrefix` for all collection names
3. UserCacheService uses `cachePrefix` for localStorage keys
4. Router uses `routePrefix` for all route paths
5. Users can toggle between environments via EnvironmentSwitcherButton
6. TestEnvironmentIndicator shows visual warning when in test mode

**Route Structure**:
```
Production:              Test:
/whoami                 /test/whoami
/admin                  /test/admin
/admin/team-members     /test/admin/team-members
/admin/events           /test/admin/events
/admin/assignments      /test/admin/assignments
/user/assignments       /test/user/assignments
/user/constraints       /test/user/constraints
```

### User Authentication System

The app uses a **user-based authentication** system via the "מי את/ה?" (Who are you?) screen:

**Key Components**:
- **TeamMember.uniqueKey**: UUID for each team member (stored in DB, not shown in UI)
- **TeamMember.isAdmin**: Boolean flag for admin permissions
- **TeamMember.isPermanent**: Boolean flag distinguishing permanent vs non-permanent members
- **UserSelectionRepository**: Manages user selection, validation, and caching
- **UserCacheService**: Browser localStorage with environment-aware keys
- **UserSelectionBloc**: State management for authentication flow

**Authentication Flow**:
1. App loads → EnvironmentService.initialize() detects test/prod mode
2. UserSelectionBloc checks for cached user in localStorage
3. If cached user found → validate against Firestore → emit UserAuthenticated
4. If no cached user → emit UserSelectionRequired → redirect to /whoami
5. User selects themselves from list → save uniqueKey to cache → redirect based on isAdmin

**Session Persistence**:
- Cached in browser localStorage (works across desktop, mobile browser, PWA)
- Separate cache keys for test vs production (`test_selected_user_key` vs `selected_user_key`)
- Survives page refreshes and browser restarts
- Can sign out to clear cache and return to /whoami

**Access Control**:
- **Admin users** (`isAdmin: true`): Can access both `/admin/*` and `/user/*` routes
- **Non-admin users** (`isAdmin: false`): Restricted to `/user/*` routes only
- **Unauthenticated**: All routes redirect to `/whoami` (or `/test/whoami` in test mode)

### Routing Architecture

Uses **go_router** with **StatefulShellRoute** for nested navigation:

```
Root (GoRouter)
│
├── /whoami (WhoamiScreen) - User selection with search
│
├── /admin (AdminChoiceScreen) - Landing page for admins
│   ├── Choice 1: Personal area (/user/assignments)
│   └── Choice 2: Management interface (SwipeablePageView)
│       ├── /admin/team-members - TeamListScreen
│       ├── /admin/events - EventListScreen
│       └── /admin/assignments - AssignmentListScreen
│
├── /user (UserNavigationShell with bottom navigation)
│   ├── /user/assignments - UserAssignmentsScreen (default)
│   └── /user/constraints - ConstraintsScreen OR AvailabilityScreen
│       (depends on isPermanent field)
│
└── /test/* - Mirror routes for test environment
    └── (same structure as above with /test prefix)
```

**Navigation Patterns**:
- **Admin Management**: SwipeablePageView (horizontal swipe between screens)
- **User Interface**: UserNavigationShell (bottom navigation bar with 2 tabs)
- **Modal Dialogs**: Event creation/editing, assignment creation, quota reduction

**Route Protection**:
- All routes require authentication (redirect to /whoami if not authenticated)
- Admin routes redirect non-admin users to /user/assignments
- Router listens to UserSelectionBloc state changes for dynamic redirects

### Role-Based System

**RoleType**: 18 roles, each with an English enum value, a Hebrew display name (`hebrewName` extension) and a database key — see `lib/core/constants/role_types.dart`.

**Team Member Capabilities**: Each TeamMember has `Map<RoleType, bool> roleCapabilities` indicating which roles they can perform.

### Constraints and Availability System

The app handles team member availability differently based on member type:

**For Permanent Members** (`isPermanent: true`):
- **Default**: Available for all events
- **Constraints**: Can request to mark dates as unavailable (ConstraintType.unavailability)
- **Approval Required**: Constraint requests start with ConstraintStatus.pending
- **Admin Review**: Admin must approve or reject via team members screen
- **UI**: ConstraintsScreen (`/user/constraints`)

**For Non-Permanent Members** (`isPermanent: false`):
- **Default**: Unavailable for all events
- **Availability**: Can mark dates when they ARE available (ConstraintType.availability)
- **Immediate Effect**: Availability has ConstraintStatus.approved automatically
- **No Admin Review**: Takes effect immediately upon creation
- **UI**: AvailabilityScreen (`/user/constraints`)

**DateConstraint Entity**:
```dart
DateConstraint {
  DateTime startDate;           // Required
  DateTime? endDate;            // Optional (null = single day)
  String? note;                 // Optional text note
  ConstraintStatus status;      // pending, approved, rejected
  ConstraintType type;          // unavailability, availability
}
```

**Constraint Logic**:
- Used by `TeamMember.isAvailableOn(DateTime date)` method
- Used by `Assignment.hasConflicts` for conflict detection
- Displayed in assignment creation flow with warning popups
- Admin can see pending requests in team member modal (indicated by yellow exclamation mark)

### Assignment Status System

Events are color-coded based on assignment completion status:

**EventAssignmentStatusHelper** calculates:
- **None** (Light Red): Event has quotas but zero assignments
- **Partial** (Light Orange): Event has some assignments but not all quotas filled
- **Complete** (Light Green): All role quotas are fully assigned
- **No Quotas** (No Color): Event has no role quotas defined

Used in:
- Event list screen row backgrounds
- Event cards and details

### V1 Import Support

The V1 system used Excel/Google Sheets. The codebase includes:
- `excel` package for importing V1 data
- `RoleTypeExtension.fromHebrewName()` to map V1 Hebrew role names
- `V1 excel & google apps script/` directory contains the old system for reference

## Common Development Patterns

### Creating a New Screen
1. Create screen file in `lib/presentation/screens/<feature>/`
2. Use `Directionality(textDirection: TextDirection.rtl)` wrapper for RTL
3. Access BLoC via `context.read<FeatureBloc>()` or `context.watch<FeatureBloc>()`
4. Use Hebrew text throughout
5. Add route to `lib/core/router/app_router.dart`
6. Consider environment awareness (test vs prod routes)

### Adding a New Entity
1. Create entity in `lib/domain/entities/`
2. Extend `Equatable` for value equality
3. Add `copyWith()` method for immutability
4. Create model in `lib/data/models/` with `toFirestore()` and `fromFirestore()`
5. Add methods to `DatabaseInterface` and implement in `FirestoreDatabase`
6. Remember to use `environmentService.collectionPrefix` in Firestore collection names
7. Create repository in `lib/data/repositories/`
8. Create BLoC events, states, and bloc in `lib/presentation/bloc/<feature>/`

### Working with Assignments
- Always use `AssignmentRepository` methods that auto-populate relations
- Check for conflicts: `assignment.hasConflicts`, `assignment.conflictWarnings`
- Never manually join data - use the repository's population methods
- Consider team member availability based on isPermanent and constraints

### Working with Environments
- Always use `EnvironmentService.instance` to get current environment
- Use `environmentService.collectionPrefix` for Firestore collections
- Use `environmentService.cachePrefix` for localStorage keys
- Use `environmentService.routePrefix` for route navigation
- Test environment switching during development
- Be aware that test and production data are completely isolated

### Environment-Aware Development Patterns

**When to use each approach:**

1. **Direct EnvironmentService access** (Simple changes):
   ```dart
   ListenableBuilder(
     listenable: EnvironmentService.instance,
     builder: (context, _) => YourWidget(
       child: EnvironmentService.instance.isTestMode
         ? TestSpecificWidget()
         : ProductionWidget(),
     ),
   )
   ```
   Use for: UI variations, conditional visibility, different icons/text

2. **Factory Pattern** (Complex state management):
   ```dart
   // Instead of: context.read<EventBloc>()
   final bloc = serviceLocator.createEventBloc();
   ```
   Use for: Different business logic, alternative repositories, test-only BLoC features

**Migration Guidelines:**
- Start with direct `EnvironmentService.instance` access for new features
- Upgrade to factory pattern when complexity increases (multiple environment-specific implementations)
- Keep both approaches available - they serve different complexity levels

### CRITICAL: Implementing Real-Time Updates

**This is mandatory for ALL new features.** The app uses Firestore streams for real-time updates. If you don't follow this pattern correctly, the UI will NOT update when data changes in the database.

#### How Real-Time Updates Work

1. **Firestore** emits changes via `snapshots()` streams
2. **Repository** exposes `watchX()` methods that return these streams
3. **BLoC** subscribes to streams and rebuilds state when data changes
4. **Equatable** compares old vs new state to determine if UI should update
5. **UI** rebuilds when state changes

#### The Golden Rule: Equatable Props

**NEVER use just IDs in Equatable props. ALWAYS use the full Equatable object.**

```dart
// ❌ WRONG - UI will NOT update when event properties change
@override
List<Object?> get props => [
  event.id,           // Only compares ID, not content!
  assignment?.id,     // Only compares ID!
];

// ✅ CORRECT - UI WILL update when any property changes
@override
List<Object?> get props => [
  event,              // Full Event object (extends Equatable)
  assignment,         // Full Assignment object (extends Equatable)
];
```

**Why this matters:**
- When an event's location changes, `event.id` stays the same
- Equatable sees "same ID" and considers the state unchanged
- BLoC doesn't emit because it thinks nothing changed
- UI never updates, even though the database changed

#### Checklist for New Features

When creating any new state class or model that will be used in BLoC states:

1. **Extend Equatable** on all entities and state classes
2. **Include ALL relevant fields** in the `props` getter
3. **Use full objects, not IDs** for related entities
4. **Test real-time updates** by manually changing data in Firebase Console

#### Example: Correct State Implementation

```dart
// Entity with proper Equatable
class Event extends Equatable {
  final String id;
  final String name;
  final String location;
  // ... other fields

  @override
  List<Object?> get props => [id, name, location, /* ALL fields */];
}

// State class with proper props
class MyFeatureLoaded extends MyFeatureState {
  final List<Event> events;
  final TeamMember? selectedMember;

  @override
  List<Object?> get props => [
    events,          // Full list of Equatable objects
    selectedMember,  // Full Equatable object, not selectedMember?.id
  ];
}

// Custom model with proper props
class MySlot extends Equatable {
  final Event event;
  final Assignment? assignment;

  @override
  List<Object?> get props => [
    event,       // ✅ Full object
    assignment,  // ✅ Full object (nullable is fine)
  ];
}
```

#### BLoC Stream Subscription Pattern

```dart
// In your BLoC, subscribe to Firestore streams:
_subscription = _repository.watchItems().listen(
  (items) {
    // Emit new state - Equatable will compare with previous
    add(RebuildFromData(items));
  },
);

// The stream will automatically emit when Firestore data changes
// No manual refresh needed if Equatable is set up correctly
```

### Firebase Best Practices
- Use batch operations for multiple writes (`insertTeamMembersBatch`)
- Validate foreign keys before creating assignments (see `_validateAssignmentForeignKeys`)
- Use Timestamps for date storage in Firestore
- Real-time streams auto-cleanup when BLoC is disposed
- Always prefix collection names with `environmentService.collectionPrefix`

### User Authentication Best Practices
- Always check `UserSelectionBloc` state before accessing user-specific data
- Use `context.read<UserSelectionBloc>().state` to get current user
- Validate admin access for admin-only operations
- Handle UserSelectionRequired state by redirecting to /whoami
- Remember cache is environment-aware (test cache ≠ prod cache)

## Important Notes

- **Platform**: This is a Flutter Web application
- **Language**: All UI text is in Hebrew. Keep code comments in English.
- **RTL**: Always wrap screens with RTL directionality
- **Immutability**: Entities use `copyWith()` methods, never mutate directly
- **Null Safety**: Full Dart null-safety enabled
- **Testing**: Real test suite — run it with `cd shavtzak && flutter test` (486 passing as of 2026-07-27). Uses `bloc_test`, `mockito`, `fake_cloud_firestore`. Add tests alongside new features.
- **Environment Isolation**: Test and production are completely separate (data, cache, routes)
- **User-Based Auth**: No traditional Firebase Authentication - uses cached team member uniqueKey

## Features To Be Implemented

### Event Duplication ☐
- Create BLoC event to duplicate event with new date/time
- Copy all assignments
- Detect date constraint conflicts
- Show duplicated event modal with conflict highlighting (bright red)

### Constraint Request UI Enhancement ☐
- Yellow exclamation mark on team member cards with pending requests
- Admin can see, approve, or reject constraint requests in team member modal
- Notification system for pending requests

## Development Workflow

### Starting Development
1. Navigate to Flutter app: `cd shavtzak`
2. Install dependencies: `flutter pub get`

### Testing Changes
When making changes to the code:
1. Run `flutter analyze` to check for compilation errors and warnings
2. **Do not run the app** - I will run the app myself to test the changes
3. If `flutter analyze` passes, the code is ready for testing
4. I will test the changes myself

**How I actually test — do not plan around `/test`.** I run the app locally against
**production** data (`flutter run` from the feature worktree), and once it looks good
I ship straight to production. I rarely use the `/test` environment, even for local
testing. So don't propose "verify it in `/test` first" as the safety net, and don't
treat `/test` coverage as a substitute for real verification.

**Consequence for backend changes:** a local `flutter run` still calls the *deployed*
`api` Cloud Function — `backend_api_service.dart` hardcodes
`us-central1-<project>.cloudfunctions.net` with no localhost override, there is one
shared `api` deployment for both prod and `/test`, and `firebase.json` has no
`emulators` block. So when a change touches `functions/`, **deploy Functions before
asking me to test the client locally**, and design the backend change to be
backward-compatible so deploying it ahead of the UI is safe. Verify backend logic
locally with `cd functions && npm test` — the serializers are pure functions with
injected data and an injected `now`, so unit tests substitute for a staging
environment on this kind of work.

### Deploying
- **Web**: Auto-deploys on merge to `main`. `.github/workflows/web.yml` triggers on every push to `main` (and runs as a check on pull requests, but its `Deploy` step is gated to `github.ref == 'refs/heads/main'`, so a PR build never publishes). It runs `flutter build web --release --base-href /Shavtzak/` from `shavtzak/`, verifies the emitted service worker self-destructs, then pushes `shavtzak/build/web/` to GitHub Pages via `peaceiris/actions-gh-pages@v4`. **Do not tell the user to run `flutter build web` and deploy it manually** — merging to `main` is the deploy.
- **Functions**: Do NOT auto-deploy — there is no CI step for `functions/`. After merging a change under `functions/`, deploy it manually: **`firebase deploy --only functions`**. The codebase builds **three** functions from one source bundle — `api` (https), `calendarJobSweep` (scheduled) and `calendarSyncTask` (taskQueue) — so `--only functions:api` ships just one of them and silently leaves the other two running the previous code. Only narrow it to `--only functions:api` when you have a specific reason to hold the others back. **Verify with `firebase functions:list`**, not with the deploy output: the CLI prints "Skipping the deploy of unchanged functions", which reads like success even when a function was never considered.
- Production and `/test` are both served by the one deployed web build and the one deployed `api` Cloud Function (routing/collection prefixes are decided client-side by `EnvironmentService`), so a single deploy of each updates both environments.

### Debugging
- Use Flutter DevTools for debugging
- Check browser console for errors
- Firestore data visible in Firebase Console
- localStorage visible in browser DevTools (Application tab)
- BLoC state changes logged in debug mode

## Troubleshooting

### Common Issues

**Issue**: Changes not appearing in UI
- **Solution**: Hot reload (r) or hot restart (R) in Flutter CLI, or switch environments to force rebuild

**Issue**: User logged out unexpectedly
- **Solution**: Check localStorage in browser DevTools, may need to clear cache and re-select user

**Issue**: Data not syncing between screens
- **Solution**: BLoCs use real-time streams - check Firestore rules and network connectivity

**Issue**: Test data appearing in production
- **Solution**: Verify EnvironmentService.isTestMode, check collection names in Firestore Console

**Issue**: Route not found
- **Solution**: Check if using correct route prefix (/test/* in test mode), verify route definition in app_router.dart

**Issue**: Constraint not working as expected
- **Solution**: Verify team member isPermanent field, check constraint type (unavailability vs availability)

**Issue**: Screen appears to "rebuild" with a brief white flash after pressing save in a dialog
- **Likely Cause**: A save dialog renders a full-screen `LoadingOverlay` (`Colors.white.withOpacity(...)`) right before closing, which looks like a full app rebuild.
- **Solution**: Do not show a white full-screen overlay on save for short local operations. Prefer closing the dialog immediately after dispatching the action, and rely on real-time stream updates + snackbar feedback.
- **Additional Check**: If a real rebuild is suspected, verify that `UserSelectionBloc` is not emitting `UserAuthenticated` for non-auth-relevant changes (e.g., constraints-only updates), and ensure `/user/*` widgets use scoped `buildWhen` / `BlocSelector` to avoid unrelated rebuilds.
