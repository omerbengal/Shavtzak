# Automatic Google Calendar Sync Implementation Plan

> **Branch Created**: `GoogleCalendarConstraintsSync` - Implementation will happen on this branch

## Overview
Implement automatic synchronization of approved constraints to a shared Google Calendar. The system will:
- Auto-sync when constraints are approved (pending → approved)
- Auto-remove when approved constraints are deleted or rejected
- Use a single shared calendar for all team members
- Each constraint appears as a single calendar event

## Architecture

### 1. New Components

#### 1.1 Google Calendar Service
- **File**: `lib/core/services/google_calendar_service.dart`
- Handles all Google Calendar API interactions
- Manages authentication via service account
- Provides CRUD operations for events
- Implements rate limiting and batching

#### 1.2 Calendar Sync Service
- **File**: `lib/core/services/calendar_sync_service.dart`
- Orchestrates sync operations
- Tracks sync state in Firestore
- Manages retry logic and error handling
- Provides sync status updates

#### 1.3 Calendar Sync BLoC
- **Files**:
  - `lib/presentation/bloc/calendar_sync/calendar_sync_bloc.dart`
  - `lib/presentation/bloc/calendar_sync/calendar_sync_event.dart`
  - `lib/presentation/bloc/calendar_sync/calendar_sync_state.dart`
- Manages async sync operations
- Listens for constraint changes
- Provides sync status to UI

#### 1.4 Sync State Collection
- **Collection**: `calendar_sync_{prefix}` (environment-aware)
- Tracks which constraints are synced
- Maps constraint ID → calendar event ID
- Stores sync timestamps and status

### 2. Integration Points

#### 2.1 Modify TeamBloc
- **File**: `lib/presentation/bloc/team/team_bloc.dart`

In `_onUpdateConstraintStatus` method (around line 295):
```dart
// After updating constraint in database
// Check if status changed to/from approved
if (oldStatus != event.newStatus) {
  if (event.newStatus == ConstraintStatus.approved) {
    // Trigger calendar sync
    final calendarSyncBloc = context.read<CalendarSyncBloc>();
    calendarSyncBloc.add(SyncConstraintToCalendar(
      teamMemberId: event.teamMemberId,
      constraintIndex: event.constraintIndex,
    ));
  } else if (oldStatus == ConstraintStatus.approved) {
    // Remove from calendar
    final calendarSyncBloc = context.read<CalendarSyncBloc>();
    calendarSyncBloc.add(RemoveConstraintFromCalendar(
      teamMemberId: event.teamMemberId,
      constraintIndex: event.constraintIndex,
    ));
  }
}
```

In `_onRemoveConstraintRequest` method (around line 377):
```dart
// Check if constraint was approved before removal
if (currentMember.constraints[event.constraintIndex].isApproved()) {
  final constraint = currentMember.constraints[event.constraintIndex];
  final calendarSyncBloc = context.read<CalendarSyncBloc>();
  calendarSyncBloc.add(RemoveConstraintById(
    constraintId: constraint.id,
  ));
}
```

#### 2.2 Update Database Interface
- **File**: `lib/data/data_sources/database_interface.dart`

Add sync state methods:
```dart
// Calendar sync state operations
Future<void> saveCalendarSyncState(String constraintId, String calendarEventId);
Future<String?> getCalendarEventId(String constraintId);
Future<void> removeCalendarSyncState(String constraintId);
```

#### 2.3 Update Firestore Database
- **File**: `lib/data/data_sources/firestore_database.dart`

Implement sync state collection operations:
```dart
// Collection reference
final CollectionReference _calendarSyncCollection =
    _firestore.collection('${_environmentService.collectionPrefix}calendar_sync');

// Methods to manage sync state
@override
Future<void> saveCalendarSyncState(String constraintId, String calendarEventId) async {
  await _calendarSyncCollection.doc(constraintId).set({
    'calendarEventId': calendarEventId,
    'syncedAt': FieldValue.serverTimestamp(),
    'status': 'synced',
  });
}
```

### 3. Implementation Steps

#### Step 1: Setup Google Calendar API
1. Create Google Cloud Project if not exists
2. Enable Calendar API
3. Create Service Account credentials
4. Share calendar with service account email
5. Store credentials securely (Firebase Remote Config)

#### Step 2: Core Services Implementation
1. Implement `GoogleCalendarService` with:
   - Authentication via service account
   - Event creation/deletion methods
   - Batch operations support
   - Error handling and rate limiting

2. Implement `CalendarSyncService` with:
   - Sync state management
   - Retry logic with exponential backoff
   - Event mapping (constraint → calendar event)
   - Conflict resolution

#### Step 3: BLoC Implementation
1. Create `CalendarSyncBloc` states:
   - `CalendarSyncInitial`
   - `CalendarSyncInProgress`
   - `CalendarSyncSuccess`
   - `CalendarSyncFailure`
   - `CalendarSyncNeedsAuth`

2. Create events:
   - `SyncConstraintToCalendar`
   - `RemoveConstraintFromCalendar`
   - `SyncAllApprovedConstraints`
   - `RetryFailedSyncs`

#### Step 4: UI Components
1. Add sync status indicator to admin screens
2. Show sync notifications on success/failure
3. Add manual sync trigger button
4. Display sync errors with retry options

#### Step 5: Testing
1. Mock Google Calendar service for unit tests
2. Test all sync scenarios
3. Test error handling
4. Test rate limiting

### 4. Event Mapping

Each constraint maps to a calendar event with:
- **Title**: `[שם חבר צוות] - חסם זמינות` or `[שם חבר צוות] - זמינות`
- **Start/End**: Constraint dates (all-day events)
- **Description**:
  - Member name and roles
  - Constraint note
  - Constraint type (אי-זמינות/זמינות)
- **Extended Properties**:
  - `constraintId`: For tracking
  - `teamMemberId`: For reference
- **Color**: Different for availability vs unavailability

### 5. Error Handling Strategy

1. **Transient Errors** (network, rate limits):
   - Retry with exponential backoff
   - Max 3 attempts
   - Queue for retry later

2. **Permanent Errors** (auth, permissions):
   - Notify admin immediately
   - Disable further syncs until resolved
   - Log detailed error

3. **Data Conflicts** (event modified externally):
   - Attempt to update instead of recreate
   - Log conflict for admin review
   - Continue with other syncs

### 6. Performance Considerations

1. **Batching**: Group multiple syncs into single API calls
2. **Debouncing**: Delay rapid successive changes
3. **Caching**: Cache calendar event IDs locally
4. **Rate Limiting**: Respect API quotas (10k requests/day)

### 7. Environment Support

- Production: Real Google Calendar
- Test: Mock service that logs operations
- Separate sync state collections
- Configurable calendar ID per environment

### 8. Dependencies to Add

```yaml
dependencies:
  googleapis: ^12.0.0
  googleapis_auth: ^1.4.1
```

### 9. Security

1. Service account credentials in Remote Config
2. Least privilege calendar access
3. Validate all input data
4. Audit trail for all sync operations

### 10. Rollout Plan

1. Phase 1: Implement core services and BLoC
2. Phase 2: Add integration points in TeamBloc
3. Phase 3: UI components and notifications
4. Phase 4: Testing and error handling
5. Phase 5: Production deployment with monitoring

### 11. Monitoring

Track metrics:
- Sync success rate
- Failed syncs count
- API usage
- Last sync timestamp
- Queue size

### 12. Critical Files Summary

**New Files:**
- `lib/core/services/google_calendar_service.dart`
- `lib/core/services/calendar_sync_service.dart`
- `lib/presentation/bloc/calendar_sync/*`
- `lib/core/constants/calendar_constants.dart`

**Modified Files:**
- `lib/presentation/bloc/team/team_bloc.dart`
- `lib/data/data_sources/database_interface.dart`
- `lib/data/data_sources/firestore_database.dart`
- `pubspec.yaml`

This plan provides a robust, automatic sync system that integrates seamlessly with the existing architecture while maintaining reliability and performance.