# Conflict Check: Continuous Stretch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every member-vs-event conflict check in the app and the backend treats an event as one continuous stretch (assembly on the first day → team end on the last day), pending constraints block like approved, and the surrounding bugs (error 500, recurring warnings, duplication batch failure, summary "שבץ בכל זאת") are fixed.

**Architecture:** One pure stretch module per side: `functions/src/event_stretch.ts` and `shavtzak/lib/core/utils/event_stretch.dart`. Moments are Israel wall-clock (date + minutes), intervals are half-open. Every existing call site keeps its entry point (`memberAvailableForEvent`, `DateConstraint.blocksEventAssignment`, `TeamMember.isAvailableForEventWithTime`, `constraintOverlapsEvent`), which now delegates to the module. Both sides are pinned by one JSON case table that a Functions test and a Flutter test both read.

**Tech Stack:** Flutter Web (Dart, BLoC, mockito), Firebase Cloud Functions (TypeScript, `node --test`), Firebase MCP tools for the read-only production pull.

**Spec:** `docs/superpowers/specs/2026-10-26-conflict-check-continuous-stretch-design.md`. Read it before any task. It holds the rule, the examples E1–E7 and the call-site tables this plan refers to.

## Global Constraints

- Worktree: `conflict-check-continuous` at `/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/conflict-check-continuous`. Run git only from there, as plain single commands. Never use bare `git stash`.
- Run Flutter commands from `shavtzak/`, Functions commands from `functions/`. A fresh worktree needs `npm ci` (in `functions/`) and `flutter pub get` (in `shavtzak/`) first.
- **Do not run the app.** The user runs it.
- `flutter analyze` must show zero **new** issues; about 107 pre-existing infos are the baseline. Test counts on `main`: about 1202 Flutter, 255 Functions.
- Hebrew copy is exact:
  - `אילוץ מאושר: `
  - `אילוץ ממתין לאישור: `
  - `לא ציין/ה זמינות`
  - `לא ציין/ה זמינות לאירוע`
  - `לא פעיל/ה`
  - `לא מוסמך/ת לתפקיד`
  - `חבר/ת הצוות לא נמצא/ה`
  - `משובצ/ת ב: `
- No new icons on assignment rows. The constrained-list rows already have an icon slot; the hourglass `Icons.hourglass_top` replaces the calendar there.
- Entities stay Equatable with full-object props. Code comments are in English, and the text the user sees is in Hebrew, laid out right to left.
- **Moments:**
  - Dart uses `DateTime.utc(y, m, d, h, min)` holding the **Israel wall-clock** fields, so DST never shifts a comparison.
  - TypeScript uses minutes since 1970-01-01 00:00 of the Israel wall clock: `normalizeDayInIsrael(day).getTime() / 60000 + minutes`.
- Time strings: only `HH:mm` with hours 0–23 and minutes 0–59 counts. Anything else (`''`, `'24:00'`, `'9:00 '`) is "missing" and falls back. A malformed time never throws.
- **Stretch:**
  - start = first day at `assemblyTime`, else `startTime`, else 00:00;
  - end = last day at `teamEndTime`, else `endTime`, else 24:00 (the next day at 00:00);
  - a one-day event whose end is not after its start ends the next day;
  - a multi-day event is read literally;
  - if `endDate` is before `startDate` (bad data), use `startDate` as the last day.
- **Constraint intervals:**
  - one-time without hours: first day 00:00 → day after the last day 00:00;
  - one-time with hours (one day or several): first day at `startTime` → last day at `endTime`;
  - one bound only: the missing start is 00:00 on the first day, the missing end is 24:00 on the last day;
  - recurring: on each matching day, the whole day, or `startTime`→`endTime`;
  - a window whose end is not after its start rolls to the next day;
  - a recurring constraint with a null `repeatEndDate` matches nothing (today's rule on both sides).
- Blocking (permanent members): an unavailability constraint with status `approved` or `pending` that overlaps the stretch. `allowMultipleAssignments` members stay exempt at the callers, exactly where they are exempt today.
- Never write to production. The only production access is read-only MCP queries, in Task 8.

## Review Focus

1. **Malformed event times** (`'24:00'`, `''`, a stray space) must fall back, not throw or 500 → case F7 in the table (Task 2) and the Dart runner (Task 3).
2. **A constraint with only one time set**, which the old UI could save → case K1 (Task 2).
3. **A recurring constraint whose `repeatEndDate` is null** must never block (today's rule) → case G7 (Task 2).
4. **An event saved with `endDate` before `startDate`** must give a valid stretch, not an empty or negative one → case J4 (Task 2).
5. **Duplicating an assignment whose member document was deleted** must not fail the batch; the row can't be kept and says `חבר/ת הצוות לא נמצא/ה` → test in Task 7.

---

### Task 1: Backend loosening parts (Functions deploy 1)

These go **before** the pending branch is merged, so this commit can be deployed alone before the user tests locally. The spec's rollout explains why.

**Files:**
- Modify: `functions/src/index.ts`: the `assignment.update` handler (~4483), the `assignment.insertBatch` handler (~4774), and the test re-exports at the bottom (~6969).
- Modify: `shavtzak/lib/data/repositories/assignment_repository.dart`: `updateAssignment` (~112), `checkConflicts` (~189).
- Test: `functions/src/assignment_availability_gate.test.ts` (new)
- Test: `shavtzak/test/data/repositories/assignment_repository_update_guard_test.dart` (new; reuse the `@GenerateMocks([DatabaseInterface])` mocks from `assignment_repository_save_batch_test.mocks.dart`)

**Interfaces:**
- Produces (TS, exported from `index.ts`): `export function shouldCheckAvailability(args: {bypassRequested: boolean; stored: {teamMemberId?: unknown; eventId?: unknown} | null; next: {teamMemberId: string; eventId: string}}): boolean`
- Produces (TS): `assignment.insertBatch` reads an optional `payload.bypassAvailability === true` and passes it to `validateAssignmentPayload`.
- Produces (Dart): `Future<List<String>> checkConflicts(Assignment assignment, {bool skipAvailability = false})`. With `skipAvailability`, only the availability message is skipped; "not found" and qualification still run.

- [ ] **Step 1: Write the failing TS tests** in `assignment_availability_gate.test.ts`:

```ts
test('shouldCheckAvailability: bypass requested → false', () =>
  assert.equal(shouldCheckAvailability({bypassRequested: true, stored: null, next: {teamMemberId: 'm1', eventId: 'e1'}}), false));
test('shouldCheckAvailability: new assignment → true', () =>
  assert.equal(shouldCheckAvailability({bypassRequested: false, stored: null, next: {teamMemberId: 'm1', eventId: 'e1'}}), true));
test('shouldCheckAvailability: same member and event as stored → false', () =>
  assert.equal(shouldCheckAvailability({bypassRequested: false, stored: {teamMemberId: 'm1', eventId: 'e1'}, next: {teamMemberId: 'm1', eventId: 'e1'}}), false));
test('shouldCheckAvailability: member replaced → true', () =>
  assert.equal(shouldCheckAvailability({bypassRequested: false, stored: {teamMemberId: 'm1', eventId: 'e1'}, next: {teamMemberId: 'm2', eventId: 'e1'}}), true));
test('shouldCheckAvailability: moved to another event → true', () =>
  assert.equal(shouldCheckAvailability({bypassRequested: false, stored: {teamMemberId: 'm1', eventId: 'e1'}, next: {teamMemberId: 'm1', eventId: 'e2'}}), true));
```

- [ ] **Step 2: Run them and see them fail.** `cd functions && npm test`. Expected: a compile error, because `shouldCheckAvailability` is not exported.

- [ ] **Step 3: Implement `shouldCheckAvailability` in `index.ts`, then wire both handlers.**
  - In `assignment.update`, read the stored assignment doc **before** `validateAssignmentPayload`, and pass `bypassAvailability: !shouldCheckAvailability({...})`. The existing in-transaction read and the 404 stay.
  - In `assignment.insertBatch`, pass `{bypassAvailability: payload['bypassAvailability'] === true}`.

- [ ] **Step 4: Run the tests and see them pass.** `cd functions && npm test`. Expected: all pass, about 260.

- [ ] **Step 5: Write the failing Dart test** in `assignment_repository_update_guard_test.dart`:
  - `updateAssignment keeps an unchanged member/event even when unavailable`:
    - mock `getAssignmentById` → stored (m1, e1);
    - mock `getEventById` → an event with no times;
    - mock `getTeamMemberById` → a permanent m1 with an approved whole-day constraint on the event's date and the role capability;
    - expect no throw;
    - verify `updateAssignment(any)` was called once.
  - `updateAssignment refuses a replaced member who is unavailable`: same, but the stored member is m0. Expect `AssignmentConflictException`.

- [ ] **Step 6: Run it and see it fail.** `flutter test test/data/repositories/assignment_repository_update_guard_test.dart`. Expected: the first test FAILS with `AssignmentConflictException`.

- [ ] **Step 7: Implement.** `updateAssignment` fetches the stored assignment and calls `checkConflicts(assignment, skipAvailability: stored != null && stored.teamMemberId == assignment.teamMemberId && stored.eventId == assignment.eventId)`.

- [ ] **Step 8: Run the test and analyze.** `flutter test test/data/repositories/assignment_repository_update_guard_test.dart`, then `flutter analyze`. Expected: PASS, and no new issues.

- [ ] **Step 9: Commit**, and record the SHA in the plan's rollout notes as **deploy-1**.

```bash
git add functions/src/index.ts functions/src/assignment_availability_gate.test.ts shavtzak/lib/data/repositories/assignment_repository.dart shavtzak/test/data/repositories/assignment_repository_update_guard_test.dart
git commit -m "fix(assignments): never re-refuse an unchanged assignment; insertBatch accepts bypassAvailability"
```

---

### Task 2: Merge pending branch, shared case table, backend stretch rule

**Files:**
- Merge: branch `worktree-pending-constraints-block` (commit baa11a2). Its worktree is locked: don't touch it, just merge the branch.
- Create: `shared/test-fixtures/event_conflict_cases.json` (repo root; the Flutter runner reads it as `../shared/...` and the Functions runner as `path.join(__dirname, '..', '..', 'shared', ...)`)
- Create: `functions/src/event_stretch.ts`
- Modify: `functions/src/index.ts`: `memberAvailableForEvent` (~3354), `constraintBlocksEvent` (~3334), test re-exports.
- Create: `functions/src/event_conflict_cases.test.ts`
- Modify: `functions/src/availability.test.ts` (keep every test whose expectation still holds; change any that flip, with a comment naming E1–E7)

**Interfaces:**
- Produces (`event_stretch.ts`):
  - `export interface WallInterval {start: number; end: number}`: minutes on the Israel wall clock, half-open.
  - `export interface StretchEventInput {firstDay: Date; lastDay: Date; assemblyTime?: string | null; startTime?: string | null; endTime?: string | null; teamEndTime?: string | null}`. Days are UTC midnight of the Israel day, i.e. `normalizeDayInIsrael` output.
  - `export interface StretchConstraintInput {firstDay: Date; lastDay: Date; startTime: string | null; endTime: string | null; repeatType: 'daily' | 'weekly' | 'monthly' | null; repeatDay: number | null; repeatEndDay: Date | null}`. `repeatDay` for weekly is 1=Mon…7=Sun.
  - `export function eventStretch(event: StretchEventInput): WallInterval`
  - `export function constraintIntervalsNear(constraint: StretchConstraintInput, stretch: WallInterval): WallInterval[]`
  - `export function constraintOverlapsStretch(constraint: StretchConstraintInput, stretch: WallInterval): boolean`
  - `export function formatWallMinutes(minutes: number): string`: `'yyyy-MM-ddTHH:mm'`.
- Produces (`index.ts` test re-exports): `__testEventStretchFromData(eventData: Record<string, unknown>): WallInterval`
- Consumes: Task 1's commit. The merge goes on top of it.

- [ ] **Step 1: Merge the branch.** `git merge --no-ff worktree-pending-constraints-block -m "Merge branch 'worktree-pending-constraints-block'"`. Then run `cd functions && npm test` and `cd shavtzak && flutter test`. Expected: a clean merge, and everything passes.

- [ ] **Step 2: Write the case table**, `shared/test-fixtures/event_conflict_cases.json`.
  - **Shape:** `{"cases": [{"id", "event", "member", "expectedAvailable", "expectedStretch"?}]}`.
  - **Event:** `{"startDate": "yyyy-MM-dd", "endDate", "assemblyTime", "startTime", "endTime", "teamEndTime"}`. Missing times are `""`.
  - **Member:** `{"isPermanent": true, "isActive": true, "isArchived": false, "availableEventIds": [], "constraints": [...]}`. Defaults are as shown, and the event id is always `"evt"`.
  - **Constraint:** `{"startDate": "yyyy-MM-dd", "endDate": null | "yyyy-MM-dd", "startTime": null | "HH:mm", "endTime", "status": "approved", "constraintType": "unavailability", "repeatType": null | "daily" | "weekly" | "monthly", "repeatDay": null | n, "repeatEndDate": null | "yyyy-MM-dd"}`. Defaults are as shown.
  - **Expected stretch:** `"expectedStretch": {"start": "yyyy-MM-ddTHH:mm", "end": "..."}`.
  - **Rules:** one constraint per case unless stated, approved unavailability unless stated. "→ free" means `expectedAvailable: true`.

  **A, one day.** Event 2026-12-01, assembly 17:00, show 19:00–20:30, team end 22:00. `expectedStretch` on A1: 2026-12-01T17:00 → 2026-12-01T22:00.

  | id | constraint | expected |
  |---|---|---|
  | A1 | 12-01 14:00–16:00 | free |
  | A2 | 12-01 15:00–17:00 (touches assembly) | free |
  | A3 | 12-01 16:30–17:30 | blocked |
  | A4 | 12-01 17:30–18:30 (assembly gap, E5) | blocked |
  | A5 | 12-01 21:00–22:00 (team end, E2) | blocked |
  | A6 | 12-01 22:00–23:00 (touches end) | free |
  | A7 | 12-01 whole day | blocked |
  | A8 | 12-02 whole day | free |
  | A9 | 11-30 whole day | free |

  **B, past midnight.** Event 2026-12-07, one day, assembly 18:30, show 19:30–23:30, team end 00:30. Stretch 12-07T18:30 → 12-08T00:30, given on B1.

  | id | constraint | expected |
  |---|---|---|
  | B1 | 12-07 23:00–23:59 (E1) | blocked |
  | B2 | 12-08 00:00–02:00 | blocked |
  | B3 | 12-08 00:30–02:00 (touches) | free |
  | B4 | 12-08 whole day | blocked |
  | B5 | 12-07 23:00 → 12-08 01:00 (multi-day constraint) | blocked |
  | B6 | event 12-09, assembly 18:30, team end 00:00, constraint 12-10 whole day. Stretch 12-09T18:30 → 12-10T00:00. | free |
  | B7 | same event as B6, constraint 12-09 23:00–23:59 | blocked |

  **C, team end before show end.**

  | id | event / constraint | expected |
  |---|---|---|
  | C1 | event 12-01, assembly 17:00, show 19:00–22:00, team end 21:00. Constraint 21:30–23:00. Stretch ends 12-01T21:00. | free |

  **D, several days.**

  | id | event / constraint | expected |
  |---|---|---|
  | D1 | event 10-27→10-28, assembly 18:00, show 19:00–22:00, team end 23:00. Stretch 10-27T18:00 → 10-28T23:00. Constraint 10-28 02:00–04:00 (E3). | blocked |
  | D2 | same event, constraint 10-27 12:00–17:00 | free |
  | D3 | same event, constraint 10-28 23:00–23:59 (touches) | free |
  | D4 | same event, constraint 10-29 whole day | free |
  | D5 | event 10-27→10-29, assembly 08:00, team end 20:00. Constraint 10-28 03:00–04:00. | blocked |
  | D6 | event 10-27→10-28, assembly 14:00, team end 12:00. Stretch 10-27T14:00 → 10-28T12:00, no roll. Constraint 10-28 13:00–15:00. | free |
  | D7 | same event as D6, constraint 10-28 11:00–12:30 | blocked |
  | D8 | event 10-27→10-29, assembly 18:00, team end 01:00. Stretch → 10-29T01:00. Constraint 10-28 20:00–22:00. | blocked |
  | D9 | the דו יומי shape: event 10-29→10-30, assembly 08:30, show 10:00–11:30, team end 13:00. Stretch 10-29T08:30 → 10-30T13:00. Constraint 10-29 20:00–22:00. | blocked |

  **E, a constraint 23:00 → 01:00.** Constraint 12-14 23:00 → 12-15 01:00.

  | id | event | expected |
  |---|---|---|
  | E-1 | 12-14, assembly 18:00, team end 22:00 | free |
  | E-2 | 12-14, assembly 18:00, team end 23:30 | blocked |
  | E-3 | 12-15, assembly 00:30, team end 03:00 | blocked |

  **F, missing fields.** Event 12-03.

  | id | event / constraint | expected |
  |---|---|---|
  | F1a | assembly "", show 19:00–21:00, team end 22:00. Stretch 12-03T19:00 → 12-03T22:00. Constraint 18:00–19:00. | free |
  | F1b | same event, constraint 18:30–19:30 | blocked |
  | F2 | assembly "", show start "", show end 21:00, team end "". Stretch 12-03T00:00 → 12-03T21:00. Constraint 08:00–09:00. | blocked |
  | F3 | assembly 17:00, show 19:00–21:00, team end "". Constraint 21:30–22:30. | free |
  | F4a | assembly 17:00, show start 19:00, show end "", team end 22:00 (E4). Constraint 22:30–23:30. | free |
  | F4b | same event as F4a, constraint 21:00–21:30 | blocked |
  | F5a | assembly 17:00, show start 19:00, no end at all. Stretch 12-03T17:00 → 12-04T00:00. Constraint 23:00–23:59. | blocked |
  | F5b | same event as F5a, constraint 12-04 whole day | free |
  | F6a | no times at all. Stretch 12-03T00:00 → 12-04T00:00. Constraint 08:00–09:00. | blocked |
  | F6b | same event as F6a, constraint 12-04 whole day | free |
  | F7 | assembly 17:00, show 19:00, show end "24:00", team end "" (malformed). Stretch → 12-04T00:00. Constraint 23:00–23:30. | blocked |

  **G, recurring.** `repeatEndDate` 2026-12-31 unless stated.

  | id | event / constraint | expected |
  |---|---|---|
  | G1 | event 10-27 (Tue) → 10-28 (Wed), assembly 18:00, team end 23:00. Weekly, repeatDay 3 (Wed), from 10-01, 18:00–20:00. | blocked |
  | G2 | event 10-20, assembly 17:00, team end 22:00. Weekly, repeatDay 2 (Tue), from 10-06, whole day (third occurrence, E6). | blocked |
  | G3a | the B event (12-07, past midnight). Daily from 10-01, 01:00–02:00. | free |
  | G3b | the D1 event. Daily from 10-01, 01:00–02:00 (night of 10-28). | blocked |
  | G4a | event 11-15, assembly 10:00, team end 12:00. Monthly, repeatDay 15, from 10-15, whole day. | blocked |
  | G4b | same constraint as G4a, event 11-16 | free |
  | G5 | weekly repeatDay 2 (Tue), from 10-06, `repeatEndDate` 10-13, whole day. Event 10-20. | free |
  | G6 | daily from 10-01, no hours. Event 12-01, the A event. | blocked |
  | G7 | daily from 10-01, `repeatEndDate` null, whole day. Event 12-01. | free |

  **H, status and type.** All on the A event.

  | id | constraint | expected |
  |---|---|---|
  | H1 | pending, 12-01 whole day | blocked |
  | H2 | rejected, 12-01 whole day | free |
  | H3 | `constraintType` availability on a permanent member, 12-01 whole day | free |

  **I, member.** All on the A event.

  | id | member | expected |
  |---|---|---|
  | I1 | non-permanent, `availableEventIds: ["evt"]` | free |
  | I2 | non-permanent, `availableEventIds: []` | unavailable |
  | I3 | non-permanent, legacy approved availability constraint 12-01 whole day | free |
  | I4 | `isActive: false` | unavailable |
  | I5 | `isArchived: true` | unavailable |

  **J, dates.**

  | id | event / constraint | expected |
  |---|---|---|
  | J1a | DST end. Event 10-24, assembly 20:00, team end 02:00. Stretch 10-24T20:00 → 10-25T02:00. Constraint 10-25 01:30–03:00. | blocked |
  | J1b | same event as J1a, constraint 10-25 02:00–03:00 | free |
  | J2 | DST start. Event 03-26, assembly 20:00, team end 02:30. Constraint 03-27 02:00–04:00. | blocked |
  | J3a | month end. Event 11-30→12-01, assembly 18:00, team end 10:00. Constraint 12-01 09:00–11:00. | blocked |
  | J3b | same event as J3a, constraint 11-30 whole day | blocked |
  | J4 | event startDate 12-05, endDate 12-04 (bad data), assembly 17:00, team end 22:00. Stretch 12-05T17:00 → 12-05T22:00. Constraint 12-05 18:00–19:00. | blocked |

  **K, partial constraint times.**

  | id | constraint | expected |
  |---|---|---|
  | K1 | A event, constraint 12-01 startTime 20:00, endTime null | blocked |

- [ ] **Step 3: Write the TS runner** `event_conflict_cases.test.ts`.
  - It loads the JSON and, for each case, runs `memberAvailableForEvent(member, event)` under `TZ=UTC` (copy `withUtcTimezone` from `availability.test.ts`). Assert it equals `expectedAvailable`, with the case `id` in the message.
  - When `expectedStretch` is present, assert `formatWallMinutes` of `__testEventStretchFromData(event)` start and end.
  - Event dates become Timestamps at Israel midnight. Use a helper `israelMidnight(dateKey)` that tries the `+03:00` and `+02:00` offsets and keeps the one whose `Asia/Jerusalem` hour is 0.
  - Constraint dates become naive strings `${date}T00:00:00.000`, the way the Flutter client stores them.
  - Add `test('case table holds at least 60 cases')`.

- [ ] **Step 4: Run it and see it fail.** `cd functions && npm test`. Expected: compile error (missing `__testEventStretchFromData`), then failures on E1–E4 cases (A4, A5, B1, D1, F4a…).

- [ ] **Step 5: Implement `event_stretch.ts`, then rewire `index.ts`.**
  - The permanent branch of `memberAvailableForEvent` becomes: any constraint with status approved or pending and type unavailability where `constraintOverlapsStretch(toStretchConstraint(c), eventStretchFromData(eventData))`.
  - The non-permanent branch is unchanged, except that `constraintBlocksEvent` no longer calls `requireString` on event times: a missing time falls back the way the stretch does. This is the legacy-availability path.
  - Keep `constraintMatchesDate` for the legacy path. The stretch module does its own recurrence matching, using the same weekday mapping (Sunday = 7).

- [ ] **Step 6: Update `availability.test.ts`.** Change only the expectations that flip under the new rule, and give each a comment naming the example (E1–E7) or "pending". Then run `cd functions && npm test`. Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add shared/test-fixtures/event_conflict_cases.json functions/src/event_stretch.ts functions/src/index.ts functions/src/event_conflict_cases.test.ts functions/src/availability.test.ts
git commit -m "feat(availability): backend judges an event as one continuous stretch"
```

---

### Task 3: App stretch rule and the assignment-side callers

**Files:**
- Create: `shavtzak/lib/core/utils/event_stretch.dart`
- Modify: `shavtzak/lib/domain/entities/team_member.dart`:
  - `DateConstraint.blocksEventAssignment` (~226) delegates to the stretch;
  - the permanent branch of `TeamMember.isAvailableForEventWithTime` becomes `constraintsBlockingEvent(event).isEmpty`;
  - `blocksEventOn` stays only for the legacy non-permanent availability loop (document that);
  - delete the deprecated `conflictsWithEventTime`.
- Create: `shavtzak/test/domain/event_conflict_cases_test.dart`
- Create: `shavtzak/test/core/utils/event_stretch_test.dart`
- Modify (change only the expectations that flip, each with an E1–E7 comment): `test/core/utils/multiday_constraint_time_span_test.dart`, `test/core/utils/event_constraint_collisions_test.dart`, `test/presentation/bloc/assignment_slot_build_characterization_test.dart`, `test/presentation/bloc/assignment_bloc_staged_within_event_availability_test.dart`, `test/presentation/bloc/assignment_bloc_staged_samedy_availability_test.dart`, `test/domain/pending_constraint_blocks_assignment_test.dart`.

**Interfaces:**
- Produces (`event_stretch.dart`):
  - `class WallInterval extends Equatable { const WallInterval(this.start, this.end); final DateTime start; final DateTime end; bool overlaps(WallInterval other); }`. Both are `DateTime.utc` wall-clock; `overlaps` is half-open.
  - `WallInterval eventStretch(Event event)`
  - `List<WallInterval> constraintIntervalsNear(DateConstraint constraint, WallInterval stretch)`
  - `bool constraintOverlapsStretch(DateConstraint constraint, WallInterval stretch)`
  - `String formatWallMoment(DateTime moment)`: `'yyyy-MM-ddTHH:mm'`.
- Consumes: the case table from Task 2. `TeamMember.constraintsBlockingEvent(Event)` and `DateConstraint.blocksAssignments` from the merged branch.

- [ ] **Step 1: Write the Dart runner** `event_conflict_cases_test.dart`.
  - It reads `File('../shared/test-fixtures/event_conflict_cases.json')` and builds an `Event` (id `evt`, dates `DateTime(y, m, d)`, the five times, the other required fields as neutral values) and a `TeamMember` per case.
  - Assert `member.isAvailableForEventWithTime(event) == expectedAvailable`, with the reason being the case id.
  - When `expectedStretch` is present, assert `formatWallMoment(eventStretch(event).start/end)`.
  - Add `test('case table holds at least 60 cases')`.

- [ ] **Step 2: Write `event_stretch_test.dart`** for what the table doesn't pin:
  - `WallInterval.overlaps` treats touching as no overlap;
  - `constraintIntervalsNear` returns one interval per matching recurring day in range (weekly Wed over a Tue–Wed stretch → exactly one interval, on the Wednesday);
  - a stretch built on 2026-10-25 (DST end) has a duration of exactly 6 h for 20:00 → 02:00.

- [ ] **Step 3: Run both and see them fail.** `flutter test test/domain/event_conflict_cases_test.dart test/core/utils/event_stretch_test.dart`. Expected: compile error, then the E1–E4 cases failing.

- [ ] **Step 4: Implement `event_stretch.dart` and the `team_member.dart` changes.** The repeat matching reuses `DateConstraint.conflictsWith(day)` for each candidate day, from the day before the date of `stretch.start` to the date of `stretch.end`. That covers rolled stretches and rolled constraint windows. The TS side uses the same candidate range.

- [ ] **Step 5: Run the runner and the new unit tests.** Expected: all 60+ cases pass, with **the same table as the backend**.

- [ ] **Step 6: Update the six existing test files** listed above, then run `flutter test` (all) and `flutter analyze`. Expected: everything passes; no new issues.

- [ ] **Step 7: Commit**

```bash
git add shavtzak/lib/core/utils/event_stretch.dart shavtzak/lib/domain/entities/team_member.dart shavtzak/test
git commit -m "feat(availability): app judges an event as one continuous stretch"
```

---

### Task 4: Constraint-save warnings and the delete offer use the stretch

**Files:**
- Modify: `shavtzak/lib/core/utils/constraint_event_overlap.dart`:
  - `constraintOverlapsEvent` → `constraintOverlapsStretch(constraint, eventStretch(event))`. This covers every occurrence of a recurring constraint.
  - `_eventHasValidTime` → "missing time" means no assembly and no show start, or no team end and no show end.
  - `getHighlightedDatesForConstraintRange` has no callers: delete it.
- Modify: `shavtzak/lib/core/utils/constraint_assignment_conflicts.dart`, only its doc comment, which still describes the old rule.
- Test: `shavtzak/test/core/utils/constraint_event_overlap_test.dart` (new), `shavtzak/test/core/utils/constraint_assignment_conflicts_test.dart` (extend)

**Interfaces:**
- Consumes: `eventStretch`, `constraintOverlapsStretch` (Task 3).
- Produces: no new names. `getConstraintEventOverlaps` and `findNewlyConflictingAssignments` keep their signatures.

- [ ] **Step 1: Write the failing tests.**
  - `constraintOverlapsEvent: assembly gap counts (E5)`: event assembly 17:00, show 19:00–20:30, constraint 17:30–18:30 → `true`.
  - `constraintOverlapsEvent: weekly constraint on its third occurrence (E6)`: weekly Tue from 2026-10-06, event 2026-10-20 → `true`.
  - `constraintOverlapsEvent: night of a two-day event (E3)` → `true`.
  - `getConstraintEventOverlaps: missing_event_time only when the stretch fell back`: an event with assembly but no show start → `date_time_overlap`; no ends at all → `missing_event_time`.
  - `findNewlyConflictingAssignments: pending constraint covering the assembly gap → returns the assignment`.

- [ ] **Step 2: Run and see them fail.** `flutter test test/core/utils/constraint_event_overlap_test.dart test/core/utils/constraint_assignment_conflicts_test.dart`.

- [ ] **Step 3: Implement** the changes listed under **Files**.

- [ ] **Step 4: Run `flutter test` and `flutter analyze`.** Expected: everything passes; no new issues.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/core/utils shavtzak/test/core/utils
git commit -m "fix(constraints): warnings and delete offer use the event stretch and every recurrence"
```

---

### Task 5: Approved vs pending in both "בעלי מגבלות / לא זמינים" lists

**Files:**
- Create: `shavtzak/lib/core/utils/constraint_labels.dart`
- Create: `shavtzak/lib/presentation/widgets/constrained_member_reasons.dart`
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart`: the list in `_showConstrainedMembersDialog` (~3265–3305).
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart`: the list (~1225–1255).
- Test: `shavtzak/test/core/utils/constraint_labels_test.dart`, `shavtzak/test/presentation/widgets/constrained_member_reasons_test.dart`

**Interfaces:**
- Produces:
  - `String constraintShortLabel(DateConstraint c)`
  - `String constraintStatusLabel(DateConstraint c)`: `'אילוץ מאושר: '` or `'אילוץ ממתין לאישור: '` + short label.
  - `class ConstrainedMemberReasons extends StatelessWidget { const ConstrainedMemberReasons({super.key, required this.member, required this.event, this.sameDayEvents = const []}); }`
  - `IconData constrainedMemberIcon(TeamMember member, Event event, {required bool sameDayAssigned})`
  - `Color constrainedMemberIconColor(TeamMember member, Event event, {required bool sameDayAssigned})`
- Consumes: `TeamMember.constraintsBlockingEvent`, `isAvailableForEventWithTime` (Task 3).
- Project 2 will reuse `constraintStatusLabel` for "⚠️ מתנגש עם …".

- [ ] **Step 1: Write the failing label tests.** Dates are `d.M`; dashes are en-dashes.
  - single day, no time, 2026-10-28 → `'28.10 (כל היום)'`
  - 2026-10-27 17:00–20:00 → `'27.10 17:00–20:00'`
  - 2026-10-27 → 2026-10-28, no time → `'27–28.10'`
  - 2026-10-30 → 2026-11-02, no time → `'30.10–2.11'`
  - 2026-10-27 17:00 → 2026-10-28 11:00 → `'27.10 17:00 – 28.10 11:00'`
  - weekly Tue (repeatDay 2) 18:00–20:00 → `'כל יום שלישי 18:00–20:00'`; daily without hours → `'כל יום'`; monthly 15 → `'כל 15 לחודש'`
  - `constraintStatusLabel` of a pending 28.10 whole-day constraint → `'אילוץ ממתין לאישור: 28.10 (כל היום)'`; approved → `'אילוץ מאושר: 28.10 (כל היום)'`

- [ ] **Step 2: Write the failing widget tests** for `ConstrainedMemberReasons`. Put each widget inside `MaterialApp` + `Directionality(rtl)`.
  - approved only → one line `'אילוץ מאושר: …'` in `Colors.red.shade600`; icon `Icons.event_busy`.
  - pending only → one line `'אילוץ ממתין לאישור: …'` in `Colors.orange.shade800`; icon `Icons.hourglass_top` in `Colors.orange.shade700`.
  - both → two lines, approved first; icon `Icons.event_busy`.
  - same-day + pending → `'משובצ/ת ב: הופעה בחיפה'` first, then the pending line; icon `Icons.event`.
  - non-permanent without availability → `'לא ציין/ה זמינות'`; icon `Icons.schedule`.

- [ ] **Step 3: Run and see them fail.** `flutter test test/core/utils/constraint_labels_test.dart test/presentation/widgets/constrained_member_reasons_test.dart`.

- [ ] **Step 4: Implement**, then replace the single `reason` subtitle and the leading icon in **both** lists with the new widget and icon helpers. "שבץ בכל זאת" stays untouched in both.

- [ ] **Step 5: Run `flutter test` and `flutter analyze`.** Expected: everything passes; no new issues.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/core/utils/constraint_labels.dart shavtzak/lib/presentation/widgets/constrained_member_reasons.dart shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart shavtzak/test
git commit -m "feat(assignments): constrained-members lists tell approved from pending"
```

---

### Task 6: Summary screen "שבץ בכל זאת" actually assigns

**Files:**
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart`: `_showAssignmentConfirmationDialog` (~898) and its three callers (~592, 611, 626).
- Test: `shavtzak/test/presentation/bloc/assignment_bloc_create_with_bypass_test.dart` (new)

**Interfaces:**
- Changes `_showAssignmentConfirmationDialog(…, {bool bypassAvailability = false})`. The `__show_constrained__` caller passes `true`; the other two keep the default.
- Consumes: `CreateAssignmentWithBypass(assignment, completion:)`, `CreateAssignment(assignment, completion:)`, `CrudActionCompleter` (`core/utils/crud_action_result.dart`).

- [ ] **Step 1: Write the failing bloc tests.**
  - `CreateAssignmentWithBypass completes success for a member blocked by a pending constraint`: mock the repository `createAssignmentWithBypass` → completes; expect `completion.future` → `isSuccess == true`.
  - `CreateAssignment completes failure for the same member`: mock `checkConflicts` → `['…']`; expect `isFailure`.

  Build the bloc inside `test()`, not `setUp` (repo convention).

- [ ] **Step 2: Run them.** The first must PASS already, since it documents the bypass path. The second must pass too. If either fails, stop and report: the screen fix relies on both.

- [ ] **Step 3: Fix the screen.**
  - Dispatch with a `Completer<CrudActionResult>`, using `CreateAssignmentWithBypass` when `bypassAvailability` is set.
  - Await it. On success, show the existing green snackbar `'שיבצת את ${member.name} לתפקיד $roleHebrewName'`. On failure, show a red snackbar with `result.message`.
  - Guard with `context.mounted`.

- [ ] **Step 4: Run `flutter test` and `flutter analyze`.** Expected: everything passes; no new issues.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart shavtzak/test/presentation/bloc/assignment_bloc_create_with_bypass_test.dart
git commit -m "fix(summary): assign-anyway from the constrained list really assigns; snackbar waits for the save"
```

---

### Task 7: Duplication uses the rule and honours the admin's choice

**Files:**
- Create: `shavtzak/lib/presentation/bloc/event/duplication_availability.dart`
- Modify: `shavtzak/lib/presentation/bloc/event/event_state.dart`: `AssignmentDuplicationInfo` gets `final bool canKeep` (default `true`, in props).
- Modify: `shavtzak/lib/presentation/bloc/event/event_bloc.dart`:
  - in `_onDuplicateEvent` (~557–575), replace `isAvailableForDateRange` with `duplicationAvailability`;
  - in `_onConfirmDuplicationWithExclusions` (~621), also drop assignments where `canKeep` is false (defensive).
- Modify: `shavtzak/lib/presentation/screens/event/widgets/duplication_conflict_resolution_dialog.dart`. A row with `canKeep == false` shows its reason, its checkbox is disabled, and it always stays in `_markedForRemoval`.
- Modify: `shavtzak/lib/data/data_sources/database_interface.dart` (~248), `firestore_database.dart` (~1268), `logging_database.dart` (~683): `insertAssignmentsBatch(List<Assignment> assignments, {bool bypassAvailability = false})`. Firestore sends `'bypassAvailability': true` only when set.
- Modify: `shavtzak/lib/data/repositories/event_repository.dart`: `duplicateEvent` (~342) and `duplicateEventWithAssignmentIds` (~382) pass `bypassAvailability: true`.
- Modify: `shavtzak/lib/domain/entities/team_member.dart`: delete `isAvailableForDateRange` (no callers left).
- Regenerate mocks. Run `dart run build_runner build --delete-conflicting-outputs` from `shavtzak/` with **no** `--build-filter` (a filter has deleted unrelated mocks before). Then check that `git status` shows only `*.mocks.dart` files of tests that mock `DatabaseInterface`.
- Test: `shavtzak/test/presentation/bloc/event/duplication_availability_test.dart` (new), `shavtzak/test/data/repositories/event_repository_duplicate_bypass_test.dart` (new)

**Interfaces:**
- Produces:
  - `class DuplicationAvailability extends Equatable { final bool flagged; final bool canKeep; final List<String> reasons; }`
  - `DuplicationAvailability duplicationAvailability({required Assignment assignment, required Event proposedEvent})`. The assignment's `teamMember` is populated by the repository; null means the member doc is gone.
- Consumes: `TeamMember.isAvailableForEventWithTime`, `constraintsBlockingEvent` (Task 3), `constraintStatusLabel` (Task 5). The backend `insertBatch` flag is Task 1.
- `AssignmentDuplicationInfo.availabilityReason` = `reasons.join('\n')`.

**The rules, in order:**
1. `teamMember == null` → flagged, `canKeep: false`, `['חבר/ת הצוות לא נמצא/ה']`.
2. `!isActive || isArchived` → flagged, `canKeep: false`, `['לא פעיל/ה']`.
3. `!canPerformRole(roleType)` → flagged, `canKeep: false`, `['לא מוסמך/ת לתפקיד']`.
4. `allowMultipleAssignments` → not flagged.
5. `!isAvailableForEventWithTime(proposedEvent)`:
   - permanent → flagged, `canKeep: true`, one `constraintStatusLabel` per `constraintsBlockingEvent(proposedEvent)`;
   - non-permanent → flagged, `canKeep: true`, `['לא ציין/ה זמינות לאירוע']`.
6. Otherwise → not flagged.

- [ ] **Step 1: Write the failing tests** in `duplication_availability_test.dart`, one per rule above. The rule 5 permanent case uses a pending constraint and asserts `reasons == ['אילוץ ממתין לאישור: …']`. Also add:
  - `a timed morning constraint does not flag an evening duplicate (E7)`: constraint 08:00–10:00, proposed event 19:00–22:00 → not flagged;
  - `a non-permanent member is flagged, keepable, for a new event`.

- [ ] **Step 2: Write the failing repository test**, `event_repository_duplicate_bypass_test.dart`: `duplicateEvent sends the batch with bypassAvailability` → `verify(mockDb.insertAssignmentsBatch(any, bypassAvailability: true)).called(1)`.

- [ ] **Step 3: Run and see them fail.** `flutter test test/presentation/bloc/event/duplication_availability_test.dart test/data/repositories/event_repository_duplicate_bypass_test.dart`.

- [ ] **Step 4: Implement** everything under **Files**, then regenerate the mocks as described there.

- [ ] **Step 5: Run `flutter test` and `flutter analyze`.** Expected: everything passes; no new issues.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib shavtzak/test
git commit -m "fix(duplication): judge with the event stretch, keep what the admin keeps, lock what the backend can't take"
```

---

### Task 8: Before/after report on production data (read-only)

**Files:**
- Create: `functions/src/scripts/conflict_report.ts` (run with `npx tsx`, outside the deployed bundle's code paths)
- Output: `~/Downloads/conflict-report-2026-10-26.csv` (UTF-8 with BOM)

**Interfaces:**
- Consumes: `__testMemberAvailableForEvent` from **two** builds of `functions/lib/index.js`, and `__testEventStretchFromData` from the new build.
- CLI: `npx tsx src/scripts/conflict_report.ts --old <dir>/lib/index.js --new lib/index.js --events <f> --assignments <f> --members <f> --today 2026-10-26 --out <csv>`

- [ ] **Step 1: Build the old rule.**
  - Run `git archive 92028b3 functions | tar -x -C <scratchpad>/old-main` (92028b3 is `main` before this work, without the pending branch).
  - Then, in `<scratchpad>/old-main/functions`, run `npm ci && npm run build`.
  - Build the new rule with `cd functions && npm run build`.

- [ ] **Step 2: Pull production, read-only.**
  - Use `mcp__plugin_firebase_firebase__firestore_query_collection` on `events`, `assignments` and `teamMembers`, each with the filter `{field: "name" (events), "eventId" (assignments), "name" (teamMembers), op: NOT_EQUAL, compare_value: {string_value: "x"}}` and limit 5000.
  - Results land in `tool-results/*.txt` as `{documents:[…]}`. Copy them into the scratchpad.
  - Timestamps arrive as `{"__type__":"Timestamp","value":"…"}`. The script turns them into `Timestamp.fromDate(new Date(value))`.

- [ ] **Step 3: Write the script.**
  - **Rows:** every assignment whose event's Israel last day ≥ `--today` and which is not `isDeactivated`. Skip members with `allowMultipleAssignments`.
  - **For each row:**
    - compute `old` and `new` = `memberAvailableForEvent(member, event)`;
    - for changed rows, re-run both sides with the member holding **one constraint at a time**, to name the responsible constraint(s).
  - **Category** (first that fits):
    - `pending now counts` (the responsible constraint is pending);
    - `recurring`;
    - `missing time` (show end empty);
    - `past midnight` (one-day event, end ≤ start);
    - `team end` (the overlap falls between show end and team end);
    - `night` (multi-day event);
    - `now free` (old blocked → new free);
    - `other`.
  - **CSV columns:** event name, Israel dates, stretch (`formatWallMinutes` start → end), member name, role key, old (`פנוי`/`חסום`), new, responsible constraint(s) as `status dates hours`, category.
  - **Last lines:** total rows checked, changed, and the count per category.

- [ ] **Step 4: Run it**, then check the counts by hand on three changed rows: open each event and member in the pulled JSON and confirm the overlap against the spec's rule.

- [ ] **Step 5: Hand the CSV to the user** (path, counts per category, three example rows). **Stop here until the user has reviewed it.** Nothing ships before that.

- [ ] **Step 6: Commit the script** (not the data):

```bash
git add functions/src/scripts/conflict_report.ts
git commit -m "chore(report): read-only before/after conflict report"
```

---

## Rollout (the orchestrator does this, with the user)

1. **Deploy 1**, after Task 1 and before the user tests locally. **Ask the user first.**
   - From the Task 1 commit: `git switch --detach <deploy-1 sha>`, then `cd functions && npm ci && firebase deploy --only functions`.
   - Verify with `firebase functions:list`: all three of `api`, `calendarJobSweep`, `calendarSyncTask` are updated.
   - `git switch worktree-conflict-check-continuous`.
2. Task 8's report is reviewed by the user.
3. The user tests locally (`flutter run` from this worktree, against production). Re-state the worktree name and path when asking.
4. Merge to `main`; the web auto-deploys.
5. **Deploy 2**, right after the merge. **Ask the user first.** `firebase deploy --only functions` from `main`, then `firebase functions:list`.
6. Tell the user the locked `worktree-pending-constraints-block` worktree can be removed.
