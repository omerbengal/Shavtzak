# Past-Event Assignment Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins export assignments for events that have already happened, in לפי אירוע (perEvent) mode only.

**Architecture:** The backend keeps its future-only event pool as the default and *exempts* the explicitly-selected event IDs from it, producing two maps — a `rowPool` (future ∪ selected past) that rows are built from, and an `annotationPool` (future only) that the "משובץ גם ב" double-booking mark is computed over. The client loads all non-deactivated events, splits them into future/past, shows past ones in a collapsed section, and unblocks past dates in the range picker by rendering them gray-but-selectable.

**Tech Stack:** Flutter Web (Dart 3.6, `flutter_bloc`, `calendar_date_picker2`), Firebase Cloud Functions (TypeScript, `node --test`), Firestore.

**Spec:** `docs/superpowers/specs/2026-08-13-past-event-export-design.md`

## Global Constraints

- Worktree: `/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/feat-past-event-export`, branch `worktree-feat-past-event-export`. Run everything from there.
- All Flutter commands run from the `shavtzak/` subdirectory. All Functions commands run from `functions/`.
- UI text is Hebrew; code comments are English. Screens are RTL.
- **perPerson (לפי אדם) behavior must not change.** It exports all future events with no date selection; its description string stays `ייצוא כל השיבוצים של אירועים עתידיים`.
- Deactivated (`isDeactivated: true`) events stay excluded from exports, past and future, on both client and backend.
- The double-booking mark (`משובץ גם ב…`) stays computed over **future events only**. Past rows never carry it.
- Select-all label, exact copy: `בחר את כל האירועים העתידיים המסוננים כרגע`. Cleared state stays `בטל בחירה`.
- Past section header copy: `אירועים שעברו`.
- `flutter analyze` has ~107 pre-existing infos. "Clean" means **zero new** infos, not zero.
- No lower bound on how far back past events go; the picker's existing null-`minDate` fallback (3 years) is the bound.

---

### Task 1: `splitEventsByPast` pure helper

Extracts the future/past boundary out of the widget so it can be tested at all — there is no widget test for the export dialog.

**Files:**
- Modify: `shavtzak/lib/core/utils/event_filter_utils.dart` (append; file is 74 lines)
- Test: `shavtzak/test/core/utils/event_filter_utils_test.dart` (append a new `group`, reuse the existing `_event` helper at the bottom of the file)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `({List<Event> future, List<Event> past}) splitEventsByPast(List<Event> events, DateTime today)`. `future` is ascending by (startDate, startTime, name); `past` is newest-first by startDate then name. An event whose `endDate` is *on* `today` counts as future. Callers are responsible for excluding deactivated events before calling.

- [ ] **Step 1: Write the failing tests**

Append to `shavtzak/test/core/utils/event_filter_utils_test.dart`, immediately before the final `}` that closes `void main()`:

```dart
  group('splitEventsByPast', () {
    final today = DateTime(2026, 8, 13);

    test('event ending today is future, event ending yesterday is past', () {
      final result = splitEventsByPast([
        _event(id: 'ends-today', start: DateTime(2026, 8, 13)),
        _event(id: 'ended-yesterday', start: DateTime(2026, 8, 12)),
      ], today);

      expect(result.future.map((e) => e.id), ['ends-today']);
      expect(result.past.map((e) => e.id), ['ended-yesterday']);
    });

    test('multi-day event spanning today is future', () {
      final result = splitEventsByPast([
        _event(
          id: 'spans',
          start: DateTime(2026, 8, 10),
          end: DateTime(2026, 8, 15),
        ),
      ], today);

      expect(result.future.map((e) => e.id), ['spans']);
      expect(result.past, isEmpty);
    });

    test('future list is ascending by date', () {
      final result = splitEventsByPast([
        _event(id: 'later', start: DateTime(2026, 9, 1)),
        _event(id: 'sooner', start: DateTime(2026, 8, 20)),
      ], today);

      expect(result.future.map((e) => e.id), ['sooner', 'later']);
    });

    test('past list is newest-first', () {
      final result = splitEventsByPast([
        _event(id: 'older', start: DateTime(2026, 7, 1)),
        _event(id: 'newer', start: DateTime(2026, 8, 1)),
      ], today);

      expect(result.past.map((e) => e.id), ['newer', 'older']);
    });

    test('same-day future events tie-break on start time then name', () {
      final result = splitEventsByPast([
        _event(id: 'b', start: DateTime(2026, 8, 20), name: 'ב'),
        _event(id: 'a', start: DateTime(2026, 8, 20), name: 'א'),
      ], today);

      expect(result.future.map((e) => e.id), ['a', 'b']);
    });

    test('empty input yields two empty lists', () {
      final result = splitEventsByPast(const [], today);

      expect(result.future, isEmpty);
      expect(result.past, isEmpty);
    });
  });
```

Note: `_event` defaults `startTime` to `'18:00'` for every event, so the same-day test tie-breaks on `name`, which is what it asserts.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd shavtzak && flutter test test/core/utils/event_filter_utils_test.dart
```

Expected: compile failure — `The function 'splitEventsByPast' isn't defined`.

- [ ] **Step 3: Implement the helper**

Append to `shavtzak/lib/core/utils/event_filter_utils.dart`, above the existing private `_dateOnly` at the bottom:

```dart
/// Split [events] into events that have not finished yet and events that are
/// over, relative to [today].
///
/// An event whose `endDate` falls on [today] counts as future — it is still
/// happening. `future` is ordered ascending (start date, then start time, then
/// name) to match the export list; `past` is ordered newest-first, because the
/// most recent history is what an admin reaches for.
///
/// Callers must exclude deactivated events before calling: this helper is
/// purely about dates.
({List<Event> future, List<Event> past}) splitEventsByPast(
  List<Event> events,
  DateTime today,
) {
  final todayDate = _dateOnly(today);
  final future = <Event>[];
  final past = <Event>[];

  for (final event in events) {
    if (_dateOnly(event.endDate).isBefore(todayDate)) {
      past.add(event);
    } else {
      future.add(event);
    }
  }

  future.sort((a, b) {
    final dateCompare = _dateOnly(a.startDate).compareTo(_dateOnly(b.startDate));
    if (dateCompare != 0) return dateCompare;
    final timeCompare = a.startTime.compareTo(b.startTime);
    if (timeCompare != 0) return timeCompare;
    return a.name.compareTo(b.name);
  });

  past.sort((a, b) {
    final dateCompare = _dateOnly(b.startDate).compareTo(_dateOnly(a.startDate));
    if (dateCompare != 0) return dateCompare;
    return a.name.compareTo(b.name);
  });

  return (future: future, past: past);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd shavtzak && flutter test test/core/utils/event_filter_utils_test.dart
```

Expected: PASS, all tests in the file.

- [ ] **Step 5: Confirm no new analyzer output**

```bash
cd shavtzak && flutter analyze lib/core/utils/event_filter_utils.dart
```

Expected: no issues for this file.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/core/utils/event_filter_utils.dart shavtzak/test/core/utils/event_filter_utils_test.dart
git commit -m "feat(export): add splitEventsByPast helper

Extracts the future/past boundary into a pure, tested function ahead of
past-event export support."
```

---

### Task 2: Backend two-pool split

The heart of the change. Everything else is UI on top of this.

**Files:**
- Modify: `functions/src/drive_export.ts` (`AssignmentOnlySerializeOptions` at :783, `filterFutureEventsData` at :167, `serializeAssignmentsOnly` at :905 and its annotation call at ~:1014, `exportProductionDataToSheets` at ~:1192, `__testSerializeAssignmentsOnly` at ~:1288)
- Modify: `functions/src/index.ts:6422` (one string)
- Test: `functions/src/drive_export.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `buildExportEventPools(eventsData, now, mode, selectedEventIds) → {rowPool, annotationPool}` (module-private). `AssignmentOnlySerializeOptions` gains a required `annotationEventsData: Record<string, Record<string, unknown>>` field. `__testSerializeAssignmentsOnly`'s input shape is unchanged, so existing tests keep compiling.

**Critical detail — the `mode` parameter is load-bearing.** `shouldIncludeEvent` (`drive_export.ts:934-938`) returns `true` unconditionally in `perPerson` mode, so the pool is the *only* thing scoping לפי אדם. If `buildExportEventPools` widened the pool regardless of mode, a `perPerson` request that happened to carry `eventIds` would export every past assignment ever recorded. Widening is gated on `perEvent`.

- [ ] **Step 1: Update the existing invalid-IDs test, which now asserts the wrong thing**

In `functions/src/drive_export.test.ts`, the test `per-event assignments export rejects selected past or nonexistent event IDs` selects `['future', 'past', 'missing', 'past']` and expects `past` to be rejected. Under this change `past` becomes *valid*. Replace that whole test with:

```ts
test('per-event assignments export rejects nonexistent event IDs', () => {
  let error: unknown;
  try {
    __testSerializeAssignmentsOnly({
      assignments: [
        {id: 'future-assignment', data: {eventId: 'future', teamMemberId: 'm1', roleType: 'medic'}},
      ],
      eventsData: {
        future: {name: 'Future', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z')},
      },
      memberNames: {m1: 'אדם אחד'},
      roleHebrewNames: {medic: 'חובש'},
      roleSortOrders: {medic: 0},
      mode: 'perEvent',
      selectedEventIds: ['future', 'missing', 'missing'],
      now: new Date('2026-05-03T00:00:00.000Z'),
    });
  } catch (caughtError) {
    error = caughtError;
  }

  assert.ok(error instanceof DriveExportValidationError);
  assert.equal(error.message, 'Selected event IDs are invalid: missing');
});

test('per-event assignments export rejects a selected deactivated event', () => {
  let error: unknown;
  try {
    __testSerializeAssignmentsOnly({
      assignments: [
        {id: 'a1', data: {eventId: 'held', teamMemberId: 'm1', roleType: 'medic'}},
      ],
      eventsData: {
        held: {
          name: 'On Hold',
          startDate: new Date('2026-05-01T00:00:00.000Z'),
          endDate: new Date('2026-05-01T00:00:00.000Z'),
          isDeactivated: true,
        },
      },
      memberNames: {m1: 'אדם אחד'},
      roleHebrewNames: {medic: 'חובש'},
      roleSortOrders: {medic: 0},
      mode: 'perEvent',
      selectedEventIds: ['held'],
      now: new Date('2026-05-03T00:00:00.000Z'),
    });
  } catch (caughtError) {
    error = caughtError;
  }

  assert.ok(error instanceof DriveExportValidationError);
  assert.equal(error.message, 'Selected event IDs are invalid: held');
});
```

- [ ] **Step 2: Write the new failing tests**

Append to `functions/src/drive_export.test.ts`:

```ts
test('per-event assignments export includes an explicitly selected past event', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a-past', data: {eventId: 'past', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a-future', data: {eventId: 'future', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      past: {name: 'Past', startDate: new Date('2026-05-01T00:00:00.000Z'), endDate: new Date('2026-05-01T00:00:00.000Z')},
      future: {name: 'Future', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z')},
    },
    memberNames: {m1: 'אדם אחד'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['past'],
    now: new Date('2026-05-03T00:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[2]), ['Past']);
});

test('per-person assignments export still excludes past events even when eventIds are sent', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'a-past', data: {eventId: 'past', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'a-future', data: {eventId: 'future', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      past: {name: 'Past', startDate: new Date('2026-05-01T00:00:00.000Z'), endDate: new Date('2026-05-01T00:00:00.000Z')},
      future: {name: 'Future', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z')},
    },
    memberNames: {m1: 'אדם אחד'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perPerson',
    selectedEventIds: ['past'],
    now: new Date('2026-05-03T00:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[2]), ['Future']);
});

test('past rows never carry the same-day double-booking mark', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'p1', data: {eventId: 'past-a', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'p2', data: {eventId: 'past-b', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      'past-a': {name: 'Past A', startDate: new Date('2026-05-01T00:00:00.000Z'), endDate: new Date('2026-05-01T00:00:00.000Z')},
      'past-b': {name: 'Past B', startDate: new Date('2026-05-01T00:00:00.000Z'), endDate: new Date('2026-05-01T00:00:00.000Z')},
    },
    memberNames: {m1: 'אדם אחד'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['past-a', 'past-b'],
    now: new Date('2026-05-03T00:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), ['אדם אחד', 'אדם אחד']);
});

test('future rows still carry the same-day mark when a past event is also exported', () => {
  const sheet = __testSerializeAssignmentsOnly({
    assignments: [
      {id: 'f1', data: {eventId: 'future-a', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'f2', data: {eventId: 'future-b', teamMemberId: 'm1', roleType: 'medic'}},
      {id: 'p1', data: {eventId: 'past', teamMemberId: 'm1', roleType: 'medic'}},
    ],
    eventsData: {
      'future-a': {name: 'Future A', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z')},
      'future-b': {name: 'Future B', startDate: new Date('2026-05-04T00:00:00.000Z'), endDate: new Date('2026-05-04T00:00:00.000Z')},
      past: {name: 'Past', startDate: new Date('2026-05-01T00:00:00.000Z'), endDate: new Date('2026-05-01T00:00:00.000Z')},
    },
    memberNames: {m1: 'אדם אחד'},
    roleHebrewNames: {medic: 'חובש'},
    roleSortOrders: {medic: 0},
    mode: 'perEvent',
    selectedEventIds: ['future-a', 'future-b', 'past'],
    now: new Date('2026-05-03T00:00:00.000Z'),
  });

  assert.deepEqual(sheet.rows.map((row) => row[0]), [
    'אדם אחד (משובץ גם בFuture B)',
    'אדם אחד (משובץ גם בFuture A)',
    'אדם אחד',
  ]);
});
```

The last test also pins the perEvent sort: both future rows sort before the past row is irrelevant here — rows sort by date ascending, so `Past` (05-01) actually comes **first**. Verify the produced order when you run it; if the run shows `['אדם אחד', 'אדם אחד (משובץ גם בFuture B)', 'אדם אחד (משובץ גם בFuture A)']`, that is the correct expectation and the assertion above should be reordered to match. Do not change the implementation to satisfy the guessed order — the date-ascending sort is existing, tested behavior.

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd functions && npm test
```

Expected: the two rewritten tests fail on the message (`Selected future event IDs are invalid: …` vs expected `Selected event IDs are invalid: …`), and `per-event assignments export includes an explicitly selected past event` fails because `past` is rejected as invalid.

- [ ] **Step 4: Add the pool builder**

In `functions/src/drive_export.ts`, directly below the existing `filterFutureEventsData` (ends at :177), add:

```ts
type ExportEventPools = {
  /** Events rows may be built from: future events plus selected past ones. */
  rowPool: Record<string, Record<string, unknown>>;
  /** Events the same-day double-booking mark is computed over: future only. */
  annotationPool: Record<string, Record<string, unknown>>;
};

/**
 * Build the two event pools an assignments export needs.
 *
 * `annotationPool` is the historical future-only pool, unchanged. `rowPool`
 * adds back any explicitly selected past event so admins can export history.
 *
 * Widening is gated on perEvent deliberately. `shouldIncludeEvent` returns true
 * for every event in perPerson mode, so the pool is the ONLY thing scoping that
 * export — widening it there would turn "all future assignments" into "every
 * assignment ever recorded".
 *
 * Deactivated events are never added back, so an explicit selection cannot
 * resurrect one; it still fails validation downstream.
 */
function buildExportEventPools(
  eventsData: Record<string, Record<string, unknown>>,
  now: Date,
  mode: AssignmentExportMode,
  selectedEventIds: string[],
): ExportEventPools {
  const annotationPool = filterFutureEventsData(eventsData, now);
  if (mode !== 'perEvent') {
    return {rowPool: annotationPool, annotationPool};
  }

  const rowPool = {...annotationPool};
  for (const eventId of selectedEventIds) {
    if (rowPool[eventId] != null) continue;
    const eventData = eventsData[eventId];
    if (eventData == null || eventData['isDeactivated'] === true) continue;
    rowPool[eventId] = eventData;
  }
  return {rowPool, annotationPool};
}
```

- [ ] **Step 5: Thread the annotation pool through the serializer**

Change `AssignmentOnlySerializeOptions` (`:783`) to:

```ts
type AssignmentOnlySerializeOptions = {
  mode: AssignmentExportMode;
  selectedEventIds: string[];
  roleSortOrders: Record<string, number>;
  /**
   * Future-only pool the "משובץ גם ב" mark is computed over. Kept separate from
   * the row pool so exported PAST rows never carry the mark, matching
   * /admin/assignments and /summary which never flag past-day conflicts.
   */
  annotationEventsData: Record<string, Record<string, unknown>>;
};
```

Change the annotation call inside `serializeAssignmentsOnly` (~:1014) from `buildSameDayOtherEventNames(assignments, eventsData)` to:

```ts
  // perEvent only: the boss asked for the mark in the לפי אירוע export.
  const sameDayOtherEventNames =
    options.mode === 'perEvent'
      ? buildSameDayOtherEventNames(assignments, options.annotationEventsData)
      : new Map<string, Map<string, string[]>>();
```

Update the block comment above `buildSameDayOtherEventNames` (`:826-846`) — it currently says `eventsData` is "the future-filtered pool ... the same set the export's own rows are built from". That second clause is now false. Replace that sentence with:

```
 * `eventsData` here is the ANNOTATION pool — future events only. It is
 * deliberately NOT the row pool: a perEvent export may contain explicitly
 * selected past events, and those rows must never be marked, for parity with
 * `/admin/assignments` and `/summary`, which never flag a conflict on a day
 * that has already passed.
```

Leave the rest of the block comment (the `isDeactivated` belt-and-braces note and the symmetry note) intact.

- [ ] **Step 6: Wire the production call site**

In `exportProductionDataToSheets` (~:1190), replace:

```ts
    const futureEventsData = filterFutureEventsData(eventsData, options.now ?? new Date());
```

with:

```ts
    const assignmentMode = options.assignmentMode ?? 'perPerson';
    const selectedEventIds = options.eventIds ?? [];
    const {rowPool, annotationPool} = buildExportEventPools(
      eventsData,
      options.now ?? new Date(),
      assignmentMode,
      selectedEventIds,
    );
```

and replace the `serializeAssignmentsOnly` call below it with:

```ts
      serializeAssignmentsOnly(assignments, rowPool, memberNames, roleHebrewNames, {
        mode: assignmentMode,
        selectedEventIds,
        roleSortOrders,
        annotationEventsData: annotationPool,
      }),
```

- [ ] **Step 7: Wire the test harness**

Replace the body of `__testSerializeAssignmentsOnly` (~:1297):

```ts
  const {rowPool, annotationPool} = buildExportEventPools(
    input.eventsData,
    input.now,
    input.mode,
    input.selectedEventIds,
  );
  return serializeAssignmentsOnly(
    input.assignments,
    rowPool,
    input.memberNames,
    input.roleHebrewNames,
    {
      mode: input.mode,
      selectedEventIds: input.selectedEventIds,
      roleSortOrders: input.roleSortOrders,
      annotationEventsData: annotationPool,
    },
  ) as {sheetName: string; headers: string[]; rows: unknown[][]};
```

- [ ] **Step 8: Reword the two "future" strings**

In `drive_export.ts` (~:925), change the thrown message to:

```ts
        `Selected event IDs are invalid: ${invalidEventIds.join(', ')}`,
```

In `functions/src/index.ts:6422`, change:

```ts
      throw new HttpError(400, 'Select at least one event to export');
```

- [ ] **Step 9: Run the full backend suite**

```bash
cd functions && npm test
```

Expected: PASS, including every pre-existing test. If `future rows still carry the same-day mark…` fails purely on row order, reorder the expectation to match the actual date-ascending output (see Step 2's note) and re-run.

- [ ] **Step 10: Commit**

```bash
git add functions/src/drive_export.ts functions/src/drive_export.test.ts functions/src/index.ts
git commit -m "feat(export): allow explicitly selected past events in perEvent export

Splits the export event pool in two: rows build from future events plus the
past events an admin actually selected, while the same-day double-booking
mark still computes over future events only.

Widening is gated on perEvent because shouldIncludeEvent returns true for
every event in perPerson mode, where the pool is the only scoping mechanism."
```

---

### Task 3: `dimBeforeDate` on the date picker

**Files:**
- Modify: `shavtzak/lib/presentation/widgets/date_picker_dialog.dart` (params ~:24-40, `dayBuilder` ~:291-321)

**Interfaces:**
- Consumes: nothing.
- Produces: `DualCalendarDatePicker` gains `final DateTime? dimBeforeDate;` as a named constructor param, defaulting to `null` (no dimming). Days before it render with grey text but stay selectable.

**No automated test.** No widget test exists for this picker, and the spec accepts that gap — the dimming rule is verified visually in Task 6. Do not add a widget-test harness here; that is a separate piece of work.

- [ ] **Step 1: Add the parameter**

After the existing `minDate` field (~:24), add:

```dart
  /// Days strictly before this date render dimmed but remain fully selectable.
  /// Null disables dimming. Distinct from [minDate], which BLOCKS earlier days.
  final DateTime? dimBeforeDate;
```

and add `this.dimBeforeDate,` to the constructor's named parameter list, directly after `this.minDate,`.

- [ ] **Step 2: Dim in the day builder**

In `dayBuilder`, after the existing `isHighlighted` line, add:

```dart
                          final dimBefore = widget.dimBeforeDate;
                          // Selected days already sit on a filled background;
                          // dimming those would read as a rendering bug.
                          final isDimmed = dimBefore != null &&
                              normalized.isBefore(_normalizeDate(dimBefore)) &&
                              isSelected != true;
```

and change the `Text` style from `style: textStyle` to:

```dart
                                style: isDimmed
                                    ? (textStyle ?? const TextStyle())
                                        .copyWith(color: Colors.grey.shade500)
                                    : textStyle,
```

Leave `decoration`, the highlight frame, and `selectableDayPredicate` untouched — dimmed days must stay clickable.

- [ ] **Step 3: Verify it compiles clean**

```bash
cd shavtzak && flutter analyze lib/presentation/widgets/date_picker_dialog.dart
```

Expected: no new issues.

- [ ] **Step 4: Confirm no existing caller changed behavior**

```bash
cd shavtzak && rg -n "DualCalendarDatePicker\(" lib | wc -l
cd shavtzak && flutter test
```

Expected: every existing call site omits `dimBeforeDate`, so all of them keep `null` and render exactly as before. Full suite still passes.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/widgets/date_picker_dialog.dart
git commit -m "feat(date-picker): add dimBeforeDate for gray-but-selectable past days

Unlike minDate, which blocks earlier days outright, dimBeforeDate only
changes their text color. Selected days are never dimmed."
```

---

### Task 4: Export dialog loads past events and the range picker accepts them

After this task the range picker can select past events, though they are not yet individually visible in the list.

**Files:**
- Modify: `shavtzak/lib/presentation/widgets/assignment_export_dialog.dart` (state fields ~:32, `initState` ~:49, `_loadFutureEvents` :79-110, `_pickDateRange` :226-249)

**Interfaces:**
- Consumes: `splitEventsByPast` (Task 1), `dimBeforeDate` (Task 3).
- Produces: `_pastEvents` state field and a `_allSelectableEvents` getter, both used by Task 5.

- [ ] **Step 1: Add the past-events state**

Next to `List<Event> _futureEvents = [];` (~:32) add:

```dart
  List<Event> _pastEvents = [];
```

and below the existing fields add the getter:

```dart
  /// Every event an admin may tick, future first then past. Deactivated events
  /// are already excluded by the loader.
  List<Event> get _allSelectableEvents => [..._futureEvents, ..._pastEvents];
```

- [ ] **Step 2: Load and split both lists**

Rename `_loadFutureEvents` to `_loadEvents` (update the `initState` call at ~:49 too) and replace its body's filtering/sorting block so the method reads:

```dart
  Future<void> _loadEvents() async {
    try {
      final events = await context.read<EventRepository>().getAllEvents();
      // Deactivated ("on hold") events are excluded from exports on the
      // backend, so they must not be selectable here — otherwise selecting
      // one fails validation ("Selected event IDs are invalid").
      final selectable =
          events.where((event) => !event.isDeactivated).toList();
      final split = splitEventsByPast(selectable, DateTime.now());

      if (!mounted) return;
      setState(() {
        _futureEvents = split.future;
        _pastEvents = split.past;
        _isLoadingEvents = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _isLoadingEvents = false;
      });
    }
  }
```

Add the import if it is not already present:

```dart
import '../../core/utils/event_filter_utils.dart';
```

(It is already imported for `filterEventsBySearchAndCategory`; confirm rather than duplicate.)

If `_dateOnly` becomes unused after this edit, delete it — `flutter analyze` will flag it otherwise.

- [ ] **Step 3: Let the range picker reach the past**

Replace the doc comment and body of `_pickDateRange` (:226-249):

```dart
  /// Pick a date range and add every event overlapping it to the export
  /// selection (union — existing picks are kept). Operates on all selectable
  /// events, past and future, independent of the active search/category filter.
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectable = _allSelectableEvents;
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (_) => DualCalendarDatePicker(
        isSingleDate: false,
        title: 'בחירת אירועים לפי טווח תאריכים',
        // No minDate: past dates are selectable. They render dimmed instead.
        dimBeforeDate: today,
        highlightedDates: eventCoverageDays(selectable),
      ),
    );
    if (result == null || result['startDate'] == null) return;
    final start = result['startDate']!;
    final end = result['endDate'] ?? start;
    final idsInRange = eventIdsInDateRange(selectable, start, end);
    if (!mounted) return;
    if (idsInRange.isNotEmpty) {
      setState(() => _selectedEventIds.addAll(idsInRange));
    }
  }
```

- [ ] **Step 4: Verify it analyzes clean**

```bash
cd shavtzak && flutter analyze lib/presentation/widgets/assignment_export_dialog.dart
```

Expected: no new issues. In particular no "unused element `_dateOnly`" and no unused-import warning.

- [ ] **Step 5: Run the full Flutter suite**

```bash
cd shavtzak && flutter test
```

Expected: PASS (486-plus tests).

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/widgets/assignment_export_dialog.dart
git commit -m "feat(export): load past events and unblock them in the range picker

The picker no longer sets minDate; past days render dimmed via dimBeforeDate
and stay selectable. Range selection and event-day highlighting now span all
selectable events."
```

---

### Task 5: Collapsed past-events section and copy changes

**Files:**
- Modify: `shavtzak/lib/presentation/widgets/assignment_export_dialog.dart` (`_buildPerEventContent` :251-400ish, including the empty state, the select-all row, and the events list)

**Interfaces:**
- Consumes: `_pastEvents`, `_allSelectableEvents` (Task 4).
- Produces: final UI. Nothing downstream depends on it.

- [ ] **Step 1: Add the expansion state and a second scroll controller**

Next to `_eventsScrollController` (~:42) add:

```dart
  final ScrollController _pastEventsScrollController = ScrollController();
  bool _isPastExpanded = false;
```

and dispose it alongside the existing controller in `dispose()`:

```dart
    _pastEventsScrollController.dispose();
```

- [ ] **Step 2: Generalize the two "עתידיים" strings**

In `_buildPerEventContent`, change the error text from `'שגיאה בטעינת אירועים עתידיים:\n$_loadError'` to:

```dart
        'שגיאה בטעינת אירועים:\n$_loadError',
```

and change the empty-state guard from `if (_futureEvents.isEmpty)` / `'אין אירועים עתידיים לייצוא'` to:

```dart
    if (_futureEvents.isEmpty && _pastEvents.isEmpty) {
      return const Text(
        'אין אירועים לייצוא',
        key: ValueKey('events-empty'),
      );
    }
```

Leave the perPerson description (`ייצוא כל השיבוצים של אירועים עתידיים…`) exactly as it is — that mode really is future-only.

- [ ] **Step 3: Rework the select-all row**

The new label is much longer than `בחר הכל` and would overflow the current `Row` (button + `Spacer` + counter). Replace that `Row` with:

```dart
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: filteredEvents.isEmpty
                    ? null
                    : () {
                        Logger.action('tap:selectAllExportEvents', {
                          'allSelected': allFilteredSelected,
                          'count': filteredIds.length,
                        });
                        setState(() {
                          if (allFilteredSelected) {
                            _selectedEventIds.removeAll(filteredIds);
                          } else {
                            _selectedEventIds.addAll(filteredIds);
                          }
                        });
                      },
                icon: Icon(
                  allFilteredSelected ? Icons.remove_done : Icons.done_all,
                  size: 20,
                ),
                label: Text(
                  allFilteredSelected
                      ? 'בטל בחירה'
                      : 'בחר את כל האירועים העתידיים המסוננים כרגע',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'נבחרו ${_selectedEventIds.length} מתוך ${_allSelectableEvents.length}',
              textAlign: TextAlign.end,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
```

`filteredEvents` / `filteredIds` / `allFilteredSelected` keep deriving from `_futureEvents` only — this toggle stays future-only by design, so a collapsed section can never silently add past events to the selection. Only the counter's denominator widens.

- [ ] **Step 4: Extract the event row so both lists share it**

Add a method that builds one checkbox row, lifted verbatim from the existing `itemBuilder` body:

```dart
  Widget _buildEventTile(Event event) {
    final isSelected = _selectedEventIds.contains(event.id);
    return CheckboxListTile(
      value: isSelected,
      title: Text(event.name),
      subtitle: Text(_formatEventSubtitle(event)),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (value) {
        Logger.action('toggle:selectExportEvent', {
          'eventId': event.id,
          'on': value == true,
        });
        setState(() {
          if (value == true) {
            _selectedEventIds.add(event.id);
          } else {
            _selectedEventIds.remove(event.id);
          }
        });
      },
    );
  }
```

Then replace the existing future `ListView.builder`'s `itemBuilder` body with `itemBuilder: (context, index) => _buildEventTile(filteredEvents[index]),`.

Check the existing `itemBuilder` before deleting it — if it carries any property not shown above, preserve it in `_buildEventTile` rather than dropping it.

- [ ] **Step 5: Add the collapsed past section**

Directly after the future list's `ConstrainedBox`, inside the same `Column`, add:

```dart
        if (filteredPastEvents.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              Logger.action('toggle:pastExportEventsSection',
                  {'on': !_isPastExpanded});
              setState(() => _isPastExpanded = !_isPastExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'אירועים שעברו (${filteredPastEvents.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(_isPastExpanded
                      ? Icons.expand_less
                      : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_isPastExpanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: Scrollbar(
                controller: _pastEventsScrollController,
                child: ListView.builder(
                  controller: _pastEventsScrollController,
                  shrinkWrap: true,
                  itemCount: filteredPastEvents.length,
                  itemBuilder: (context, index) =>
                      _buildEventTile(filteredPastEvents[index]),
                ),
              ),
            ),
        ],
```

and define `filteredPastEvents` next to the existing `filteredEvents` computation at the top of `_buildPerEventContent`:

```dart
    final filteredPastEvents = filterEventsBySearchAndCategory(
      _pastEvents,
      query: _searchQuery,
      categoryIds: _selectedCategoryIds,
    );
```

The search and category filter therefore apply to both lists, and the section header count reflects the filter.

- [ ] **Step 6: Verify it analyzes clean**

```bash
cd shavtzak && flutter analyze lib/presentation/widgets/assignment_export_dialog.dart
```

Expected: no new issues.

- [ ] **Step 7: Run the full Flutter suite**

```bash
cd shavtzak && flutter test
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add shavtzak/lib/presentation/widgets/assignment_export_dialog.dart
git commit -m "feat(export): collapsed past-events section in the per-event list

Past events are selectable individually, filtered by the same search and
category bar. The select-all toggle stays future-only and says so."
```

---

### Task 6: Full verification and deploy

**Files:** none modified. This task is a gate.

- [ ] **Step 1: Full analyzer sweep, compared against baseline**

```bash
cd shavtzak && flutter analyze 2>&1 | tail -5
```

Expected: the pre-existing ~107 infos, and **zero new** ones. If the count rose, find and fix the new entries before continuing.

- [ ] **Step 2: Full test suites**

```bash
cd shavtzak && flutter test
cd functions && npm test
```

Expected: both PASS.

- [ ] **Step 3: Deploy Functions FIRST**

```bash
firebase deploy --only functions:api
```

This must happen **before** local client testing. A local `flutter run` calls the deployed `api` function (`backend_api_service.dart` hardcodes `us-central1-<project>.cloudfunctions.net`, and there is no emulators block), so until this runs the backend rejects every past event ID and the feature looks broken from your machine.

Deploying ahead of the UI is safe: with no past IDs in the request, `rowPool` equals the old future-only pool and `annotationPool` is unchanged, so every existing export behaves identically.

- [ ] **Step 4: Manual smoke test against production**

```bash
cd shavtzak && flutter run -d chrome --web-hostname localhost --web-port 8080
```

Go to the admin home → ייצוא שיבוצים → לפי אירוע, and confirm:

1. The dialog opens looking as it did before, with `אירועים שעברו (N)` collapsed at the bottom.
2. Expanding it lists past events newest-first; ticking one updates `נבחרו X מתוך Y`.
3. Typing in the search box filters both lists, and the section header count follows.
4. The select-all button reads `בחר את כל האירועים העתידיים המסוננים כרגע`, fits without overflowing, and does **not** select anything in the past section.
5. In `בחירה לפי טווח תאריכים`: past days are gray, still clickable, and days holding events still show the red frame. Selecting a past range adds those events to the selection.
6. Exporting a past-only selection produces a spreadsheet whose rows are the past assignments, with **no** `(משובץ גם ב…)` marks on them.
7. Switching to לפי אדם and exporting still yields future events only.

- [ ] **Step 5: Merge**

```bash
git checkout main && git merge worktree-feat-past-event-export
git push
```

Flutter web auto-builds and deploys via `web.yml`. Allow roughly 5 minutes commit-to-live plus browser cache; a stale-looking site is not a failed deploy.

---

## Self-Review

**Spec coverage:** Backend two-pool split → Task 2. `dimBeforeDate` → Task 3. Client load/split → Task 4. Collapsed section, select-all label, generalized strings, counter denominator → Task 5. `splitEventsByPast` → Task 1. Testing section → Tasks 1, 2, 6. Deployment ordering → Task 6. Every spec section maps to a task.

**Deliberate spec deviation:** the spec's decision table says the past section gets "its own select-all". That is dropped. It conflicts with the later instruction to keep selection future-only, adds a second toggle whose semantics ("select all filtered past") duplicate what the range picker already does better, and YAGNI applies. Raise it if you disagree — it is one small addition to Task 5.

**Placeholder scan:** clean. Every code step carries real code; no TBD/TODO; no "similar to Task N".

**Type consistency:** `splitEventsByPast` returns `({List<Event> future, List<Event> past})` and is consumed as `split.future` / `split.past` in Task 4. `buildExportEventPools(eventsData, now, mode, selectedEventIds)` is called with that exact arity in Task 2 Steps 6 and 7. `annotationEventsData` is the field name in the type, the production call site, and the test harness. `dimBeforeDate` is the param name in Task 3 and the call site in Task 4.

**Known uncertainty flagged in-plan:** the expected row order in `future rows still carry the same-day mark…` (Task 2, Step 2) is a prediction about existing sort behavior; the step tells the implementer to trust the actual output over the guess rather than bend the implementation.
