# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Shavtzak** (שבצק) is a team management and event scheduling web application built with Flutter Web and Firebase. The app manages team members, events, and role-based assignments for events, primarily in Hebrew (RTL). It replaces a V1 system that used Google Sheets with Apps Script.

**Key Problem Solved**: V1 used positional spreadsheet data which caused sync issues when rows/columns changed. V2 uses explicit foreign key relationships (Assignment → Event, Assignment → TeamMember) to maintain data integrity.

**Platform**: This is a Flutter Web application. While Flutter supports multiple platforms, this project is primarily designed for web deployment.

## Development Commands

### Flutter Web Commands
```bash
# Navigate to Flutter app directory first
cd shavtzak

# Install dependencies
flutter pub get

# Run the web app in development mode
flutter run -d chrome
# or
flutter run -d web-server

# Build for web production
flutter build web

# Serve the built web app locally
# (after flutter build web, serve from build/web/)

# Analyze code (lint)
flutter analyze

# Clean build artifacts
flutter clean

# Update dependencies
flutter pub upgrade
```

### Firebase Configuration
- Firebase is initialized in `lib/main.dart`
- Firebase configuration is in `lib/firebase_options.dart` (auto-generated via FlutterFire CLI)
- To regenerate: `flutterfire configure`

## Architecture

### Clean Architecture Layers

The codebase follows Clean Architecture with clear separation:

1. **Domain Layer** (`lib/domain/`)
   - `entities/`: Pure business objects (TeamMember, Event, Assignment, AdminDevice)
   - No dependencies on other layers or external frameworks
   - Rich domain logic (e.g., `TeamMember.isAvailableOn()`, `Assignment.hasConflicts`)

2. **Data Layer** (`lib/data/`)
   - `data_sources/`: Abstract database interface + Firestore implementation
   - `models/`: Data models that convert between entities and Firestore documents
   - `repositories/`: Repository implementations that use data sources
   - Key: `DatabaseInterface` makes the app backend-agnostic

3. **Presentation Layer** (`lib/presentation/`)
   - `screens/`: UI screens organized by feature (team/, event/, assignment/)
   - `bloc/`: BLoC state management for each feature
   - All text is in Hebrew, all layouts use RTL (`TextDirection.rtl`)

4. **Core** (`lib/core/`)
   - `constants/`: Enums and constants (RoleType, EventStatus, AssignmentStatus)
   - `theme/`: App theme configuration
   - `utils/`: Helper utilities (device_id, date_utils, validators)

### State Management (BLoC Pattern)

Uses `flutter_bloc` with the BLoC (Business Logic Component) pattern:

- **TeamBloc**: Manages team members with real-time Firestore streams via `emit.forEach`
- **EventBloc**: Manages events with real-time updates
- **AssignmentBloc**: Most complex - manages assignments with related Event and TeamMember data

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
- `adminDevices` - Device registration for admin access

**Key Pattern - Relation Population**:
Assignments store only `eventId` and `teamMemberId` (foreign keys), but the repository populates full `Event` and `TeamMember` objects via `_populateAssignmentRelations()` for UI display. This prevents denormalization issues.

**Real-time Updates**:
Firestore implementation provides both async methods (getX) and stream methods (watchX) for real-time updates.

### Role-Based System

**RoleType Enum** (18 roles):
- Medical: medic, paramedic
- Leadership: eventCommander, safetyOfficer, safetyManager, entryCommander
- Operations: internalProduction, entryScreening, investigation, operationsCrew
- Support: social, guidesToInvestigation, orderOrganization, giftDistribution, commandCenter, rabbi

Each role has:
- English enum value for code
- Hebrew display name (`hebrewName` extension)
- Database key for storage

**Team Member Capabilities**: Each TeamMember has `Map<RoleType, bool> roleCapabilities` indicating which roles they can perform.

### Date Constraints System

Team members can have `DateConstraint` objects that mark when they're unavailable:
- Single-day constraints: just `startDate`
- Range constraints: `startDate` + `endDate`
- Used for conflict detection in assignments

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

### Adding a New Entity
1. Create entity in `lib/domain/entities/`
2. Extend `Equatable` for value equality
3. Create model in `lib/data/models/` with `toFirestore()` and `fromFirestore()`
4. Add methods to `DatabaseInterface` and implement in `FirestoreDatabase`
5. Create repository in `lib/data/repositories/`
6. Create BLoC events, states, and bloc in `lib/presentation/bloc/<feature>/`

### Working with Assignments
- Always use `AssignmentRepository` methods that auto-populate relations
- Check for conflicts: `assignment.hasConflicts`, `assignment.conflictWarnings`
- Never manually join data - use the repository's population methods

### Firebase Best Practices
- Use batch operations for multiple writes (`insertTeamMembersBatch`)
- Validate foreign keys before creating assignments (see `_validateAssignmentForeignKeys`)
- Use Timestamps for date storage in Firestore
- Real-time streams auto-cleanup when BLoC is disposed

## Device Registration

The app uses device-based admin authentication:
- On startup, `DeviceIdService` generates/retrieves a unique device ID
- `AuthRepository.registerDevice()` registers device in `adminDevices` collection
- This allows admin access without traditional user accounts

## Important Notes

- **Platform**: This is a Flutter Web application
- **Language**: All UI text is in Hebrew. Keep code comments in English.
- **RTL**: Always wrap screens with RTL directionality
- **Immutability**: Entities use `copyWith()` methods, never mutate directly
- **Null Safety**: Full Dart null-safety enabled
- **Testing**: Test infrastructure exists (`bloc_test`, `mockito`, `fake_cloud_firestore`) but no tests implemented yet

## Features to be implemented:

Feature 1: Fix text from 'סה"כ משרות' to 'סה"כ תפקידים' in team members screen
  ☒ Feature 2: Add 'isPermanent' boolean field to TeamMember entity with copyWith support
  ☒ Feature 2: Update TeamMemberModel to serialize/deserialize 'isPermanent' field to/from Firestore
  ☒ Feature 2: Add toggle switch in team member create/edit UI for permanent status
  ☒ Feature 3: Add validation to event form to make location field required (non-empty)
  ☒ Feature 4: Update assignments screen to display event time (startTime-endTime) next to event date
  ☒ Feature 4: Update assignments screen to display event location in assignment rows
  ☒ Feature 5: Add optional 'note' String field to DateConstraint entity
  ☒ Feature 5: Update date constraint UI to show text field for adding/editing notes
  ☒ Feature 6: Implement logic to identify empty vs assigned role slots when reducing quotas
  ☒ Feature 6: Create popup dialog that lists assigned people and asks user to select which to remove when quota reduction
    requires it
  ☒ Feature 6: Update event edit modal role quota logic to delete empty slots first, then show popup if needed
  ☐ Feature 7: Create helper method to calculate event assignment status (none/partial/complete/no-quotas)
  ☐ Feature 7: Update events screen to apply row background colors based on assignment status (red=none, orange=partial,
    green=complete)
  ☐ Feature 8: Add Dismissible widget to assignment rows in assignments screen for swipe-to-delete
  ☐ Feature 8: Implement delete logic that removes both quota and assignment when swiping assignment row
  ☐ Feature 9: Add GestureDetector/InkWell to event name text in assignment rows to open event edit modal
  ☐ Feature 10: Add GestureDetector/InkWell to role name text in assignment rows to open event edit modal
  ☐ Feature 10: Implement focus/scroll logic to highlight selected role when opening modal via role click
  ☐ Feature 11: Create multi-step manual assignment flow UI (step 1: select event)
  ☐ Feature 11: Add step 2: select team member with constraint validation and warning popup
  ☐ Feature 11: Add step 3: select role from member's capabilities and auto-create quota + assignment
  ☐ Feature 12: Create event duplication BLoC event that copies event with new date/time
  ☐ Feature 12: Implement logic to duplicate all assignments and detect date constraint conflicts
  ☐ Feature 12: Update UI to show duplicated event edit modal with assignments highlighted in bright red if conflicts exist
  ☐ Feature 13: Design user authentication system with unique user codes (entity, model, repository)
  ☐ Feature 13: Create user-specific routing with /user/{code} URL pattern
  ☐ Feature 13: Link TeamMembers to User accounts for personalized views
  ☐ Feature 14: Create user-facing constraint management screen accessible via user URL
  ☐ Feature 14: Remove constraint management from admin team members screen (admin view only)