# Hiding דו יומי tasks - design (approved 24/11/2026)

## Intent
A task manager sometimes prepares a task that may not happen. They create it, hide it, and
un-hide it when it becomes relevant. A hidden task is invisible to team members (also to its
assignees); managers (admin or `canManageTasks`) still see it, clearly marked as hidden.
Only the דו יומי tasks (`tasks`), not the team tasks (`teamTasks`).

## Goals / non-goals
- Goal: a member never sees a hidden task on any du-yomi screen.
- Goal: a manager can hide / un-hide in one tap and can create a task already hidden.
- Non-goal: secrecy against a member reading Firestore directly (approach B, later if wanted).
- Anti-goal: a hidden task leaking into a member's counters, filters, calendar or timeline.

## Approaches
- **A. Hide on screens only (picked by Omer, msg 6335).** An `isHidden` field; the member's
  screens filter it out. No rules change, no backfill.
- B. Airtight: A + a Firestore rule and a member-only query. Needs a production backfill and a
  timed rules/app rollout (old clients would get an empty list). Not now; A does not block it.

## Design
- Data: `isHidden: boolean` on a task; missing = false. Written only by the backend.
- Backend: new `task.setHidden {taskId, isHidden}` (managers only, audit-logged).
  `task.insert` and `stage.import` take `isHidden` from the payload (default false);
  `task.update` sets it only when the key is a boolean (old clients keep it); `stage.sync`
  never changes it on an existing task, and Excel-created tasks are visible.
- Client: `TaskItem.isHidden`; `TaskItemModel` reads and sends it; `SetTaskHidden` bloc event.
- Visibility: non-managers get the event board without hidden tasks (one filter where the
  board is built), so every tab, the calendar, the timeline and the counters follow.
- Counters (`taskProgress`, the late / due-soon lists) never count a hidden task, also for
  managers, so a manager's numbers match the team's.
- Marking (managers): the row is faded with a "מוסתרת" chip (eye-off icon) next to the title,
  on the phone rows, the wide table, the task detail and the editing screen.
- Toggle: an eye button next to edit/delete (table row and task detail), a "משימה מוסתרת"
  checkbox in the task form (create and edit).
- Cycle copy keeps hidden; Excel export includes hidden tasks with no new column.

## Left to the builder
Exact colours (from `TaskStyle`), keys, the snackbar text.
