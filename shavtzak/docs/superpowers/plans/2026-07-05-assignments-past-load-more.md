# Assignments Past Look‑Back: "Load More" + Faithful History — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On `/admin/assignments`, let admins page back through history older than the 90‑day window ("טען עוד", 25 rows/tap), flip the grid newest→oldest when the past toggle is on, and guarantee every assignment on a visible event appears as a row (off‑quota rows included).

**Architecture:** All logic lives in `AssignmentBloc` + `AssignmentListScreen`. The initial 90‑day window is unchanged; "load more" incrementally fetches older events/assignments into a BLoC‑side cache, merged into the existing stream‑rebuild and capped to a revealed row count. Off‑quota (orphaned) assignments become extra rows built alongside quota slots.

**Tech Stack:** Flutter Web, `flutter_bloc`, Firestore (`cloud_firestore`), `equatable`.

## Global Constraints

- Flutter **Web** app; all UI text **Hebrew**, all screens **RTL**; code comments **English**. (per `CLAUDE.md`)
- **No automated test suite exists and none is to be added.** Per `CLAUDE.md`, the developer runs the app manually. **Per‑task verification = `flutter analyze` from the `shavtzak/` directory reports no new issues.** Do **NOT** run the app. Manual app checks are listed per task for the developer and consolidated in "Manual Verification" at the end.
- All Firestore collection names MUST use the env‑prefixed getters (`_eventsCollection`, `_assignmentsCollection`, …) so test/prod stay isolated.
- **Equatable rule:** every new field on an entity/state MUST be added to `props`; use full objects, never IDs. (per `CLAUDE.md`)
- Work on a branch off `main`: `git checkout -b feat/assignments-past-load-more` before Task 1.
- End every commit message with this trailer line:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Constants introduced: `pastLoadMoreRowChunk = 25` (rows revealed per tap), `pastEventFetchBatch = 15` (events fetched per Firestore round‑trip).
- All file paths below are relative to the repo root; the Flutter app lives under `shavtzak/`.

---

## File Structure

- `shavtzak/lib/data/data_sources/database_interface.dart` — add 2 read signatures.
- `shavtzak/lib/data/data_sources/firestore_database.dart` — implement the 2 reads.
- `shavtzak/lib/data/repositories/event_repository.dart` — pass‑through for `getEventsBeforeDate`.
- `shavtzak/lib/data/repositories/assignment_repository.dart` — pass‑through for `getAssignmentsByEventIds`.
- `shavtzak/lib/presentation/screens/assignment/models/assignment_slot.dart` — add `isOffQuota` + `copyWith`.
- `shavtzak/lib/presentation/bloc/assignment/assignment_event.dart` — add `LoadMorePastAssignmentSlots`.
- `shavtzak/lib/presentation/bloc/assignment/assignment_state.dart` — add `hasMorePast`/`isLoadingMorePast` to `AssignmentSlotsLoaded`.
- `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` — sort flip, off‑quota building, pagination, reveal cap, mutation‑splice.
- `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart` — off‑quota row rendering + "טען עוד" footer button.

---

## Task 1: Data‑layer read methods

**Files:**
- Modify: `shavtzak/lib/data/data_sources/database_interface.dart`
- Modify: `shavtzak/lib/data/data_sources/firestore_database.dart` (near `getEventsByDateRange` ~line 607 and `getAssignmentsInTimeWindow` ~line 855)
- Modify: `shavtzak/lib/data/repositories/event_repository.dart`
- Modify: `shavtzak/lib/data/repositories/assignment_repository.dart`

**Interfaces:**
- Produces:
  - `DatabaseInterface.getEventsBeforeDate(DateTime cursor, {required int limit}) → Future<List<Event>>` — events with `startDate < cursor`, newest‑of‑the‑older first.
  - `DatabaseInterface.getAssignmentsByEventIds(List<String> eventIds) → Future<List<Assignment>>` — populated assignments for the given events.
  - `EventRepository.getEventsBeforeDate(DateTime cursor, {required int limit})`, `AssignmentRepository.getAssignmentsByEventIds(List<String> eventIds)`.

- [ ] **Step 1: Add the two abstract signatures to `DatabaseInterface`.** Place them next to `getEventsByDateRange` / `getAssignmentsInTimeWindow`.

```dart
  /// Get events strictly older than [cursor], newest-first, capped to [limit].
  /// Used for paging back through history beyond the assignments time window.
  Future<List<Event>> getEventsBeforeDate(DateTime cursor, {required int limit});

  /// Get all assignments for the given event ids (batched whereIn, ≤30/chunk).
  Future<List<Assignment>> getAssignmentsByEventIds(List<String> eventIds);
```

- [ ] **Step 2: Implement both in `FirestoreDatabase`.** Add after `getEventsByDateRange` and after `getAssignmentsInTimeWindow` respectively. Mirrors the existing env‑prefix + mapping + populate patterns.

```dart
  @override
  Future<List<Event>> getEventsBeforeDate(DateTime cursor,
      {required int limit}) async {
    try {
      final cursorTimestamp = Timestamp.fromDate(cursor);
      final snapshot = await _firestore
          .collection(_eventsCollection)
          .where('startDate', isLessThan: cursorTimestamp)
          .orderBy('startDate', descending: true)
          .limit(limit)
          .get();

      final events = snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
      // Newest-of-the-older first so the caller can append them below the window.
      events.sort(compareEventsChronologicallyDescending);
      return events;
    } catch (e) {
      throw DatabaseException('Failed to get events before date: $e');
    }
  }

  @override
  Future<List<Assignment>> getAssignmentsByEventIds(
      List<String> eventIds) async {
    try {
      if (eventIds.isEmpty) return [];
      final assignments = <Assignment>[];
      for (int i = 0; i < eventIds.length; i += 30) {
        final chunk = eventIds.skip(i).take(30).toList();
        final snapshot = await _firestore
            .collection(_assignmentsCollection)
            .where('eventId', whereIn: chunk)
            .get();
        assignments.addAll(snapshot.docs
            .map((doc) => AssignmentModel.fromFirestore(doc).toEntity()));
      }
      return await _populateAssignmentRelations(assignments);
    } catch (e) {
      throw DatabaseException('Failed to get assignments by event ids: $e');
    }
  }
```

`compareEventsChronologicallyDescending` already exists in `core/utils/event_sorting.dart` and is imported by this file (used by `getEventsByDateRange`). `EventModel`, `AssignmentModel`, `Timestamp`, `_populateAssignmentRelations` are all already in scope.

- [ ] **Step 3: Add repository pass‑throughs.**

In `event_repository.dart` (next to the other event reads):

```dart
  /// Get events strictly older than [cursor], newest-first, capped to [limit].
  Future<List<Event>> getEventsBeforeDate(DateTime cursor,
          {required int limit}) =>
      _database.getEventsBeforeDate(cursor, limit: limit);
```

In `assignment_repository.dart` (next to the other assignment reads):

```dart
  /// Get all assignments for the given event ids (populated relations).
  Future<List<Assignment>> getAssignmentsByEventIds(List<String> eventIds) {
    return _database.getAssignmentsByEventIds(eventIds);
  }
```

- [ ] **Step 4: Verify it analyzes clean.**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!` (or: no new issues beyond any pre‑existing baseline).

- [ ] **Step 5: Commit.**

```bash
git add shavtzak/lib/data
git commit -m "feat(assignments): add getEventsBeforeDate + getAssignmentsByEventIds reads

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Conditional sort flip (past ON → newest→oldest)

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` — `_compareAssignmentSlots` (~line 740)

**Interfaces:**
- Consumes: `FilterPersistence.showPastEvents` (already imported), `compareEventsChronologically` / `compareEventsChronologicallyDescending` (already imported).
- Produces: no new symbols; changes ordering behavior of every slots rebuild.

- [ ] **Step 1: Make the event‑level comparison direction depend on the past toggle.** Replace the first two lines of `_compareAssignmentSlots`:

Old:
```dart
  int _compareAssignmentSlots(AssignmentSlot a, AssignmentSlot b) {
    final eventCompare = compareEventsChronologically(a.event, b.event);
```

New:
```dart
  int _compareAssignmentSlots(AssignmentSlot a, AssignmentSlot b) {
    // Past ON → newest→oldest so "load older" reads downward (like /db);
    // Past OFF (default/upcoming view) → oldest→newest, unchanged.
    final eventCompare = FilterPersistence.showPastEvents
        ? compareEventsChronologicallyDescending(a.event, b.event)
        : compareEventsChronologically(a.event, b.event);
```

Leave the rest of the method (event‑name, role, slotIndex, member tie‑breaks) unchanged — roles keep their normal order within an event in both modes.

- [ ] **Step 2: Verify analyze clean.**

Run: `cd shavtzak && flutter analyze`
Expected: no new issues.

- [ ] **Step 3: Commit.**

```bash
git add shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart
git commit -m "feat(assignments): flip slot order newest→oldest when past events shown

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Manual check (developer, later): toggle "אירועי עבר" ON → the grid order reverses (future at top, older at bottom); OFF → unchanged.

---

## Task 3: Off‑quota rows — model field + BLoC building

Guarantees every assignment on a built event is represented. An assignment that did not land in a normal quota slot (quota reduced below its `slotIndex`, duplicate `slotIndex`, or permanently‑deleted role) becomes an extra `isOffQuota` slot.

**Files:**
- Modify: `shavtzak/lib/presentation/screens/assignment/models/assignment_slot.dart`
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` — `_compareAssignmentSlots`, `_buildSlotsFromAssignments`, `_onRebuildAssignmentSlotsFromData`, `_mergeSlotsWithOptimisticUpdates`

**Interfaces:**
- Consumes: `Role`, `RoleTypeExtension` (already imported in the bloc), `_cachedRoles`.
- Produces:
  - `AssignmentSlot.isOffQuota` (bool, default `false`) + `AssignmentSlot copyWith({...})`.
  - `AssignmentBloc._resolveRoleForKey(String key) → Role`.
  - `AssignmentBloc._buildOffQuotaSlots(Event event, List<Assignment> eventAssignments, Set<String> placedAssignmentIds) → List<AssignmentSlot>`.

- [ ] **Step 1: Add `isOffQuota` + `copyWith` to `AssignmentSlot`.**

Add the field (after `sameDayEventInfo`):
```dart
  /// True when this row represents an assignment that has no matching quota
  /// slot (quota reduced below its slotIndex, duplicate slotIndex, or a
  /// permanently-deleted role). Rendered as "מחוץ למכסה" and delete-only.
  final bool isOffQuota;
```

Add `this.isOffQuota = false,` to the constructor (after `this.sameDayEventInfo = const {}`).

Add `isOffQuota` to `props` (append to the list).

Add a `copyWith` (so reconstructions preserve every field, incl. `isOffQuota`):
```dart
  AssignmentSlot copyWith({
    Event? event,
    Role? role,
    int? slotIndex,
    Assignment? currentAssignment,
    List<TeamMember>? availableMembers,
    List<TeamMember>? alreadyAssignedMembers,
    bool? hasDoubleAssignment,
    List<String>? otherRoles,
    List<TeamMember>? sameDayAssignedMembers,
    Map<String, List<String>>? sameDayEventInfo,
    bool? isOffQuota,
  }) {
    return AssignmentSlot(
      event: event ?? this.event,
      role: role ?? this.role,
      slotIndex: slotIndex ?? this.slotIndex,
      currentAssignment: currentAssignment ?? this.currentAssignment,
      availableMembers: availableMembers ?? this.availableMembers,
      alreadyAssignedMembers:
          alreadyAssignedMembers ?? this.alreadyAssignedMembers,
      hasDoubleAssignment: hasDoubleAssignment ?? this.hasDoubleAssignment,
      otherRoles: otherRoles ?? this.otherRoles,
      sameDayAssignedMembers:
          sameDayAssignedMembers ?? this.sameDayAssignedMembers,
      sameDayEventInfo: sameDayEventInfo ?? this.sameDayEventInfo,
      isOffQuota: isOffQuota ?? this.isOffQuota,
    );
  }
```

Note: `currentAssignment` in `copyWith` cannot be set back to null via this signature; that is fine — no caller needs to null it here.

- [ ] **Step 2: Add helpers to `AssignmentBloc`** (place near `_compareAssignmentSlots`).

```dart
  /// Resolve a Role for an assignment's roleType key. Uses the roles cache
  /// (which includes archived roles). If the role was PERMANENTLY deleted,
  /// synthesize a display-only Role so the assignment still renders a name.
  Role _resolveRoleForKey(String key) {
    for (final role in _cachedRoles) {
      if (role.key == key) return role;
    }
    String hebrew;
    try {
      hebrew = RoleTypeExtension.fromString(key).hebrewName;
    } catch (_) {
      hebrew = key; // unknown key → show the raw key rather than crash
    }
    final now = DateTime.now();
    return Role(
      id: key,
      key: key,
      hebrewName: hebrew,
      isVisible: false,
      isArchived: true,
      sortOrder: 1 << 20, // sort after all real roles
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Build "off-quota" rows for every [eventAssignments] entry whose id is NOT
  /// in [placedAssignmentIds] (i.e. it never landed in a normal quota slot).
  List<AssignmentSlot> _buildOffQuotaSlots(
    Event event,
    List<Assignment> eventAssignments,
    Set<String> placedAssignmentIds,
  ) {
    final result = <AssignmentSlot>[];
    for (final assignment in eventAssignments) {
      if (placedAssignmentIds.contains(assignment.id)) continue;
      result.add(AssignmentSlot(
        event: event,
        role: _resolveRoleForKey(assignment.roleType),
        slotIndex: assignment.slotIndex,
        currentAssignment: assignment,
        availableMembers: const [],
        alreadyAssignedMembers: const [],
        isOffQuota: true,
      ));
    }
    return result;
  }
```

- [ ] **Step 3: Add the off‑quota tie‑break to `_compareAssignmentSlots`.** Immediately after the `eventNameCompare` block (and before the `roleOrderCompare` line), insert:

```dart
    // Off-quota rows sort AFTER their event's normal rows.
    if (a.isOffQuota != b.isOffQuota) {
      return a.isOffQuota ? 1 : -1;
    }
```

- [ ] **Step 4: Emit off‑quota rows from `_onRebuildAssignmentSlotsFromData`** (the live stream path).

4a. At the very top of the `for (final eventData in filteredEvents)` body, add a per‑event placed‑id set:
```dart
        final placedAssignmentIds = <String>{};
```

4b. Inside the `for (int i = 0; i < requiredCount; i++)` loop, right after the existing `slots.add(AssignmentSlot(...));` that adds the quota slot, record the placed assignment:
```dart
            if (assignment != null) placedAssignmentIds.add(assignment.id);
```

4c. Change the filled‑slot member hydration so an inactive member's name is not lost. Find:
```dart
              .map((a) => a.withRelations(
                    event: eventData,
                    teamMember: teamMembersMap[a.teamMemberId],
                  ))
```
Replace the `teamMember:` line with:
```dart
                    teamMember: teamMembersMap[a.teamMemberId] ?? a.teamMember,
```
(`a.teamMember` is already populated from the full member cache by `_populateAssignmentRelations`; the active map is preferred so live edits still show.)

4d. Immediately after the inner `for (final role in sortedRoles)` loop closes (still inside the `for (final eventData in filteredEvents)` body), append off‑quota rows:
```dart
        final eventAssignmentsAll = rebuildEvent.assignments
            .where((a) => a.eventId == eventData.id)
            .map((a) => a.withRelations(
                  event: eventData,
                  teamMember: teamMembersMap[a.teamMemberId] ?? a.teamMember,
                ))
            .toList();
        slots.addAll(
          _buildOffQuotaSlots(eventData, eventAssignmentsAll, placedAssignmentIds),
        );
```

- [ ] **Step 5: Emit off‑quota rows from `_buildSlotsFromAssignments`** (the post‑edit full path).

5a. At the top of the `for (final event in events)` body add:
```dart
      final placedAssignmentIds = <String>{};
```

5b. Inside the `for (int i = 0; i < requiredCount; i++)` loop, after the existing `slots.add(AssignmentSlot(...));`, record the placed assignment:
```dart
          if (assignment != null) placedAssignmentIds.add(assignment.id);
```

5c. Immediately after the inner `for (final role in sortedRoles)` loop closes (still inside `for (final event in events)`), append off‑quota rows (`assignments` here is already populated by the repository):
```dart
      final eventAssignmentsAll =
          assignments.where((a) => a.eventId == event.id).toList();
      slots.addAll(
        _buildOffQuotaSlots(event, eventAssignmentsAll, placedAssignmentIds),
      );
```

- [ ] **Step 6: Keep off‑quota rows intact through double‑assignment detection.** In BOTH build methods, the block `for (final slot in slots) { if (slot.isFilled) { ... } else { ...add(slot); } }` may reconstruct filled slots. Add a guard as the FIRST statement inside that `for` loop (both methods):
```dart
      if (slot.isOffQuota) {
        slotsWithDoubleAssignmentDetection.add(slot);
        continue;
      }
```

- [ ] **Step 7: Keep off‑quota rows intact through the optimistic merge.** In `_mergeSlotsWithOptimisticUpdates`, add three guards so off‑quota rows pass through untouched:

7a. In the availability‑recompute loop `for (final slot in eventSlots) { ... }` (the one that rebuilds member lists and reassigns `eventSlots[slotIndex] = AssignmentSlot(...)`), add as the first statement:
```dart
        if (slot.isOffQuota) continue;
```

7b. In the double‑assignment re‑detection loop near the end `for (final slot in eventResultSlots) { if (slot.isFilled) { ... } }`, add as the first statement inside the `for`:
```dart
        if (slot.isOffQuota) continue;
```

7c. In the final `final resultSlots = databaseSlots.map((dbSlot) { ... }).toList();`, add as the first statement inside the map callback:
```dart
      if (dbSlot.isOffQuota) return dbSlot;
```

- [ ] **Step 8: Verify analyze clean.**

Run: `cd shavtzak && flutter analyze`
Expected: no new issues.

- [ ] **Step 9: Commit.**

```bash
git add shavtzak/lib/presentation/screens/assignment/models/assignment_slot.dart shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart
git commit -m "feat(assignments): build off-quota rows for orphaned assignments

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Off‑quota rows — screen rendering + delete

**Files:**
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart` — `_applyAssignmentLabelsToSlots`, `_buildSlotRow`

**Interfaces:**
- Consumes: `AssignmentSlot.isOffQuota`, `AssignmentSlot.copyWith`, `AssignmentRepository.deleteAssignment`.
- Produces: no new symbols; off‑quota rows render distinctly and are delete‑only.

- [ ] **Step 1: Preserve `isOffQuota` through the label pass.** In `_applyAssignmentLabelsToSlots`, replace the whole `return AssignmentSlot( ... );` reconstruction with a `copyWith` so no field is dropped:

Old:
```dart
      return AssignmentSlot(
        event: slot.event,
        role: slot.role,
        slotIndex: slot.slotIndex,
        currentAssignment: updatedAssignment,
        availableMembers: slot.availableMembers,
        alreadyAssignedMembers: slot.alreadyAssignedMembers,
        hasDoubleAssignment: slot.hasDoubleAssignment,
        otherRoles: slot.otherRoles,
        sameDayAssignedMembers: slot.sameDayAssignedMembers,
        sameDayEventInfo: slot.sameDayEventInfo,
      );
```
New:
```dart
      return slot.copyWith(currentAssignment: updatedAssignment);
```

- [ ] **Step 2: Render off‑quota rows distinctly and disable editing.** In `_buildSlotRow`, at the very top of the method add:
```dart
    if (slot.isOffQuota) {
      return _buildOffQuotaRow(slot);
    }
```

Then add this new method next to `_buildSlotRow`:
```dart
  /// A row for an assignment that has no matching quota slot. Display + delete
  /// only: no dropdown, no notes-edit swipe. Swipe-left deletes just the
  /// assignment document (no quota change — it is already outside the quota).
  Widget _buildOffQuotaRow(AssignmentSlot slot) {
    final assignment = slot.currentAssignment!;
    final memberName = assignment.teamMember?.name ?? 'לא ידוע';

    return Dismissible(
      key: Key('offquota_${assignment.id}'),
      direction: DismissDirection.endToStart,
      secondaryBackground: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      background: const SizedBox.shrink(),
      dismissThresholds: const {DismissDirection.endToStart: 0.5},
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('מחיקת שיבוץ מחוץ למכסה'),
              content: const Text(
                'שיבוץ זה נמצא מחוץ למכסת האירוע. האם למחוק אותו?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('ביטול'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('מחק', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        );
        if (confirmed == true) {
          Logger.action('delete:offQuotaAssignment', {
            'assignmentId': assignment.id,
          });
          try {
            await context
                .read<AssignmentRepository>()
                .deleteAssignment(assignment.id);
            if (mounted) {
              _showAssignmentSnackBar('השיבוץ נמחק בהצלחה',
                  backgroundColor: Colors.green);
            }
          } catch (e) {
            if (mounted) {
              _showAssignmentSnackBar('שגיאה במחיקת השיבוץ: $e',
                  backgroundColor: Colors.red);
            }
          }
        }
        return false; // real-time stream removes the row after delete
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade400, width: 1.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(slot.event.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(_formatEventDatesHebrew(slot.event),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(slot.role.hebrewName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(memberName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('מחוץ למכסה',
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
```

`_formatEventDatesHebrew`, `_showAssignmentSnackBar`, `Logger`, and `AssignmentRepository` are already used elsewhere in this file.

- [ ] **Step 3: Verify analyze clean.**

Run: `cd shavtzak && flutter analyze`
Expected: no new issues.

- [ ] **Step 4: Commit.**

```bash
git add shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart
git commit -m "feat(assignments): render off-quota rows with marker + delete

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Manual check (developer, later): reduce a role quota on an event that has an assignment in the removed slot → an amber "מחוץ למכסה" row appears; swipe‑left deletes only that assignment.

---

## Task 5: Load‑more pagination — BLoC

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_event.dart`
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_state.dart`
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart`

**Interfaces:**
- Consumes: `EventRepository.getEventsBeforeDate`, `AssignmentRepository.getAssignmentsByEventIds` (Task 1); `_slotsWindowStart`, `_windowEventsMap`, `_windowMembersMap` (new fields, below).
- Produces:
  - `LoadMorePastAssignmentSlots` event.
  - `AssignmentSlotsLoaded.hasMorePast` / `.isLoadingMorePast` (+ updated `copyWith`).
  - `AssignmentBloc._onLoadMorePastAssignmentSlots`, `_countDisplayRows`, `_applyPastRevealCap`.

- [ ] **Step 1: Add the event.** In `assignment_event.dart`:
```dart
/// Reveal the next page (25 rows) of history older than the 90-day window.
class LoadMorePastAssignmentSlots extends AssignmentEvent {
  const LoadMorePastAssignmentSlots();
}
```

- [ ] **Step 2: Add the two state fields + update `copyWith` and `props`.** Replace the `AssignmentSlotsLoaded` class body constructor/props/copyWith with:

```dart
class AssignmentSlotsLoaded extends AssignmentState {
  final List<AssignmentSlot> slots;
  final int totalSlots;
  final int filledSlots;
  final int unfilledSlots;
  final Set<String> selectedEventIds;
  final Map<String, PendingOperation> pendingOperations;

  /// True when older history remains to be loaded via "load more".
  final bool hasMorePast;

  /// True while a "load more" fetch is in flight.
  final bool isLoadingMorePast;

  AssignmentSlotsLoaded(
    this.slots, {
    this.selectedEventIds = const {},
    this.pendingOperations = const {},
    this.hasMorePast = false,
    this.isLoadingMorePast = false,
  })  : totalSlots = slots.length,
        filledSlots = slots.where((s) => s.isFilled).length,
        unfilledSlots = slots.where((s) => !s.isFilled).length;

  @override
  List<Object?> get props => [
        slots,
        totalSlots,
        filledSlots,
        unfilledSlots,
        selectedEventIds,
        pendingOperations,
        hasMorePast,
        isLoadingMorePast,
      ];

  AssignmentSlotsLoaded copyWith({
    Set<String>? selectedEventIds,
    Map<String, PendingOperation>? pendingOperations,
    bool? hasMorePast,
    bool? isLoadingMorePast,
  }) {
    return AssignmentSlotsLoaded(
      slots,
      selectedEventIds: selectedEventIds ?? this.selectedEventIds,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      hasMorePast: hasMorePast ?? this.hasMorePast,
      isLoadingMorePast: isLoadingMorePast ?? this.isLoadingMorePast,
    );
  }
}
```

- [ ] **Step 3: Register the handler + add pagination fields in `AssignmentBloc`.**

3a. In the constructor's handler registrations, add:
```dart
    on<LoadMorePastAssignmentSlots>(_onLoadMorePastAssignmentSlots);
```

3b. Add these fields near the other private fields (e.g. after `_cachedRoles`):
```dart
  // --- Past-history pagination (load more) ---
  static const int _pastLoadMoreRowChunk = 25; // rows revealed per tap
  static const int _pastEventFetchBatch = 15; // events fetched per round-trip

  // Live 90-day window data, promoted to fields so the load-more handler can
  // trigger a rebuild that merges the extra-past cache on top.
  final Map<String, Event> _windowEventsMap = {};
  final Map<String, TeamMember> _windowMembersMap = {};
  DateTime? _slotsWindowStart; // now - 90d; boundary between window and "extra-past"

  // Events/assignments older than the window, loaded on demand.
  final Map<String, Event> _extraPastEventsMap = {};
  final List<Assignment> _extraPastAssignments = [];
  int _extraPastRowsRevealed = 0; // reveal cap for extra-past rows
  DateTime? _oldestLoadedEventStart; // pagination cursor
  bool _pastPagingExhausted = false; // reached the start of history
```

- [ ] **Step 4: Wire the window maps as fields and reset pagination in `_onLoadAssignmentSlots`.**

4a. Replace the local declarations:
```dart
      final cachedMembersMap = <String, TeamMember>{};
      cachedMembersMap.addAll({for (var tm in cachedMembers) tm.id: tm});
      final cachedEventsMap = <String, Event>{};
      cachedEventsMap.addAll({for (var e in cachedEvents) e.id: e});
```
with field resets + the pagination reset:
```dart
      _windowMembersMap
        ..clear()
        ..addAll({for (var tm in cachedMembers) tm.id: tm});
      _windowEventsMap
        ..clear()
        ..addAll({for (var e in cachedEvents) e.id: e});

      // Reset past-history pagination on every (re)load, incl. toggling past.
      _slotsWindowStart = windowStart;
      _extraPastEventsMap.clear();
      _extraPastAssignments.clear();
      _extraPastRowsRevealed = 0;
      _oldestLoadedEventStart = windowStart; // fetch events strictly older than the window
      _pastPagingExhausted = false;
```

4b. In the rest of `_onLoadAssignmentSlots` and all four stream listeners, replace every remaining reference to `cachedMembersMap` with `_windowMembersMap` and every `cachedEventsMap` with `_windowEventsMap` (the `.clear()`/`.addAll(...)` calls inside the `watchTeamMembers`/`watchEventsByDateRange` listeners, and the `RebuildAssignmentSlotsFromData(...)` dispatches). After this step there are no local `cachedEventsMap`/`cachedMembersMap` identifiers left.

- [ ] **Step 5: Add the counting + reveal‑cap helpers to `AssignmentBloc`.**

```dart
  /// Count how many display rows the given events would produce (quota slots +
  /// off-quota rows), for non-deactivated events. Lightweight mirror of the
  /// slot-build loops, used to decide how many older events to fetch per tap.
  int _countDisplayRows(Iterable<Event> events, List<Assignment> assignments) {
    var count = 0;
    for (final event in events) {
      if (event.isDeactivated) continue;
      final placed = <String>{};
      for (final role in _cachedRoles) {
        final required = event.roleRequirements[role.key] ?? 0;
        if (required == 0) continue;
        count += required;
        final roleAssignments = assignments
            .where((a) => a.eventId == event.id && a.roleType == role.key)
            .toList();
        for (int i = 0; i < required; i++) {
          Assignment? match;
          for (final a in roleAssignments) {
            if (a.slotIndex == i) {
              match = a;
              break;
            }
          }
          if (match != null) placed.add(match.id);
        }
      }
      count += assignments
          .where((a) => a.eventId == event.id && !placed.contains(a.id))
          .length;
    }
    return count;
  }

  /// Keep all window rows plus the first [_extraPastRowsRevealed] extra-past
  /// rows (rows for events older than the window). Only applies when past is
  /// shown; otherwise past rows are already removed by the showPastEvents
  /// filter. Returns the capped list and whether more history is available.
  ({List<AssignmentSlot> slots, bool hasMore}) _applyPastRevealCap(
      List<AssignmentSlot> sorted) {
    final windowStart = _slotsWindowStart;
    if (!FilterPersistence.showPastEvents || windowStart == null) {
      return (slots: sorted, hasMore: false);
    }
    final kept = <AssignmentSlot>[];
    var extraShown = 0;
    var extraTotal = 0;
    for (final slot in sorted) {
      final isExtraPast = slot.event.startDate.isBefore(windowStart);
      if (!isExtraPast) {
        kept.add(slot);
      } else {
        extraTotal++;
        if (extraShown < _extraPastRowsRevealed) {
          kept.add(slot);
          extraShown++;
        }
      }
    }
    final hasMore = extraShown < extraTotal || !_pastPagingExhausted;
    return (slots: kept, hasMore: hasMore);
  }
```

- [ ] **Step 6: Merge the extra‑past cache + apply the cap in `_onRebuildAssignmentSlotsFromData`.**

6a. At the very start of the method body (before `final eventsList = ...`), merge the extra cache into local copies:
```dart
      final mergedEvents = <String, Event>{
        ...rebuildEvent.events,
        ..._extraPastEventsMap,
      };
      final mergedAssignmentsById = <String, Assignment>{
        for (final a in rebuildEvent.assignments) a.id: a,
        for (final a in _extraPastAssignments) a.id: a,
      };
      final mergedAssignments = mergedAssignmentsById.values.toList();
```
Then use `mergedEvents` where the method currently reads `rebuildEvent.events` and `mergedAssignments` where it reads `rebuildEvent.assignments` — specifically: the `eventsList`/`filteredEvents` source, the `roleAssignments` filter, the `eventAssignments`/same‑day loops, the off‑quota `eventAssignmentsAll` (Task 3 step 4d), and the `teamMembersMap` stays as `rebuildEvent.teamMembers`. (Replace `rebuildEvent.events` → `mergedEvents`, `rebuildEvent.assignments` → `mergedAssignments` throughout this method.)

6b. Replace the final emit. Old:
```dart
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        filteredSlots,
        _pendingOperations,
      );

      _emitOrLog(emit, AssignmentSlotsLoaded(
        mergedSlots,
        selectedEventIds: rebuildEvent.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
```
New:
```dart
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        filteredSlots,
        _pendingOperations,
      );

      final capped = _applyPastRevealCap(mergedSlots);

      _emitOrLog(emit, AssignmentSlotsLoaded(
        capped.slots,
        selectedEventIds: rebuildEvent.selectedEventIds,
        pendingOperations: _pendingOperations,
        hasMorePast: capped.hasMore,
        isLoadingMorePast: false,
      ));
```

- [ ] **Step 7: Apply the cap in the full path too.** In `_onRebuildAssignmentSlots` (the handler that calls `_buildSlotsFromAssignments` then `_mergeSlotsWithOptimisticUpdates`), replace its final emit similarly:

Old:
```dart
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        databaseSlots.slots,
        _pendingOperations,
      );

      _emitOrLog(emit, AssignmentSlotsLoaded(
        mergedSlots,
        selectedEventIds: filterToUse,
        pendingOperations: _pendingOperations,
      ));
```
New:
```dart
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        databaseSlots.slots,
        _pendingOperations,
      );

      final capped = _applyPastRevealCap(mergedSlots);

      _emitOrLog(emit, AssignmentSlotsLoaded(
        capped.slots,
        selectedEventIds: filterToUse,
        pendingOperations: _pendingOperations,
        hasMorePast: capped.hasMore,
        isLoadingMorePast: false,
      ));
```

- [ ] **Step 8: Implement the load‑more handler.**

```dart
  /// Reveal the next 25 rows of history older than the 90-day window. Fetches
  /// older events (and their assignments) on demand until enough rows exist,
  /// then rebuilds with the extra-past cache merged in.
  Future<void> _onLoadMorePastAssignmentSlots(
    LoadMorePastAssignmentSlots event,
    Emitter<AssignmentState> emit,
  ) async {
    if (state is! AssignmentSlotsLoaded) return;
    final current = state as AssignmentSlotsLoaded;
    if (!current.hasMorePast || current.isLoadingMorePast) return;

    _emitOrLog(emit, current.copyWith(isLoadingMorePast: true));

    final target = _extraPastRowsRevealed + _pastLoadMoreRowChunk;

    try {
      while (!_pastPagingExhausted &&
          _countDisplayRows(_extraPastEventsMap.values, _extraPastAssignments) <
              target) {
        final cursor = _oldestLoadedEventStart;
        if (cursor == null) {
          _pastPagingExhausted = true;
          break;
        }
        final batch = await _eventRepository.getEventsBeforeDate(
          cursor,
          limit: _pastEventFetchBatch,
        );
        if (batch.isEmpty) {
          _pastPagingExhausted = true;
          break;
        }
        for (final e in batch) {
          _extraPastEventsMap[e.id] = e;
        }
        _oldestLoadedEventStart = batch
            .map((e) => e.startDate)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final freshIds = batch.map((e) => e.id).toList();
        final newAssignments =
            await _repository.getAssignmentsByEventIds(freshIds);
        _extraPastAssignments.addAll(newAssignments);
        if (batch.length < _pastEventFetchBatch) {
          _pastPagingExhausted = true;
        }
      }

      _extraPastRowsRevealed = target;

      // Rebuild from the live window data with the extra-past cache merged in.
      add(RebuildAssignmentSlotsFromData(
        _repository.getCurrentAssignments(),
        _windowEventsMap,
        _windowMembersMap,
        _currentEventFilter,
      ));
    } catch (e) {
      _emitOrLog(emit, current.copyWith(isLoadingMorePast: false));
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת היסטוריה: $e'));
    }
  }
```

Note: the trailing `RebuildAssignmentSlotsFromData` recomputes `hasMorePast`/`isLoadingMorePast=false` via `_applyPastRevealCap` (Step 6), so the spinner clears and the button hides when history is exhausted.

- [ ] **Step 9: Verify analyze clean.**

Run: `cd shavtzak && flutter analyze`
Expected: no new issues.

- [ ] **Step 10: Commit.**

```bash
git add shavtzak/lib/presentation/bloc/assignment
git commit -m "feat(assignments): paginate history older than the 90-day window

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Load‑more — screen footer button

**Files:**
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart` — `_buildSlotGrid` (the `ListView.builder`)

**Interfaces:**
- Consumes: `AssignmentSlotsLoaded.hasMorePast`, `.isLoadingMorePast`, `FilterPersistence.showPastEvents`, `LoadMorePastAssignmentSlots`.

- [ ] **Step 1: Show a "טען עוד" footer as the last list item when past is on and more history exists.** In `_buildSlotGrid`, the grid rows are rendered by `ListView.builder(itemCount: slots.length, itemBuilder: ...)`. Replace that `ListView.builder` with a footer‑aware version:

```dart
                    ? Builder(
                        builder: (context) {
                          final showLoadMore =
                              FilterPersistence.showPastEvents && state.hasMorePast;
                          return ListView.builder(
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: slots.length + (showLoadMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (showLoadMore && index == slots.length) {
                                return _buildLoadMorePastButton(state);
                              }
                              return _buildSlotRow(slots[index]);
                            },
                          );
                        },
                      )
```

(`state` is the `AssignmentSlotsLoaded` in scope inside `_buildSlotGrid`.)

- [ ] **Step 2: Add the footer button widget** next to `_buildSlotGrid`:

```dart
  Widget _buildLoadMorePastButton(AssignmentSlotsLoaded state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Align(
        alignment: Alignment.center,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: state.isLoadingMorePast
              ? null
              : () {
                  Logger.action('tap:loadMorePast');
                  context
                      .read<AssignmentBloc>()
                      .add(const LoadMorePastAssignmentSlots());
                },
          icon: state.isLoadingMorePast
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more),
          label: const Text('טען עוד'),
        ),
      ),
    );
  }
```

- [ ] **Step 3: Verify analyze clean.**

Run: `cd shavtzak && flutter analyze`
Expected: no new issues.

- [ ] **Step 4: Commit.**

```bash
git add shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart
git commit -m "feat(assignments): add load-more-past footer button

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Manual check (developer, later): with past ON, a "טען עוד" button sits at the bottom; tapping loads ~25 older rows and shows a spinner while fetching; it disappears at the start of history.

---

## Task 7: Keep the extra‑past cache consistent on edits (mutation‑splice)

Without this, editing an assignment on an event older than the window would be reverted on the next window‑stream re‑emit, because `_onRebuildAssignmentSlotsFromData` merges the (stale) `_extraPastAssignments` cache.

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart`

**Interfaces:**
- Consumes: `_slotsWindowStart`, `_extraPastEventsMap`, `_extraPastAssignments`, `AssignmentRepository.getAssignmentsByEventIds`.
- Produces: `AssignmentBloc._refreshExtraPastEvent(String eventId)`.

- [ ] **Step 1: Add the splice helper.**

```dart
  /// If [eventId] is an event older than the window (its rows come from the
  /// extra-past cache, not the live stream), re-fetch its assignments so an
  /// edit/delete is reflected instead of being reverted by the next rebuild.
  Future<void> _refreshExtraPastEvent(String eventId) async {
    if (!_extraPastEventsMap.containsKey(eventId)) return;
    try {
      final fresh = await _repository.getAssignmentsByEventIds([eventId]);
      _extraPastAssignments.removeWhere((a) => a.eventId == eventId);
      _extraPastAssignments.addAll(fresh);
    } catch (_) {
      // Best-effort; the next full reload will reconcile.
    }
  }
```

- [ ] **Step 2: Call it after successful mutations.** In `_syncAttendeesForAffectedEvents` the affected event ids are already gathered; reuse that idea at the mutation sites. In each of `_onCreateAssignment`, `_onUpdateAssignment`, `_onDeleteAssignment`, `_onOptimisticCreateAssignment`, `_onOptimisticUpdateAssignment`, `_onOptimisticDeleteAssignment`, and `_onUpdateAssignmentNotes`, immediately after the successful repository write (right where `_syncAttendeesForAffectedEvents(...)` is called, or right after the `await _repository....` for notes), add a splice for the affected event id(s). Examples:

In `_onDeleteAssignment`, after `_syncAttendeesForAffectedEvents(previousAssignment: assignmentToDelete);`:
```dart
      if (assignmentToDelete != null) {
        await _refreshExtraPastEvent(assignmentToDelete.eventId);
      }
```

In `_onCreateAssignment` / `_onOptimisticCreateAssignment`, after the create + `_syncAttendeesForAffectedEvents(nextAssignment: event.assignment);`:
```dart
      await _refreshExtraPastEvent(event.assignment.eventId);
```

In `_onUpdateAssignment` / `_onOptimisticUpdateAssignment`, after the update + sync (splice both old and new event ids, which are the same for an in‑place edit):
```dart
      await _refreshExtraPastEvent(event.assignment.eventId);
      if (previousAssignment != null &&
          previousAssignment.eventId != event.assignment.eventId) {
        await _refreshExtraPastEvent(previousAssignment.eventId);
      }
```

In `_onUpdateAssignmentNotes` the `UpdateAssignmentNotes` event exposes only the assignment id (`event.id`), not its event id. Notes edits are infrequent, so after a successful `await _repository.updateAssignmentNotes(...)` simply refresh all currently‑loaded extra‑past events (cheap — the extra cache is small):
```dart
      if (_extraPastEventsMap.isNotEmpty) {
        final fresh = await _repository
            .getAssignmentsByEventIds(_extraPastEventsMap.keys.toList());
        _extraPastAssignments
          ..clear()
          ..addAll(fresh);
      }
```

- [ ] **Step 3: Verify analyze clean.**

Run: `cd shavtzak && flutter analyze`
Expected: no new issues.

- [ ] **Step 4: Commit.**

```bash
git add shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart
git commit -m "fix(assignments): keep extra-past cache consistent after edits

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Manual check (developer, later): load an ancient row via "טען עוד", edit its notes/label → the change persists and does not revert.

---

## Manual Verification (developer runs the app, test env)

Per `CLAUDE.md` the developer runs the app. After all tasks + a clean `flutter analyze`, verify in the **test** environment (`/test/admin/assignments`):

1. **Default view unchanged** — past OFF → grid is oldest→newest; no "טען עוד".
2. **Flip** — past ON → grid is newest→oldest; "טען עוד" at the bottom.
3. **Load more** — tap "טען עוד" → ~25 older rows appear below; spinner during fetch; repeat; button disappears at the start of history.
4. **Reach the example** — assignment `0471a3ff-b6e8-4cc8-adcc-854a53e9f557` becomes visible after enough taps.
5. **Off-quota** — reduce a role quota below an existing assignment → an amber "מחוץ למכסה" row appears; swipe deletes only that assignment; verify it also shows on a future event (everywhere scope).
6. **Inactive member name** — an old assignment to a now‑inactive member still shows the name.
7. **Edit persistence** — edit notes/label on a loaded ancient row → sticks (no revert).
8. **Filters** — search / filled‑unfilled / label still work on top of loaded rows.

---

## Self-Review (completed during authoring)

- **Spec coverage:** §5.1 sort→Task 2; §5.2 pagination→Tasks 1,5,6; §5.3 off‑quota→Tasks 3,4; §5.4 merge+cap→Task 5; §5.5 names→Task 3 (member‑preserve + `_resolveRoleForKey`; the "full member map" is achieved more simply by not clobbering the already‑populated relation); §5.6 UI→Tasks 4,6; §5.7 data layer→Task 1; §9 mutation‑splice→Task 7. All covered.
- **Placeholder scan:** none — every step has concrete code/commands. (Task 7 Step 2 offers a simpler bulk alternative for notes; the executor picks the bulk form as instructed.)
- **Type consistency:** `getEventsBeforeDate(DateTime, {required int limit})`, `getAssignmentsByEventIds(List<String>)`, `AssignmentSlot.isOffQuota`/`copyWith`, `AssignmentSlotsLoaded.hasMorePast`/`isLoadingMorePast`/`copyWith`, `_applyPastRevealCap` record `({List<AssignmentSlot> slots, bool hasMore})`, and `RebuildAssignmentSlotsFromData(assignments, events, teamMembers, selectedEventIds)` are used consistently across tasks.
