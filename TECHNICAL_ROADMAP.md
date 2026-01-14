# Shavtzak - Technical Improvement Roadmap

This document outlines technical improvements, missing features, and code quality issues identified in the Shavtzak codebase. It is intended to provide enough context for any developer (human or AI) to understand and implement these improvements.

---

## 🔴 CRITICAL (Technical Debt)

### 1. ✅ FIXED - Stream Subscription Memory Leaks in BLoCs

**What was the problem:**
Multiple BLoCs used `emit.forEach()` to listen to Firestore streams. After certain operations (like updating a team member or creating an assignment), the BLoC restarted the stream listener by calling `emit.forEach()` again. However, the previous subscription may still be active, creating a race condition where two listeners compete to emit state.

**Where it existed:**
- `shavtzak/lib/presentation/bloc/team/team_bloc.dart`
- `shavtzak/lib/presentation/bloc/event/event_bloc.dart`

**Fix applied:**
Added explicit `StreamSubscription` tracking with proper cancellation:
- `TeamBloc`: Added `_teamSubscription` field, cancel before starting new subscription, cancel in `close()`
- `EventBloc`: Added `_eventsSubscription` and `_assignmentsSubscription` fields, proper lifecycle management
- Both BLoCs now use internal events (`_TeamMembersUpdated`, `_EventsDataUpdated`) to emit states from stream updates
- Removed redundant `emit.forEach()` calls that were restarting streams after operations

---

### 2. ✅ FIXED - Calendar Sync in Test Mode

**What was the problem:**
The test mode was mocking calendar operations instead of actually syncing to the calendar. This meant test events were not being created in Google Calendar at all.

**Where it existed:**
- `shavtzak/lib/core/services/google_calendar_service.dart` - `createConstraintEvent`, `updateConstraintEvent`, `deleteConstraintEvent`, `eventExists`

**Fix applied:**
Test mode now creates real calendar events with visual differentiation:
- **Yellow color**: Test events use `CalendarEventColors.testMode = '5'` (Banana/Yellow) instead of red/green
- **Title prefix**: Test event titles start with `"שבצק טסטינג: "` (e.g., `"שבצק טסטינג: יוסי כהן - מגבלה"`)
- Same Google Calendar is used for both test and production
- Test events are easily identifiable by their yellow color and prefix
- The `'keys'` collection is intentionally shared (same calendar credentials for both environments)

---

## 🟡 MISSING FEATURES (High Value)

### 1. ✅ IMPLEMENTED - Event Duplication

**What's needed:**
Ability to duplicate an existing event with a new date/time, optionally copying all assignments. This is explicitly listed in CLAUDE.md under "Features To Be Implemented".

**User story:**
As an admin, I want to duplicate a recurring event (like a weekly shift) to a new date, copying the role requirements and optionally the team member assignments, so I don't have to manually recreate everything.

**Implementation requirements:**
1. Add "Duplicate" button/option on event cards or in event detail modal
2. Show a dialog to select new date/time for the duplicated event
3. Option to copy assignments (checkbox)
4. If copying assignments, detect date constraint conflicts:
   - For each assignment, check if the team member has a constraint on the new date
   - Highlight conflicting assignments in bright red
   - Allow admin to proceed anyway or deselect conflicting members
5. Create new Event with new ID but same role requirements
6. If copying assignments, create new Assignment records pointing to new event

**Files to modify:**
- `shavtzak/lib/presentation/bloc/event/event_bloc.dart` - Add `DuplicateEvent` event
- `shavtzak/lib/presentation/bloc/event/event_event.dart` - Define the event class
- `shavtzak/lib/presentation/screens/event/event_list_screen.dart` - Add duplicate button
- `shavtzak/lib/data/repositories/event_repository.dart` - Add duplication logic
- Create new `DuplicateEventDialog` widget

**Conflict detection logic:**
```dart
for (final assignment in originalAssignments) {
  final member = assignment.teamMember;
  if (member != null && !member.isAvailableOn(newEventDate)) {
    conflictingAssignments.add(assignment);
  }
}
```

---

### 2. Data Export/Reports

**What's needed:**
Ability to export data to PDF or Excel for offline viewing, printing, or sharing with stakeholders who don't have app access.

**Useful reports:**
1. **Event Schedule Report** - All events for a date range with assignments
2. **Team Member Schedule** - Individual member's upcoming assignments
3. **Availability Report** - Grid showing who's available on which dates
4. **Unfilled Positions Report** - Events with role quotas not yet filled
5. **Constraint Requests Report** - Pending/approved/rejected constraints

**Implementation approach:**
- Use `pdf` package for PDF generation
- Use `excel` package (already installed for V1 import) for Excel export
- Add export buttons to relevant screens (event list, team list, assignment list)
- Generate documents client-side and trigger download

**Files to create:**
- `shavtzak/lib/core/services/export_service.dart` - Central export logic
- `shavtzak/lib/presentation/widgets/export_button.dart` - Reusable export UI

**Example PDF structure for Event Schedule:**
```
שבצק - לוח אירועים
תאריך: 01/01/2025 - 31/01/2025

אירוע: שמירה לילית
תאריך: 15/01/2025 18:00-06:00
מיקום: שער ראשי
תפקידים:
  - פראמדיק: יוסי כהן, דני לוי
  - מפקד אירוע: שרה אברהם
```

---

### 3. Undo for Delete Operations

**What's needed:**
When a user deletes a team member, event, or assignment, provide a way to undo the action within a short time window (e.g., 5-10 seconds).

**Current behavior:**
Delete operations are immediate and permanent. If a user accidentally deletes something, they must manually recreate it.

**Implementation approaches:**

**Option A: Snackbar with Undo Action (Recommended)**
- After delete, show snackbar: "האירוע נמחק" with "בטל" button
- Keep deleted item in memory for 5-10 seconds
- If user taps "בטל", re-insert the item
- If snackbar dismisses, deletion is permanent

**Option B: Soft Delete with Recovery**
- Add `deletedAt` timestamp field to entities
- "Delete" sets `deletedAt` instead of removing document
- Filter out deleted items in queries
- Add "Trash" screen to view/restore deleted items
- Background job permanently deletes after 30 days

**Implementation for Option A:**
```dart
// In BLoC after successful delete:
emit(EventDeleted(
  message: 'האירוע נמחק',
  deletedEvent: event, // Keep reference
  canUndo: true,
));

// In UI:
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('האירוע נמחק'),
    action: SnackBarAction(
      label: 'בטל',
      onPressed: () => context.read<EventBloc>().add(RestoreEvent(event)),
    ),
    duration: Duration(seconds: 8),
  ),
);
```

---

### 4. Sorting Options in Lists

**What's needed:**
Allow users to sort lists by different criteria, not just filter them.

**Current state:**
- Team members: No sorting UI (ordered by name from Firestore query)
- Events: No sorting UI (ordered by date)
- Assignments: No sorting UI

**Desired sorting options:**

**Team Members:**
- Name (א-ת / ת-א)
- Number of roles (most capable first)
- Recently added
- Active status

**Events:**
- Date (ascending/descending)
- Name
- Assignment completion status
- Location

**Assignments:**
- Event date
- Team member name
- Role type
- Status

**Implementation:**
1. Add sort dropdown/buttons to list screens
2. Store sort preference in local state or persist with `SharedPreferences`
3. Apply sorting client-side (Firestore already returns data)

**Example UI:**
```dart
Row(
  children: [
    Text('מיון:'),
    DropdownButton<SortOption>(
      value: _currentSort,
      items: [
        DropdownMenuItem(value: SortOption.nameAsc, child: Text('שם א-ת')),
        DropdownMenuItem(value: SortOption.nameDesc, child: Text('שם ת-א')),
        DropdownMenuItem(value: SortOption.dateAsc, child: Text('תאריך ↑')),
      ],
      onChanged: (sort) => setState(() => _currentSort = sort),
    ),
  ],
)
```

---

### 5. ✅ FIXED - Pagination for Scalability

**What's needed:**
Currently, all queries fetch entire collections. This works fine for small teams (10-50 members) but will cause performance issues and increased Firestore costs as data grows.

**Current problematic patterns:**
```dart
// Fetches ALL team members every time
Future<List<TeamMember>> getAllTeamMembers() async {
  final snapshot = await _teamMembersCollection.orderBy('name').get();
  return snapshot.docs.map((doc) => ...).toList();
}
```

**When it becomes a problem:**
- 100+ team members
- 500+ events (accumulating over months/years)
- 1000+ assignments
- Slow initial load times
- High Firestore read costs

**Implementation approach:**
1. Add pagination parameters to repository methods
2. Use Firestore's `limit()` and `startAfter()` for cursor-based pagination
3. Implement infinite scroll or "Load More" button in UI
4. Consider archiving old events (past events older than X months)

**Example paginated query:**
```dart
Future<List<Event>> getEventsPaginated({
  int limit = 20,
  DocumentSnapshot? startAfter,
}) async {
  Query query = _eventsCollection.orderBy('startDate').limit(limit);

  if (startAfter != null) {
    query = query.startAfterDocument(startAfter);
  }

  final snapshot = await query.get();
  return snapshot.docs.map((doc) => EventModel.fromFirestore(doc).toEntity()).toList();
}
```

**UI implementation:**
- Use `ListView.builder` with lazy loading
- Detect when user scrolls near bottom, trigger load of next page
- Show loading indicator while fetching
- Cache loaded pages to avoid re-fetching

---

## 🟠 UX POLISH

### 1. Loading States in Buttons

**What's the problem:**
When a user taps a save/submit button, the button appears normal while the async operation is in progress. Users don't know if their tap registered and may tap multiple times.

**Current behavior:**
```dart
ElevatedButton(
  onPressed: _saveEvent,  // No loading state
  child: Text('שמור'),
)
```

**Desired behavior:**
```dart
ElevatedButton(
  onPressed: _isSaving ? null : _saveEvent,  // Disabled while saving
  child: _isSaving
    ? SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      )
    : Text('שמור'),
)
```

**Files to update:**
- `shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart`
- `shavtzak/lib/presentation/screens/team/widgets/team_member_form_modal.dart`
- `shavtzak/lib/presentation/screens/assignment/manual_assignment_flow_dialog.dart`
- Any other forms with save/submit buttons

**Implementation:**
1. Add `_isLoading` state variable to form widgets
2. Set `true` before async operation, `false` after (in finally block)
3. Disable button and show spinner while loading
4. Handle errors gracefully (show error, re-enable button)

---

### 2. Better Error Messages

**Current state:**
Error messages are often generic like "שגיאה בטעינת נתונים" (Error loading data) without helpful context.

**Problems:**
- Users don't know what went wrong
- No distinction between network errors, permission errors, or data errors
- No recovery suggestions

**Desired error messages:**
```dart
// Instead of:
"שגיאה בטעינת נתונים"

// Use specific messages:
"לא ניתן להתחבר לשרת. בדוק את חיבור האינטרנט ונסה שוב."
"אין הרשאה לבצע פעולה זו. פנה למנהל המערכת."
"חבר הצוות כבר משובץ לאירוע זה."
"האירוע נמחק על ידי משתמש אחר. רענן את הרשימה."
```

**Implementation approach:**
1. Create error type enum or exception hierarchy
2. Map error types to user-friendly Hebrew messages
3. Include recovery action when possible (retry button, refresh, contact admin)

```dart
enum AppErrorType {
  network,
  permission,
  notFound,
  conflict,
  validation,
  unknown,
}

String getErrorMessage(AppErrorType type, {String? details}) {
  switch (type) {
    case AppErrorType.network:
      return 'לא ניתן להתחבר לשרת. בדוק את חיבור האינטרנט ונסה שוב.';
    case AppErrorType.permission:
      return 'אין הרשאה לבצע פעולה זו.';
    // ... etc
  }
}
```

---

### 3. Offline Read-Only Mode

**Current behavior:**
When the app detects no internet connection, it shows a blocking overlay that prevents all interaction. The user cannot view any cached data.

**Where it's implemented:**
- `shavtzak/lib/presentation/widgets/offline_blocking_overlay.dart`
- `shavtzak/lib/core/services/connectivity_service.dart`

**Problems:**
- Users can't view their upcoming assignments while offline
- Frustrating UX when connection is briefly lost
- No access to previously loaded data

**Desired behavior:**
1. When offline, allow read-only access to cached/loaded data
2. Show subtle banner indicating offline status (not blocking overlay)
3. Disable write operations (add, edit, delete buttons greyed out)
4. Queue write operations to sync when back online (advanced, optional)

**Implementation:**
```dart
// Instead of blocking overlay, show non-blocking banner
if (!isOnline) {
  return Column(
    children: [
      MaterialBanner(
        content: Text('אין חיבור לאינטרנט. מציג נתונים שמורים.'),
        backgroundColor: Colors.orange[100],
        actions: [
          TextButton(
            onPressed: _retryConnection,
            child: Text('נסה שוב'),
          ),
        ],
      ),
      Expanded(child: _buildContent()), // Show cached content
    ],
  );
}

// Disable write operations
ElevatedButton(
  onPressed: isOnline ? _saveEvent : null,
  child: Text('שמור'),
)
```
---

## 🔵 CODE QUALITY

### 1. Large BLoC Files

**Current state:**
- `TeamBloc`: 793 lines
- `AssignmentBloc`: 786 lines

These files handle too many responsibilities, making them hard to maintain and test.

**Problems:**
- Difficult to understand all the event handlers
- Changes risk breaking unrelated functionality
- Hard to write focused unit tests
- Long files are intimidating for new developers

**Suggested split:**

**TeamBloc → TeamBloc + ConstraintBloc:**
- `TeamBloc`: Team member CRUD operations only
- `ConstraintBloc`: All constraint-related operations (add, approve, reject, sync)

**AssignmentBloc → AssignmentBloc + SlotBloc:**
- `AssignmentBloc`: Assignment CRUD and filtering
- `SlotBloc`: Slot grid building and management

**Implementation approach:**
1. Create new BLoC files with focused responsibilities
2. Move relevant events, states, and handlers
3. Use `MultiBlocProvider` to provide both BLoCs
4. Have BLoCs communicate via events or shared repository

---

### 2. Request Debouncing

**What's the problem:**
In `AssignmentBloc`, three separate streams all trigger `RebuildAssignmentSlots` when data changes:

```dart
_assignmentSubscription = _repository.watchAssignments().listen(
  (_) => add(const RebuildAssignmentSlots()),
);
_teamMemberSubscription = _teamRepository.watchTeamMembers().listen(
  (_) => add(const RebuildAssignmentSlots()),
);
_eventSubscription = _eventRepository.watchEvents().listen(
  (_) => add(const RebuildAssignmentSlots()),
);
```

**Problem:**
If a batch operation updates all three collections, three `RebuildAssignmentSlots` events fire. Each rebuild:
- Queries all assignments
- Queries all events
- Queries all team members
- Rebuilds the entire slot grid

This is expensive and causes UI flickering.

**Solution - Debounce rebuilds:**
```dart
Timer? _rebuildDebounce;

void _triggerRebuild() {
  _rebuildDebounce?.cancel();
  _rebuildDebounce = Timer(const Duration(milliseconds: 300), () {
    add(const RebuildAssignmentSlots());
  });
}

// In stream listeners:
_assignmentSubscription = _repository.watchAssignments().listen(
  (_) => _triggerRebuild(),  // Debounced
);
```

This ensures only one rebuild happens even if multiple streams update within 300ms.

---

## Summary

This document provides context for implementing improvements to the Shavtzak application. Issues are prioritized by impact:

| Priority | Category | Description |
|----------|----------|-------------|
| 🔴 Critical | Technical Debt | Fix first - affects stability and data integrity |
| 🟡 High Value | Missing Features | Planned functionality with high user value |
| 🟠 Medium | UX Polish | Improves user experience and accessibility |
| 🔵 Low | Code Quality | Improves maintainability long-term |

### Completed Items ✅
- Stream subscription memory leaks in BLoCs
- Calendar sync in test mode
- Event duplication
- Pagination

### Quick Reference - Remaining TODO Items

| Feature/Fix | Primary Files |
|-------------|---------------|
| Data export/reports | New `export_service.dart`, list screens |
| Undo delete | BLoC files, list screens |
| Sorting options | List screens |
| Loading states | Form modal files |
| Error messages | BLoC files, new error utility |
| Offline mode | `offline_blocking_overlay.dart`, `connectivity_service.dart` |
| BLoC splitting | `team_bloc.dart`, `assignment_bloc.dart` |
| Request debouncing | `assignment_bloc.dart` |
