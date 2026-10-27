# Custom hours for one member's assignment (partial attendance)

**Date:** 2026-10-26
**Status:** approved 2026-10-27. The user delegated the review ("I trust you.
You can start."); the section "Revisions after Project 1" at the end was
written then and **overrides** anything above it that disagrees.
**Depends on:** "Project 1", SHIPPED 2026-10-27 (main `6f148f1`). Every
conflict check now judges an event as one continuous stretch
(`eventStretch` in `shavtzak/lib/core/utils/event_stretch.dart`, twin in
`functions/src/event_stretch.ts`), and a pending unavailability blocks like an
approved one. This feature plugs a member's custom hours into that same rule.
**Mockups (approved):** `2026-10-26-assignment-custom-hours/` next to this file
(`custom-hours-dialog.html` — option **A** was chosen; `event-save-resolve.html`;
`duplicate-custom-hours.html`; `member-card.html` — option **B** was chosen;
`replace-member.html`)

## Why

Some members are assigned to an event but attend only part of it: they come
only on day 1 of a 2-day event, arrive at 14:00, leave right after the show,
or come the evening before. Today the only way to say so is free text in
"הערות לשיבוץ". That text shows in the app, but the member's personal ICS
calendar feed still shows the whole event (an "התייצבות והכנות" block plus the
event block), and every conflict check still judges the member against the
whole event.

The feature gives one member's assignment its own start and end. The
member's calendar, their screens, and conflict checks all follow it.

Conflicts between members and events are taken very seriously by the user.
Every place that says "conflict" or "no conflict" must be right about the
hours that actually apply to that member.

## Goals

- An admin can give one member's assignment in one event a custom start
  (date + time) and a custom end (date + time).
- The member's ICS feed shows **one** block, from their start to their end,
  instead of the usual assembly + main pair.
- Every place that shows the assignment shows the member's own hours.
- Every conflict check uses the member's own hours when they have them.
- Changing an event's dates/times can never leave stale custom hours behind:
  the admin must resolve them before the event change is saved.
- Duplicating an event can carry custom hours over, moved to the new dates,
  with confirmation.

## Non-goals

- Changing the event itself. Custom hours belong to one member's assignment;
  the event's own dates and times are untouched.
- Members setting their own hours. Only admins set them.
- Per-day schedules ("day 1 14:00–23:00 and day 2 08:00–12:00"). One
  continuous span per member per event.
- Custom hours for the old shared Google Calendar sync code
  (`calendar_sync_backend.ts` / `calendar_integration.ts`). Only the
  per-member ICS feed (`functions/src/calendar_feed.ts`) matters.

## Anti-goals (would make this a failure even if it "works")

- A member's calendar or screen showing hours that no longer match the event
  because the event moved and nobody was told.
- A conflict warning that is wrong about the hours that actually apply (shown
  when the member is fine, or missing when they are not).
- More icons on the admin assignment row. Mobile rows are already crowded;
  custom hours appear as **text**, never as a new icon or a persistent badge.

## Decisions (from the user)

| Topic | Decision |
|---|---|
| Scope | One member's assignment in one event. Not an event change. |
| Granularity | Any date and time. Start and end may fall **before the event starts or after it ends** (e.g. "the evening before"). |
| Who sets it | Admins only. |
| Several roles in one event | One member has one set of hours per event, shared by all their roles in it (the ICS feed already merges a member's roles into one entry). |
| Where it's set | Inside the existing "הערות לשיבוץ" dialog (right swipe on the row on `/admin/assignments`). Option **A**: a switch "שעות מותאמות ל<name>", then "מגיע/ה" (date + time) and "עוזב/ת" (date + time), pre-filled with the event's normal assembly start and end. |
| Date picker | The picker used for those dates marks the event's **start date and end date**, so the admin sees where the event sits. |
| ICS feed | With custom hours: **one** block from start to end. No "התייצבות והכנות" block. |
| Admin assignment row | One text line in the notes area under the row (where "הערות לשיבוץ" already shows). No icon. |
| Member card in "השיבוצים שלי" | Option **B**: the member's own hours *replace* the matching rows, with the event's own value in brackets: the date row shows the member's day(s) "(האירוע עד 28.10)", "ההגעה שלך: 14:00 (התייצבות צוות 12:00)", "היציאה שלך: 27.10 23:00 (סיום צוות 28.10 23:30)". Show times (תחילת המופע, סיום מופע משוער, etc.) stay as they are. |
| Everywhere else the assignment shows | Show the member's hours ("מי איתי באירוע?", the event image export, event assignments dialog, event team-members dialog, admin row). |
| Conflicts | When an assignment has custom hours, conflict checks use them instead of the event's hours, in both directions: hours that skip day 2 drop a day-2 conflict; hours that start the evening before add a conflict on that evening. |
| Constraint warnings | Show **approved and pending** constraints, labeled: "⚠️ מתנגש עם אילוץ מאושר של אבי: 28.10 (כל היום)" / "⚠️ מתנגש עם אילוץ ממתין לאישור של אבי: 28.10 (כל היום)". |
| Event dates/times change | The event **cannot be saved** until every member with custom hours in it is resolved. A modal lists them (see below). No "stale" state ever exists. |
| No persistent marker | No badge/icon on rows for stale or custom hours. |
| Event duplication | In the duplicate modal, under the "copy assignments" switch, an indented sub-switch "שכפל שעות מותאמות", **on by default**. When on, the duplication window shows a "⏰ שעות מותאמות" section listing each member's hours moved to the new dates, every row ticked; the admin confirms or unticks. |
| Replacing a member who has custom hours | Two steps (see below). The picker judges against the event's hours, with a hint for who fits the slot's custom hours; then a popup asks which hours the new member gets, each choice showing its own conflict result. |

## Behaviour in detail

### 1. Setting hours (notes dialog, `/admin/assignments`)

- The "הערות לשיבוץ" dialog gains, under the existing fields (לייבל, notes,
  טלפון חד פעמי לשיבוץ), a switch "שעות מותאמות ל<member first name>".
- Switch on: two rows, "מגיע/ה" and "עוזב/ת", each a date field and a time
  field. They start filled with the event's normal span. A hint line under
  them shows that span.
- **The event's normal span** (used for the pre-fill, the hint, "שעות האירוע
  הרגילות" and "להסיר שעות מותאמות" displays, and the "לא חופף לאירוע החדש"
  check) is exactly what the ICS feed shows a member today: assembly time
  (fallback: start time) on the start date → team end time `teamEndTime`
  (fallback: show end `endTime`) on the end date, rolled to the next day when
  it wraps past midnight (`buildDesiredAppEventState` in
  `calendar_sync_backend.ts`). An event missing those times has no span; the
  pre-fill is then the start date 00:00 → end date 23:59 *(my call)*.
- Time fields reuse the typable time-field pattern already used in the event
  modal and the constraint dialogs (numpad entry, wheel behind a clock
  button).
- Date fields open the app's date picker with the event's start and end dates
  marked.
- Validation: both ends required when the switch is on; end strictly after
  start. No other limit (before/after the event is allowed).
- Switch off: the assignment has no custom hours (removing them is just
  turning it off).
- On save, if the new hours collide with any of the member's approved or
  pending constraints, show the warning lines (format above) and ask the
  admin to confirm. Confirming saves anyway, like assigning a constrained
  member today.
- Shared hours: saving hours on one of the member's roles in the event applies
  the same hours to **all** of that member's assignments in that event. The
  dialog says so when the member has more than one role there
  ("השעות יחולו על כל התפקידים של דנה באירוע").
- *My call:* this is a **staged** change on `/admin/assignments`, exactly like
  editing notes today (`StageNotesChange` → written by `assignment.saveBatch`
  on "שמירה"). The yellow dirty border applies as for notes.

### 2. Showing hours

Format *(my call)*: `27.10 14:00 – 27.10 23:00`; when both ends are on the
same day, the builder may shorten to `27.10 14:00–23:00`.

- **Admin assignment row** — a line "שעות מותאמות: …" at the top of the notes
  area under the row, before "הערות לשיבוץ: …". Text only.
- **"השיבוצים שלי" card** — option B above. Upcoming/past grouping stays based
  on the event's dates *(my call)*.
- **"מי איתי באירוע?"**, **event assignments dialog**, **event team-members
  dialog**, **event image export** (`event_assignments_share_*`) — a short
  hours line next to the member, in the same place notes appear there.
- **ש.מ.פ clipboard export** (`shamap_export_dialog.dart`) — each member's line
  uses **their own** start and end dates (from their custom hours) instead of
  the event's (user-confirmed).

### 3. ICS feed (`functions/src/calendar_feed.ts`, `buildMemberFeedParts`)

- If the member's assignments in the event carry custom hours: emit **one**
  timed part from start to end, title = the event's main title, location and
  description as today (description = roles + notes). Use the existing
  `…-main-<memberId>` UID so calendar apps update the entry in place; the
  assembly UID simply stops appearing.
- This holds even when the event itself would render as all-day *(my call)*.
- Without custom hours: unchanged.
- Timezone handling as today (`TZID=Asia/Jerusalem` with local
  `YYYY-MM-DDTHH:MM` prefixes).

### 4. Conflicts

**One rule, used everywhere:** the window a member is judged against for an
assignment = their custom hours if set, otherwise the event's window as today.

- Client: today `TeamMember.isAvailableForEventWithTime(event)` is called from
  ~8 places (assignment entity, assignment repository, assignment bloc,
  assignment list screen, summary tile, event bloc / duplication, manual
  assignment flow). Add a window-aware variant and route every call that is
  about an *existing or chosen* assignment through it. Calls that are about
  "can this member fill this event at all" (choosing a new member) keep the
  event's window.
- A custom window is one continuous span, judged with **the same continuous
  rule Project 1 introduces for events**: a constraint conflicts if it touches
  any minute of the span, nights and past-midnight included (user, 2026-10-26:
  "you can't know" whether someone is off at night, so the safe side is to
  warn). The only difference from an event is where the span starts and ends.
- Backend: `memberAvailableForEvent` in `functions/src/index.ts` uses the same
  rule, kept in sync with the client (Project 1 sets up the shared test
  cases that run against both).
- **"Already booked at another event that day"** (`eventsShareDay` /
  `sameDayOtherEventsByMember`, plus the backend copy in the by-event Drive
  export): for an assignment with custom hours, only the days its hours touch
  count as booked. Still whole days, as today. Example (user-confirmed): Dana
  comes only on day 1 of event A, so she is free for event B on day 2. If she
  arrives the evening before, that evening's day counts as booked.
- Note: `assignment.saveBatch` already passes `bypassAvailability: true`
  (conflicts are surfaced client-side with admin confirmation). That stays.
  The backend still validates the shape of the hours (below).
- Non-permanent members marked available for the event (`availableEventIds`)
  stay available whatever their hours *(my call)*: they said yes to the
  event; custom hours only narrow or shift it by admin decision.
- Members with `allowMultipleAssignments` keep bypassing conflict checks.
- The "constraints that collide with this event" button
  (`event_constraint_collisions*`) uses each assigned member's own hours
  *(my call)*.
- Warnings list approved **and** pending constraints, labeled by status. Only
  approved ones count as a real conflict where the app distinguishes the two
  today *(my call — pending ones are shown, never block)*.

### 5. Changing an event's dates or times

Trigger: an admin saves the event form and **any** of start date, end date,
assembly time, start time, actual show start time, end time or team end time
changed, **and** at least one assignment in the event has custom hours
*(the field list is my call; "any date or time field" errs on the safe side)*.

Modal (mockup `event-save-resolve.html`): title "⏰ לחלק מהצוות יש שעות
מותאמות", the event's old → new dates/times, then one card per member with
their current hours and four choices:

| Choice | Result |
|---|---|
| להזיז עם האירוע | Shift both ends by the number of days the event's start date moved; clock times unchanged. Hidden when only times changed (the shift would be zero). |
| להשאיר כמו שזה | Keep the hours unchanged. If they no longer overlap the new event at all, the button shows "⚠️ לא חופף לאירוע החדש" (still allowed). |
| לערוך… | Opens the same date + time fields inline in the card. |
| להסיר שעות מותאמות | The member gets the event's normal hours. |

- Bulk shortcut at the top: "להזיז את כולם עם האירוע (+N ימים)" (only when the
  dates moved).
- Each card shows constraint warnings (approved + pending) for the hours that
  would result from its selected choice.
- "שמור אירוע" is disabled until every card has a choice ("נשאר N לבחירה").
  "ביטול" returns to the event form with nothing saved.
- **Atomic and enforced by the backend** *(my call)*: `event.update` accepts the
  resolutions with the event and writes the event and the changed assignments
  in one batch. If the dates/times changed and an assignment with custom hours
  in that event is not covered by the request, the backend refuses (409, Hebrew
  message). This protects against a second admin adding custom hours between
  the modal opening and the save, and against any other code path that
  updates the event.

### 6. Duplicating an event

- In the duplicate modal (the event form in duplication mode), when "copy
  assignments" is turned on, an indented sub-switch "שכפל שעות מותאמות"
  appears, **on by default**. *My call:* it appears only if at least one
  assignment in the source event has custom hours.
- Sub-switch on and at least one copied assignment has custom hours → the
  existing duplication window (`DuplicationConflictResolutionDialog`, "בחירת
  שיבוצים לאירוע המשוכפל") opens even when there are no other conflicts, with
  a new section "⏰ שעות מותאמות (N)": per member, old hours struck through and
  the moved hours under them, a checkbox **ticked by default**, a "סמן הכל"
  link, and constraint warnings (approved + pending) for the moved hours.
  Unticked members get the new event's normal hours.
- Moved = shifted by the number of days between the source event's start date
  and the new start date; clock times unchanged.
- If a member is removed in the "קונפליקטי זמינות" section, their row in the
  custom-hours section disappears. The availability section is computed
  against each member's resulting window (moved hours if ticked, the new
  event's hours if not).
- Sub-switch off → no custom hours are copied; the window opens only for the
  conflicts it opens for today.

### 7. Replacing a member who has custom hours

Mockup `replace-member.html`. When the admin replaces Dana (custom hours) in
a slot with another member:

1. **Picking:** the picker and the "constrained members" dialog judge
   availability against the **event's** hours, as today. Addition: in the
   constrained-members list, members who would be free during the slot's
   custom hours get a green text "פנוי בשעות של <name>". Text only.
2. **After picking:** a popup "⏰ ל<name> היו שעות מותאמות" asks which hours the
   new member gets:
   - "לשמור את השעות של <name>" (shows the hours)
   - "שעות האירוע הרגילות" (shows the event span)
   - "שעות אחרות…" (opens the date + time fields)

   Each choice shows its own conflict result **for the new member** ("✅ אין
   התנגשות עם אילוצים של יוסי" / "⚠️ מתנגש עם אילוץ מאושר של יוסי: 28.10 (כל
   היום)", pending ones labeled). *My call:* nothing is preselected, because
   the hours may have been made for Dana's own needs. "ביטול" undoes the
   replacement and Dana stays.
- Edge *(my call)*: if the incoming member already holds another role in the
  same event, the shared-hours rule applies. Whatever is chosen becomes their
  hours for every role in the event, and the popup says so. If they already
  have custom hours there, the popup adds a fourth choice, "השעות הקיימות של
  <new member>" (still nothing preselected).
- Removing an assignment (swipe delete) removes its hours with it.

## Data *(my calls; the builder may adjust names)*

- On each assignment document, two optional fields: `customStartAt` and
  `customEndAt`, Israel-local strings `yyyy-MM-ddTHH:mm`. Both present or both
  absent. Local strings, not Timestamps, to avoid the UTC-midnight
  off-by-one already seen with `events.startDate`, and because the ICS feed
  already works with local `YYYY-MM-DDTHH:MM` prefixes.
- Shared-hours rule enforced by the backend wherever assignments are written
  (`assignment.insert`, `assignment.update`, `assignment.updateMetadata`,
  `assignment.saveBatch`, `assignment.insertBatch`, `event.update` with
  resolutions): after the write, every assignment of one member in one event
  has identical custom hours (or none). `saveBatch` already loads the live
  assignments of every affected event, so the check fits there.
- **Exception *(my call)*:** members with `allowMultipleAssignments` (the
  placeholder "תגבורת …" members, where each slot is a different real person)
  are exempt from the shared-hours rule: their hours are per assignment, the
  notes dialog does not show the "applies to all roles" line, and the ICS feed
  (which no real person subscribes to for them) uses the earliest start and
  latest end among their assignments in the event.
- Backend validation: format, both-or-neither, end > start.
- Drive "שיבוצים" sheet (`drive_export.ts`, a raw data dump with English
  headers): append two columns `customStartAt`, `customEndAt` at the end;
  existing columns unchanged *(my call)*.
- Entity/model: `Assignment` gains the two fields in `props`, `copyWith`,
  `toFirestore`/`fromFirestore`. Equatable rule from CLAUDE.md applies.
- Backward compatible: old documents have no fields → behaviour unchanged.

## Constraints

- Flutter web, Hebrew, RTL everywhere. Left/right in RTL must be checked
  visually, not by API names.
- Real-time: all display paths read from the existing `watchX` streams; no
  awaited one-shot `getX()` gating first paint.
- Functions do not auto-deploy. This feature changes `functions/` (feed,
  availability, validation, `event.update`). Deploy Functions
  (`firebase deploy --only functions`, verify with `firebase functions:list`)
  **before** the user tests the client locally, and the backend change must
  be safe to ship ahead of the UI (old clients send no custom hours and no
  resolutions; `event.update` from an old client must still work when no
  assignment in the event has custom hours).
- The user tests locally against **production** data. No `/test`-only safety
  net.
- Tests: `cd functions && npm test` for the feed, the window rule, the
  `event.update` refusal and the shared-hours validation; Flutter unit and
  widget tests for the window rule, the dialogs and the bloc changes.

## Left to the builder

- Exact widget structure and file split; reuse of the existing time-field and
  date-picker widgets.
- How the staged-change machinery carries custom hours (a new staged change
  type vs extending the notes change), as long as it behaves like notes.
- Exact Hebrew wording beyond what is quoted above (gendered forms follow the
  app's existing "/" style).
- Where the shared window function lives (likely next to
  `time_range_utils.dart`).
- Whether the replace-popup and the event-save modal share a "custom hours
  choice card" widget.

## Revisions after Project 1 (2026-10-27)

Written after Project 1 shipped and the code was re-surveyed. Each item
overrides the text above where they disagree.

1. **The event's normal span is `eventStretch(event)`** (backend:
   `eventStretchFromData`), the span every conflict check uses. It is used
   for the pre-fill, the hint, "שעות האירוע הרגילות", "להסיר שעות מותאמות"
   and the "לא חופף לאירוע החדש" check. Missing times fall back to its
   00:00 / 24:00 edges (24:00 shows as 00:00 of the next day). This replaces
   the ICS-based definition and the 23:59 fallback in §1.
2. **Pending constraints block, exactly like approved ones.** This is the
   user's Project 1 decision, and it replaces the §4 call "pending ones are
   shown, never block". Warnings still label each one: "⚠️ מתנגש עם אילוץ
   מאושר של <first name>: <label>" / "⚠️ מתנגש עם אילוץ ממתין לאישור של
   <first name>: <label>", where the label is `constraintShortLabel`
   (`constraint_labels.dart`).
3. **Storage format.** Hours are stored as `formatWallMoment` output:
   `yyyy-MM-ddTHH:mm`, zero-padded, on the Israel wall clock.
   - The new client always sends both keys, as `null` when there are no hours.
   - On an update, an explicit `null` clears the hours.
   - An **absent** key leaves the stored hours untouched. After a deploy, users'
     devices run the previous build for one open, and an old build's update
     carries no hours. Reading absent as `null` would silently erase hours that
     a new build set.
4. **One window rule, both sides, shared cases.**
   - Window = the assignment's custom hours when both parse and the end is
     after the start; otherwise the event stretch.
   - Readers never trust stored data blindly: unreadable hours fall back to
     the event stretch.
   - `shared/test-fixtures/event_conflict_cases.json` gains cases with an
     optional `customHours: {start, end}`, and both runners judge them.
5. **Which checks use the member's hours.**
   - The assignment's window is used by every check about an existing or
     chosen assignment:
     - `AssignmentRepository.checkConflicts` and
       `Assignment.hasAvailabilityConflict`.
     - The duplication flags.
     - `findNewlyConflictingAssignments` (the dialog "your new constraint hits
       these assignments").
     - The "constraints that collide with this event" button, for members
       assigned with custom hours.
     - The backend `memberAvailableForEvent`, when a write carries hours.
   - Checks about picking a member for a slot keep the event stretch: the
     picker lists, "בעלי מגבלות", and the manual-assignment flow.
   - `shouldCheckAvailability` and `saveBatch`'s bypass stay as they are:
     hours are admin-confirmed in the client, like notes.
6. **Same-day booking by days touched.**
   - An assignment's days are the calendar days its window touches: from the
     start's day to the day of the last minute before its end. With no
     custom hours they are the event's dates, as today.
   - This applies on both sides of every same-day check: slot builders,
     summary tile, manual flow, filled-slot marks, and the Drive by-event
     export.
7. **`assignment.updateMetadata` is unchanged.** It never writes hours, so it
   cannot break the shared-hours rule, and no UI calls it.
8. **ICS with several assignments in one event.** One part, from the earliest
   custom start to the latest custom end among the member's assignments
   there that carry valid hours. For a normal member these are all equal
   (shared rule). For an `allowMultipleAssignments` member it is the
   envelope, as §Data says.
9. **Drive.**
   - The full raw export (`serializeAssignments`, English headers) appends
     `customStartAt` and `customEndAt`.
   - The assignments-only export keeps its 10 columns, because the Apps
     Script formatting is index-coupled. It changes only through item 6.
10. **Changing an event's dates/times.**
    - The client already knows which assignments carry hours (from the live
      stream), so the 409 is a plain Hebrew message for the race case, not a
      structured body: "לחלק מהצוות נוספו שעות מותאמות בינתיים — יש לפתוח את
      האירוע מחדש".
    - The resolve modal runs **before** the existing quota-reduction step, so
      "ביטול" leaves nothing written.
    - The backend ignores resolutions for assignments no longer in the event
      (e.g. deleted by a quota reduction). It also ignores resolutions when no
      date/time field changed.
    - The event write and the resolved assignments go in one Firestore
      transaction.
11. **Duplication.**
    - The sub-switch "שכפל שעות מותאמות" appears only when the source event
      has an assignment with hours. The form reads that from the source
      event's assignments stream (first value), never from an awaited
      one-shot get.
    - Moved hours shift by whole calendar days, from the source start date to
      the new start date.
12. **Filling or replacing a slot (§7, generalised).**
    - The hours popup appears after picking whenever the slot's previous
      occupant had hours **or** the incoming member already has hours in this
      event.
    - Choices, shown only where they apply: the previous occupant's hours;
      the incoming member's existing hours; שעות האירוע הרגילות; שעות אחרות….
    - Nothing is preselected.
    - The choice applies to every role of the incoming member in the event
      (shared rule), except for `allowMultipleAssignments` members.
    - Without either condition, nothing changes from today.
13. **Display format.** Days use `d.M` like the constraint labels:
    `27.10 14:00 – 28.10 02:00`, or `27.10 14:00–23:00` when both ends fall
    on one day.
14. **Project 1 follow-ups folded in.**
    - `WallInterval` asserts its ends are UTC.
    - `constraintStatusLabel` labels a rejected constraint as rejected, never
      as approved.
15. **Direct creates inherit the member's hours.**
    - Some paths create an assignment directly through `assignment.insert` or
      `assignment.insertBatch`: the summary tile, the manual-assignment flow,
      and "שבץ בכל זאת".
    - When such a create carries no hours and the member already has hours in
      that event, the backend copies those hours onto it.
    - A create that carries different hours is refused with 400.
    - `saveBatch` never inherits. The staged client states hours explicitly. A
      batch that leaves a member with different hours across roles in one event
      is refused with 400, but only for groups the batch touches.
