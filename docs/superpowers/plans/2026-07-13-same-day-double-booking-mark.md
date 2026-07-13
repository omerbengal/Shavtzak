# Same-Day Double-Booking Mark — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mark a person who is assigned to an event when that same person is also assigned to a *different* event sharing a calendar day — in the `/admin/assignments` grid, in the `מסך מנהלים` per-event assignments popup, and in the `לפי אירוע` Excel export.

**Architecture:** One pure predicate + index (`lib/core/utils/same_day_assignments.dart`) is the single source of truth for "shares a day" and "who else is booked that day". Two pure slot-annotation passes (`assignment_slot_annotations.dart`) turn that index into a new `AssignmentSlot.sameDayOtherEvents` field, replacing two verbatim-duplicated inline passes in `AssignmentBloc`. One shared widget (`SameDayAssignmentMark`) renders the icon + tooltip + dialog so both screens look identical. The export mirrors the same rule in TypeScript.

**Tech Stack:** Flutter Web (Dart, BLoC, Equatable), Firebase Cloud Functions (TypeScript, `node:test`).

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-07-13-same-day-double-booking-mark-design.md`. Read it before starting.
- **Branch:** `feat/same-day-double-booking-mark` (already created and checked out).
- **Pre-existing dirty files:** `functions/src/calendar_integration.ts`, `functions/src/calendar_sync_backend.ts`, `functions/src/index.ts` and `Google_Calendar_Problem.txt` are Omer's uncommitted work. **Never `git add -A` / `git commit -a`.** Always `git add` the exact paths listed in the task.
- **UI language:** all user-facing strings in Hebrew, code comments in English.
- **RTL:** any new dialog is wrapped in `Directionality(textDirection: TextDirection.rtl)`.
- **Equatable rule (project-critical):** every new field on an entity or BLoC-state-carried model MUST be added to `props`, using the full object — never just an id. A field missing from `props` means the UI silently stops live-updating.
- **`flutter analyze` baseline:** REVISED at Task 4 (f7772e1): `flutter analyze` = **108 issues found** (down from 110 — deleting two vestigial `?? false` / `?? const []` expressions in the optimistic merge removed two `dead_null_aware_expression` warnings), `flutter test` = **208 passing**, `cd functions && npm test` = **54 passing**. "Clean" means **zero NEW** issues over 108, not zero issues.
- **Do not run the app.** Per `CLAUDE.md`, Omer runs and smoke-tests it himself. Verification here = `flutter analyze` + `flutter test` + `npm test`.
- **The mark's rule** (copy verbatim into doc comments where relevant): for member `M` assigned to event `E`, collect every event `O` where `O.id != E.id`, `O.isDeactivated == false`, `O` overlaps `E` on ≥1 calendar day, and `M` is also assigned to `O`. Sort that set by start date, then name. The relation is **symmetric** — `M` is marked on `O` too, naming `E`. Members flagged `allowMultipleAssignments` **are** marked.

---

### Task 1: The shared same-day predicate and index

**Files:**
- Create: `shavtzak/lib/core/utils/same_day_assignments.dart`
- Test: `shavtzak/test/core/utils/same_day_assignments_test.dart`

**Interfaces:**
- Consumes: `Event`, `Assignment` from `shavtzak/lib/domain/entities/`.
- Produces (every later task depends on these exact signatures):
  - `bool eventsShareDay(Event a, Event b)`
  - `Map<String, List<Event>> sameDayOtherEventsByMember({required Event event, required List<Event> allEvents, required List<Assignment> allAssignments})`
  - `Map<String, Map<String, List<Event>>> buildSameDayOtherEventsIndex({required List<Event> events, required List<Assignment> assignments})`

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/core/utils/same_day_assignments_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/same_day_assignments.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';

void main() {
  group('eventsShareDay', () {
    test('two single-day events on the same date share a day', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 12)),
          _event(id: 'b', start: DateTime(2026, 7, 12)),
        ),
        isTrue,
      );
    });

    test('two single-day events on different dates do not share a day', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 12)),
          _event(id: 'b', start: DateTime(2026, 7, 13)),
        ),
        isFalse,
      );
    });

    test('a multi-day event overlapping by one day shares a day', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 5), end: DateTime(2026, 7, 7)),
          _event(id: 'b', start: DateTime(2026, 7, 7)),
        ),
        isTrue,
      );
    });

    test('back-to-back events do not share a day', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 5), end: DateTime(2026, 7, 6)),
          _event(id: 'b', start: DateTime(2026, 7, 7)),
        ),
        isFalse,
      );
    });

    test('times of day are ignored', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 12, 8), end: DateTime(2026, 7, 12, 11)),
          _event(id: 'b', start: DateTime(2026, 7, 12, 20), end: DateTime(2026, 7, 12, 23)),
        ),
        isTrue,
      );
    });
  });

  group('sameDayOtherEventsByMember', () {
    test('maps a member assigned to another event on the same day', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final evening =
          _event(id: 'evening', name: 'מופע ערב', start: DateTime(2026, 7, 12));

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm1'),
        ],
      );

      expect(result.keys, ['m1']);
      expect(result['m1']!.map((e) => e.id), ['evening']);
    });

    test('omits a member who is only assigned to this event, and one who is '
        'only assigned to the other', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final evening = _event(id: 'evening', start: DateTime(2026, 7, 12));

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm2'),
        ],
      );

      // m1 is in summer but nowhere else. m2 is in evening but NOT in summer —
      // m2 must not be credited to summer at all: the map answers "who, of the
      // people assigned to THIS event, is also booked elsewhere".
      expect(result, isEmpty);
    });

    test('omits a member whose other event is on a different day', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final nextDay = _event(id: 'nextDay', start: DateTime(2026, 7, 13));

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, nextDay],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'nextDay', memberId: 'm1'),
        ],
      );

      expect(result, isEmpty);
    });

    test('never counts a deactivated event as the other event', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final onHold = _event(
        id: 'onHold',
        start: DateTime(2026, 7, 12),
        isDeactivated: true,
      );

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, onHold],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'onHold', memberId: 'm1'),
        ],
      );

      expect(result, isEmpty);
    });

    test('lists the other event once even when the member holds two roles in it',
        () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final evening = _event(id: 'evening', start: DateTime(2026, 7, 12));

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm1', roleType: 'medic'),
          _assignment(id: 'a3', eventId: 'evening', memberId: 'm1', roleType: 'commander'),
        ],
      );

      expect(result['m1']!.map((e) => e.id), ['evening']);
    });

    test('sorts other events by start date, then by name', () {
      final anchor = _event(
        id: 'anchor',
        start: DateTime(2026, 7, 12),
        end: DateTime(2026, 7, 14),
      );
      final late = _event(id: 'late', name: 'אאא', start: DateTime(2026, 7, 14));
      final earlyB = _event(id: 'earlyB', name: 'בבב', start: DateTime(2026, 7, 12));
      final earlyA = _event(id: 'earlyA', name: 'aaa', start: DateTime(2026, 7, 12));

      final result = sameDayOtherEventsByMember(
        event: anchor,
        allEvents: [anchor, late, earlyB, earlyA],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'anchor', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'late', memberId: 'm1'),
          _assignment(id: 'a3', eventId: 'earlyB', memberId: 'm1'),
          _assignment(id: 'a4', eventId: 'earlyA', memberId: 'm1'),
        ],
      );

      expect(result['m1']!.map((e) => e.id), ['earlyA', 'earlyB', 'late']);
    });
  });

  group('buildSameDayOtherEventsIndex', () {
    test('is symmetric: each event names the other', () {
      final summer = _event(id: 'summer', name: 'אירוע קיץ', start: DateTime(2026, 7, 12));
      final evening = _event(id: 'evening', name: 'מופע ערב', start: DateTime(2026, 7, 12));

      final index = buildSameDayOtherEventsIndex(
        events: [summer, evening],
        assignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm1'),
        ],
      );

      expect(index['summer']!['m1']!.map((e) => e.id), ['evening']);
      expect(index['evening']!['m1']!.map((e) => e.id), ['summer']);
    });

    test('omits events that have no double-booked member', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final evening = _event(id: 'evening', start: DateTime(2026, 7, 12));

      final index = buildSameDayOtherEventsIndex(
        events: [summer, evening],
        assignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm2'),
        ],
      );

      expect(index, isEmpty);
    });
  });
}

Event _event({
  required String id,
  required DateTime start,
  DateTime? end,
  String name = 'אירוע',
  bool isDeactivated = false,
}) {
  final now = DateTime(2026, 7, 1);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: end ?? start,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
    isDeactivated: isDeactivated,
  );
}

Assignment _assignment({
  required String id,
  required String eventId,
  required String memberId,
  String roleType = 'medic',
  int slotIndex = 0,
}) {
  final now = DateTime(2026, 7, 1);
  return Assignment(
    id: id,
    eventId: eventId,
    teamMemberId: memberId,
    roleType: roleType,
    slotIndex: slotIndex,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd shavtzak && flutter test test/core/utils/same_day_assignments_test.dart
```

Expected: FAIL — `Error: Couldn't resolve the package 'shavtzak/core/utils/same_day_assignments.dart'` / "Target of URI doesn't exist".

- [ ] **Step 3: Write the implementation**

Create `shavtzak/lib/core/utils/same_day_assignments.dart`:

```dart
import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';

/// True when [a] and [b] occupy at least one calendar day in common.
///
/// Day precision — times are ignored. The comparison deliberately does NOT add
/// a `Duration` to a local `DateTime`: `DateTime(y, m, d).add(const
/// Duration(days: 1))` shifts by an hour across an Israel DST boundary and can
/// report a spurious overlap. `!isAfter` has no such hazard.
bool eventsShareDay(Event a, Event b) {
  final aStart = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
  final aEnd = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
  final bStart = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
  final bEnd = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);

  return !aStart.isAfter(bEnd) && !bStart.isAfter(aEnd);
}

/// Other events sharing a calendar day with [event] that a member is ALSO
/// assigned to, keyed by member id. Members with no such event are absent.
///
/// Each list is sorted by start date, then name, so every surface renders the
/// same order and a re-export of unchanged data is byte-identical.
///
/// Deactivated events never count as the other event.
///
/// This deliberately does NOT filter by role capability, availability, or the
/// `allowMultipleAssignments` flag — unlike the candidate-filtering logic in
/// `AssignmentBloc` that it sits beside. That logic answers "who should I hide
/// from the assign dropdown". This answers a different question: is this
/// person, who is ALREADY assigned, booked somewhere else the same day? A
/// member who cannot perform this slot's role, or who carries the
/// `שיבוץ מרובה` flag, is absent from that logic yet must still be marked here.
Map<String, List<Event>> sameDayOtherEventsByMember({
  required Event event,
  required List<Event> allEvents,
  required List<Assignment> allAssignments,
}) {
  final otherEventsById = <String, Event>{};
  for (final candidate in allEvents) {
    if (candidate.id == event.id) continue;
    if (candidate.isDeactivated) continue;
    if (!eventsShareDay(event, candidate)) continue;
    otherEventsById[candidate.id] = candidate;
  }
  if (otherEventsById.isEmpty) return const {};

  // A member only qualifies if they are assigned to [event] itself — the
  // function answers "who here is ALSO booked elsewhere", not "who is booked
  // to any same-day event".
  final eventMemberIds = <String>{};
  for (final assignment in allAssignments) {
    if (assignment.eventId != event.id) continue;
    eventMemberIds.add(assignment.teamMemberId);
  }

  // Inner map keyed by event id: a member holding two roles in the same other
  // event must see that event listed once.
  final byMember = <String, Map<String, Event>>{};
  for (final assignment in allAssignments) {
    if (!eventMemberIds.contains(assignment.teamMemberId)) continue;
    final other = otherEventsById[assignment.eventId];
    if (other == null) continue;
    byMember.putIfAbsent(
      assignment.teamMemberId,
      () => <String, Event>{},
    )[other.id] = other;
  }

  return {
    for (final entry in byMember.entries)
      entry.key: entry.value.values.toList()..sort(_byStartDateThenName),
  };
}

/// eventId -> memberId -> other same-day events, for every event in [events].
/// Events with no double-booked member are absent from the outer map.
///
/// The relation is symmetric: if member M is in E and O on a shared day, then
/// `index[E.id][M]` names O *and* `index[O.id][M]` names E. Every surface must
/// look up the event it is currently rendering — do not collapse this into a
/// one-directional check.
Map<String, Map<String, List<Event>>> buildSameDayOtherEventsIndex({
  required List<Event> events,
  required List<Assignment> assignments,
}) {
  final index = <String, Map<String, List<Event>>>{};
  for (final event in events) {
    final byMember = sameDayOtherEventsByMember(
      event: event,
      allEvents: events,
      allAssignments: assignments,
    );
    if (byMember.isNotEmpty) {
      index[event.id] = byMember;
    }
  }
  return index;
}

int _byStartDateThenName(Event a, Event b) {
  final byDate = a.startDate.compareTo(b.startDate);
  if (byDate != 0) return byDate;
  return a.name.compareTo(b.name);
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd shavtzak && flutter test test/core/utils/same_day_assignments_test.dart
```

Expected: PASS — `+13: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/core/utils/same_day_assignments.dart shavtzak/test/core/utils/same_day_assignments_test.dart
git commit -m "feat(assignments): shared same-day double-booking predicate and index"
```

---

### Task 2: Retire the three copy-pasted "shares a day" helpers

Three files each carry their own implementation of the day-overlap check; point them all at `eventsShareDay`.

Behaviour is identical **except at one edge**, deliberately: two of the three write the overlap as `aStart.isBefore(bEnd.add(const Duration(days: 1)))`. `Duration` is absolute, so on the night Israel enters DST that `+1 day` lands on 01:00 rather than midnight, and two events on *adjacent* days can be reported as overlapping. `eventsShareDay` uses the `!isAfter` form (which the third copy, in `EventSummaryTile`, already used) and has no such hazard. This is a fix, not a regression — but do not describe this task as behaviour-preserving.

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` (call sites `:1643`, `:1954`; delete `_eventsShareDate` at `:2297-2309`)
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart` (call site `:708`; delete `_eventsShareDay` at `:803-816`)
- Modify: `shavtzak/lib/presentation/screens/assignment/manual_assignment_flow_dialog.dart` (call site `:851`; delete `_eventsShareDate` at `:865-877`)

**Interfaces:**
- Consumes: `eventsShareDay(Event, Event)` from Task 1.
- Produces: nothing new.

- [ ] **Step 1: Migrate `AssignmentBloc`**

Add to the import block of `assignment_bloc.dart`, after `import '../../../core/utils/filter_persistence.dart';`:

```dart
import '../../../core/utils/same_day_assignments.dart';
```

Replace the call at `:1643`:

```dart
            if (_eventsShareDate(event, otherEvent)) {
```

with:

```dart
            if (eventsShareDay(event, otherEvent)) {
```

Replace the call at `:1954`:

```dart
              if (_eventsShareDate(eventData, otherEvent)) {
```

with:

```dart
              if (eventsShareDay(eventData, otherEvent)) {
```

Delete the whole `_eventsShareDate` method (`:2297-2309`), including its comment:

```dart
  bool _eventsShareDate(Event a, Event b) {
    // Normalize dates to day precision (ignore time)
    final aStart =
        DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final aEnd = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    final bStart =
        DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
    final bEnd = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);

    // Check for overlap: events overlap if one starts before the other ends
    return aStart.isBefore(bEnd.add(const Duration(days: 1))) &&
        bStart.isBefore(aEnd.add(const Duration(days: 1)));
  }
```

- [ ] **Step 2: Migrate `EventSummaryTile`**

Add to the import block of `event_summary_tile.dart`, after `import '../../../../core/debug/logger.dart';`:

```dart
import '../../../../core/utils/same_day_assignments.dart';
```

Replace the call at `:708`:

```dart
      if (_eventsShareDay(event, otherEvent)) {
```

with:

```dart
      if (eventsShareDay(event, otherEvent)) {
```

Delete the whole `_eventsShareDay` method (`:803-816`):

```dart
  bool _eventsShareDay(Event event1, Event event2) {
    // Get date ranges (normalize to midnight)
    final start1 = DateTime(
        event1.startDate.year, event1.startDate.month, event1.startDate.day);
    final end1 =
        DateTime(event1.endDate.year, event1.endDate.month, event1.endDate.day);
    final start2 = DateTime(
        event2.startDate.year, event2.startDate.month, event2.startDate.day);
    final end2 =
        DateTime(event2.endDate.year, event2.endDate.month, event2.endDate.day);

    // Check if ranges overlap
    return !start1.isAfter(end2) && !start2.isAfter(end1);
  }
```

- [ ] **Step 3: Migrate `ManualAssignmentFlowDialog`**

Add to the import block of `manual_assignment_flow_dialog.dart` (alongside the other `../../../core/...` imports):

```dart
import '../../../core/utils/same_day_assignments.dart';
```

Replace the call at `:851`:

```dart
      if (_eventsShareDate(_selectedEvent!, otherEvent)) {
```

with:

```dart
      if (eventsShareDay(_selectedEvent!, otherEvent)) {
```

Delete the whole `_eventsShareDate` method (`:865-877`), including its doc comment:

```dart
  /// Helper function to check if two events share at least one day
  bool _eventsShareDate(Event a, Event b) {
    // Normalize dates to day precision (ignore time)
    final aStart = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final aEnd = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    final bStart = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
    final bEnd = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);

    // Check for overlap: events overlap if one starts before the other ends
    return aStart.isBefore(bEnd.add(const Duration(days: 1))) &&
           bStart.isBefore(aEnd.add(const Duration(days: 1)));
  }
```

- [ ] **Step 4: Verify nothing else references the deleted helpers**

```bash
cd shavtzak && grep -rn "_eventsShareDate\|_eventsShareDay" lib/
```

Expected: no output.

- [ ] **Step 5: Analyze and run the full suite**

```bash
cd shavtzak && flutter analyze && flutter test
```

Expected: analyze still reports 110 issues (the baseline — zero new), and all 186 tests pass. If `flutter analyze` reports an unused-import or unused-element warning, you missed a deletion — fix it.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart shavtzak/lib/presentation/screens/assignment/manual_assignment_flow_dialog.dart
git commit -m "refactor(assignments): one definition of 'events share a day'"
```

---

### Task 3: `AssignmentSlot.sameDayOtherEvents` + the two pure annotation passes

`AssignmentBloc` currently carries two **verbatim-duplicated** inline double-assignment passes (`:1722-1766` and `:2041-2084`). Both rebuild the slot with the **raw constructor instead of `copyWith`**, silently dropping `sameDayAssignedMembers` / `sameDayEventInfo` — a live bug that degrades the "בעלי מגבלות / לא זמינים" dialog for anyone holding two roles in an event. Extract both passes into one pure, unit-testable file, fix the drop, and add the new same-day pass beside it.

**Files:**
- Modify: `shavtzak/lib/presentation/screens/assignment/models/assignment_slot.dart`
- Create: `shavtzak/lib/presentation/screens/assignment/models/assignment_slot_annotations.dart`
- Test: `shavtzak/test/presentation/screens/assignment/models/assignment_slot_annotations_test.dart`

**Interfaces:**
- Consumes: `buildSameDayOtherEventsIndex` from Task 1.
- Produces:
  - `AssignmentSlot.sameDayOtherEvents` → `List<Event>` (defaults to `const []`, in `copyWith`, in `props`)
  - `List<AssignmentSlot> annotateDoubleAssignments(List<AssignmentSlot> slots)`
  - `List<AssignmentSlot> annotateSameDayOtherEvents(List<AssignmentSlot> slots, {required List<Event> allEvents, required List<Assignment> allAssignments})`

- [ ] **Step 1: Add the field to `AssignmentSlot`**

In `shavtzak/lib/presentation/screens/assignment/models/assignment_slot.dart`:

Add the field, right after `sameDayEventInfo`:

```dart
  final Map<String, List<String>> sameDayEventInfo; // memberId -> other event names

  /// Other events sharing a calendar day that the slot's ASSIGNED member is
  /// also assigned to. Empty when the slot is unfilled or the member is not
  /// double-booked. Distinct from [sameDayAssignedMembers], which is about
  /// CANDIDATES for this slot, not the person already in it.
  final List<Event> sameDayOtherEvents;
```

Add the constructor default, after `this.sameDayEventInfo = const {},`:

```dart
    this.sameDayOtherEvents = const [],
```

Add the `copyWith` parameter, after `Map<String, List<String>>? sameDayEventInfo,`:

```dart
    List<Event>? sameDayOtherEvents,
```

Add the `copyWith` body line, after `sameDayEventInfo: sameDayEventInfo ?? this.sameDayEventInfo,`:

```dart
      sameDayOtherEvents: sameDayOtherEvents ?? this.sameDayOtherEvents,
```

Add to `props`, after `sameDayEventInfo,`:

```dart
        sameDayOtherEvents,
```

- [ ] **Step 2: Write the failing test**

Create `shavtzak/test/presentation/screens/assignment/models/assignment_slot_annotations_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot.dart';
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot_annotations.dart';

void main() {
  final summer = _event(id: 'summer', name: 'אירוע קיץ', start: DateTime(2026, 7, 12));
  final evening = _event(id: 'evening', name: 'מופע ערב', start: DateTime(2026, 7, 12));
  final medic = _role('medic', 'חובש');
  final commander = _role('commander', 'מפקד אירוע');

  group('annotateSameDayOtherEvents', () {
    test('marks a filled quota slot whose member is in another same-day event',
        () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1'),
      ];

      final result = annotateSameDayOtherEvents(
        slots,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', member: member),
          _assignment(id: 'a2', eventId: 'evening', member: member),
        ],
      );

      expect(result.single.sameDayOtherEvents.map((e) => e.id), ['evening']);
    });

    test('marks off-quota rows too — they are real assignments', () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(
          event: summer,
          role: medic,
          member: member,
          assignmentId: 'a1',
          isOffQuota: true,
        ),
      ];

      final result = annotateSameDayOtherEvents(
        slots,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', member: member),
          _assignment(id: 'a2', eventId: 'evening', member: member),
        ],
      );

      expect(result.single.sameDayOtherEvents.map((e) => e.id), ['evening']);
    });

    test('leaves an unfilled slot alone', () {
      final slots = [_slot(event: summer, role: medic)];

      final result = annotateSameDayOtherEvents(
        slots,
        allEvents: [summer, evening],
        allAssignments: const [],
      );

      expect(result.single.sameDayOtherEvents, isEmpty);
    });

    test('preserves fields set by an earlier pass', () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1')
            .copyWith(hasDoubleAssignment: true, otherRoles: ['מפקד אירוע']),
      ];

      final result = annotateSameDayOtherEvents(
        slots,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', member: member),
          _assignment(id: 'a2', eventId: 'evening', member: member),
        ],
      );

      expect(result.single.hasDoubleAssignment, isTrue);
      expect(result.single.otherRoles, ['מפקד אירוע']);
      expect(result.single.sameDayOtherEvents, isNotEmpty);
    });
  });

  group('annotateDoubleAssignments', () {
    test('flags a member holding two roles in the same event', () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1'),
        _slot(event: summer, role: commander, member: member, assignmentId: 'a2'),
      ];

      final result = annotateDoubleAssignments(slots);

      expect(result[0].hasDoubleAssignment, isTrue);
      expect(result[0].otherRoles, ['מפקד אירוע']);
      expect(result[1].hasDoubleAssignment, isTrue);
      expect(result[1].otherRoles, ['חובש']);
    });

    test('preserves sameDay* fields when flagging (regression: used the raw '
        'constructor and dropped them)', () {
      final member = _member('m1', 'יוסי כהן');
      final other = _member('m2', 'דנה לוי');
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1')
            .copyWith(
          sameDayAssignedMembers: [other],
          sameDayEventInfo: {
            'm2': ['מופע ערב']
          },
        ),
        _slot(event: summer, role: commander, member: member, assignmentId: 'a2'),
      ];

      final result = annotateDoubleAssignments(slots);

      expect(result[0].hasDoubleAssignment, isTrue);
      expect(result[0].sameDayAssignedMembers, [other]);
      expect(result[0].sameDayEventInfo, {
        'm2': ['מופע ערב']
      });
    });

    test('skips members flagged שיבוץ מרובה', () {
      final member = _member('m1', 'יוסי כהן', allowMultipleAssignments: true);
      final slots = [
        _slot(event: summer, role: medic, member: member, assignmentId: 'a1'),
        _slot(event: summer, role: commander, member: member, assignmentId: 'a2'),
      ];

      final result = annotateDoubleAssignments(slots);

      expect(result[0].hasDoubleAssignment, isFalse);
      expect(result[1].hasDoubleAssignment, isFalse);
    });

    test('skips off-quota slots', () {
      final member = _member('m1', 'יוסי כהן');
      final slots = [
        _slot(
          event: summer,
          role: medic,
          member: member,
          assignmentId: 'a1',
          isOffQuota: true,
        ),
        _slot(event: summer, role: commander, member: member, assignmentId: 'a2'),
      ];

      final result = annotateDoubleAssignments(slots);

      expect(result[0].hasDoubleAssignment, isFalse);
    });
  });
}

AssignmentSlot _slot({
  required Event event,
  required Role role,
  TeamMember? member,
  String? assignmentId,
  bool isOffQuota = false,
}) {
  return AssignmentSlot(
    event: event,
    role: role,
    slotIndex: 0,
    currentAssignment: member == null
        ? null
        : _assignment(id: assignmentId!, eventId: event.id, member: member,
            roleType: role.key),
    availableMembers: const [],
    isOffQuota: isOffQuota,
  );
}

Event _event({
  required String id,
  required String name,
  required DateTime start,
  DateTime? end,
}) {
  final now = DateTime(2026, 7, 1);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: end ?? start,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}

Role _role(String key, String hebrewName) {
  final now = DateTime(2026, 7, 1);
  return Role(
    id: key,
    key: key,
    hebrewName: hebrewName,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}

TeamMember _member(
  String id,
  String name, {
  bool allowMultipleAssignments = false,
}) {
  final now = DateTime(2026, 7, 1);
  return TeamMember(
    id: id,
    name: name,
    isActive: true,
    isPermanent: true,
    constraints: const [],
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'unique-$id',
    allowMultipleAssignments: allowMultipleAssignments,
  );
}

Assignment _assignment({
  required String id,
  required String eventId,
  required TeamMember member,
  String roleType = 'medic',
}) {
  final now = DateTime(2026, 7, 1);
  return Assignment(
    id: id,
    eventId: eventId,
    teamMemberId: member.id,
    roleType: roleType,
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
    teamMember: member,
  );
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd shavtzak && flutter test test/presentation/screens/assignment/models/assignment_slot_annotations_test.dart
```

Expected: FAIL — "Target of URI doesn't exist: 'package:shavtzak/presentation/screens/assignment/models/assignment_slot_annotations.dart'".

- [ ] **Step 4: Write the implementation**

Create `shavtzak/lib/presentation/screens/assignment/models/assignment_slot_annotations.dart`:

```dart
import '../../../../core/utils/same_day_assignments.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/event.dart';
import 'assignment_slot.dart';

/// Pure passes that annotate already-built slots. Both `AssignmentBloc`
/// slot-building paths run them, so the grid cannot disagree with itself.

/// Flag every filled quota slot whose member also holds a DIFFERENT role in the
/// SAME event, and list those other roles.
///
/// Off-quota slots are skipped — they are already flagged "מחוץ למכסה" and are
/// display+delete only. Members flagged `allowMultipleAssignments`
/// (`שיבוץ מרובה`) are skipped too: several roles in one event is exactly what
/// that flag permits, so it is not worth warning about.
List<AssignmentSlot> annotateDoubleAssignments(List<AssignmentSlot> slots) {
  return slots.map((slot) {
    if (slot.isOffQuota || !slot.isFilled) return slot;

    final member = slot.currentAssignment!.teamMember;
    if (member?.allowMultipleAssignments ?? false) return slot;

    final otherRoles = slots
        .where((other) =>
            other.event.id == slot.event.id &&
            other.isFilled &&
            other.currentAssignment!.teamMemberId ==
                slot.currentAssignment!.teamMemberId &&
            other.role.key != slot.role.key)
        .map((other) => other.role.hebrewName)
        .toList();

    if (otherRoles.isEmpty) return slot;

    // copyWith, never the raw constructor: hand-rebuilding the slot drops every
    // field the call forgets, which is how sameDayAssignedMembers /
    // sameDayEventInfo used to vanish from exactly the rows that had a double
    // assignment.
    return slot.copyWith(hasDoubleAssignment: true, otherRoles: otherRoles);
  }).toList();
}

/// Flag every filled slot — including off-quota rows, which are real
/// assignments — whose member is also assigned to another event sharing a
/// calendar day, and list those events.
///
/// [allEvents] and [allAssignments] must be the FULL loaded window, before any
/// event filter is applied. Narrowing the grid to a single event must not erase
/// that event's own marks.
List<AssignmentSlot> annotateSameDayOtherEvents(
  List<AssignmentSlot> slots, {
  required List<Event> allEvents,
  required List<Assignment> allAssignments,
}) {
  final index = buildSameDayOtherEventsIndex(
    events: allEvents,
    assignments: allAssignments,
  );
  if (index.isEmpty) return slots;

  return slots.map((slot) {
    if (!slot.isFilled) return slot;

    final otherEvents =
        index[slot.event.id]?[slot.currentAssignment!.teamMemberId];
    if (otherEvents == null || otherEvents.isEmpty) return slot;

    return slot.copyWith(sameDayOtherEvents: otherEvents);
  }).toList();
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd shavtzak && flutter test test/presentation/screens/assignment/models/assignment_slot_annotations_test.dart
```

Expected: PASS — `+8: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/screens/assignment/models/assignment_slot.dart shavtzak/lib/presentation/screens/assignment/models/assignment_slot_annotations.dart shavtzak/test/presentation/screens/assignment/models/assignment_slot_annotations_test.dart
git commit -m "feat(assignments): AssignmentSlot.sameDayOtherEvents + pure annotation passes"
```

---

### Task 4: Run the annotation passes in both `AssignmentBloc` paths

Replace both inline double-assignment blocks with the shared passes, and add the same-day pass **after** them — so that even if a future edit reintroduces a raw-constructor rebuild in the double-assignment pass, it cannot drop the new field.

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` (`:1722-1774` and `:2041-2087`)

**Interfaces:**
- Consumes: `annotateDoubleAssignments`, `annotateSameDayOtherEvents` from Task 3.
- Produces: `AssignmentSlotsLoaded` slots now carry `sameDayOtherEvents`.

- [ ] **Step 1: Import the annotations**

In `assignment_bloc.dart`, next to the existing `import '../../screens/assignment/models/assignment_slot.dart';`, add:

```dart
import '../../screens/assignment/models/assignment_slot_annotations.dart';
```

- [ ] **Step 2: Rewrite path 1 (`_buildSlotsFromAssignments`)**

Replace everything from `// 6. Detect double assignments` (`:1722`) through the `return AssignmentSlotsLoaded(...)` (`:1774`) — i.e. delete the whole 45-line inline `slotsWithDoubleAssignmentDetection` loop — with:

```dart
    // 6. Annotate the built slots. Same-day runs LAST so that no later pass can
    //    drop it (see annotateDoubleAssignments' copyWith note). Both passes see
    //    the full loaded window — the event filter is applied downstream, in the
    //    widget, so narrowing the grid never erases an event's own marks.
    var annotatedSlots = annotateDoubleAssignments(slots);
    annotatedSlots = annotateSameDayOtherEvents(
      annotatedSlots,
      allEvents: events,
      allAssignments: assignments,
    );

    // 7. Sort slots deterministically so same-role rows do not flip order.
    annotatedSlots.sort(_compareAssignmentSlots);

    return AssignmentSlotsLoaded(
      annotatedSlots,
      selectedEventIds: selectedEventIds ?? {},
    );
  }
```

- [ ] **Step 3: Rewrite path 2 (`_onRebuildAssignmentSlotsFromData`)**

Replace everything from `// Detect double assignments` (`:2041`) through `slotsWithDoubleAssignmentDetection.sort(_compareAssignmentSlots);` (`:2087`) with:

```dart
      // Annotate the built slots — same passes, same order as
      // _buildSlotsFromAssignments. Runs BEFORE the event filter below, so
      // filtering the grid to one event keeps that event's own marks.
      var annotatedSlots = annotateDoubleAssignments(slots);
      annotatedSlots = annotateSameDayOtherEvents(
        annotatedSlots,
        allEvents: filteredEvents,
        allAssignments: mergedAssignments,
      );

      // Sort slots deterministically so same-role rows do not flip order.
      annotatedSlots.sort(_compareAssignmentSlots);
```

Then update the two references that followed it (`:2090-2095`) from `slotsWithDoubleAssignmentDetection` to `annotatedSlots`:

```dart
      // Apply filter if needed
      final filteredSlots = rebuildEvent.selectedEventIds.isNotEmpty
          ? annotatedSlots
              .where((slot) =>
                  rebuildEvent.selectedEventIds.contains(slot.event.id))
              .toList()
          : annotatedSlots;
```

- [ ] **Step 4: Verify the inline passes are gone**

```bash
cd shavtzak && grep -rn "slotsWithDoubleAssignmentDetection\|skipDoubleAssignmentWarning" lib/
```

Expected: no output.

- [ ] **Step 5: Analyze and run the full suite**

```bash
cd shavtzak && flutter analyze && flutter test
```

Expected: no NEW analyze issues; all tests pass (this includes the existing `assignment_bloc_*_test.dart` files — they must still be green, since this task changes no behaviour they assert on).

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart
git commit -m "feat(assignments): populate sameDayOtherEvents in both slot-build paths"
```

---

### Task 5: The `SameDayAssignmentMark` widget

One widget, used by both screens, so they cannot drift apart.

**Files:**
- Create: `shavtzak/lib/presentation/widgets/same_day_assignment_mark.dart`
- Test: `shavtzak/test/presentation/widgets/same_day_assignment_mark_test.dart`

**Interfaces:**
- Consumes: `Event`.
- Produces: `SameDayAssignmentMark({Key? key, required List<Event> otherEvents, required String memberName, double size = 20})`.

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/presentation/widgets/same_day_assignment_mark_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/widgets/same_day_assignment_mark.dart';

void main() {
  final evening = _event('evening', 'מופע ערב', DateTime(2026, 7, 12));
  final ceremony = _event('ceremony', 'טקס', DateTime(2026, 7, 12));

  Widget wrap(Widget child) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('renders nothing when the member is not double-booked',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SameDayAssignmentMark(otherEvents: [], memberName: 'יוסי כהן'),
    ));

    expect(find.byIcon(Icons.event_repeat), findsNothing);
  });

  testWidgets('renders the mark when the member is double-booked',
      (tester) async {
    await tester.pumpWidget(wrap(
      SameDayAssignmentMark(otherEvents: [evening], memberName: 'יוסי כהן'),
    ));

    expect(find.byIcon(Icons.event_repeat), findsOneWidget);
  });

  testWidgets('tapping the mark lists every other event', (tester) async {
    await tester.pumpWidget(wrap(
      SameDayAssignmentMark(
        otherEvents: [evening, ceremony],
        memberName: 'יוסי כהן',
      ),
    ));

    await tester.tap(find.byIcon(Icons.event_repeat));
    await tester.pumpAndSettle();

    expect(find.text('שיבוץ באירוע נוסף באותו יום'), findsOneWidget);
    expect(find.text('יוסי כהן משובץ/ת גם באירועים:'), findsOneWidget);
    expect(find.text('• מופע ערב — 12/07/2026'), findsOneWidget);
    expect(find.text('• טקס — 12/07/2026'), findsOneWidget);
  });
}

Event _event(String id, String name, DateTime start) {
  final now = DateTime(2026, 7, 1);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: start,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd shavtzak && flutter test test/presentation/widgets/same_day_assignment_mark_test.dart
```

Expected: FAIL — "Target of URI doesn't exist: 'package:shavtzak/presentation/widgets/same_day_assignment_mark.dart'".

- [ ] **Step 3: Write the implementation**

Create `shavtzak/lib/presentation/widgets/same_day_assignment_mark.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/debug/logger.dart';
import '../../core/utils/date_utils.dart' as app_date_utils;
import '../../domain/entities/event.dart';

/// The mark shown next to a person who is also assigned to a different event on
/// a day this event covers. Tap to see which events.
///
/// Deliberately a DIFFERENT icon from the orange ⚠ that flags a second role in
/// the SAME event: a person can carry both marks at once and they are different
/// problems, so an identical icon would force the user to tap each one to find
/// out what it is telling them.
class SameDayAssignmentMark extends StatelessWidget {
  const SameDayAssignmentMark({
    super.key,
    required this.otherEvents,
    required this.memberName,
    this.size = 20,
  });

  /// Sorted by start date then name — see `sameDayOtherEventsByMember`.
  final List<Event> otherEvents;
  final String memberName;
  final double size;

  static const Color _markColor = Colors.orange;

  @override
  Widget build(BuildContext context) {
    if (otherEvents.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: 'משובץ/ת גם ב: ${otherEvents.map(_shortLabel).join(', ')}',
      child: InkWell(
        onTap: () {
          Logger.action('open:sameDayAssignmentDialog', {
            'otherEventCount': otherEvents.length,
          });
          _showOtherEventsDialog(context);
        },
        child: Icon(Icons.event_repeat, color: _markColor, size: size),
      ),
    );
  }

  static String _shortLabel(Event event) =>
      '${event.name} (${event.startDate.day}/${event.startDate.month})';

  void _showOtherEventsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          // otherEvents is unbounded. Without this, AlertDialog wraps content in
          // a bare Flexible, which permits shrinking but does not prevent
          // overflow — a person with several same-day events, or two long event
          // names, spills outside the dialog.
          scrollable: true,
          title: Row(
            children: const [
              Icon(Icons.event_repeat, color: _markColor),
              SizedBox(width: 8),
              Expanded(child: Text('שיבוץ באירוע נוסף באותו יום')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$memberName משובץ/ת גם באירועים:',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              ...otherEvents.map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${event.name} — '
                    '${app_date_utils.DateUtils.formatDate(event.startDate)}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:close:sameDayAssignmentDialog');
                Navigator.of(dialogContext).pop();
              },
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd shavtzak && flutter test test/presentation/widgets/same_day_assignment_mark_test.dart
```

Expected: PASS — `+3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/widgets/same_day_assignment_mark.dart shavtzak/test/presentation/widgets/same_day_assignment_mark_test.dart
git commit -m "feat(assignments): SameDayAssignmentMark widget"
```

---

### Task 6: Show the mark in the `שיבוצים` grid (`/admin/assignments`)

**Files:**
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart` (`_buildAssignmentCell` at `:2701`, `_buildOffQuotaRow` at `:1429`)

**Interfaces:**
- Consumes: `SameDayAssignmentMark` (Task 5), `AssignmentSlot.sameDayOtherEvents` (Task 3).

- [ ] **Step 1: Import the widget**

In `assignment_list_screen.dart`, alongside the other `../../widgets/...` imports, add:

```dart
import '../../widgets/same_day_assignment_mark.dart';
```

- [ ] **Step 2: Add the mark to the quota row's assignment cell**

In `_buildAssignmentCell`, the returned `Row` currently ends like this (`:2699-2721`):

```dart
        ),

        const SizedBox(width: 4),

        // "ניקוי" button - only show if slot is filled AND currentMember is valid
        if (slot.isFilled && currentMember != null)
          IconButton(
```

Insert the mark between the `SizedBox` and the `ניקוי` button:

```dart
        ),

        const SizedBox(width: 4),

        // Same-day double-booking mark — this person is also assigned to
        // another event sharing a day with this one.
        if (slot.isFilled && slot.sameDayOtherEvents.isNotEmpty) ...[
          SameDayAssignmentMark(
            otherEvents: slot.sameDayOtherEvents,
            memberName: currentMember?.name ??
                slot.currentAssignment?.teamMemberName ??
                '',
          ),
          const SizedBox(width: 4),
        ],

        // "ניקוי" button - only show if slot is filled AND currentMember is valid
        if (slot.isFilled && currentMember != null)
          IconButton(
```

- [ ] **Step 3: Add the mark to the off-quota row**

In `_buildOffQuotaRow`, replace the member-name `Text` (`:1429-1431`):

```dart
                  Text(memberName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13)),
```

with a row that can carry the mark:

```dart
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(memberName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      if (slot.sameDayOtherEvents.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        SameDayAssignmentMark(
                          otherEvents: slot.sameDayOtherEvents,
                          memberName: memberName,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
```

- [ ] **Step 4: Analyze and run the full suite**

```bash
cd shavtzak && flutter analyze && flutter test
```

Expected: no NEW analyze issues; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart
git commit -m "feat(assignments): show the same-day mark in the שיבוצים grid"
```

---

### Task 7: Show the mark in the `מסך מנהלים` per-event assignments popup

`EventSummaryTile` already receives every non-deactivated event and every assignment from `SummaryScreen` (via `CategorySummaryCard`, which passes them straight through). It computes the map for its own event and hands it to the dialog.

**Files:**
- Modify: `shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart` (both constructors; `_buildAssignmentRow` at `:745-753`)
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart` (`:97-110`)

**Interfaces:**
- Consumes: `SameDayAssignmentMark` (Task 5), `sameDayOtherEventsByMember` (Task 1).
- Produces: `EventAssignmentsDialog(..., Map<String, List<Event>> sameDayOtherEventsByMemberId = const {})` on both constructors. (Named `...ByMemberId`, not `...ByMember`, so it cannot be mistaken for the top-level function of that name from Task 1.)

- [ ] **Step 1: Add the parameter to `EventAssignmentsDialog`**

In `event_assignments_dialog.dart`, add the import alongside the other `../../../widgets/...` import:

```dart
import '../../../widgets/same_day_assignment_mark.dart';
```

Add the field after `final List<Assignment>? assignments;` (`:30`):

```dart
  final List<Assignment>? assignments; // Optional: if provided, skip loading

  /// memberId -> other events sharing a calendar day with this event that the
  /// member is also assigned to, sorted by start date then name. Empty map =
  /// no marks: the BLoC-loading constructor path has no cross-event data, so
  /// only callers that hold every event and assignment can supply this.
  final Map<String, List<Event>> sameDayOtherEventsByMemberId;
```

Add the default to the main constructor:

```dart
  const EventAssignmentsDialog({
    super.key,
    this.event,
    this.eventId,
    this.eventName,
    this.assignments,
    this.sameDayOtherEventsByMemberId = const {},
  }) : assert(
```

and to the `.withAssignments` constructor:

```dart
  const EventAssignmentsDialog.withAssignments({
    super.key,
    this.event,
    this.eventId,
    this.eventName,
    required this.assignments,
    this.sameDayOtherEventsByMemberId = const {},
  })  : assert(assignments != null,
```

- [ ] **Step 2: Render the mark in `_buildAssignmentRow`**

In `_buildAssignmentRow`, the name row currently reads (`:745-753`):

```dart
              Expanded(
                child: Text(
                  member.name,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if ((member.phoneNumber != null &&
```

Insert the mark between the name and the phone block:

```dart
              Expanded(
                child: Text(
                  member.name,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if ((widget.sameDayOtherEventsByMemberId[member.id] ?? const [])
                  .isNotEmpty) ...[
                SameDayAssignmentMark(
                  otherEvents: widget.sameDayOtherEventsByMemberId[member.id]!,
                  memberName: member.name,
                ),
                const SizedBox(width: 8),
              ],
              if ((member.phoneNumber != null &&
```

- [ ] **Step 3: Compute and pass the map from `EventSummaryTile`**

In `event_summary_tile.dart`, the `צפה בשיבוצים` button's `onPressed` currently reads (`:97-110`):

```dart
              onPressed: () {
                Logger.action('open:eventAssignmentsDialog', {'eventId': data.event.id});
                // Filter assignments for this event from the already-loaded list
                final eventAssignments = allAssignments
                    .where((a) => a.eventId == data.event.id)
                    .toList();
                showDialog(
                  context: context,
                  builder: (context) => EventAssignmentsDialog.withAssignments(
                    event: data.event,
                    assignments: eventAssignments,
                  ),
                );
              },
```

Replace it with:

```dart
              onPressed: () {
                Logger.action('open:eventAssignmentsDialog', {'eventId': data.event.id});
                // Filter assignments for this event from the already-loaded list
                final eventAssignments = allAssignments
                    .where((a) => a.eventId == data.event.id)
                    .toList();
                // allEvents / allAssignments are every non-deactivated event and
                // every assignment, so the mark sees the member's real calendar
                // — not just this event's roster.
                final sameDayOtherEvents = sameDayOtherEventsByMember(
                  event: data.event,
                  allEvents: allEvents,
                  allAssignments: allAssignments,
                );
                showDialog(
                  context: context,
                  builder: (context) => EventAssignmentsDialog.withAssignments(
                    event: data.event,
                    assignments: eventAssignments,
                    sameDayOtherEventsByMemberId: sameDayOtherEvents,
                  ),
                );
              },
```

The `same_day_assignments.dart` import was already added in Task 2.

- [ ] **Step 4: Analyze and run the full suite**

```bash
cd shavtzak && flutter analyze && flutter test
```

Expected: no NEW analyze issues; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart
git commit -m "feat(assignments): show the same-day mark in the מסך מנהלים event popup"
```

---

### Task 8: Mark double-booked people in the `לפי אירוע` Excel export

> **⚠️ SUPERSEDED after the branch was finished (commit `55c8eb5`).** This task's
> `allEventsData` option — an "other events" pool of ALL events including ones that had
> already ended — was **removed** at Omer's request. The export was naming a conflict
> the two UI screens do not, and he wanted parity. The pool is now the same
> `futureEventsData` the exported rows are built from, so a conflict on a day that has
> already passed is never marked, anywhere. **Do not re-apply this task's
> `allEventsData` steps.** The living record is the spec's "Event pool parity across all
> three surfaces" section; the code below is kept only as the execution history.

The name cell becomes `יוסי כהן (משובץ גם במופע ערב)`. Nothing else in the sheet changes, so the Google Apps Script — which hard-codes the 10-column layout — needs no update.

**Files:**
- Modify: `functions/src/drive_export.ts`
- Test: `functions/src/drive_export.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks (this is the TypeScript mirror of the same rule).
- Produces: `AssignmentOnlySerializeOptions` gains `allEventsData: Record<string, Record<string, unknown>>`; `__testSerializeAssignmentsOnly` is unchanged in signature (it already takes the unfiltered `eventsData`).

- [ ] **Step 1: Write the failing tests**

Append to `functions/src/drive_export.test.ts`:

```ts
test('per-event export suffixes a member who is booked in another event the same day', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a3', data: {eventId: 'summer', teamMemberId: 'm2', roleType: 'medic'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      evening: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן', m2: 'דנה לוי'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    // Only 'summer' is exported — the mark still names the event that is NOT
    // in the file, because it describes the person's real calendar.
    selectedEventIds: ['summer'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), [
    'דנה לוי',
    'יוסי כהן (משובץ גם במופע ערב)',
  ]);
});

test('per-event export comma-joins several same-day events, sorted by date then name', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'anchor', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'later', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a3', data: {eventId: 'sooner', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      anchor: {
        name: 'עוגן',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-14T00:00:00.000Z'),
      },
      later: {
        name: 'טקס',
        startDate: new Date('2026-07-14T00:00:00.000Z'),
        endDate: new Date('2026-07-14T00:00:00.000Z'),
      },
      sooner: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['anchor'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), [
    'יוסי כהן (משובץ גם במופע ערב, טקס)',
  ]);
});

test('per-event export does not suffix when the other event is on a different day', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'nextDay', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      nextDay: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-13T00:00:00.000Z'),
        endDate: new Date('2026-07-13T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['summer'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), ['יוסי כהן']);
});

test('per-event export never counts a deactivated event as the other event', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'onHold', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      onHold: {
        name: 'אירוע מוקפא',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
        isDeactivated: true,
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['summer'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), ['יוסי כהן']);
});

test('per-event export lists the other event once when the member holds two roles in it', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a3', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'commander'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      evening: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש', commander: 'מפקד אירוע'},
    roleSortOrders: {medic: 0, commander: 1},
    mode: 'perEvent',
    selectedEventIds: ['summer'],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), [
    'יוסי כהן (משובץ גם במופע ערב)',
  ]);
});

test('per-person export never suffixes the member name', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a1', data: {eventId: 'summer', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a2', data: {eventId: 'evening', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      summer: {
        name: 'אירוע קיץ',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
      evening: {
        name: 'מופע ערב',
        startDate: new Date('2026-07-12T00:00:00.000Z'),
        endDate: new Date('2026-07-12T00:00:00.000Z'),
      },
    },
    memberNames: {m1: 'יוסי כהן'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perPerson',
    selectedEventIds: [],
    now: new Date('2026-07-01T12:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), ['יוסי כהן', 'יוסי כהן']);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd functions && npm test
```

Expected: FAIL — the new tests report the plain name (e.g. `'יוסי כהן'`) where `'יוסי כהן (משובץ גם במופע ערב)'` was expected. The six pre-existing tests still pass.

- [ ] **Step 3: Implement in `drive_export.ts`**

Add `allEventsData` to the options type (`:783-787`):

```ts
type AssignmentOnlySerializeOptions = {
  mode: AssignmentExportMode;
  selectedEventIds: string[];
  roleSortOrders: Record<string, number>;
  /**
   * EVERY event, past ones included — the pool for "assigned elsewhere that
   * day". Deliberately not the future-filtered set used for rows: the mark
   * describes the person's real calendar, not what the admin happened to
   * export. Deactivated events are filtered out here.
   */
  allEventsData: Record<string, Record<string, unknown>>;
};
```

Add `teamMemberId` to the row type (`:789-803`), after `teamMember`:

```ts
type AssignmentOnlyRow = {
  teamMember: string;
  teamMemberId: string;
  roleKey: string;
  ...
```

Add these three helpers immediately above `serializeAssignmentsOnly` (`:805`):

```ts
function eventDayRange(eventData: Record<string, unknown>): [string, string] | null {
  const start = parseDate(eventData['startDate']);
  const end = parseDate(eventData['endDate']);
  if (start == null || end == null) return null;
  const startKey = israelCalendarDateKey(start);
  const endKey = israelCalendarDateKey(end);
  if (startKey.length === 0 || endKey.length === 0) return null;
  return [startKey, endKey];
}

/** Day-precision overlap. Date keys are 'YYYY-MM-DD', so string order is date order. */
function eventsShareDay(
  first: Record<string, unknown>,
  second: Record<string, unknown>,
): boolean {
  const a = eventDayRange(first);
  const b = eventDayRange(second);
  if (a == null || b == null) return false;
  return a[0] <= b[1] && b[0] <= a[1];
}

/**
 * memberId -> eventId -> names of the OTHER events sharing a calendar day with
 * that event to which the member is also assigned, sorted by start date then
 * name. Deactivated events never count as the other event.
 *
 * Symmetric by construction: if a member is in E and O on a shared day, the map
 * names O under E *and* E under O.
 */
function buildSameDayOtherEventNames(
  assignments: FirestoreDoc[],
  allEventsData: Record<string, Record<string, unknown>>,
): Map<string, Map<string, string[]>> {
  const eventIdsByMember = new Map<string, Set<string>>();
  for (const doc of assignments) {
    const memberId = asString(doc.data['teamMemberId']);
    const eventId = asString(doc.data['eventId']);
    if (memberId.length === 0 || eventId.length === 0) continue;
    const eventData = allEventsData[eventId];
    if (eventData == null || eventData['isDeactivated'] === true) continue;
    const ids = eventIdsByMember.get(memberId) ?? new Set<string>();
    ids.add(eventId);
    eventIdsByMember.set(memberId, ids);
  }

  const result = new Map<string, Map<string, string[]>>();
  for (const [memberId, eventIdSet] of eventIdsByMember) {
    const eventIds = Array.from(eventIdSet);
    if (eventIds.length < 2) continue;

    const perEvent = new Map<string, string[]>();
    for (const eventId of eventIds) {
      const others = eventIds
        .filter(
          (otherId) =>
            otherId !== eventId &&
            eventsShareDay(allEventsData[eventId], allEventsData[otherId]),
        )
        .sort((first, second) => {
          const byDate = (eventDayRange(allEventsData[first])?.[0] ?? '').localeCompare(
            eventDayRange(allEventsData[second])?.[0] ?? '',
          );
          if (byDate !== 0) return byDate;
          return asString(allEventsData[first]['name']).localeCompare(
            asString(allEventsData[second]['name']),
          );
        })
        .map((otherId) => asString(allEventsData[otherId]['name']));
      if (others.length > 0) perEvent.set(eventId, others);
    }
    if (perEvent.size > 0) result.set(memberId, perEvent);
  }
  return result;
}

function decorateTeamMemberName(
  row: AssignmentOnlyRow,
  sameDayOtherEventNames: Map<string, Map<string, string[]>>,
): string {
  const others = sameDayOtherEventNames.get(row.teamMemberId)?.get(row.eventId);
  if (others == null || others.length === 0) return row.teamMember;
  return `${row.teamMember} (משובץ גם ב${others.join(', ')})`;
}
```

In `serializeAssignmentsOnly`, populate `teamMemberId` in the row builder (`:854-868`):

```ts
      const roleKey = asString(doc.data['roleType']);
      return {
        teamMember: memberNames[asString(doc.data['teamMemberId'])] ?? '',
        teamMemberId: asString(doc.data['teamMemberId']),
        roleKey,
```

Then, after the `rows.sort(...)` block and immediately before the `return {`, add:

```ts
  // perEvent only: the boss asked for the mark in the לפי אירוע export.
  const sameDayOtherEventNames =
    options.mode === 'perEvent'
      ? buildSameDayOtherEventNames(assignments, options.allEventsData)
      : new Map<string, Map<string, string[]>>();
```

and change the projection's first column from `row.teamMember` to the decorated name:

```ts
  return {
    sheetName: 'שיבוצים',
    headers,
    // The suffix is applied HERE, not on the row object: the perEvent sort
    // tiebreaks on `teamMember`, and perPerson's colorByTeamMember groups rows
    // by column A. Both must see the clean name.
    rows: rows.map((row) => [
      decorateTeamMemberName(row, sameDayOtherEventNames),
      row.roleType,
      row.event,
      row.eventStartDate,
      row.eventEndDate,
      row.assemblyTime,
      row.eventStartTime,
      row.eventEndTime,
      row.location,
      row.notes,
    ]),
    colorByTeamMember: options.mode === 'perPerson',
  };
```

Pass the new option from `exportProductionDataToSheets` (`:1082-1086`):

```ts
    const sheets = [
      serializeAssignmentsOnly(assignments, futureEventsData, memberNames, roleHebrewNames, {
        mode: options.assignmentMode ?? 'perPerson',
        selectedEventIds: options.eventIds ?? [],
        roleSortOrders,
        allEventsData: eventsData,
      }),
    ];
```

And from the test hook `__testSerializeAssignmentsOnly` (`:1190-1194`):

```ts
    {
      mode: input.mode,
      selectedEventIds: input.selectedEventIds,
      roleSortOrders: input.roleSortOrders,
      allEventsData: input.eventsData,
    },
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd functions && npm test
```

Expected: PASS — all pre-existing tests plus the six new ones.

- [ ] **Step 5: Commit**

```bash
git add functions/src/drive_export.ts functions/src/drive_export.test.ts
git commit -m "feat(export): mark same-day double-booked people in the לפי אירוע export"
```

---

### Task 9: Full verification, hand-off, and deploy

**Files:** none (verification only).

- [ ] **Step 1: Run every check**

```bash
cd shavtzak && flutter analyze && flutter test
cd ../functions && npm test
```

Expected: analyze still reports 108 issues (baseline, zero new); Flutter tests >= 208 passing; Functions tests >= 54 passing. **Paste the actual output** — do not claim success without it.

- [ ] **Step 2: Confirm nothing outside the feature was committed**

```bash
git status --short
```

Expected: exactly the four pre-existing dirty entries and nothing else:

```
 M functions/src/calendar_integration.ts
 M functions/src/calendar_sync_backend.ts
 M functions/src/index.ts
?? Google_Calendar_Problem.txt
```

If anything else is dirty or was committed, stop and report.

- [ ] **Step 3: Review the diff**

```bash
git log --oneline main..HEAD
git diff main...HEAD --stat
```

- [ ] **Step 4: Hand Omer the manual smoke list**

The app is not run by the implementer (per `CLAUDE.md`). Report these steps for Omer to run in `/test`:

1. Assign one person to two events on the same date (use "שבץ בכל זאת" in the "בעלי מגבלות / לא זמינים" dialog for the second one).
2. `/admin/assignments` — an orange 🗓 mark appears **on both** rows. Tap each: the dialog names the *other* event.
3. Also give that person a second role in one of the events — both marks now show on the same row (⚠ in the role column, 🗓 next to the person) and each opens its own dialog.
4. `מסך מנהלים` → 👥 `צפה בשיבוצים` on each event — the mark appears next to that person in both popups.
5. Deactivate one of the two events — the mark disappears from the other.
6. `ייצוא שיבוצים` → `לפי אירוע` → select **only one** of the two events → the sheet's `שם חבר צוות` cell reads `<name> (משובץ גם ב<other event>)`. Then `לפי אדם` → no suffix anywhere.

- [ ] **Step 5: Deploy**

Flutter (surfaces 1 & 2) ships **automatically** on merge to `main` — `web.yml` builds and deploys to GitHub Pages. Nothing to run.

The export (surface 3) is a Cloud Function and does **not** auto-deploy. After merging:

```bash
cd functions && firebase deploy --only functions
```

The Google Apps Script needs **no change** — the mark rides inside the existing `שם חבר צוות` column.

---

## Notes for the implementer

- **Do not `git add -A`.** Omer has uncommitted calendar work in `functions/src/`. Every task lists the exact paths to stage.
- **Do not run the app.** Verification is `flutter analyze` + `flutter test` + `npm test`. Omer smoke-tests.
- If `flutter analyze` shows an issue you did not introduce, leave it — the baseline is 108 pre-existing issues.

### Two deliberate deviations from the spec's testing section

The spec called for an `assignment_bloc` test and for widget tests of the mark *embedded in* the grid and the dialog. Both would need mockito codegen (`@GenerateMocks` + `build_runner`) or heavy repository/BLoC scaffolding.

Instead, the logic those tests would have covered was **extracted into pure units and tested there**: `assignment_slot_annotations_test.dart` (Task 3) asserts exactly the two behaviours the BLoC test was for — a filled slot gets `sameDayOtherEvents`, and the double-assignment pass no longer drops `sameDayAssignedMembers` — and `same_day_assignment_mark_test.dart` (Task 5) asserts the mark's whole rendering contract.

What that leaves unverified by automation: the ~15 lines of *wiring* (Task 4's two `annotate…` calls, and the `if (…) SameDayAssignmentMark(…)` in each of the three render sites). Those are covered by `flutter analyze` and by Omer's smoke list in Task 9 — step 2 in particular would fail loudly if the BLoC were wired to the wrong event list.
