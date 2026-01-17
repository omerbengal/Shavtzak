# Role Management System - Implementation Plan

## Overview

Convert the hardcoded `RoleType` enum to a dynamic role management system stored in Firestore, allowing admins to:
- **Add** new roles with Hebrew names
- **Archive** roles (move to archive list, can be restored later)
- **Rename** roles (change Hebrew display name)
- **Toggle visibility** (active/inactive for event quota configuration)
- **Reorder** roles (drag to change display order)

## Design Decision: Minimal Change Approach

**Rationale**: Keep string keys in existing entities, create a new `Role` entity to manage the list. This:
- Maintains backward compatibility with existing Firestore data
- Minimizes risk of breaking existing functionality
- Avoids complex data migrations

**How it works**:
- New `roles` Firestore collection stores role definitions
- Existing Event/TeamMember/Assignment documents remain unchanged (they already use string keys)
- UI components switch from `RoleType.values` to dynamic role list from Firestore
- `RoleType` enum will be removed after migration is complete

---

## Files to Create

### 1. Domain Layer
- `lib/domain/entities/role.dart` - Role entity (Equatable)

### 2. Data Layer
- `lib/data/models/role_model.dart` - Firestore serialization
- `lib/data/repositories/role_repository.dart` - CRUD + watch methods

### 3. Presentation Layer
- `lib/presentation/bloc/role/role_event.dart` - BLoC events
- `lib/presentation/bloc/role/role_state.dart` - BLoC states
- `lib/presentation/bloc/role/role_bloc.dart` - BLoC implementation
- `lib/presentation/screens/event/widgets/role_management_dialog.dart` - Admin UI

---

## Files to Modify

### Core Infrastructure
| File | Change |
|------|--------|
| `lib/data/data_sources/database_interface.dart` | Add role CRUD method signatures |
| `lib/data/data_sources/firestore_database.dart` | Implement role methods + seed logic |
| `lib/main.dart` | Add RoleRepository + RoleBloc providers |

### UI Components (replace `RoleType.values` with dynamic roles)
| File | Change |
|------|--------|
| `lib/presentation/screens/event/event_list_screen.dart` | Add gear icon to AppBar for role management |
| `lib/presentation/screens/event/widgets/event_form_modal.dart` | Use visible roles from RoleBloc for quota config |
| `lib/presentation/screens/team/team_list_screen.dart` | Use all roles from RoleBloc for capability checkboxes |
| `lib/presentation/screens/assignment/manual_assignment_flow_dialog.dart` | Use RoleBloc for role display names |
| `lib/presentation/screens/summary/widgets/event_summary_tile.dart` | Use RoleBloc for missing roles display |

---

## Role Entity Design

```dart
class Role extends Equatable {
  final String id;           // Same as key (e.g., "eventCommander")
  final String key;          // Database key matching existing usage
  final String hebrewName;   // Display name in Hebrew
  final bool isVisible;      // Controls appearance in event quota form (active/inactive)
  final bool isArchived;     // If true, role is in archive list (effectively inactive)
  final int sortOrder;       // Display order (0 = first)
  final DateTime createdAt;
  final DateTime updatedAt;

  // Equatable props: [id, key, hebrewName, isVisible, isArchived, sortOrder, createdAt, updatedAt]

  // Helper: role is only shown in EventFormModal if visible AND not archived
  bool get isActiveForQuotas => isVisible && !isArchived;
}
```

---

## Firestore Schema

**Collection**: `{prefix}roles` (uses environment prefix for test/prod isolation)

**Document ID**: `{role.key}` (e.g., "eventCommander")

**Fields**:
- `key`: String
- `hebrewName`: String
- `isVisible`: Boolean (active/inactive toggle)
- `isArchived`: Boolean (archived roles are in separate list)
- `sortOrder`: Number
- `createdAt`: Timestamp
- `updatedAt`: Timestamp

---

## Migration Strategy

On first load, seed `roles` collection from `RoleType.values`:
1. Check if `roles` collection is empty
2. If empty, batch-write all 16 current roles with their Hebrew names
3. Set `isVisible: true` and sequential `sortOrder` for all

**No data migration needed** - existing Event/TeamMember/Assignment documents already use string keys that match role.key.

---

## Implementation Phases

### Phase 1: Foundation
1. Create `Role` entity with Equatable
2. Create `RoleModel` with toFirestore/fromFirestore
3. Add role methods to `DatabaseInterface`
4. Implement role methods in `FirestoreDatabase` (including seed)
5. Create `RoleRepository`

### Phase 2: State Management
6. Create `RoleBloc` (events, states, bloc)
7. Add `RoleRepository` and `RoleBloc` to `main.dart` providers
8. Trigger `LoadRoles` on app initialization

### Phase 3: Management Dialog
9. Create `RoleManagementDialog` widget with two views:

   **Main List (Non-archived roles)**:
   - List of all non-archived roles with Hebrew names
   - Visibility toggle (eye icon) - active/inactive
   - Add role button at bottom
   - Swipe-to-archive (moves to archive list)
   - Tap to rename
   - Drag to reorder

   **Archive List (accessed via history icon button)**:
   - List of archived roles
   - No visibility toggle (all archived roles are inactive)
   - Single action: "Restore" button - moves back to main list, sets active

10. Add gear icon to `EventListScreen` AppBar

### Phase 4: Integration
11. Update `EventFormModal` - use `context.watch<RoleBloc>()` for visible roles
12. Update `team_list_screen.dart` - use RoleBloc for capability checkboxes
13. Update `manual_assignment_flow_dialog.dart` - use RoleBloc for role names
14. Update `event_summary_tile.dart` - use RoleBloc for missing roles

### Phase 5: Safety & Edge Cases
15. Implement archive/restore functionality
16. Handle unknown role keys in existing data (fallback to key as display name)
17. Handle empty roles collection (should auto-seed, but show error if fails)

---

## Key Implementation Details

### RoleBloc Events
- `LoadRoles` - Initial load and subscribe to stream
- `CreateRole` - Add new role
- `UpdateRole` - Rename or change visibility
- `ArchiveRole` - Move role to archive list (set isArchived: true)
- `RestoreRole` - Move role from archive back to main list (set isArchived: false, isVisible: true)
- `ReorderRoles` - Update sortOrder for all roles

### RoleBloc States
- `RoleInitial` - Initial state
- `RoleLoading` - Loading from Firestore
- `RolesLoaded` - Contains `List<Role>` with helpers:
  - `activeRoles` getter - non-archived roles for main list
  - `archivedRoles` getter - archived roles for history view
  - `visibleRoles` getter - roles where `isActiveForQuotas` is true (for EventFormModal)
  - `allNonArchivedRoles` getter - for team capability checkboxes
  - `getRoleByKey(String)` - lookup for display (searches all roles including archived)
- `RoleError` - Error message
- `RoleOperationSuccess` - Success message (for snackbar)

### Visibility Behavior
- Toggling `isVisible: false` does NOT affect:
  - Existing assignments
  - Team member capabilities
- It ONLY controls whether the role appears in EventFormModal quota configuration

### Archive System (No Real Deletion)
Roles are never deleted - they are archived instead:

**Archive behavior**:
- `isArchived: true` moves role to archive list
- Archived roles don't appear in EventFormModal quota configuration
- Archived roles still exist for:
  - Displaying existing assignments correctly
  - Team member capability lookups
  - Historical data integrity

**Restore behavior**:
- Sets `isArchived: false` and `isVisible: true`
- Role returns to main list and becomes active

---

## Verification

1. **Seed Test**: Fresh install seeds all 16 roles from enum
2. **Add Role**: Create new role, verify appears in EventFormModal
3. **Rename Role**: Change Hebrew name, verify updates across all UI
4. **Toggle Visibility**: Hide role, verify disappears from EventFormModal but existing assignments unchanged
5. **Archive Role**: Archive a role, verify moves to archive list, disappears from EventFormModal
6. **Restore Role**: Restore archived role, verify returns to main list as active
7. **Archive with Assignments**: Archive a role that has assignments, verify existing assignments still display correctly
8. **Reorder**: Drag to reorder, verify persists after refresh
9. **Real-time**: Change role in Firebase Console, verify UI updates automatically
10. **Environment Isolation**: Verify test and prod have separate role collections
11. **Backward Compatibility**: Verify existing events/assignments display correctly

---

## Critical Paths

- `lib/core/constants/role_types.dart` - Will be removed after migration (used for seeding initial roles)
- `lib/data/data_sources/firestore_database.dart` - Add collection + methods
- `lib/presentation/screens/event/widgets/event_form_modal.dart` - Primary consumer of roles for quotas (lines 1126-1192)
- `lib/presentation/screens/team/team_list_screen.dart` - Role capability checkboxes (lines 1541-1618)
- `lib/presentation/screens/event/event_list_screen.dart` - Add gear icon to AppBar (around line 127)
