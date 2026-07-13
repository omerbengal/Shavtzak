# Same-Day Double-Booking Mark — Design

**Date**: 2026-07-13
**Branch**: `feat/same-day-double-booking-mark`
**Status**: Approved by Omer (brainstorming session 2026-07-13)

## Overview

Request from Omer's boss, verbatim:

> סימן שבן אדם משובץ בעוד אירוע באותו היום (במסך שיבוצים, במסך מנהלים בתוך רשימת
> שיבוץ לאירוע, בייצוא לאקס לפי אירועים)

Put a mark next to a person who is **already assigned** to an event, when that same
person is **also assigned to a different event that shares a calendar day**. Three
surfaces, listed below.

This is a display-only feature. Nothing about how assignments are created, validated
or blocked changes. Double-booking is already possible today — via the
"שבץ בכל זאת" bypass in the constrained-members dialog, via the manual-assignment
wizard's warning, via the `שיבוץ מרובה` flag, or simply because an event's date was
moved after people were assigned. The app warns you *before* you double-book but
then shows nothing *afterwards*. This feature closes that gap.

## The rule

For an assignment of member **M** to event **E**, collect every event **O** where:

- `O.id != E.id`
- `O.isDeactivated == false`
- `O`'s date range overlaps `E`'s date range on at least one calendar day
  (day-precision, times ignored)
- `M` also has an assignment to `O`

If that set is non-empty, **M is marked on E**, and the mark names the events in the
set. The set is **sorted by start date, then by name** — every surface lists them in
that order, so a re-export of unchanged data produces a byte-identical file and a
tooltip does not reshuffle between rebuilds.

**The relation is symmetric and both sides must show it.** When a surface renders `O`,
`E` is the "other" event, so `M` is marked there too, naming `E`. This falls out for
free as long as each surface computes the map *relative to the event it is currently
rendering* — which is the required implementation. Do not "optimize" this into a
one-directional check.

Explicitly decided:

- **Members flagged `שיבוץ מרובה` (`allowMultipleAssignments`) ARE marked.** That flag
  means "may take several roles in the *same* event"; it says nothing about being in
  two *different* events on one day.
- **Multi-day events count** if they overlap on any single calendar day (5–7 July vs
  7 July → marked).
- **Deactivated events never count** as the other event `O`.
- Two roles in the *same* event is a different problem and already has its own ⚠
  mark. The two marks are independent and can appear together on one person.

## What already exists, and why we are not reusing it

`AssignmentSlot` already carries `sameDayAssignedMembers` / `sameDayEventInfo`, and
`AssignmentBloc` + `EventSummaryTile` already compute them. **Do not reuse these for
the mark.** They answer a *different question*: "which candidates should I hide from
the assign-dropdown", so they additionally filter by `canPerformRole(role)`,
`isAvailableForEventWithTime(event)`, and `!allowMultipleAssignments` — all wrong for
"is this already-assigned person double-booked". A member who is assigned to another
event but cannot perform *this* slot's role, or is flagged `שיבוץ מרובה`, is absent
from those maps yet must still be marked.

The new computation is its own, simpler predicate. It lives beside the existing one.

## New shared component

`shavtzak/lib/core/utils/same_day_assignments.dart` — pure functions, no Flutter, no
Firestore, directly unit-testable:

```dart
/// True when [a] and [b] overlap on at least one calendar day (day precision).
bool eventsShareDay(Event a, Event b);

/// memberId -> other non-deactivated events sharing a day with [event] that the
/// member is also assigned to. Members with no such events are absent from the map.
Map<String, List<Event>> sameDayOtherEventsByMember({
  required Event event,
  required List<Event> allEvents,
  required List<Assignment> allAssignments,
});
```

`eventsShareDay` replaces the three copy-pasted implementations that exist today
(`AssignmentBloc._eventsShareDate:2297`, `EventSummaryTile._eventsShareDay`, and the
inline copy in `ManualAssignmentFlowDialog`) so there is one definition of "shares a
day". This is the only refactor in scope; the rest of those call sites keep their
current behaviour.

## Surfaces

### 1. `שיבוצים` grid — `/admin/assignments` (`assignment_list_screen.dart`)

**Data.** New field on `AssignmentSlot`:

```dart
final List<Event> sameDayOtherEvents; // other events the ASSIGNED member is in
```

Added to `copyWith` and — critically — to `props`. Per the project's Equatable rule,
a field missing from `props` means the UI silently stops live-updating.

Populated in `AssignmentBloc` by a post-pass over the built slots, mirroring the
existing double-assignment post-pass, and applied to **every filled slot including
off-quota rows** (those are real assignments). The pass must run against the full
loaded event window *before* the UI's event filter — filtering the grid down to one
event must not erase that event's own marks. (It won't: the event filter is applied
in the widget, in `_filterAssignments`, not in the BLoC.)

Both slot-building paths need it — `_buildSlotsFromAssignments:1546` and
`_onRebuildAssignmentSlotsFromData:1842` are near-duplicates and each has its own
copy of the double-assignment pass.

**Required bug fix (blocking).** Both copies of the double-assignment post-pass
(`:1750`, `:2068`) rebuild the slot with the **raw constructor instead of
`copyWith`**, dropping `sameDayAssignedMembers` / `sameDayEventInfo`. Today that
silently degrades the "בעלי מגבלות / לא זמינים" dialog for anyone holding two roles
in an event. If left as-is it would also drop the new `sameDayOtherEvents` on exactly
the rows most likely to need it. Switch both to
`slot.copyWith(hasDoubleAssignment: true, otherRoles: otherRoleNames)`.

**UI.** In `_buildAssignmentCell`, between the dropdown and the ✕ button, when
`slot.isFilled && slot.sameDayOtherEvents.isNotEmpty`:

- `Icon(Icons.event_repeat, color: Colors.orange, size: 20)`
- `Tooltip`: `משובץ/ת גם ב: מופע ערב (12/07)` — several events comma-joined:
  `משובץ/ת גם ב: מופע ערב (12/07), טקס (12/07)`
- tap → `AlertDialog`, same shape as the existing `שיבוץ כפול` dialog:
  - title row: `Icon(Icons.event_repeat, color: Colors.orange)` + `שיבוץ באירוע נוסף באותו יום`
  - content: `משובץ/ת גם באירועים:` then one line per event — `מופע ערב — 12/07/2026`
  - action: `סגור`
- `Logger.action('open:sameDayAssignmentDialog', {...})`, matching the instrumentation
  convention of neighbouring taps.

Same treatment in `_buildOffQuotaRow`.

### 2. `מסך מנהלים` → per-event assignments popup

`/summary` → the 👥 `צפה בשיבוצים` button on an event card → `EventAssignmentsDialog`.

**Data.** `EventSummaryTile` already receives `allEvents` (every non-deactivated
event) and `allAssignments` (every assignment) from `SummaryScreen`. It calls
`sameDayOtherEventsByMember` for its event and passes the result into
`EventAssignmentsDialog` as a new optional named parameter, defaulting to `const {}`:

```dart
final Map<String, List<Event>> sameDayOtherEventsByMember;
```

`EventAssignmentsDialog` is the only consumer; its other constructor path (BLoC-loaded,
currently unused in `lib/`) simply gets the default empty map and shows no marks.

**UI.** In `_buildAssignmentRow`, next to the member's name, before the 📞 icon —
same icon, same tooltip, same tap-dialog as surface 1.

### 3. Excel export, `לפי אירוע` mode only (`functions/src/drive_export.ts`)

In `serializeAssignmentsOnly`, when `mode === 'perEvent'`, the team-member cell
becomes:

```
יוסי כהן (משובץ גם במופע ערב)
יוסי כהן (משובץ גם במופע ערב, טקס)      # 2+ events, comma-joined inside one paren
```

- The "other events" pool is **all events** (`eventsData`, not `futureEventsData`) minus
  deactivated ones — a person's real calendar, not the export's selection. Consequence,
  and it is correct: if the admin exports only `E`, M's row under `E` still reads
  `(משובץ גם ב-O)` even though `O` is not in the file. If they export both, M appears
  twice, each row naming the other.
- **The suffix is applied only in the final `rows.map(...)` projection.** The row object
  keeps the clean `teamMember` name, because the `perEvent` sort tiebreaks on
  `teamMember.localeCompare` — suffixing before sorting would shuffle rows.
- `perPerson` mode is untouched (`colorByTeamMember` there groups rows by name; the
  boss asked for `לפי אירוע` only).
- **No Google Apps Script change.** The mark rides inside the existing
  `שם חבר צוות` column, so the script's hard-coded 10-column layout (column widths,
  the D+E merge, the notes-wrap on column J) is unaffected.

## The three surfaces use different event pools (deliberate)

The rule above says "every event `O`" `M` is also assigned to, but "every event" is
not the same set on all three surfaces. This is a deliberate choice, not an
inconsistency — recorded here so it does not get "fixed" into a bug later.

- **The Excel export**'s pool is ALL events, including ones that have already ended.
  `drive_export.ts` passes the unfiltered `eventsData` as `allEventsData` into
  `serializeAssignmentsOnly`, deliberately not the future-filtered `futureEventsData`
  used for the exported rows themselves.
- **`/summary`**'s pool excludes ended events, with no way to widen it. `SummaryScreen`
  narrows `allEvents` down to `upcomingEvents` (`endDate >= today`) before any of it
  reaches `EventSummaryTile`.
- **`/admin/assignments`**'s pool excludes ended events *by default*, but — unlike
  `/summary` — the "show past events" filter widens it: `AssignmentBloc` gates the
  narrowing on `if (!FilterPersistence.showPastEvents)`.

**Consequence:** the export can name a same-day conflict that neither UI screen shows.
The reverse cannot happen — the export's pool is a superset of both UI pools. The gap
only bites when the *other* event `O` has fully ENDED while the anchor event `E` is a
still-running multi-day event: a conflict that is already history and cannot be acted
on. Widening `/summary`'s pool to close this gap would drag ended events into a screen
that is deliberately forward-looking only — see the reasoning inline at
`event_summary_tile.dart`, above the `sameDayOtherEventsByMember(...)` call:

> `allAssignments` is every assignment; `allEvents` is every non-deactivated event that
> has NOT yet ended (`SummaryScreen` narrows it to `upcomingEvents` before it reaches
> this tile). So the mark sees the member's real calendar rather than just this event's
> roster — with one deliberate gap: a conflict on a day that has already passed inside a
> still-running multi-day event is not marked. That conflict is history and cannot be
> acted on, and `/admin/assignments` applies the same window by default (it can widen it
> via the "show past events" filter; this screen has no such toggle).

## Non-goals

- The user-facing `מי איתי` popup (`EventTeamMembersDialog`) — a near-copy of surface
  2's dialog. Left alone deliberately; the boss listed three surfaces.
- The shared assignments **image** from the surface-2 popup
  (`event_assignments_share_card.dart`). It is a hand-out for the team; a
  "this person is elsewhere too" mark is noise there.
- `לפי אדם` export mode.
- Any change to assignment creation, validation, or blocking.

## Testing

- **`same_day_assignments_test.dart`** (new, pure unit): single-day match; no match;
  multi-day partial overlap; deactivated `O` excluded; `שיבוץ מרובה` member still
  matched; member with two roles in the *same* event not matched by itself;
  symmetry (querying from `E` and from `O` each names the other).
- **`assignment_bloc` test**: a filled slot whose member is in another same-day event
  gets `sameDayOtherEvents`; and — regression for the fix above — a slot that is *both*
  double-role and same-day keeps `sameDayAssignedMembers` after the double-assignment
  pass.
- **Widget tests**: the icon renders in the grid row and in `EventAssignmentsDialog`
  when the data is present, and is absent when it is not.
- **`drive_export.test.ts`**: `perEvent` suffixes the name for a double-booked member
  (one other event, and two); `perPerson` does not; sort order is unaffected by the
  suffix; a deactivated other-event produces no suffix.

## Deployment

| Change | How it ships |
| --- | --- |
| Flutter (surfaces 1 & 2) | **Automatic** — `web.yml` builds and deploys to GitHub Pages on merge to `main`. |
| `functions/src/drive_export.ts` (surface 3) | **Manual** — `firebase deploy --only functions`. Does not ship on merge. |
| Google Apps Script | **No change required.** |

## Risks

- `serializeAssignmentsOnly` now needs an events-by-member index over all assignments.
  The export already reads every assignment and event into memory, so this is an
  in-memory group-by, not new I/O.
- The `AssignmentSlot` props change touches a hot path (the grid rebuilds on every
  assignment stream tick). `sameDayOtherEvents` holds `Event` objects, which are
  `Equatable`, so the comparison stays value-based and correct.
