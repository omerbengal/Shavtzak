# Custom Hours per Assignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An admin can give one member's assignment in one event its own start
and end. The member's ICS feed, every screen that shows the assignment, and
every conflict check follow those hours.

**Architecture:**
- **Two fields per assignment.** Each assignment document gains optional
  `customStartAt` and `customEndAt`: Israel wall-clock strings
  `yyyy-MM-ddTHH:mm`.
- **One window rule, on both sides.** An assignment's window is its custom
  hours, or else the event stretch. It lives next to Project 1's
  `eventStretch`, in `event_stretch.dart` and `event_stretch.ts`, and is pinned
  by the shared case table.
- **Backend first.** It stores, validates and enforces the hours: the
  shared-hours rule, `event.update` resolutions, the ICS feed and the Drive
  export. It stays backward-compatible, so it can deploy ahead of the client.
- **Then the client.** Hours are set through the staged notes dialog. The
  client shows them everywhere, and resolves them when an event's times change,
  when an event is duplicated, and when a slot is filled or replaced.

**Tech Stack:** Flutter Web (BLoC, Equatable, Hebrew RTL), Firebase Cloud Functions (TypeScript, `node:test`), Firestore.

**Spec:** `docs/superpowers/specs/2026-10-26-assignment-custom-hours-design.md`.
Its last section, "Revisions after Project 1 (2026-10-27)", **overrides** the
text above it. Read both before starting.

## Global Constraints

- **Running commands.** Run Flutter from `shavtzak/` and Functions from
  `functions/`.
  - Flutter tests: `flutter test`. Analyze: `flutter analyze`. The baseline is
    113 infos; no new ones are allowed.
  - Functions: `npm test`. Fresh worktrees need `npm ci` and `flutter pub get`
    first.
- **Never run the app.** Do not run `flutter run` or a browser. The user tests
  manually.
- **Storage format.** Custom hours are stored as the `formatWallMoment` output:
  `yyyy-MM-ddTHH:mm`, zero-padded, on the Israel wall clock.
  - Both keys are present or both are absent.
  - The end must be strictly after the start.
- **Absent versus null on the wire.**
  - The new client always sends both keys, with `null` meaning "no hours".
  - On an update, an **absent** key keeps the stored value, and an explicit
    `null` clears it.
  - On a create, an absent key means none, or the member's inherited hours
    (spec revision 15).
- **Readers never throw on bad stored hours.** Hours that can't be read, or
  whose end is not after the start, fall back to the event stretch.
- **Hebrew copy is quoted exactly where the spec quotes it.** Gendered forms
  use the app's "/" style (מגיע/ה, עוזב/ת).
- **Every screen is RTL** (`Directionality(textDirection: TextDirection.rtl)`).
- **No new icon or badge on the admin assignment row.** Hours appear as text
  only.
- **Equatable rule.** New fields go into `props`, `copyWith`, `withRelations`
  and every hand-built `Assignment(...)`. Nullable fields use the existing
  `String? Function()?` sentinel in `copyWith`.
- **Real-time.** Displays read from the existing `watchX` streams. Never gate a
  first paint on an awaited one-shot `getX()`. When a single read is needed,
  use `watchAssignmentsByEvent(id).first` with a 10 s timeout.
- **Pending constraints block** exactly like approved ones (Project 1).
  Warnings label each constraint's status.
- **Backward compatibility.**
  - An old client sends no hours and no `customHoursResolutions`, and must
    behave exactly as today.
  - `event.update` from an old client must still succeed when no assignment in
    the event has hours.
- **Mocks.** When the `DatabaseInterface` changes, update every implementation
  and mock: `FirestoreDatabase`, `LoggingDatabase`, and the mockito mocks. If
  you regenerate mocks with build_runner, check `git status`. It once deleted
  unrelated generated mocks; restore any you didn't mean to touch.
- **Commits.** Commit after each task's tests pass, with a conventional-commit
  message ending in the two trailer lines:

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01HgbF1exAEFFKyGoeHaL1Ru
  ```

## Review Focus

1. **An old client's update must not erase hours.** An `assignment.update` or
   `saveBatch` update without the two keys keeps the stored hours. Pinned in
   Task 2.
2. **DST change weeks.** Israel's DST ends on 2026-10-25. Shifting hours by
   days, and computing the days a window touches, must not drift by an hour
   across it. Pinned in Task 1 (Dart and TS shift helpers) and Task 5
   (`assignmentDays`).
3. **An end at exactly 00:00.** `27.10 18:00 → 28.10 00:00` touches only 27.10
   for same-day booking. Pinned in Task 5 (Dart) and Task 3 (Drive export).
4. **A member with several roles in one event.**
   - Hours set on one role are staged on every role.
   - Replacing the member in one role leaves the others consistent.
   - The backend refuses a batch that splits them.

   Pinned in Task 2 (backend), Task 7 (staging) and Task 11 (replace).
5. **A stale persisted staged cache.** A cache written before this feature,
   with no hour keys, rehydrates as "hours unchanged" and is not dirty. Pinned
   in Task 6.

---

## File Structure

**Backend (`functions/src/`)**
- `event_stretch.ts`: modify. Adds `parseWallMoment`, `customHoursInterval`,
  `shiftWallMoment` and `wallDayKeysTouched`.
- `assignment_hours.ts`: create, pure. Holds `HoursRow`,
  `findSharedHoursViolations`, `validateCustomHoursPair`,
  `planEventHoursResolution` and `eventTimesChanged`.
- `index.ts`: modify.
  - `assignmentDocFromJson`, `validateAssignmentPayload`,
    `memberAvailableForEvent`.
  - The insert, update, insertBatch and saveBatch actions.
  - `event.update`, the ICS feed projection, and `markEventCalendarJob`
    typing.
- `calendar_feed.ts`: modify. Adds `FeedAssignment` hours and the
  custom-hours part.
- `drive_export.ts`: modify. Two columns in `serializeAssignments`, and
  same-day by days touched.
- Tests:
  - `event_conflict_cases.test.ts`
  - `assignment_hours.test.ts` (new)
  - `assignment_custom_hours_api.test.ts` (new; pure helpers only)
  - `calendar_feed.test.ts`
  - `drive_export.test.ts`
  - `event_stretch.test.ts` (if present; else add the cases to
    `assignment_hours.test.ts`)

**Shared**
- `shared/test-fixtures/event_conflict_cases.json`: modify. Adds group L.

**Client (`shavtzak/lib/`)**
- `core/utils/event_stretch.dart`: modify. Adds a UTC assert,
  `parseWallMoment`, `customHoursInterval`, `assignmentWindow` and
  `shiftWallMoment`.
- `core/utils/constraint_labels.dart`: modify. Rejected constraints get their
  own prefix.
- `core/utils/custom_hours.dart`: create. Formatting, `calendarDaysBetween`,
  `eventTimesChanged`, warning lines and first name.
- `core/utils/same_day_assignments.dart`: modify. Adds `DayRange`,
  `eventDays`, `assignmentDays` and `dayRangesOverlap`.
- `domain/entities/team_member.dart`: modify. Adds the window parameter and
  `constraintsBlockingWindow`.
- `domain/entities/assignment.dart` and `data/models/assignment_model.dart`:
  modify. Adds the fields and the window getters.
- `domain/entities/custom_hours_resolution.dart`: create.
- `presentation/widgets/custom_hours_fields.dart`: create. Two rows, each a
  date and a time.
- `presentation/widgets/custom_hours_conflict_dialog.dart`: create. A
  confirm-anyway dialog that lists the warning lines.
- `presentation/screens/event/widgets/custom_hours_resolve_dialog.dart`: create.
- `presentation/screens/assignment/widgets/replacement_hours_dialog.dart`: create.
- Modified across tasks:
  - bloc: assignment and event;
  - staged change model;
  - the screens and dialogs named in each task.

---

### Task 1: The window rule, both sides, with shared cases

**Files:**
- Modify: `shavtzak/lib/core/utils/event_stretch.dart`
- Modify: `functions/src/event_stretch.ts`
- Modify: `shavtzak/lib/domain/entities/team_member.dart` (`isAvailableForEventWithTime`, `constraintsBlockingEvent`)
- Modify: `functions/src/index.ts` (`memberAvailableForEvent`, and its `__test` export)
- Modify: `shavtzak/lib/core/utils/constraint_labels.dart`
- Modify: `shared/test-fixtures/event_conflict_cases.json`
- Test: `shavtzak/test/domain/event_conflict_cases_test.dart`, `functions/src/event_conflict_cases.test.ts`, `shavtzak/test/core/utils/event_stretch_test.dart`, `shavtzak/test/core/utils/constraint_labels_test.dart` (create if missing), `functions/src/assignment_hours.test.ts` (create; the TS helper cases)

**Interfaces:**
- Produces (Dart, `event_stretch.dart`):
  - `DateTime? parseWallMoment(String? value)`. Strict
    `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$`, a real calendar date (round-trips
    through `DateTime.utc`), hours 0–23 and minutes 0–59. It returns a
    `DateTime.utc` holding the wall fields, or null. It never throws.
  - `WallInterval? customHoursInterval(String? customStartAt, String? customEndAt)`.
    Non-null only when both parse and the end is after the start.
  - `WallInterval assignmentWindow(Event event, {String? customStartAt, String? customEndAt})`
    returns `customHoursInterval(...) ?? eventStretch(event)`.
  - `String? shiftWallMoment(String? value, int days)` shifts by whole
    calendar days with the clock unchanged. It returns null when the value is
    unreadable.
  - `WallInterval`'s constructor asserts `start.isUtc && end.isUtc`.
- Produces (Dart, `team_member.dart`):
  - `List<DateConstraint> constraintsBlockingWindow(WallInterval window)`.
    Permanent members only; `[]` otherwise.
  - `constraintsBlockingEvent(Event event)` becomes
    `constraintsBlockingWindow(eventStretch(event))`.
  - `bool isAvailableForEventWithTime(Event event, {WallInterval? window})`.
    For a permanent member, a null `window` means the event stretch. The
    non-permanent path ignores `window` (spec §4: `availableEventIds` stays
    available).
- Produces (TS, `event_stretch.ts`):
  - `parseWallMoment(value: unknown): number | null`, in minutes on the wall
    clock, using the same rule as Dart.
  - `customHoursInterval(start: unknown, end: unknown): WallInterval | null`.
  - `shiftWallMoment(value: string, days: number): string | null`.
  - `wallDayKeysTouched(interval: WallInterval): [string, string]`. These are
    `yyyy-MM-dd` keys from the start's day to the day of `end - 1` minute.
- Produces (TS, `index.ts`):
  - `memberAvailableForEvent(memberData, eventData, window?: WallInterval | null)`.
    For a permanent member, a null or absent window means
    `eventStretchFromData(eventData)`.
- Produces (Dart, `constraint_labels.dart`): `constraintStatusLabel` uses the
  prefix `'אילוץ שנדחה: '` for a rejected constraint.

- [ ] **Step 1: Add group L to the shared table.**
  - Optional per-case field: `"customHours": {"start": "...", "end": "..."}`.
  - Update the `about` string to mention it.
  - Every L case uses the base event: `startDate` 2026-12-01, `endDate`
    2026-12-02, assembly 17:00, start 19:00, end 20:30, team end 22:00.
  - The member is permanent, active and not archived, unless the case says
    otherwise.
  - A constraint is approved unavailability unless the case says otherwise.

| id | customHours start → end | constraint(s) | expectedAvailable |
|---|---|---|---|
| L1 | 2026-12-01T17:00 → 2026-12-01T23:30 | 2026-12-02 all day | true |
| L2 | 2026-11-30T19:00 → 2026-12-02T22:00 | 2026-11-30 18:00–20:00 | false |
| L3 | 2026-12-01T17:00 → 2026-12-01T20:00 | 2026-12-01 20:00–23:00 | true |
| L4 | 2026-12-01T17:00 → 2026-12-02T02:00 | 2026-12-02 01:00–03:00 | false |
| L5 | 2026-12-01T17:00 → 2026-12-01T23:00 | 2026-12-01 21:00–22:00, **pending** | false |
| L6 | 2026-12-01T17:00 → 2026-12-01T23:00 | 2026-12-01 21:00–22:00, **rejected** | true |
| L7 | 2026-11-30T19:00 → 2026-12-01T22:00 | weekly, repeatDay 1, 18:00–21:00, start 2026-11-01, repeatEndDate 2026-12-31 | false |
| L8 | 2026-11-29T08:00 → 2026-11-29T10:00 | member non-permanent, `availableEventIds: ["evt"]`, no constraints | true |
| L9 | `"2026-12-01 17:00"` (space) → 2026-12-01T23:00 | 2026-12-02 all day | false (unreadable → event stretch) |
| L10 | 2026-12-01T23:00 → 2026-12-01T17:00 | 2026-12-02 all day | false (end before start → event stretch) |
| L11 | 2026-12-05T10:00 → 2026-12-05T12:00 | 2026-12-01 all day | true |
| L12 | 2026-12-05T10:00 → 2026-12-05T12:00 | 2026-12-05 11:00–11:30 | false |

- [ ] **Step 2: Make both runners pass the window.**
  - Dart:
    `isAvailableForEventWithTime(event, window: assignmentWindow(event, customStartAt: c.start, customEndAt: c.end))`.
  - TS:
    `memberAvailableForEvent(member, event, customHoursInterval(c.start, c.end))`.
  - A case with no `customHours` passes no window.
  - Keep the existing "at least 60 cases" and "unique ids" asserts.
  - Run both and expect the L cases to fail before the implementation.
    - Dart: `cd shavtzak && flutter test test/domain/event_conflict_cases_test.dart`
    - TS: `cd functions && npm test`

- [ ] **Step 3: Write the helper unit tests.**
  - Dart, `event_stretch_test.dart`:
    - `parseWallMoment`:
      - `'2026-10-25T01:30'` gives `DateTime.utc(2026,10,25,1,30)`.
      - These give null: `'2026-02-30T10:00'`, `'2026-10-25T24:00'`,
        `'2026-10-25T9:00'`, `''`, `null`.
    - `customHoursInterval`:
      - null when either value is null;
      - null when start equals end.
    - `shiftWallMoment('2026-10-24T22:00', 2)` gives `'2026-10-26T22:00'`. This
      crosses the DST change of 2026-10-25.
    - `shiftWallMoment('2026-12-01T17:00', -1)` gives `'2026-11-30T17:00'`.
    - Constructing a `WallInterval` from non-UTC values throws an
      `AssertionError`.
  - TS, `assignment_hours.test.ts`:
    - the same parse cases;
    - the same shift across 2026-10-25;
    - `wallDayKeysTouched` of 2026-10-27T18:00 → 2026-10-28T00:00 gives
      `['2026-10-27','2026-10-27']`;
    - `wallDayKeysTouched` of 2026-10-27T18:00 → 2026-10-28T00:01 gives
      `['2026-10-27','2026-10-28']`.
  - Dart, `constraint_labels_test.dart`: a rejected one-day constraint on 28.10
    gives `'אילוץ שנדחה: 28.10 (כל היום)'`.

- [ ] **Step 4: Implement** the Interfaces above. In `team_member.dart` and
  `index.ts`, update the doc comments: "the window is the assignment's custom
  hours when set (see `assignmentWindow`)".

- [ ] **Step 5: Run everything.**
  - `cd shavtzak && flutter test && flutter analyze` (no new infos).
  - `cd functions && npm test`.
  - All pass.

- [ ] **Step 6: Commit.** Use `feat(conflicts): an assignment's window — custom hours or the event stretch`.

---

### Task 2: Backend storage, validation and the shared-hours rule

**Files:**
- Create: `functions/src/assignment_hours.ts` (pure)
- Modify: `functions/src/index.ts`:
  - `assignmentDocFromJson` (~2942)
  - `validateAssignmentPayload` (~3481)
  - the actions `assignment.insert` (~4530), `assignment.update` (~4555),
    `assignment.insertBatch` (~4859) and `assignment.saveBatch` (~4899)
  - the saveBatch live projection (~4963–5000)
- Modify: `functions/src/drive_export.ts`, `serializeAssignments` (~542): append
  headers `customStartAt` and `customEndAt`, with the values or `''`.
- Test: `functions/src/assignment_hours.test.ts`, `functions/src/assignment_custom_hours_api.test.ts`, `functions/src/drive_export.test.ts`

**Interfaces:**
- Consumes: `customHoursInterval` and `parseWallMoment` (Task 1).
- Produces (`assignment_hours.ts`):
  - `interface HoursRow { id: string; eventId: string; teamMemberId: string; customStartAt: string | null; customEndAt: string | null }`
  - `validateCustomHoursPair(start: unknown, end: unknown): 'none' | 'ok' | 'incomplete' | 'order'`
    - `'none'`: both values are null or undefined.
    - `'ok'`: both parse and the end is after the start.
    - `'incomplete'`: exactly one value is present, or either one is
      unreadable.
    - `'order'`: the end is not after the start.
  - `findSharedHoursViolations(rows: HoursRow[], exemptMemberIds: ReadonlySet<string>, touchedIds?: ReadonlySet<string>): Array<{ eventId: string; teamMemberId: string }>`
    - Groups the rows by (eventId, teamMemberId) and skips exempt members.
    - A group is a violation when its rows have more than one distinct
      `(customStartAt, customEndAt)` pair. Null is a value.
    - When `touchedIds` is given, only groups containing a touched row count.
  - `inheritedHours(rows: HoursRow[], eventId: string, teamMemberId: string): { customStartAt: string; customEndAt: string } | null`
    returns the hours of the first row of that member in that event that has
    valid hours.
- Produces (`index.ts`):
  - `assignmentDocFromJson` writes `customStartAt` and `customEndAt` **only
    when the key is present** in the JSON. Present `null` writes `null`; an
    absent key leaves the field out of the doc.
    - Use `'customStartAt' in assignment`. Do not use `?? null`.
    - Creates set an absent pair to `null` explicitly, after inheritance.
  - Error messages (exact):
    - `'שעות מותאמות חייבות לכלול תאריך ושעה של הגעה ושל עזיבה'` for
      `incomplete`;
    - `'שעת העזיבה חייבת להיות אחרי שעת ההגעה'` for `order`;
    - `'לחבר/ת צוות חייבות להיות אותן שעות מותאמות בכל התפקידים באירוע'` for a
      shared-hours violation.

    All of them are `HttpError(400, …)`.

- [ ] **Step 1: Write failing pure tests** in `assignment_hours.test.ts`:
  - `validateCustomHoursPair`:
    - `(null, undefined)` gives `'none'`;
    - `('2026-12-01T17:00', null)` gives `'incomplete'`;
    - `('2026-12-01T17:00', '2026-12-01T17:00')` gives `'order'`;
    - `('2026-12-01T17:00', '2026-12-02T01:00')` gives `'ok'`.
  - `findSharedHoursViolations`:
    - two rows of member m in event e, one with hours and one with null:
      one violation `{eventId:'e', teamMemberId:'m'}`;
    - the same rows with m exempt: none;
    - two rows with equal hours: none;
    - a violation group with no touched row, when `touchedIds` is given:
      none.
  - `inheritedHours`: returns the valid pair and ignores a row with
    unreadable hours.

- [ ] **Step 2: Write failing API-helper tests** in
  `assignment_custom_hours_api.test.ts`. Export `assignmentDocFromJson` as
  `__testAssignmentDocFromJson` if it isn't exported yet.
  - JSON without the keys gives a doc with neither key (`'customStartAt' in
    doc` is false).
  - Keys present with null give a doc with both keys `null`.
  - Valid strings are copied verbatim.

- [ ] **Step 3: Implement the write rules in the actions.**
  - **`validateAssignmentPayload`.**
    - Run `validateCustomHoursPair` on the payload's keys, but only for the
      keys that are present, and throw the messages above.
    - Pass `customHoursInterval(...)` as the third argument of
      `memberAvailableForEvent`.
  - **`assignment.insert` and `assignment.insertBatch`.**
    - Inside the transaction, read the event's assignments with
      `where('eventId','==',id)`. Do the same per item for the batch, and
      include the batch's own earlier items.
    - When the payload pair is `none` and the member isn't exempt
      (`allowMultipleAssignments`), copy `inheritedHours`.
    - When the payload has hours, run `findSharedHoursViolations` over live +
      new, with the new id as touched. A violation throws.
  - **`assignment.update`.** Compute the after-state of the touched row: the
    stored values, overlaid by the keys that are present. Then run the same
    violation check over the event's assignments.
  - **`assignment.saveBatch`.**
    - Extend the live projection with `customStartAt`/`customEndAt` (null when
      absent).
    - Apply deletes, then updates (present keys overlay the stored values),
      then creates.
    - Run `findSharedHoursViolations(after, exemptMemberIds, touched = create
      and update ids)` and throw on any violation.
    - `saveBatch` never inherits.
  - **`assignment.updateMetadata`** is unchanged.

- [ ] **Step 4: Add the Drive export columns.** Test in `drive_export.test.ts`:
  the full export header row ends `…,'createdAt','updatedAt','customStartAt','customEndAt'`.
  A row without hours has `''` in both cells.

- [ ] **Step 5: Run `cd functions && npm test`.** All pass, including the
  existing `assignment_save_batch.test.ts` and
  `assignment_availability_gate.test.ts`.

- [ ] **Step 6: Commit.** Use `feat(api): store and validate custom hours; one set of hours per member per event`.

---

### Task 3: ICS feed and Drive same-day by the member's days

**Files:**
- Modify: `functions/src/calendar_feed.ts`: `FeedAssignment` (~186) and
  `buildMemberFeedParts` (~232).
- Modify: `functions/src/index.ts`, the feed route's projection (~6861–6868):
  add `customStartAt` and `customEndAt`.
- Modify: `functions/src/drive_export.ts`: `eventDayRange` (~850),
  `eventsShareDay` (~865) and `buildSameDayOtherEventNames` (~894).
- Test: `functions/src/calendar_feed.test.ts`, `functions/src/drive_export.test.ts`

**Interfaces:**
- Consumes: `customHoursInterval`, `formatWallMinutes` and
  `wallDayKeysTouched` (Task 1).
- Produces:
  - `type FeedAssignment = { eventId: string; roleType: string; notes?: string; customStartAt?: string | null; customEndAt?: string | null }`.
  - Drive: an assignment's day range is `wallDayKeysTouched(custom)` when its
    hours are valid; otherwise it is the event's day keys, as today.
    `buildSameDayOtherEventNames` compares the member's range in each event.

- [ ] **Step 1: Write failing feed tests.** Use the existing `timedEvent`
  helper: assembly 17:00, start 20:00, end 23:00, dates 2026-08-15.
  - **One role with hours.** Hours `2026-08-15T14:00 → 2026-08-15T21:00`:
    - exactly one part;
    - uid `evt-1-main-mem-1@shavtzak`;
    - title is the event's main title;
    - start `'2026-08-15T14:00'`, end `'2026-08-15T21:00'`;
    - no assembly part.
  - **All-day event with hours.** An event that would be all-day (no
    assembly), with hours: one timed part, `allDayStart` null.
  - **Two roles, same hours.** One part, and the description lists both roles.
  - **Envelope.** Two assignments with different hours (an exempt member):
    one part from the earliest start to the latest end.
  - **Unreadable hours.** Hours like `'2026-08-15 14:00'`: the normal
    assembly + main pair, unchanged.

- [ ] **Step 2: Write failing Drive tests.** Run them through
  `__testSerializeAssignmentsOnly`, perEvent mode.
  - **Day 1 only.**
    - Setup:
      - member m is in event A (2026-12-01 → 2026-12-02) with hours
        `2026-12-01T17:00 → 2026-12-01T23:00`;
      - m is also in event B on 2026-12-02.
    - Expect: neither row carries the `(משובץ גם ב…)` suffix.
  - **Evening before.** Hours `2026-11-30T19:00 → 2026-12-01T23:00`, and event
    C on 2026-11-30: A's row is suffixed with C.
  - **End at 00:00.** Hours ending `2026-12-02T00:00`, against an event on
    2026-12-02: not suffixed.

- [ ] **Step 3: Implement.** In the feed, group per event:
  - collect the valid custom intervals of the member's assignments there;
  - when there are any, emit the one part (min start, max end, formatted with
    `formatWallMinutes`) and `continue`;
  - otherwise, today's code.

- [ ] **Step 4: Run `cd functions && npm test`.** All pass.

- [ ] **Step 5: Commit.** Use `feat(feed): one calendar block for custom hours; same-day export by the member's days`.

---

### Task 4: `event.update` resolutions and the 409

**Files:**
- Modify: `functions/src/assignment_hours.ts` (add the planner)
- Modify: `functions/src/index.ts`: the `event.update` admin branch
  (~4328–4359), and `markEventCalendarJob`'s writer parameter.
- Test: `functions/src/assignment_hours.test.ts`

**Interfaces:**
- Produces:
  - `eventTimesChanged(before: Record<string, unknown>, after: Record<string, unknown>): boolean`.
    - It compares the Israel day keys of `startDate` and `endDate`.
    - It also compares the trimmed strings `assemblyTime`, `startTime`,
      `actualShowStartTime`, `endTime` and `teamEndTime`. Absent is `''`.
  - `interface HoursResolution { assignmentId: string; customStartAt: string | null; customEndAt: string | null }`
  - `planEventHoursResolution(args: { timesChanged: boolean; live: HoursRow[]; resolutions: HoursResolution[]; exemptMemberIds: ReadonlySet<string> }): { ok: true; updates: HoursResolution[] } | { ok: false; reason: 'uncovered' | 'invalid' | 'shared' }`
    - `timesChanged` false: ok, with no updates. Resolutions are ignored.
    - A live row with non-null stored hours and no resolution for its id
      gives `uncovered`.
    - Resolutions for ids not in `live` are dropped.
    - Each kept resolution's pair must be `none` or `ok`, else `invalid`.
    - The after-state must pass `findSharedHoursViolations`, else `shared`.
  - Payload: `event.update` accepts an optional
    `customHoursResolutions: HoursResolution[]`. Admins only; the non-admin
    parking branch ignores it.
  - Errors:
    - `uncovered` is `HttpError(409, 'לחלק מהצוות נוספו שעות מותאמות בינתיים — יש לפתוח את האירוע מחדש')`;
    - `invalid` and `shared` are 400, with Task 2's messages.

- [ ] **Step 1: Write failing tests** for `eventTimesChanged`:
  - only `teamEndTime` changed gives true;
  - only `name` or `location` changed gives false;
  - `startDate` moved by one day gives true.

  Write failing tests for `planEventHoursResolution`:
  - times unchanged, with live hours and no resolutions: ok with no updates
    (an old client's edit of a name works);
  - times changed, with a live row with hours and no resolution: `uncovered`;
  - times changed, with a resolution for every row with hours: ok, with
    exactly those updates;
  - a resolution for a deleted id: dropped, still ok;
  - a resolution pair `('2026-12-01T17:00', null)`: `invalid`;
  - two rows of one member, where only one is resolved to new hours and the
    other also had hours: `uncovered`;
  - both rows resolved but with different hours: `shared`.

- [ ] **Step 2: Implement.**
  - **Transaction.** The admin branch runs in `db.runTransaction`:
    - read the event doc and the event's assignments;
    - read `allowMultipleAssignments` for the members that have hours;
    - plan;
    - then write the event and update each resolved assignment's two fields
      plus `updatedAt`.
  - **Calendar job.** Widen `markEventCalendarJob`'s first parameter to
    `WriteBatch | Transaction`; both have `set`/`update`.
  - **Unchanged around it.** Keep the duplicate-name check, the
    deletion-pending 409, `enqueueEventCalendarJob` and the audit log. Record
    the resolution count in the audit `after`.

- [ ] **Step 3: Run `cd functions && npm test`.** All pass.

- [ ] **Step 4: Commit.** Use `feat(api): event.update resolves custom hours atomically when its times change`.

> **Deploy checkpoint (controller).** After Task 4 the backend is complete and
> backward-compatible. The controller runs `firebase deploy --only functions`
> and verifies with `firebase functions:list` before Task 9's client work is
> handed to the user, because the client calls the deployed api. Tasks 5–11
> don't block on the deploy.

---

### Task 5: Client data plumbing and the day helpers

**Files:**
- Modify: `shavtzak/lib/domain/entities/assignment.dart`:
  - the fields;
  - the constructor;
  - `withRelations` (~104);
  - `copyWith` (~129), using the sentinel;
  - `props` (~166).
- Modify: `shavtzak/lib/data/models/assignment_model.dart`: all six
  conversions.
  - `toJson` **always** emits both keys, null included.
  - `toFirestore` writes `FieldValue.delete()` for null, like
    `alternativePhoneNumber`.
- Modify the hand-built `Assignment(...)` sites. Each carries the two fields
  through:
  - `data/repositories/assignment_repository.dart:358`
  - `presentation/screens/summary/widgets/event_summary_tile.dart:944` (a create:
    it passes null, and the backend inherits)
- Modify: `shavtzak/lib/core/utils/same_day_assignments.dart`.
- Create: `shavtzak/lib/core/utils/custom_hours.dart`.
- Test:
  - `shavtzak/test/domain/entities/assignment_custom_hours_test.dart`
  - `shavtzak/test/data/models/assignment_model_test.dart` (extend or create)
  - `shavtzak/test/core/utils/same_day_assignments_test.dart` (extend)
  - `shavtzak/test/core/utils/custom_hours_test.dart`

**Interfaces:**
- Consumes: `customHoursInterval`, `assignmentWindow`, `eventStretch` and
  `constraintsBlockingWindow` (Task 1).
- Produces (`Assignment`):
  - Fields: `final String? customStartAt; final String? customEndAt;`
  - `WallInterval? get customWindow` returns
    `customHoursInterval(customStartAt, customEndAt)`.
  - `bool get hasCustomHours` returns `customWindow != null`.
  - `WallInterval windowIn(Event event)` returns `customWindow ?? eventStretch(event)`.
  - `hasAvailabilityConflict()` judges against `windowIn(event!)`.
- Produces (`same_day_assignments.dart`):
  - `class DayRange extends Equatable { final DateTime first; final DateTime last; }`
    holds local date-only `DateTime(y,m,d)` values.
  - `DayRange eventDays(Event e)`.
  - `DayRange assignmentDays(Assignment a, Event event)`. With hours, it runs
    from the start's wall day to the wall day of `end - 1 minute`. Without
    hours, it is `eventDays`.
  - `bool dayRangesOverlap(DayRange a, DayRange b)` is inclusive and uses
    `!isAfter`, never `Duration` arithmetic on local dates.
  - `eventsShareDay(a, b)` is kept, as
    `dayRangesOverlap(eventDays(a), eventDays(b))`.
  - `sameDayOtherEventsByMember` and `buildSameDayOtherEventsIndex` keep
    their signatures. They judge the member's days in `event` (the union over
    their assignments there) against the member's assignment days in each
    other event.
- Produces (`custom_hours.dart`):
  - `String formatCustomHours(WallInterval w)`:
    - `'27.10 14:00 – 28.10 02:00'`, or `'27.10 14:00–23:00'` when the day of
      the start equals the day of the end;
    - days are `d.M`, times `HH:mm`;
    - an end at exactly 00:00 shows as the next day's `00:00`.
  - `int calendarDaysBetween(DateTime from, DateTime to)` is a date-only
    difference via `DateTime.utc(y,m,d)`.
  - `bool eventTimesChanged(Event before, Event after)` uses the same field
    list as the TS twin (Task 4).
  - `String memberFirstName(String name)` returns the first whitespace token.
  - `List<String> customHoursWarningLines(TeamMember member, WallInterval window)`
    has one line per `constraintsBlockingWindow(window)`:
    - `'⚠️ מתנגש עם אילוץ מאושר של <first>: <constraintShortLabel>'`;
    - for a pending constraint, `'⚠️ מתנגש עם אילוץ ממתין לאישור של <first>: <label>'`.

- [ ] **Step 1: Write failing tests.**
  - **Model round-trip.**
    - `toJson` of an assignment without hours contains the keys
      `customStartAt` and `customEndAt` with null values.
    - `fromJson` and `fromFirestore` of a map without the keys give nulls.
    - Valid strings round-trip.
  - **`copyWith(customStartAt: () => null)`** clears the field. `props` differ
    when only `customEndAt` differs.
  - **`withRelations`** keeps both fields.
  - **`assignmentDays`:**
    - hours 2026-10-27T18:00 → 2026-10-28T00:00 give first = last = 27.10;
    - 2026-10-24T22:00 → 2026-10-26T02:00 give first 24.10 and last 26.10,
      across DST;
    - no hours give the event dates.
  - **`sameDayOtherEventsByMember`.**
    - Member m is in A (1–2.12) with hours on day 1 only, and in B on 2.12.
      Neither A's nor B's map names the other.
    - Without the hours, both name each other.
  - **`formatCustomHours`.**
    - `WallInterval(utc(2026,10,27,14), utc(2026,10,27,23))` gives
      `'27.10 14:00–23:00'`.
    - `WallInterval(utc(2026,10,27,14), utc(2026,10,28,2))` gives
      `'27.10 14:00 – 28.10 02:00'`.
  - **`customHoursWarningLines`.** A pending constraint inside the window, for
    member 'דנה כהן', gives
    `'⚠️ מתנגש עם אילוץ ממתין לאישור של דנה: 28.10 (כל היום)'`.

- [ ] **Step 2: Implement.** Then run `cd shavtzak && flutter test && flutter analyze`.
  All pass, with no new infos.

- [ ] **Step 3: Commit.** Use `feat(assignments): custom hours on the client entity, model and day helpers`.

---

### Task 6: Staged changes carry hours; existing-assignment checks use the window

**Files:**
- Modify:
  `shavtzak/lib/presentation/bloc/assignment/models/staged_assignment_change.dart`.
  - Adds `desiredCustomStartAt`, `desiredCustomEndAt`,
    `baselineCustomStartAt` and `baselineCustomEndAt`.
  - Updates `matchesBaseline`, `copyWith`, `toJson`, `fromJson` (missing keys
    → null) and `props`.
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart`.
  - Carry the four fields through `_seedStaged` (~1486), the manual-add
    constructor (~2029), the committed-row re-key (~1945),
    `_stagedAsPendingOperations` (~1668), `_stagedEffectiveAssignments`
    (~1710) and `_assignmentFromStaged` (~3142).
  - In `classifyStagedConflicts` (~2434), add an `hoursDiverged` check that
    joins the notes-changed conflict (type F).
  - In the slot builders (~3612, ~4083), the other-booking side uses
    `assignmentDays` for the same-day check. The candidate side keeps
    `eventDays(event)`.
- Modify: `shavtzak/lib/data/repositories/assignment_repository.dart`,
  `checkConflicts` (~228). It judges the payload assignment's
  `windowIn(event)` through `isAvailableForEventWithTime(event, window:)`.
- Modify: `shavtzak/lib/core/utils/constraint_assignment_conflicts.dart`,
  `findNewlyConflictingAssignments` (~71). Each assignment is judged by
  `windowIn(event)`.
- Modify: `shavtzak/lib/core/utils/event_constraint_collisions.dart` and its
  dialog.
  - For members assigned to the event with custom hours, judge against their
    window.
  - Feed the dialog the event's assignments via
    `watchAssignmentsByEvent(id).first`.
- Modify: `event_summary_tile.dart` (~812) and `manual_assignment_flow_dialog.dart`
  (~826). Their other-booking side uses `assignmentDays`.
- Test:
  - `shavtzak/test/presentation/bloc/assignment/staged_assignment_change_test.dart` (extend or create)
  - `shavtzak/test/data/repositories/assignment_repository_conflicts_test.dart` (extend the closest existing)
  - `shavtzak/test/core/utils/constraint_assignment_conflicts_test.dart` (extend)
  - `shavtzak/test/core/utils/event_constraint_collisions_test.dart` (extend)

**Interfaces:**
- Consumes: Task 5's `Assignment` fields, `windowIn`, `assignmentDays` and
  `eventDays`.
- Produces: `StagedAssignmentChange.copyWith(desiredCustomStartAt: String? Function()?, desiredCustomEndAt: String? Function()?)`.
  The baseline fields are set only by `_seedStaged` and `fromJson`.

- [ ] **Step 1: Write failing tests.**
  - **Old cache.** `StagedAssignmentChange.fromJson` of an old-cache map with
    no hour keys has both desired and baseline hours null, and
    `matchesBaseline` is true when the other fields match.
  - **Hours make it dirty.** Desired hours differ from baseline:
    `matchesBaseline` false. The `toJson`/`fromJson` round-trip keeps all
    four fields.
  - **`checkConflicts`.** The member has an all-day constraint on day 2 of a
    2-day event, and the assignment's hours are day 1 only: no availability
    conflict. Without hours: a conflict.
  - **`findNewlyConflictingAssignments`.** A new constraint on day 2 does not
    hit an assignment whose hours skip day 2.
  - **Collisions.** For a member assigned with day-1 hours, a day-2 constraint
    is not listed. For an unassigned member, it is listed.

- [ ] **Step 2: Implement.** Run `flutter test && flutter analyze`. All pass.

- [ ] **Step 3: Commit.** Use `feat(assignments): staged hours and window-aware checks for existing assignments`.

---

### Task 7: Setting hours in the notes dialog; the admin row line

**Files:**
- Create: `shavtzak/lib/presentation/widgets/custom_hours_fields.dart`
- Create: `shavtzak/lib/presentation/widgets/custom_hours_conflict_dialog.dart`
- Modify: `shavtzak/lib/presentation/widgets/date_picker_dialog.dart`: add
  `String? highlightLegend`. Null keeps today's text,
  `'מסגרת אדומה = יש אירוע בתאריך זה'`.
- Modify:
  `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart`.
  - `_showNotesDialog` (~1943).
  - `_buildAssignmentExtraInfo` (~1104). Its null guard includes hours.
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_event.dart`.
  `StageNotesChange` gains `String? customStartAt` and `String? customEndAt`,
  both in `props`.
- Modify: `assignment_bloc.dart`, `_upsertStagedNotes` (~1557) and
  `_onStageNotesChange` (~1812).
- Test:
  - `shavtzak/test/presentation/widgets/custom_hours_fields_test.dart`
  - `shavtzak/test/presentation/bloc/assignment/stage_custom_hours_test.dart`
  - `shavtzak/test/presentation/screens/assignment/notes_dialog_custom_hours_test.dart`
    (if the screen harness allows; otherwise test the extracted pieces)

**Interfaces:**
- Consumes: `eventStretch`, `customHoursInterval` and `formatWallMoment`
  (Task 1); `formatCustomHours`, `customHoursWarningLines` and
  `memberFirstName` (Task 5).
- Produces:
  - `CustomHoursFields({super.key, required Event event, required WallInterval initial, required ValueChanged<WallInterval?> onChanged})`.
    - It has two rows, labelled `'מגיע/ה'` and `'עוזב/ת'`. Each row is a date
      field and an `EventTimeField`.
    - The date field opens `DualCalendarDatePicker(isSingleDate: true, minDate: null, highlightedDates: {event start day, event end day}, highlightLegend: 'מסגרת = תחילת האירוע וסופו')`.
    - A hint line under the rows reads `'שעות האירוע: ' + formatCustomHours(eventStretch(event))`.
    - It emits null while any part is missing or the end is not after the
      start.
    - Inline errors: `'יש למלא תאריך ושעה'` when a part is missing, and
      `'העזיבה חייבת להיות אחרי ההגעה'` when the order is wrong.
    - Controllers are not disposed (Flutter Web use-after-dispose; follow the
      dialog's comment at ~2212).
  - `CustomHoursConflictDialog.show(BuildContext, {required List<String> lines}) → Future<bool>`.
    - Title: `'⚠️ התנגשות עם אילוצים'`.
    - One `Text` per line.
    - Buttons `'ביטול'` (false) and `'שמור בכל זאת'` (true).
- **Dialog behaviour.**
  - Under the existing fields there is a `SwitchListTile` titled
    `'שעות מותאמות ל<first name>'`.
    - It starts on when the slot's effective assignment has hours.
    - When on, it shows `CustomHoursFields`. The initial value is the
      assignment's window if set, else `eventStretch`.
  - When the member is non-exempt and holds more than one slot in this event,
    a line shows `'השעות יחולו על כל התפקידים של <first name> באירוע'`.
  - On שמור:
    - Switch on with a null value: stay open.
    - When the warning lines aren't empty, `CustomHoursConflictDialog`. A
      false keeps the dialog open.
    - Then `StageNotesChange(..., customStartAt: formatWallMoment(w.start), customEndAt: formatWallMoment(w.end))`.
      Switch off sends both null.
- **Bloc.**
  - `_upsertStagedNotes` sets this slot's desired hours.
  - Unless the member is `allowMultipleAssignments`, it also stages
    hours-only changes on every other slot whose effective occupant is the
    same member in the same event (from the current slots). Their notes,
    label and phone are kept.
  - Each change goes through `_commitStaged`, so a revert un-dirties.
- **Admin row.** The first line of `_buildAssignmentExtraInfo` is
  `Text('שעות מותאמות: ' + formatCustomHours(...))`, at fontSize 11, w600,
  `Colors.indigo.shade800`. No icon and no card.

- [ ] **Step 1: Write failing widget tests for `CustomHoursFields`.**
  - It pre-fills from `initial` and shows the hint with the event stretch.
  - Setting the end time before the start emits null and shows
    `'העזיבה חייבת להיות אחרי ההגעה'`.
  - A valid change emits the interval.

- [ ] **Step 2: Write failing bloc tests.** Use the existing
  `AssignmentBloc` test harness; build blocs inside `testWidgets`/`test`,
  not `setUp`.
  - **Siblings.** Member d fills two slots of event E. `StageNotesChange` on
    slot 1 with hours stages both slots with the same desired hours. Slot 2's
    notes are unchanged, and both keys are in `stagedSlotKeys`.
  - **Exempt member.** Only the edited slot is staged.
  - **Revert.** Staging the hours back to the baseline removes the slot from
    `stagedSlotKeys`.
  - **Save.** `SaveStagedChanges` sends updates whose `toJson` carry the
    hours. Use the mock repository's captured `saveAssignmentsBatch` args.

- [ ] **Step 3: Implement.** Run `flutter test && flutter analyze`. All pass.

- [ ] **Step 4: Commit.** Use `feat(assignments): set custom hours in the notes dialog`.

---

### Task 8: Showing hours everywhere

**Files:**
- Modify: `shavtzak/lib/presentation/screens/user/user_assignments_screen.dart`.
  - `_buildAssignmentCard` (~492) gets option B. Read the mockup
    `docs/superpowers/specs/2026-10-26-assignment-custom-hours/member-card.html`,
    option B.
- Modify: `shavtzak/lib/presentation/widgets/event_team_members_dialog.dart`
  (row ~272–391).
- Modify: `shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart`
  (`_buildAssignmentRow` ~732).
- Modify: `event_assignments_share_models.dart` and
  `event_assignments_share_data_builder.dart` (`buildRow` ~21).
- Modify: `shavtzak/lib/presentation/widgets/shamap_export_dialog.dart`,
  `_copyToClipboard` (~760).
- Test:
  - `shavtzak/test/presentation/widgets/event_team_members_dialog_test.dart` (extend)
  - `event_assignments_share_data_builder_test.dart` (extend)
  - `shavtzak/test/presentation/screens/user/user_assignments_card_hours_test.dart`
    (create; if the screen is too heavy, extract the row-building into a pure
    function `memberCardTimeRows(Event, WallInterval?)` and test that)
  - `shavtzak/test/presentation/widgets/shamap_export_lines_test.dart`
    (extract `shamapLine(TeamMember, Event, List<Assignment>, String location)`
    and test it)

**Interfaces:**
- Consumes: `Assignment.customWindow` and `windowIn`, `formatCustomHours`,
  `assignmentDays` (Task 5).
- Produces (copy is exact):
  - **Member card**, when any of the member's assignments in the event has
    hours (shared rule: take the first valid window):
    - **Date rows** show the member's days (`assignmentDays`) in today's
      single-day or multi-day format. When those differ from the event's
      days, add the event's end in brackets, `' (האירוע עד <d.M>)'`, or its
      start, `' (האירוע מ-<d.M>)'`.
    - **"שעת התייצבות:"** is replaced by
      `'ההגעה שלך: <HH:mm> (התייצבות צוות <assemblyTime>)'`. Prefix
      `<d.M> ` to the arrival when it is not on the event's first day. Drop
      the bracket when the assembly time is empty.
    - **"סיום צוות משוער:"** is replaced by
      `'היציאה שלך: <d.M HH:mm> (סיום צוות <d.M HH:mm of eventStretch end>)'`.
    - Every other row is unchanged. Upcoming/past grouping is unchanged.
  - **The other dialogs.** "מי איתי באירוע?" and the event assignments dialog
    get a line `'שעות: ' + formatCustomHours(window)`, directly above the notes
    box, with the same padding (`right: 26, top: 4`). Text only.
  - **Image export.** A member with hours gets a note number. The note text is
    `'שעות ' + formatCustomHours(window)`, then `' · ' + notes` when there are
    notes.
  - **ש.מ.פ.** Each member's start and end dates come from `assignmentDays`
    over their assignments in the event (first valid window), as
    `dd/MM/yyyy`. Without hours, it uses the event's dates, as today.

- [ ] **Step 1: Write failing tests.**
  - **Share builder.** A member with hours `27.10 14:00–23:00` and notes
    'מביא ציוד' gets note text `'שעות 27.10 14:00–23:00 · מביא ציוד'`.
  - **מי איתי.** The dialog shows `'שעות: 27.10 14:00–23:00'` for that member.
  - **ש.מ.פ.** For a 2-day event with day-1 hours, `shamapLine` has the start
    and end both on day 1.
  - **Member card rows.**
    - Event 27–28.10 with team end 23:30 and assembly 12:00; hours
      27.10 14:00 → 27.10 23:00.
    - Expect the rows to contain `'ההגעה שלך: 14:00 (התייצבות צוות 12:00)'`
      and `'היציאה שלך: 27.10 23:00 (סיום צוות 28.10 23:30)'`.

- [ ] **Step 2: Implement.** Run `flutter test && flutter analyze`. All pass.

- [ ] **Step 3: Commit.** Use `feat(assignments): show a member's custom hours on every assignment view`.

---

### Task 9: Resolving hours when an event's dates or times change

**Files:**
- Create: `shavtzak/lib/domain/entities/custom_hours_resolution.dart`.
  `class CustomHoursResolution extends Equatable { final String assignmentId; final String? customStartAt; final String? customEndAt; Map<String, dynamic> toJson(); }`
- Create: `shavtzak/lib/presentation/screens/event/widgets/custom_hours_resolve_dialog.dart`.
  Read `docs/superpowers/specs/2026-10-26-assignment-custom-hours/event-save-resolve.html`.
- Modify:
  - `DatabaseInterface.updateEvent(Event event, {List<CustomHoursResolution> customHoursResolutions = const []})`,
    together with `FirestoreDatabase`, `LoggingDatabase` and the mocks.
  - `FirestoreDatabase` sends `customHoursResolutions` in the payload only
    when the list is not empty.
- Modify: `EventRepository.updateEvent(Event, {Event? knownOriginal, List<CustomHoursResolution> customHoursResolutions = const []})`.
- Modify: `UpdateEvent` (`event_event.dart`), which gains the list (in
  `props`), and `EventBloc._onUpdateEvent`.
- Modify: `event_form_modal.dart` `_saveEvent` (~363). The new step goes
  **before** `_resolveQuotaReductions` (~451), in edit mode only (not
  duplication).
- Test:
  - `shavtzak/test/presentation/screens/event/widgets/custom_hours_resolve_dialog_test.dart`
  - `shavtzak/test/presentation/bloc/event/event_bloc_update_resolutions_test.dart`
  - `shavtzak/test/core/utils/custom_hours_test.dart` (the `eventTimesChanged`
    cases)

**Interfaces:**
- Consumes: `eventTimesChanged`, `calendarDaysBetween`, `formatCustomHours`
  and `customHoursWarningLines` (Task 5); `shiftWallMoment` and
  `eventStretch` (Task 1); `CustomHoursFields` (Task 7).
- Produces:
  `CustomHoursResolveDialog.show(BuildContext, {required Event oldEvent, required Event newEvent, required List<Assignment> withHours}) → Future<List<CustomHoursResolution>?>`
  (null = ביטול).
  - **Header and cards.**
    - Title `'⏰ לחלק מהצוות יש שעות מותאמות'`, followed by the old → new dates
      and times.
    - One card per member. An exempt member gets one card per assignment.
    - Each card shows the member's current hours (`formatCustomHours`).
  - **The four choices.** Nothing is preselected.
    - `'להזיז עם האירוע'` shifts both ends by
      `calendarDaysBetween(oldEvent.startDate, newEvent.startDate)` days. It
      is hidden when the shift is 0.
    - `'להשאיר כמו שזה'` keeps the hours. When they don't overlap
      `eventStretch(newEvent)`, the label adds `' ⚠️ לא חופף לאירוע החדש'`.
    - `'לערוך…'` shows `CustomHoursFields` inline, with the current hours as
      the initial value.
    - `'להסיר שעות מותאמות'` resolves to null/null.
  - **Bulk shortcut.** `'להזיז את כולם עם האירוע (+N ימים)'` (or `(-N ימים)`)
    sits at the top, only when the shift is not 0.
  - **Warnings.** Each card shows `customHoursWarningLines(member, resultingWindow)`
    for its current choice. "להסיר" is judged against
    `eventStretch(newEvent)`.
  - **Buttons.**
    - `'שמור אירוע'` is disabled until every card has a choice, and an edit
      choice holds a valid interval.
    - While it is disabled, a line reads `'נשאר N לבחירה'`.
    - `'ביטול'` pops null.
  - **Result.** One `CustomHoursResolution` per assignment. A member's card
    yields the same hours for each of their assignments.
- **Form behaviour.**
  - When `eventTimesChanged(widget.event!, newEvent)`, load the event's
    assignments with `context.read<AssignmentRepository>().watchAssignmentsByEvent(id).first.timeout(const Duration(seconds: 10))`,
    then keep the ones with `hasCustomHours`.
    - If any have hours, show the dialog. A null result resets `_isSaving`,
      returns, and writes nothing.
    - A load timeout shows a snackbar `'לא ניתן לבדוק שעות מותאמות כרגע — נסו שוב'`
      and aborts.
  - The resolutions are passed in `UpdateEvent`.

- [ ] **Step 1: Write failing dialog widget tests.**
  - **Day-1 move.** The event moves +7 days, with one member with hours.
    - "שמור אירוע" is disabled and `'נשאר 1 לבחירה'` is shown.
    - Tapping "להזיז עם האירוע" enables it, and the result is shifted by 7
      days.
  - **Times only.** Only times changed: "להזיז עם האירוע" is absent.
  - **No overlap.** Hours that don't overlap the new stretch show
    `'להשאיר כמו שזה ⚠️ לא חופף לאירוע החדש'`.
  - **Two roles.** A member with two assignments yields two resolutions with
    equal hours.

- [ ] **Step 2: Write a failing bloc test.** `UpdateEvent` with resolutions
  calls `repository.updateEvent(event, knownOriginal:, customHoursResolutions: [...])`
  (verify with the mock).

- [ ] **Step 3: Implement.** Run `flutter test && flutter analyze`. All pass.

- [ ] **Step 4: Commit.** Use `feat(events): resolve members' custom hours before saving changed event times`.

---

### Task 10: Duplicating custom hours

**Files:**
- Modify: `event_form_modal.dart`.
  - Below the "שכפל גם את השיבוצים" switch (~2228), add an indented
    `SwitchListTile` titled `'שכפל שעות מותאמות'`, state
    `_duplicateCustomHours = true`.
  - It shows only when copy-assignments is on and the source has hours.
    `_sourceHasCustomHours` is set from
    `watchAssignmentsByEvent(source.id).first` in `initState` (duplication
    mode only, with errors ignored).
- Modify: `event_event.dart`:
  - `DuplicateEvent` gains `bool duplicateCustomHours`;
  - `ConfirmDuplicationWithExclusions` gains
    `Set<String> customHoursDropped` (assignment ids).
- Modify: `event_state.dart`. `AssignmentDuplicationInfo` gains
  `String? movedCustomStartAt`, `String? movedCustomEndAt`, and the
  availability with the event's own hours
  (`DuplicationAvailability availabilityWithEventHours`). The existing
  `availability` is judged with the moved hours.
- Modify: `duplication_availability.dart`. It takes
  `{WallInterval? window}` and passes it to `isAvailableForEventWithTime`.
- Modify: `event_bloc.dart`, `_onDuplicateEvent` (~477) and
  `_onConfirmDuplicationWithExclusions` (~614).
- Modify: `duplication_conflict_resolution_dialog.dart`. It gets a new section
  and returns a record (see below).
- Modify: `event_repository.dart`, `duplicateEvent` (~308). It gains
  `{Map<String, ({String? start, String? end})> hoursByAssignmentId = const {}}`
  and sets those on the copies.
- Test:
  - `shavtzak/test/presentation/bloc/event/event_bloc_duplication_test.dart` (extend)
  - `duplication_conflict_resolution_dialog_test.dart` (extend)
  - `shavtzak/test/data/repositories/event_repository_duplicate_bypass_test.dart` (extend)

**Interfaces:**
- Consumes: `shiftWallMoment` and `customHoursInterval` (Task 1);
  `calendarDaysBetween`, `formatCustomHours` and `customHoursWarningLines`
  (Task 5).
- Produces:
  - **The dialog's result** becomes
    `({Set<String> excluded, Set<String> hoursDropped})?`. Update its single
    caller, the listener at `event_form_modal.dart` ~1129.
  - **The section `'⏰ שעות מותאמות (N)'`**:
    - one row per member, keyed by their first assignment;
    - the old hours struck through (`TextDecoration.lineThrough`), with the
      moved hours under them;
    - a checkbox, **ticked by default**;
    - a `'סמן הכל'` link;
    - the warning lines for the moved hours.
  - **Unticking a member** adds all of that member's assignment ids to
    `hoursDropped`. That member's availability row switches to
    `availabilityWithEventHours`.
  - **A member marked for removal** in "קונפליקטי זמינות" has their hours row
    hidden.
- **Bloc.**
  - The shift is `calendarDaysBetween(original.startDate, newStartDate)`.
  - When `duplicateCustomHours` is on and any copied assignment has hours,
    the dialog opens even with no other conflicts.
  - At confirm, `canKeep` is re-judged with each row's resulting window. The
    repository gets the moved hours for ticked rows and none for dropped
    ones.
  - With the sub-switch off, no hours are copied, and the dialog opens only
    when it does today.

- [ ] **Step 1: Write failing tests.**
  - **Bloc, dialog opens for hours.**
    - Setup: the source (1.12) has one assignment with hours
      `2026-12-01T14:00 → 2026-12-01T20:00`, there are no conflicts, and the
      duplicate is on 8.12 with `duplicateCustomHours: true`.
    - Expect `DuplicationRequiresConflictResolution`, with
      `movedCustomStartAt '2026-12-08T14:00'`.
  - **Bloc, sub-switch off.** No dialog, and the copies carry null hours
    (check the captured `insertAssignmentsBatch` assignments).
  - **Confirm.** With `hoursDropped` empty, the copies carry the moved hours.
    With the id dropped, they carry null.
  - **Dialog.**
    - The section lists the member, ticked.
    - Unticking makes the result's `hoursDropped` contain the id.
    - Marking the member for removal hides their hours row.

- [ ] **Step 2: Implement.** Run `flutter test && flutter analyze`. All pass.

- [ ] **Step 3: Commit.** Use `feat(events): duplicate members' custom hours, moved to the new dates`.

---

### Task 11: Filling or replacing a slot when hours are involved

**Files:**
- Create: `shavtzak/lib/presentation/screens/assignment/widgets/replacement_hours_dialog.dart`.
  Read `docs/superpowers/specs/2026-10-26-assignment-custom-hours/replace-member.html`.
- Modify: `assignment_event.dart`. `StageMemberChange` gains
  `String? customStartAt`, `String? customEndAt` and
  `bool setsCustomHours = false`, all in `props`.
- Modify: `assignment_bloc.dart`, `_onStageMemberChange` (~1800) and
  `_upsertStagedMember` (~1532).
  - When `setsCustomHours`, set the slot's desired hours.
  - Unless the member is exempt, stage the same hours on the incoming
    member's other slots in the event.
  - When not `setsCustomHours`, the desired hours are set to null for a new
    occupant. They are never inherited from the previous occupant.
- Modify: `assignment_list_screen.dart`.
  - `_handleAssignmentChange` and `_handleAssignmentChangeWithBypass` (~3356–3388)
    run the hours step before dispatching.
  - `_showConstrainedMembersDialog` (~3147) gets the green hint.
- Test:
  - `shavtzak/test/presentation/screens/assignment/widgets/replacement_hours_dialog_test.dart`
  - `shavtzak/test/presentation/bloc/assignment/stage_member_change_hours_test.dart`

**Interfaces:**
- Consumes: `customHoursWarningLines`, `formatCustomHours`,
  `memberFirstName` (Task 5); `CustomHoursFields` (Task 7).
- Produces:
  `ReplacementHoursDialog.show(BuildContext, {required Event event, required TeamMember incoming, TeamMember? previous, WallInterval? previousHours, WallInterval? incomingExistingHours, required bool incomingHasOtherRoles}) → Future<({WallInterval? hours})?>`.
  - `null` = ביטול. `(hours: null)` = event hours.
  - **Title.** `'⏰ ל<previous first name> היו שעות מותאמות'` when
    `previousHours` is set. Otherwise `'⏰ ל<incoming first name> יש שעות מותאמות באירוע'`.
  - **Choices.** Shown only where they apply, and nothing is preselected:
    - `'לשמור את השעות של <previous first>'`, which shows `previousHours`;
    - `'השעות הקיימות של <incoming first>'`, which shows
      `incomingExistingHours`;
    - `'שעות האירוע הרגילות'`, which shows `eventStretch(event)`;
    - `'שעות אחרות…'`, which shows `CustomHoursFields` inline.
  - **Conflict result per choice, for the incoming member.**
    - `'✅ אין התנגשות עם אילוצים של <incoming first>'`, or
    - the warning lines.
  - **Other roles.** When `incomingHasOtherRoles` and the member is not
    exempt, a line reads `'השעות יחולו על כל התפקידים של <first> באירוע'`.
- **Screen behaviour.**
  - The step runs when the slot's effective assignment had hours **or** the
    incoming member has hours on another slot of this event.
  - On a result, dispatch
    `StageMemberChange(slot:, member:, setsCustomHours: true, customStartAt/End: formatted or null)`.
  - On ביטול, run `_resetDropdown(slot)` and keep the previous occupant.
  - Otherwise it dispatches as today.
- **Hint in "בעלי מגבלות".**
  - When the slot's effective assignment has hours, a row's subtitle gets a
    green `Text('פנוי בשעות של <previous first>')` (`Colors.green.shade700`,
    fontSize 12).
  - It shows for each listed member whose
    `isAvailableForEventWithTime(event, window: previousHours)` is true.
  - Text only, no icon.

- [ ] **Step 1: Write failing tests.**
  - **Dialog, both hours.** With both `previousHours` and
    `incomingExistingHours`, all four choices show, none are selected, and
    the confirm button is disabled until one is chosen.
  - **Dialog, conflicting choice.** Choosing a conflicting option shows the
    `'⚠️ מתנגש עם אילוץ מאושר של …'` line.
  - **Bloc, replace with kept hours.** Replacing dana (with hours) by yossi
    with `setsCustomHours: true` and dana's hours sets yossi's slot to
    dana's hours.
  - **Bloc, other roles.** yossi's other slot in the event is staged with the
    same hours.
  - **Bloc, plain replace.** Without `setsCustomHours`, the new occupant's
    desired hours are null.

- [ ] **Step 2: Implement.** Run `flutter test && flutter analyze`. All pass.

- [ ] **Step 3: Commit.** Use `feat(assignments): choose the hours when filling or replacing a slot`.

---

### Task 12: Docs

**Files:**
- Modify: `CLAUDE.md`:
  - Under "Working with Assignments", add one short paragraph:
    - custom hours fields and format;
    - the window rule and where it lives;
    - absent versus null on the wire;
    - the shared-hours rule.
  - Update the test counts line.

- [ ] **Step 1: Write the paragraph.** Run `cd shavtzak && flutter test`, then
  `cd functions && npm test`, and record the counts in CLAUDE.md.
- [ ] **Step 2: Commit.** Use `docs: custom hours in CLAUDE.md`.
