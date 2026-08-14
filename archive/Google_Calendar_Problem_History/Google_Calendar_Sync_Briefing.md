# Google Calendar Sync Briefing For Claude

## Context

This repository is the Shavtzak Flutter Web + Firebase project. The current Google Calendar work is focused on making app event syncing reliable while removing Google Calendar guest/invite behavior for app events.

The product decision is final for now:

- Do not add Google Calendar invitees/guests to app-created calendar events.
- Do not send Google Calendar invitation emails for app event assignment/team-member changes.
- Keep one main Shavtzak Google Calendar. Do not move to one calendar per person.
- Existing future Google Calendar events created by the app need a guest cleanup path.
- Start guest cleanup safely with a button that removes only `omerbengal7@gmail.com` from future app events; an all-guests cleanup button is also implemented for later explicit use.

## Required Behavior

For app events:

- Creating an app event should create/update the matching Google Calendar event without `attendees`.
- Editing event details should update Calendar details without adding guests.
- Manual event re-sync should not add guests.
- Assignment changes should not add/remove Google Calendar guests.
- Team member email changes should not create Calendar attendee mutations.
- Calendar API calls for app events should use `sendUpdates: 'none'`.
- Normal detail sync must omit `attendees`, so guests manually added directly in Google Calendar are preserved.
- Explicit cleanup is the only place where attendees are modified.

For existing future Calendar events:

- Cleanup must only touch active future app-owned events in the current environment.
- Future means event `endDate >= today` using Israel date semantics.
- Cleanup must skip unrelated calendar events, constraints, past events, deleted/deactivated app events, and anything without exact app metadata.
- Omer-only cleanup removes only `omerbengal7@gmail.com` and preserves all other attendee objects.
- All-guests cleanup sets `attendees: []`, only when explicitly triggered.

Constraints calendar behavior is separate and should remain unchanged unless specifically requested.

## Current Implementation Status

Implemented but not deployed.

Backend changes are in Firebase Functions:

- `functions/src/calendar_integration.ts`
  - App event create/update/delete now use `sendUpdates: 'none'`.
  - App event creates omit `attendees`.
  - App event detail updates omit `attendees`, preserving any manually-added Google guests.
  - Legacy app attendee actions are no-ops.
  - Explicit guest cleanup supports Omer-only and all-guests modes.
  - Calendar event metadata/environment/type validation prevents touching unrelated events.
  - Deterministic Calendar event IDs are generated using Node's built-in `node:crypto`.

- `functions/src/calendar_sync_backend.ts`
  - Reconciliation ignores attendees.
  - Targeted sync deletes Calendar artifacts for missing, deactivated, or past app events.
  - App-owned artifact validation happens before delete/reconcile.
  - Constraint behavior remains separate.

- `functions/src/index.ts`
  - Durable Calendar sync job documents were added.
  - Cloud Tasks dispatches event sync work through a single writer.
  - App event CRUD marks revisioned dirty jobs and enqueues best-effort work.
  - Assignment/team-member Calendar guest side effects are removed/no-op.
  - Retry policy handles quota, auth, transient, and terminal failures.
  - Every-5-minute sweeper recovers stuck or delayed jobs.
  - OAuth recovery window resumes auth-blocked work after reconnection.
  - Guest cleanup jobs are durable, resumable, and split into part documents to avoid giant job payloads.
  - Omer-only and all-guests cleanup modes are mutually exclusive; starting a different mode while one exists returns conflict instead of silently doing the wrong cleanup.
  - Event deletion fencing prevents relation writes racing with delete cascades.
  - Legacy `/calendar/sync-app-event-attendees` compatibility endpoint returns a no-op for stale web clients.

New backend helper/test files:

- `functions/src/calendar_job_state.ts`
- `functions/src/calendar_job_state.test.ts`
- `functions/src/calendar_error_policy.ts`
- `functions/src/calendar_error_policy.test.ts`

Frontend changes:

- `shavtzak/lib/core/services/calendar_sync_service.dart`
  - App attendee methods are explicit no-ops.
  - Constraint attendee behavior remains unchanged.

- `shavtzak/lib/core/services/google_calendar_service.dart`
  - Added API models/methods for cleanup start/status/progress/queue state.

- `shavtzak/lib/presentation/bloc/calendar_sync/*`
  - Supports cleanup start and polling.
  - Manual repair queues backend work instead of doing client-side Calendar mutation.
  - Auth-blocked progress polling avoids duplicate retry behavior.

- `shavtzak/lib/presentation/bloc/event/*`
  - Event CRUD no longer performs client-side Calendar mutations.

- Team/user-selection/assignment Calendar attendee hooks were removed or made no-op.

- `shavtzak/lib/presentation/screens/admin/admin_choice_screen.dart`
  - Added Omer-only cleanup button.
  - Added all-guests cleanup button.
  - Added confirmation/progress/result/retry UI.
  - Manual sync wording now says it queues event syncing instead of promising immediate completion.

- Invite-all permanent team toggle is hidden. Legacy stored value remains but should not drive app event invite behavior.

- `firebase.json`
  - Functions predeploy runs TypeScript build.

## Real-Time Sync Design

The app now treats Google Calendar syncing as backend-owned asynchronous work:

- App writes happen in Firestore.
- Functions mark the affected event sync job dirty with a revision.
- Cloud Tasks performs the Calendar write.
- A single-writer/rate-limited queue prevents concurrent Calendar writes from racing.
- The sweeper periodically recovers jobs that were missed, delayed, auth-blocked, or stale.
- Revision-aware completion prevents an older worker from marking a newer event state as synced.

This is the current compromise for "real-time" syncing: app data updates immediately in Firestore, then Calendar sync follows through Cloud Tasks quickly and durably. It avoids the rejected per-person-calendar approach and avoids Calendar guest email spam.

## Deployment And Local Testing

The changes are not deployed yet.

Running the Flutter app locally currently still calls deployed Firebase Functions because `BackendApiService` builds URLs like:

```text
https://us-central1-$projectId.cloudfunctions.net/api
```

There is no wired local Functions emulator routing in Flutter at the moment.

To test the new backend behavior from a local Flutter app, deploy Functions first:

```bash
cd "/Users/omerbengal/Documents/Github Projects/Shavtzak"
firebase deploy --only functions
cd shavtzak
flutter run -d chrome
```

Hosting does not need to be deployed just to test local Flutter against the updated backend.

A full local emulator path would require wiring Flutter to the Functions emulator plus matching Firestore/Auth/Cloud Tasks behavior. That is not currently configured and is not the recommended path for this specific end-to-end test.

## Verification Already Run

These checks passed after the implementation:

```bash
cd functions
npm test
npm run build
```

Results:

- `npm test`: 102 tests passing.
- `npm run build`: TypeScript build passing.

Flutter checks:

```bash
cd shavtzak
flutter test --reporter compact
flutter analyze
```

Results:

- `flutter test --reporter compact`: 242 tests passing.
- `flutter analyze`: exits with existing baseline warnings/info. No new Calendar compile errors were found.

Also checked:

```bash
git diff --check
```

Result: clean.

## Manual QA Checklist After Deploying Functions

1. Deploy Functions only.
2. Run the Flutter app locally.
3. Use the test environment first.
4. Create a future app event and confirm the Google Calendar event has no guests.
5. Edit event details and confirm the Calendar event updates without adding guests.
6. Run manual event re-sync and confirm it does not add guests.
7. Assign and unassign a team member and confirm no Calendar guest is added/removed.
8. Manually add a guest directly in Google Calendar, then edit/re-sync the app event and confirm the manual guest is preserved.
9. Use the Omer-only cleanup button and confirm only `omerbengal7@gmail.com` is removed from eligible future app events.
10. Use all-guests cleanup only after the Omer-only cleanup behavior is verified.
11. Confirm constraints Calendar behavior still works as before.

## Regression Traps

Do not reintroduce app event guests through any of these paths:

- Event create.
- Event edit.
- Manual event re-sync.
- Assignment create/update/delete.
- Team member email update.
- Legacy app attendee sync endpoint.
- Invite-all permanent team toggle.

Do not replace this with:

- One Google Calendar per team member.
- Google Calendar guest invitations for app events.
- Google Apps Script as the primary sync engine.
- Client-side Calendar mutations from Flutter for app events.

Do not set `attendees: []` during normal detail sync. That would delete manually-added Google Calendar guests. Normal event update should omit the `attendees` field entirely.

Only the explicit guest cleanup flow should edit attendees.

## Worktree Notes

The repo may contain unrelated user changes. Do not revert them.

Known user-owned/unrelated files from this session:

- `AGENTS.md` may be modified by the user.
- `Google_Calendar_Problem_part_1.txt`
- `Google_Calendar_Problem_part_2.txt`

Those two text files contain prior Claude Code conversations and are useful context, but they should not be modified unless the user explicitly asks.

## Suggested Claude Task

If continuing this work, start by reviewing the changed Calendar files and validating the invariants above. The main job is not to redesign the approach; it is to preserve the no-guests decision, deploy/test carefully, and fix only concrete issues found during QA.
