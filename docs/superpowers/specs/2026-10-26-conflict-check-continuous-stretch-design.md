# Conflict check: an event is one continuous stretch

**Status:** draft for review
**Date:** 2026-10-26
**Worktree:** `conflict-check-continuous` (branch `worktree-conflict-check-continuous`, from `origin/main` 92028b3)
**Followed by:** `2026-10-26-assignment-custom-hours-design.md` (Project 2, on branch `worktree-assignment-custom-hours`), which builds on this rule.

## Why

Whether a team member is free for an event is "a real serious manner" (the user's words). While designing custom hours for one member's assignment, it turned out the app answers that question with three different rules that disagree, and the main one has holes. The user: "I did not know that this is the check today!!! … This is not good!", and "This needs fixing, and also A LOT OF TESTING".

What happens today (every example checked against the code on `main`):

| # | Scene | Today | Should be |
|---|---|---|---|
| E1 | Event 20:00–01:00 (one day). Constraint 23:00–23:59 that day. | Free. `timesOverlap` compares minutes within one day, so an end of 01:00 makes the event look like it never reaches 23:00. | Blocked |
| E2 | Show ends 20:30, team ends 22:00. Constraint 21:00–22:00. | Free. The check stops at the show end (`endTime`) and ignores `teamEndTime`. | Blocked |
| E3 | Two-day event 27–28.10, 18:00–23:00. Constraint 28.10 02:00–04:00. | Free. Each day is checked from 18:00 to 23:00 only, so nights never count. | Blocked. The user: "you can't know… maybe someone has a constraint from 23:00 to 01:00 the day after". |
| E4 | Event with team end filled but show end empty (common). Member with a timed constraint that day. | App: blocks until 23:59 (over-blocks). Backend: **error 500** (`requireString(eventData['endTime'])` in `constraintBlocksEvent`). | Judged against team end |
| E5 | Assembly 17:00, show 19:00. Constraint 17:30–18:30. | The assignment check blocks, but the warning when the constraint is saved and the offer to delete conflicting assignments say nothing. `constraintOverlapsEvent` starts at the show start. | Same answer everywhere: blocked |
| E6 | Weekly constraint "every Tuesday", event on its third Tuesday. | The warnings and the delete offer compare only the first Tuesday (`constraintOverlapsEvent` ignores `repeatType`). | Every occurrence counts |
| E7 | Duplicating an event to new dates. | The check is dates-only (`isAvailableForDateRange`): a constraint 08:00–10:00 flags an evening event, and hours are ignored. Keeping a flagged member makes `assignment.insertBatch` (no bypass) refuse the **whole** batch. The new event is left with no one assigned. | Same rule as assigning. The admin's choice to keep is honoured. |

## Goals

1. **One rule.** An event is one continuous stretch, from its start on the first day to its end on the last day, rolling past midnight. A constraint touching any minute of it blocks, nights included.
2. **One implementation per side, and the two sides provably agree.** One Dart function and one TypeScript function. Both are run against the same table of cases.
3. **Every conflict check uses it**, in the app and in the backend (call sites listed below).
4. **Pending constraints block like approved ones.** In the "בעלי מגבלות / לא זמינים" lists, each constraint is labeled approved or pending.
5. **Fix the bugs met on the way:** E4's error 500, E6, and E7's whole-batch failure.
6. **Prove it on real data before shipping.** A read-only report of every assignment on an event that hasn't ended whose answer changes, with the reason. The user reviews it.

## Non-goals

- Custom hours for one member (Project 2). This project only keeps the door open for it (see "Constraints").
- The same-day booking check (`same_day_assignments.dart`, and its backend copy in `drive_export.ts`). It stays whole-day.
- The ICS feed. Its blocks don't change.
- Non-permanent members' per-event "yes" (`availableEventIds`), which stays as it is. The four old date-based availability entries in production (all whole-day, all from February 2026) keep today's behaviour.
- Making event duplication atomic. The event is still created before its assignments.

## Anti-goals

- **The app and the backend disagree again.** Two copies that drift is exactly what got us here.
- **Existing assignments start failing on edits.** The stricter rule must not make the backend refuse a save that touches an assignment the admin already made. See the `saveBatch` duplicate incident of 2026-07-20.
- Silent changes to real assignments. Nothing is deleted or modified by this project. It changes answers, and the report shows which.

## Decided by the user

- An event is one continuous stretch from start on the first day to end on the last day, rolling past midnight. Any minute of overlap is a conflict, nights included.
- Project 1 ships and is verified on its own, before Project 2.
- Testing:
  - a large case table;
  - the same cases run against the app and the backend;
  - a read-only before/after report on production data, reviewed by the user before shipping.
- Past midnight: a one-day event whose end time is earlier than its start time ends the next morning. A multi-day event is read literally, the last day at its end time.
- Pending unavailability blocks assignment like approved. In the "בעלי מגבלות / לא זמינים" list there must be a visible difference between approved and pending (mockup approved, see "UI").
- In duplication, a member the admin chose to keep is assigned, even if flagged. "If the admin chose to leave him and not remove, he should be assigned as the admin requested."

## The rule

### Moments

Every comparison is done in **Israel wall-clock time**: a moment is (Israel date, minutes since midnight). DST changes then need no special case; the 2026-10-25 change was the night before this was written. Event `startDate`/`endDate` are stored as Israel local midnight as UTC (see the memory note on this). Each side converts to the Israel date first, the way `normalizeDayInIsrael` already does.

### The event's stretch

- **Start:** the first day at `assemblyTime`. If that's empty, at `startTime` (show start). If that's empty too, at 00:00.
- **End:** the last day at `teamEndTime`. If that's empty, at `endTime` (show end). If that's empty too, at the end of the last day (24:00).
- **Roll (decided by the user):**
  - **One-day event** (start date = end date) whose end time is not after its start time: the end is the next morning. That's how admins enter shows that end past midnight; production has seven, e.g. "היסטריה" 18:30–00:30.
  - **Multi-day event:** read literally, the last day at the end time, even when that time is earlier in the day than the start time. The user: "it makes sense that the end time could be before the start time due to changing days". A show on 27–28.10 ending at 01:00 after the second night is entered with end date 29.10.

  This matches the ICS feed's comparison in `buildDesiredAppEventState` (`formatDateTimePrefix(endDate, endTime) <= formatDateTimePrefix(startDate, mainStartTime)`). On a multi-day event that comparison can never fire.

Examples:

| Event | Stretch |
|---|---|
| 27.10, assembly 17:00, show 19:00–20:30, team end 22:00 | 27.10 17:00 → 27.10 22:00 |
| 27.10, assembly 20:00, team end 01:00 | 27.10 20:00 → 28.10 01:00 |
| 27–28.10, assembly 18:00, team end 23:00 | 27.10 18:00 → 28.10 23:00, the night included |
| 27–28.10, assembly 14:00, team end 12:00 | 27.10 14:00 → 28.10 12:00, no roll on a multi-day event |
| 27–29.10, assembly 18:00, team end 01:00 | 27.10 18:00 → 29.10 01:00 |
| 27.10, no times at all | 27.10 00:00 → 28.10 00:00 |
| 27.10, show 19:00, team end 22:00, no assembly, no show end | 27.10 19:00 → 27.10 22:00 |

### A constraint's time

A constraint covers one or more intervals of the same kind of moments:

- **One-time, no hours:** from 00:00 on its first day to 24:00 on its last day.
- **One-time with hours, one day:** that day, from start time to end time.
- **One-time with hours over several days:** one block, from the start time on the first day to the end time on the last day. This is today's rule, `rangeWindowOn` / `constraintTimeWindowOn`, now expressed as one interval.
- **Recurring (daily / weekly / monthly):** one interval on each matching day between `startDate` and `repeatEndDate`. It's the whole day without hours, otherwise start time to end time.
- An interval whose end is not after its start (the UI doesn't allow it) rolls to the next day, like an event.

### Overlap

Intervals are half-open, so touching is not a conflict: a constraint ending exactly at assembly does not block. Conflict means `constraint.start < stretch.end && stretch.start < constraint.end` for any of the constraint's intervals.

### Who is blocked

Who is checked doesn't change from today; only the time test does.

- Inactive or archived: unavailable, as today.
- **Permanent member:** blocked when any **approved or pending** unavailability constraint overlaps the stretch. Rejected doesn't block. An availability-type constraint on a permanent member is ignored, as today.
- **Non-permanent member:** available only if the event is in `availableEventIds`, or through the old date-based availability. That fallback keeps today's behaviour; production has four such entries, all past.
- `allowMultipleAssignments` (the "תגבורת" pool): exempt, as today. The exemption stays where it is, at the callers.

## Where the rule applies

Every site below switches to the one rule. The builder must also grep for anything missed. Names are from `main` plus the pending-constraints branch.

**App (Dart)**

| Site | Today | After |
|---|---|---|
| `TeamMember.isAvailableForEventWithTime`, `DateConstraint.blocksEventOn` / `blocksEventAssignment`, `TeamMember.constraintsBlockingEvent` (branch) in `team_member.dart` | per day, start → show end | stretch |
| Slot builds in `assignment_bloc.dart` (~1289, 3596, 3618, 4058, 4082) and the "בעלי מגבלות / לא זמינים" lists in `assignment_list_screen.dart` (~3183) and `event_summary_tile.dart` (~813, 829, 886) | via `isAvailableForEventWithTime` | stretch, via the same method |
| `AssignmentRepository.checkConflicts`, `Assignment.hasConflicts` / `conflictWarnings` (and the conflict count in `assignment_state.dart`) | same | stretch |
| `manual_assignment_flow_dialog.dart` | the branch already moved it to `constraintsBlockingEvent` | stretch |
| `event_constraint_collisions.dart` (the "constraints colliding with this event" button) | `blocksEventAssignment` | stretch, all statuses as today |
| `constraint_event_overlap.dart` `constraintOverlapsEvent` / `getConstraintEventOverlaps`. These drive the warnings when a constraint is saved (`constraints_screen.dart`, `team_list_screen.dart`, `constraint_warning_actions.dart`) and the offer to delete conflicting assignments (`findNewlyConflictingAssignments`). | show start → show end, first occurrence only | stretch, every occurrence |
| `event_bloc._onDuplicateEvent` | `isAvailableForDateRange` (dates only) | `isAvailableForEventWithTime(proposedEvent)` |

`getHighlightedDatesForConstraintRange` has no callers; the builder may delete it. `isAvailableOn` / `isAvailableForDateRange` / `TeamRepository` (~94) are date-only helpers. The builder checks whether anything live still needs them, and removes or keeps them; none may be used to decide an event conflict.

**Backend (TypeScript, `functions/src/index.ts`)**

| Site | After |
|---|---|
| `memberAvailableForEvent`, `constraintBlocksEvent`, `constraintTimeWindowOn`, `timesOverlap` (the availability one at ~1884) | one stretch function plus a constraint-interval function. No `requireString` on event times, so E4's error 500 is gone. |
| `assignment.insertBatch` | accepts an optional `bypassAvailability`, like `insert` / `update` / `saveBatch`. It's backward-compatible: old clients don't send it. |
| `assignment.update` | doesn't run the availability check when the member and event are unchanged from the stored document (see "Existing assignments"). |

## UI

### "בעלי מגבלות / לא זמינים" lists (assignments screen and summary screen)

Mockup approved by the user: `2026-10-26-conflict-check-continuous-stretch/constrained-list-pending.html`.

- Under the name, one line per blocking constraint, with its dates and hours:
  - **Approved:** red text, today's calendar icon. Example: "אילוץ מאושר: 28.10 (כל היום)".
  - **Pending:** orange text, an hourglass icon. Example: "אילוץ ממתין לאישור: 27.10 17:00–20:00".
  - A member with both gets both lines. The row's icon is the calendar if any constraint is approved, and the hourglass if all are pending.
- The same-day line ("משובצ/ת ב: …") and the non-permanent line ("לא ציין/ה זמינות") stay. If a member has more than one reason, all reasons are shown, same-day first.
- "שבץ בכל זאת" works the same for every row.
- The wording "אילוץ מאושר" / "אילוץ ממתין לאישור" matches the Project 2 warnings ("⚠️ מתנגש עם אילוץ ממתין לאישור של אבי: 28.10 (כל היום)").

### Duplication dialog

- Flags come from the new rule against the proposed event (new dates and times).
- The reason line uses the same labels as the list above. A permanent member gets their blocking constraints ("אילוץ מאושר: …" / "אילוץ ממתין לאישור: …"). A non-permanent member gets "לא ציין/ה זמינות לאירוע". A new event is never in their list, so they are always flagged, as today.
- Flagged members start marked for removal, as today. Any the admin keeps are assigned. Duplication sends `bypassAvailability: true` with its batch: the admin has reviewed the list, so the backend must not overrule it.
- Two reasons can't be overruled, because the backend refuses them even with the bypass and no screen in the app assigns them either:
  - the member is no longer active ("לא פעיל/ה");
  - the member can no longer do that role ("לא מוסמך/ת לתפקיד").

  These rows are listed with their reason and locked to removal. The batch the dialog sends can then never fail on a member the admin kept.

### Summary screen "שבץ בכל זאת" (live bug)

- **Today:** on the summary screen, choosing a member from "בעלי מגבלות / לא זמינים" and confirming saves nothing:
  - `event_summary_tile.dart` `_showAssignmentConfirmationDialog` sends a plain `CreateAssignment`;
  - `_onCreateAssignment` runs `checkConflicts` and refuses the member;
  - the green "שיבצת את…" snackbar shows anyway, because it is shown before the result is known.
- **Why it matters now:** once pending blocks, members with only a pending constraint move into this broken path.
- **Fix:**
  - a pick from the constrained list goes through `CreateAssignmentWithBypass`, the same as "שבץ בכל זאת" everywhere else;
  - the success snackbar shows only after the save succeeds;
  - a failure shows an error.

### Other messages

- `checkConflicts` already says "יש הגבלה מאושרת" / "יש הגבלה הממתינה לאישור" on the branch. Keep it.
- The constraint-save warnings keep their "event has no time" note (`missing_event_time`). It applies when the stretch had to fall back to a day edge, i.e. no assembly and no show start, or no end at all.

## Pending-constraints branch

`worktree-pending-constraints-block` (commit baa11a2, 2026-10-18, never merged) makes pending block in:

- `team_member.dart`: `blocksAssignments`, `constraintsBlockingEvent`;
- `index.ts`;
- `constraint_assignment_conflicts.dart`;
- `assignment_repository.dart`;
- `manual_assignment_flow_dialog.dart`;
- plus tests.

It does **not** touch the two "בעלי מגבלות" lists, which still say "מגבלה מאושרת" for everyone. Merge it into this branch first, then build the stretch rule underneath `blocksAssignments` / `constraintsBlockingEvent`. Its worktree is locked; leave it alone, and tell the user it can be removed after this ships.

## Existing assignments

The new rule blocks more than today: pending constraints, nights, team end, past midnight. An assignment made earlier, legitimately or through "שבץ בכל זאת", may now count as blocked. That must change what the lists and warnings show, but never make a save fail:

- `saveBatch` (the staged Save, which includes notes) and the slot compaction already bypass availability.
- `assignment.update` without bypass skips the availability check when `teamMemberId` and `eventId` match the stored document. Only a new member or a new event is checked.
- `AssignmentRepository.updateAssignment` (the client pre-check) follows the same rule.

Reachability today is low. `AssignmentFormScreen` has no route, and confirm/decline isn't dispatched from any screen. This is a cheap guard against the 2026-07-20 class of incident, not a fix for a known failure.

## Testing

### One case table, two runners

- One JSON file of cases, read by both a Flutter test and a Functions test. The builder picks its location, somewhere both can reach with a relative path (Flutter tests run from `shavtzak/`, Functions tests from `functions/`).
- Each case holds:
  - an event: Israel dates `yyyy-MM-dd` and the five time fields;
  - a member: permanent or not, active, archived, constraints, `availableEventIds`;
  - the expected answer and a short label.
- Each runner converts dates to its own stored form. Dart uses `DateTime(y, m, d)`. TypeScript uses a Timestamp at Israel midnight, as `availability.test.ts` already does, with `TZ=UTC` pinned.
- A test in each runner fails if the file has fewer cases than a floor. The table can't silently shrink.

The table must cover at least:

- **One day:**
  - a constraint before assembly, inside, after the end;
  - ending exactly at assembly, starting exactly at the end (touching means free);
  - inside the assembly-to-show gap (E5).
- **Team end:** a constraint between the show end and the team end (E2). Team end earlier than show end (data as entered).
- **Past midnight:**
  - E1;
  - a constraint the next morning that touches the rolled end, and one just after it;
  - an event ending exactly at 00:00.
- **Several days:**
  - the night between the days (E3);
  - an end time earlier in the day than the assembly time (no roll: a constraint later that last day is free);
  - before assembly on the first day, after the end on the last day;
  - a middle day of a three-day event.
- **Multi-day constraint:**
  - 23:00 → 01:00 the next day, against an event ending at 22:00 (free) and at 23:30 (blocked);
  - an event starting 00:30 on the second day (blocked).
- **Missing fields:**
  - no assembly;
  - no show start and no assembly;
  - no team end;
  - team end only (E4);
  - no end at all;
  - no times at all.
- **Recurring:**
  - weekly on the second day of a two-day event;
  - weekly on its third occurrence (E6);
  - daily with hours overlapping the night;
  - monthly;
  - recurring with `repeatEndDate` before the event;
  - recurring without hours.
- **Status:** approved blocks, pending blocks, rejected doesn't. An availability-type constraint on a permanent member is ignored.
- **Member:**
  - non-permanent with and without the event in `availableEventIds`;
  - the old date-based availability;
  - inactive; archived.
- **Dates:** the 2026-10-25 and 2026-03-27 DST nights; an event across a month end.

### Other tests

- Update the existing Rule A, Rule B and availability tests: about 35 Flutter tests, 17 in `availability.test.ts`, and the branch's tests. Cases whose expected answer changes under the user's rule are changed, with a comment naming which example (E1–E7) they are.
- The duplication flow:
  - flags come from the new rule;
  - a kept flagged member is sent with `bypassAvailability`;
  - `insertBatch` honours the flag and still refuses without it.
- `assignment.update` with an unchanged member and event passes when the member is blocked, and is refused when the member changed.
- Widget tests for both "בעלי מגבלות" lists: approved line, pending line, both, same-day plus constraint.

### Before/after report on production data (before shipping)

- Read-only. Pull `events`, `assignments` and `teamMembers` through the Firebase MCP tools, as in the memory note on ad-hoc Firestore pulls. No writes and no admin-SDK scripts.
- Compute old and new answers with the **real** backend functions: the old ones built from `main`, the new ones from this branch. Run them in a local script over the pulled JSON.
- Cover every assignment on an event that hasn't ended (not deactivated; exempt pool members excluded, as the rule does).
- **Output:** a table of every assignment whose answer changes, with:
  - event, its dates and stretch, member, role;
  - old → new answer;
  - the constraint responsible (status, dates, hours);
  - the reason category: pending now counts / night / team end / past midnight / assembly gap / recurring / missing time.
- Also give a count of rows unchanged. Write it as a CSV with a UTF-8 BOM in `~/Downloads/`. It's a heads-up list of existing assignments now shown as conflicts; nothing is changed automatically.
- The user reviews it before merge.

## Rollout

1. Merge the pending branch, build, and make all tests pass (`flutter analyze` with zero new issues, `flutter test`, `cd functions && npm test`).
2. Produce the before/after report; the user reviews it.
3. **Functions deploy 1, before the user tests the client locally** (local runs call the deployed `api`). It holds only the parts that loosen or add:
   - the optional `insertBatch` bypass flag;
   - the `assignment.update` guard.

   Deploy it from a commit that holds just those, with `firebase deploy --only functions`, and verify with `firebase functions:list`.
4. The user tests locally against production, then merges. The web auto-deploys.
5. **Functions deploy 2, right after the merge:** the new rule in `memberAvailableForEvent`, which also removes the error 500.

   **Why two:** the new rule makes `assignment.insert` refuse more. The one live screen that inserts without the bypass is the summary screen's plain assign. While the old web build is still in use, it would refuse a member the old app thinks is free, behind a success snackbar. The user's local testing can take days, and `sw.js` keeps the old build for one more open, so that gap must not open before the merge.

   **What this costs:** during local testing, the backend still runs the old rule. The new client's own check is stricter, so it rarely asks the old backend for something the old backend refuses. The exception is E4's existing error 500, which is not new.

## Constraints

- Project 2 will pass a member's own hours in place of the event's. Build the rule as a stretch value (start moment, end moment) computed from an event, with the overlap check taking a stretch. Project 2 can then substitute one without touching the overlap code.
- Clean architecture and the Equatable full-object rule, as everywhere in this repo.
- Hebrew UI, RTL, and no new icons on assignment rows. The list rows already have an icon slot; the hourglass replaces the calendar there.

## Left to the builder

- Names, file layout and the case-file location.
- Whether the Dart stretch lives on `Event` or in a util.
- How each side represents a moment (minutes since an epoch day, or a date key plus minutes), provided both agree on the table.
- Deleting dead helpers (`getHighlightedDatesForConstraintRange`, `conflictsWithEventTime`, `AssignmentFormScreen._checkConflicts`) if nothing live uses them.
- The short date format in list lines ("28.10", "27–28.10", recurring as "כל יום שלישי 18:00–20:00").

## My calls (not discussed with the user)

1. Missing times fall back like this:
   - start: assembly → show start → 00:00;
   - end: team end → show end → end of day.

   This differs from the ICS feed, which shows all-day when assembly is missing. The conflict check is more exact; the ICS is unchanged.
2. Intervals are half-open: a constraint ending exactly at assembly is not a conflict, same as today.
3. Recurring or one-day constraint hours with end before start roll to the next day. The UI doesn't allow it; this is for robustness.
4. `assignment.update` skips availability when the member and event are unchanged. `insertBatch` gets an optional bypass flag. Duplication always sends it.
5. A list row with several reasons shows all of them, same-day first.
6. The old date-based availability for non-permanent members keeps today's behaviour. Production has four entries, all whole-day and all from February 2026.
7. In duplication, an inactive member, or one who can no longer do the role, is shown with the reason and can't be kept. The backend refuses them even with the bypass.
8. The summary screen's "שבץ בכל זאת" is fixed to actually assign. Its success message waits for the save.
9. Functions go out in two deploys: the loosening parts before local testing, and the stricter rule right after the merge.
