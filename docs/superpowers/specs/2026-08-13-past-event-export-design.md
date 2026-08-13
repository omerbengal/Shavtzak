# Past-event assignment export — design

**Date:** 2026-08-13
**Branch:** `worktree-feat-past-event-export`
**Status:** approved design, not yet implemented

## Problem

Admins can only export assignments for future events. The date-range picker in the
export dialog blocks past dates outright, so there is no way to produce a record of
what already happened. The immediate trigger was a request for "all assignments from
mid-July to end of September", which had to be satisfied by querying Firestore
directly and hand-building CSVs.

"No past events" is enforced at three independent layers, all of which must move:

1. `assignment_export_dialog.dart:237` passes `minDate: today` to the range picker.
2. `_loadFutureEvents()` (same file) drops every event whose `endDate` is before today,
   so the picker would select nothing even if past dates were clickable.
3. `drive_export.ts:1192` filters the event pool to future-only, and `perEvent` mode
   throws `DriveExportValidationError` for any selected ID outside that pool.

## Scope

**In scope:** past-event support in **לפי אירוע (perEvent) mode only**.

**Explicitly out of scope:** לפי אדם (perPerson) keeps its current meaning — all
assignments for all future events, no date selection. Its on-screen description
("ייצוא כל השיבוצים של אירועים עתידיים") stays accurate and unchanged.

**No lower bound on how far back.** The picker's existing null-`minDate` fallback
(`date_picker_dialog.dart:284`) already caps navigation at three years back. That is
the bound; no new setting is introduced.

**Deactivated ("מושהה") events remain excluded** everywhere, past and future alike,
matching current behavior on both client and backend.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | perEvent mode only | perPerson has no date scoping UI; widening it would mean "every assignment ever" |
| 2 | Past events in a collapsed `אירועים שעברו` section, newest-first | Dialog looks unchanged on open; mirrors the existing split in `shamap_export_dialog.dart:810-840` |
| 3 | The "משובץ גם ב" double-booking mark stays **future-only** | Preserves documented parity with `/admin/assignments` and `/summary`, which never flag past-day conflicts |
| 4 | Past days in the picker render **gray but remain selectable**; red event frames still shown on past days | Gray = past is a single readable rule; frames are needed to see where to aim the range |
| 5 | "Select all filtered" acts on the **future list only** | A collapsed section must never silently add dozens of past events to the selection |

## Architecture

### Backend — `functions/src/drive_export.ts`

The core move is **exempting the explicitly-selected event IDs from the future
filter**, rather than adding an `includePast` flag or widening the pool globally.

This distinction is load-bearing. `shouldIncludeEvent` returns `true`
unconditionally in `perPerson` mode (`drive_export.ts:934-938`), which means the
future-filtered pool is the *only* thing scoping לפי אדם. Any global widening would
silently turn that export into every assignment ever recorded. Exempting specific IDs
confines the change to events an admin actually ticked, which by construction only
happens in לפי אירוע.

Decision 3 splits the single event pool into two:

- **`rowPool`** — future events ∪ selected past events. Rows are built from this.
- **`annotationPool`** — future events only. `buildSameDayOtherEventNames` uses this.

A new pure function builds both:

```ts
function buildExportEventPools(
  eventsData: Record<string, Record<string, unknown>>,
  now: Date,
  selectedEventIds: string[],
): {rowPool: ...; annotationPool: ...}
```

`annotationPool` is exactly today's `filterFutureEventsData` output. `rowPool` adds
back any selected ID that exists in `eventsData` and is not deactivated. Because
deactivated events are never added back, selecting one still fails validation as it
does today.

`serializeAssignmentsOnly` takes the annotation pool as an added parameter and passes
it to `buildSameDayOtherEventNames`; every other use of `eventsData` inside it becomes
the row pool. The block comment at `drive_export.ts:826-846` documenting the
future-only annotation rationale must be updated to explain the two-pool split rather
than deleted — the reasoning still holds, the mechanism changed.

Two strings drop the now-inaccurate word "future":

- `Selected future event IDs are invalid: …` → `Selected event IDs are invalid: …`
- `index.ts:6422` `Select at least one future event to export` → `Select at least one event to export`

### Client — `shavtzak/lib/presentation/widgets/date_picker_dialog.dart`

One new optional parameter:

```dart
/// Days before this date render dimmed but stay fully selectable.
final DateTime? dimBeforeDate;
```

In `dayBuilder`, when `dimBeforeDate != null && date.isBefore(dimBeforeDate!) &&
!isSelected`, the day's text color is overridden to grey. The red highlight frame and
`decoration` are untouched, and nothing routes through the package's `isDisabled`
path, so dimmed days remain clickable. Excluding selected days from dimming matters:
a selected day already renders on a filled background, and dimming it there would
look like a rendering bug.

### Client — `shavtzak/lib/presentation/widgets/assignment_export_dialog.dart`

`_loadFutureEvents()` becomes `_loadEvents()`: same `getAllEvents()` call, same
deactivated exclusion, but the result splits into `_futureEvents` (ascending, as
today) and `_pastEvents` (newest-first).

The range picker call changes to `minDate: null`, `dimBeforeDate: today`, with
`highlightedDates: eventCoverageDays([..._futureEvents, ..._pastEvents])`, and
`eventIdsInDateRange` fed from the combined list.

The per-event list keeps its current future list, and gains a collapsed
`אירועים שעברו (N)` expansion section beneath it that reuses the same
`CheckboxListTile` row. The search and category filter apply to both lists. The
selection-count denominator becomes future + past.

The "select all" toggle keeps operating on filtered **future** events only. Its label
in the unselected state becomes `בחר את כל האירועים העתידיים המסוננים כרגע`; the
cleared state keeps `בטל בחירה`. That label is materially longer than `בחר הכל`, and
it shares a `Row` with a `Spacer` and the "נבחרו X מתוך Y" counter — the label needs
to flex or wrap rather than overflow. The past section gets its own select-all for its
own filtered items.

Strings that say "עתידיים" and no longer should: the loading-error text
(`שגיאה בטעינת אירועים עתידיים`) and the empty state (`אין אירועים עתידיים לייצוא`).
The perPerson description keeps its wording — that mode really is future-only.

### Shared — `shavtzak/lib/core/utils/event_filter_utils.dart`

```dart
({List<Event> future, List<Event> past}) splitEventsByPast(
  List<Event> events,
  DateTime today,
);
```

Past means `endDate` (date-only) before `today`, matching the existing predicate and
`shamap_export_dialog.dart`. This lives here rather than inline in the widget because
there is no widget test for the export dialog — extracting the boundary logic is what
makes it testable at all.

## Data flow

```
AssignmentExportDialog
  getAllEvents() → drop deactivated → splitEventsByPast()
    ├─ future list (asc)          ─┐
    └─ past list (desc, collapsed) ┤→ user ticks events / picks a date range
                                    │   (picker: past days gray, still selectable)
                                    ↓
  onExport(perEvent, [ids incl. past])
    → ExportService.exportAssignmentsOnly
    → POST drive/export {type, mode, eventIds}
    → index.ts handler (admin-gated, non-empty eventIds required)
    → exportProductionDataToSheets
    → buildExportEventPools(eventsData, now, eventIds)
         rowPool        = future ∪ selected past (never deactivated)
         annotationPool = future only
    → serializeAssignmentsOnly(rowPool, annotationPool)
    → Apps Script → spreadsheet URL
```

## Error handling

- Selecting an event that is deactivated or absent still raises
  `DriveExportValidationError`, surfaced to the admin unchanged.
- `perEvent` with an empty selection is still rejected at `index.ts` with a 400.
- An event whose `endDate` fails to parse is treated as not-future by
  `isFutureOrTodayByEndDate` today and would now be exportable only if explicitly
  selected — acceptable, and unchanged in spirit.
- Client load failure keeps its existing error panel, with generalized wording.

## Testing

**`functions/src/drive_export.test.ts`** (497 lines, already the strongest coverage
in the change):

1. A selected past event produces rows in `perEvent`.
2. `perPerson` still excludes past events even when `eventIds` is non-empty.
3. Past rows carry **no** `(משובץ גם ב…)` mark, while a future row in the same export
   still gets one.
4. A selected *deactivated* past event still throws.
5. Updated assertion for the reworded validation message.

**`shavtzak/test/core/utils/event_filter_utils_test.dart`:** cases for
`splitEventsByPast` — boundary at today (an event ending today is future), multi-day
events spanning today, ordering of each list.

**Known gap:** no widget test exists for `AssignmentExportDialog` or
`DualCalendarDatePicker`, and this change does not add one. The dimming rule and the
collapsed section are verified by inspection in a real browser.

**Verification commands:**

```
cd shavtzak && flutter analyze     # zero NEW infos against the ~107 baseline
cd shavtzak && flutter test
cd functions && npm test
```

## Can the backend change be verified locally?

Yes — effectively all of it, with no deploy.

The change is a pure transformation: `buildExportEventPools` and
`serializeAssignmentsOnly` take injected data and an injected `now`, and
`__testSerializeAssignmentsOnly` already exposes that seam. `cd functions && npm test`
builds and runs the suite locally. The only parts not covered by unit tests are two
string literals and one wiring line in `exportProductionDataToSheets`.

The Functions **emulator is not a practical option here** and should not be planned
around: `firebase.json` has no `emulators` block, `backend_api_service.dart` builds
`Uri.https('us-central1-<project>.cloudfunctions.net', …)` with no localhost
override, and `getDriveConfig` posts to the live Apps Script regardless. Pointing the
app at a local backend would be its own change. There is also no staging backend —
one `api` deployment serves both prod and `/test`.

## Deployment

The developer's workflow is: run the app locally against **production** data, then
ship to production. `/test` is not part of it. That makes ordering critical, because
a local `flutter run` still calls the *deployed* `api`.

**Order:**

1. Implement and verify locally — `cd functions && npm test`, `cd shavtzak && flutter analyze && flutter test`.
2. **Deploy Functions first:** `firebase deploy --only functions:api`
3. Then run the client locally against prod and exercise a past-range export.
4. Merge to `main` — Flutter web auto-builds and deploys via `web.yml`.

Step 2 before step 3 is not optional: until it runs, the deployed backend rejects any
past event ID and the feature looks broken from the local client.

Deploying the backend ahead of the UI is safe **by design** — with no past IDs in the
request, `rowPool` equals today's future-only pool and `annotationPool` is unchanged,
so every existing export behaves identically. The change is a strict superset of
current behavior.

לפי אירוע is production-only (`enabled: !isTestMode`), so there is no `/test` smoke
path even if it were wanted. Final verification is one real export over a past range.
