# Design — Invite all permanent staff to the calendar when an event has no assignments

**Date:** 2026-05-18
**Status:** Approved (pending spec review)
**Branch:** `worktree-calendar-invite-all-permanent`

## 1. Problem & goal

The app already syncs each `Event` to Google Calendar (1–2 calendar events — "assembly" and
"main" — depending on the event's time fields) and keeps the attendee list equal to the event's
assigned team members.

Requested feature: provide a way to invite **all permanent team members** to an event's calendar
event(s) **while the event has no assignments**, so the permanent staff sees the event on their
calendars before anyone is specifically assigned. Once the first person is assigned, the calendar
must revert to inviting only the assignee(s) — which is exactly today's behavior.

This is **opt-in per event**, controlled by a new toggle in the event modal (not automatic, not a
separate button).

## 2. Scope

### In scope
- A new persisted boolean on `Event`.
- A new toggle in the event form modal, coupled to the existing "permanent team only" toggle.
- A rule, mirrored in the Flutter client **and** the Cloud Functions backend, that substitutes
  "all eligible permanent members" for the (empty) assignee email list when the event qualifies.

### Out of scope
- Creating real `Assignment` records. This feature only changes **Google Calendar attendees**.
  (Creating assignments would itself violate the "no assignments" condition.)
- Any change to the existing per-assignee attendee behavior.
- Any new button, screen, or save-time confirmation dialog.
- The `declined` `AssignmentStatus`. The decline action is not a used feature of this app, so
  assignment status is irrelevant to this design (see §5).

## 3. Key architectural constraint (drives the whole approach)

The Google Calendar attendee list is computed in **two independent places**:

1. **Flutter client** — `CalendarSyncService.syncAttendeesForAppEvent(eventId)`
   (`shavtzak/lib/core/services/calendar_sync_service.dart` ≈ lines 635–693). It loads the
   event's assignments, collects assignee emails, and pushes the list via
   `GoogleCalendarService.updateEventAttendees(...)` → backend action `updateEventAttendees`
   (`functions/.../calendar_integration.ts` ≈ line 1781), which applies the client-provided list
   verbatim.
2. **Cloud Functions backend reconcile path** —
   `syncAppEventCalendars → reconcileSingleAppEvent → readEventAttendeeEmails`
   (`functions/src/calendar_sync_backend.ts`, `readEventAttendeeEmails` ≈ lines 827–868,
   `reconcileSingleAppEvent` ≈ lines 1051–1149). This path **independently re-derives the
   attendee list from assignments**, bypassing the client. It runs on the admin
   "sync events and constraints" action and on background / best-effort syncs.

**Consequence:** a client-only change would work until the backend reconcile ran, which would
then silently overwrite the all-permanent invite list with an empty list (zero assignments) —
breaking the required "sticky" behavior. Therefore the rule must exist on **both** sides.

### Approach chosen
**Mirror a single small rule helper on each side.** Attendee logic is already duplicated
client/backend today, so this matches the existing architecture and is the lowest-risk option.

Rejected alternatives:
- *Client-only change* — rejected: backend reconcile silently wipes the invites.
- *Centralize all attendee computation in the backend (client stops computing)* — rejected:
  large, risky refactor of a working path; out of scope for this feature.

## 4. Data model

Add one field to the `Event` entity, mirroring the existing `isDeactivated` boolean pattern
end to end:

- **`Event.inviteAllPermanentWhenUnassigned`** — `bool`, default `false`.
  - `shavtzak/lib/domain/entities/event.dart`: add to constructor (`= false` default),
    `copyWith`, and **`props`** (required for real-time UI updates per the project's Equatable
    rule).
  - `shavtzak/lib/data/models/event_model.dart`: `toFirestore()` writes
    `'inviteAllPermanentWhenUnassigned': inviteAllPermanentWhenUnassigned`; `fromFirestore()`
    reads `data['inviteAllPermanentWhenUnassigned'] as bool? ?? false`.
  - It flows through `CreateEvent` / `UpdateEvent` automatically because those carry the full
    `Event` object (`event_bloc.dart` `_onCreateEvent`/`_onUpdateEvent` ≈ lines 286–332).

Stored on the `events` document → automatically test/prod-isolated (env-aware collection
prefix), and it **survives event edits**, which is what makes the behavior "sticky" with no
extra state to manage.

## 5. The rule

Let `event` be the specific event being synced. The **all-permanent substitution applies when
all of the following are true**:

1. `event.inviteAllPermanentWhenUnassigned == true`, **and**
2. the event is permanent-only — `event.relevantForExtendedTeam == false`
   (defensive guard mirroring the UI coupling in §6; prevents inconsistent data from
   misbehaving), **and**
3. **this specific event has zero assignment records** (scoped strictly to this event:
   client uses `getAssignmentsByEvent(eventId)`; backend uses
   `.where('eventId', '==', eventId)`. Never global across events.)

When it applies, the attendee email list = the email of **every team member where**
`isPermanent == true && isActive == true && isArchived == false` and `email` is non-null and
non-empty (after trimming).

Otherwise, behavior is unchanged: attendees = emails of the event's assignees (today's logic).

**Assignment status is not considered.** The `declined` status exists in the enum but the
decline action is not a used feature of the app, so "zero assignment records for this event"
is the exact, simplest trigger.

This rule is evaluated **live on every sync**, so "sticky + self-resuming" falls out for free
with no state machine:
- Save event with the toggle ON and no assignments → all permanent invited.
- First assignment created → existing assignment→sync hook re-runs → only the assignee.
- All assignments later deleted while toggle still ON → next sync → all permanent again.
- Toggle OFF → today's behavior, always.

### Where the rule lives
- **Client:** a private helper used inside `CalendarSyncService.syncAttendeesForAppEvent`.
  It must additionally load the `Event` (the method currently only loads sync-state +
  assignments) to read the two flags, and filter `DatabaseInterface.getTeamMembers()` in
  memory. No new `DatabaseInterface` method and no Firestore index are required (team size is
  small).
- **Backend:** a single shared helper that `readEventAttendeeEmails` (and any other path that
  derives attendees from assignments) routes through. `reconcileSingleAppEvent` already holds
  the event document (`eventData`), so the two flags are available without an extra read; the
  eligible-member list is an in-memory filter of the team members collection. The
  implementation plan must enumerate and route **every** backend attendee-from-assignments
  entry point through this one helper (known entry point: `readEventAttendeeEmails` /
  `reconcileSingleAppEvent`; also verify `syncAppEventCalendars`, the best-effort/
  fire-and-forget sync, and the admin "sync events and constraints" action).

## 6. UI — one toggle in the event modal

Add a new `SwitchListTile` **directly below** the existing "permanent team only" switch in
`shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart` (existing switch
≈ lines 1977–1987, title `'צוות קבוע בלבד?'`).

- **Title:** `הזמן את כל הצוות הקבוע כשאין שיבוצים?`
- **Subtitle:** `כשאין אף שיבוץ באירוע, כל הצוות הקבוע עם אימייל יוזמן ליומן. עם השיבוץ הראשון – רק המשובצים יוזמנו.`
- **Default:** OFF for new events; for existing events, initialized from
  `widget.event?.inviteAllPermanentWhenUnassigned ?? false`.

### Coupling to the existing "permanent team only" switch
Polarity note: the existing switch's state variable `_relevantForExtendedTeam` is `true` when
the switch is **ON** = "permanent team only" (it is persisted inverted as
`relevantForExtendedTeam: !_relevantForExtendedTeam`, modal save ≈ line 574; init
≈ line 152).

- The new toggle is **interactive only while the "permanent team only" switch is ON**
  (`_relevantForExtendedTeam == true`). When OFF, render it disabled/grayed
  (`onChanged: null`) and shown as off.
- Extend the existing switch's `onChanged`: when it is turned OFF, also set the new
  state variable to `false` (and mark the form dirty).
- On save, persist defensively:
  `inviteAllPermanentWhenUnassigned: _relevantForExtendedTeam ? _newToggleValue : false`
  (never persist `true` for a non-permanent-only event). Save dispatch is unchanged
  (`CreateEvent`/`UpdateEvent` with the full `Event`, modal ≈ lines 578–584).

## 7. Triggers (all already exist — reused, no new wiring)

- **Event create/update:** `EventBloc._onCreateEvent`/`_onUpdateEvent` →
  `_syncEventToCalendar` → `SyncAppEventToCalendar` →
  `CalendarSyncService.syncAppEventToCalendar`, which already auto-calls
  `syncAttendeesForAppEvent` (`calendar_sync_service.dart` ≈ line 435). Saving an event with
  the toggle ON and no assignments therefore performs the invite immediately — **no separate
  button is needed.**
- **Assignment create/update/delete:** `AssignmentBloc._syncAttendeesForAffectedEvents`
  (`assignment_bloc.dart` ≈ lines 1313–1333) → `SyncAttendeesForAppEvent` →
  `syncAttendeesForAppEvent`. This is the existing mechanism that reverts to per-assignee and
  also self-resumes when assignments return to zero.
- **Backend admin/background reconcile:** `syncAppEventCalendars` → `reconcileSingleAppEvent`
  → shared attendee helper (the §3 path that mandates the backend mirror).

## 8. Consequences accepted by the product owner

- **Real emails:** enabling the toggle on a zero-assignment event emails the entire eligible
  permanent staff; creating the first assignment then sends calendar cancellations to all of
  them plus an invite to the assignee. This is the intended behavior.
- **No save-time confirmation dialog** (explicitly not wanted).
- Test/prod isolation and real-time UI updates require no extra work (env-aware collections on
  both sides; covered by adding the field to `Event.props`).

## 9. Risks & mitigations

- **Client/backend rule drift:** the rule is duplicated in Dart and TypeScript. Mitigation:
  keep it tiny and centralized in exactly one helper per side; document the predicate (§5)
  identically in both; cover both with the acceptance criteria in §10.
- **Missed backend entry point:** if a backend attendee-derivation path is not routed through
  the shared helper, that path would wipe the invites. Mitigation: the implementation plan
  must enumerate all such paths and route them through the single helper (§5).

## 10. Acceptance criteria

1. New event, "permanent team only" ON, new toggle ON, no assignments, saved → both calendar
   event(s) have exactly the eligible permanent members (`isPermanent && isActive &&
   !isArchived` and non-empty email) as attendees.
2. Members failing any eligibility condition (non-permanent, inactive, archived, or
   blank/missing email) are excluded.
3. Creating the first assignment on that event → calendar attendees become exactly the
   assignee(s); the all-permanent list is removed.
4. Deleting all assignments while the toggle is still ON → calendar attendees return to the
   eligible permanent members (self-resuming).
5. Toggle OFF → a zero-assignment event has no attendees (today's behavior); turning the
   "permanent team only" switch OFF forces the new toggle off and disables/grays it, and the
   persisted value is `false`.
6. Editing an unrelated event field and re-saving (which triggers a full event sync), and the
   backend admin "sync events and constraints" action, both preserve the all-permanent list
   for a qualifying event (i.e., the backend honors the rule, not just the client).
7. The trigger is strictly per-event: assignments on other events never affect this event's
   eligibility.
8. Behavior is identical in test and production environments (separate calendars/collections).
