# דו יומי task management — design

**Date:** 2026-10-11
**Branch:** `worktree-feat-du-yomi-tasks`
**Status:** decisions confirmed in conversation, not yet implemented

## Problem

The team runs the "דו יומי" events off an ad-hoc task list. There is no place in
Shavtzak to say "this needs doing for that event, by these people, by this time" and
watch it get done. The checklist feature is close but is a yes/no item with one
responsible member and a notes chat; it has no due time, no subtasks and no progress.

This adds a task screen: tasks tied to an event, assigned to one or more members, with
subtasks, a due date and time, a completion state and a short status note from the
assignees.

## Supersedes `feat/tasks-feature`

An earlier משימות feature (spec `2026-05-08-tasks-feature-design.md`, branch
`feat/tasks-feature`, 40 commits, 8–12 May) was built but never merged or deployed: no
`tasks` collection exists in Firestore. It is 387 commits behind `main`.

This feature **replaces** it and is built fresh from `main`. The old branch is not
merged and is left untouched. The new feature takes the `tasks` collection name. The
old design's five statuses, append-only update history, archive state, date-only
deadline, admin-only overview and navigation tab are all dropped.

## Decisions

| # | Decision | Source |
|---|---|---|
| 1 | A task can be attached to **any future event**; no category restriction. The screen is only *titled* דו יומי. | user |
| 2 | **Task managers** are admins plus any member with a new `canManageTasks` flag, toggled in the team-member modal. | user |
| 3 | **All active members** can open the screen and read every task. | user |
| 4 | The screen is **link-only** (`/tasks`): no tab, menu entry or card points at it. Unlike `/db` it requires sign-in. | user |
| 5 | A subtask is a **title and a done flag**, nothing else. | user |
| 6 | A task with subtasks **completes automatically** when its last subtask is ticked and reopens when one is unticked. A task without subtasks has a manual checkbox. | user |
| 7 | The assignee update is **one shared text, overwritten**; no history in the UI, but every save is written to the audit log with its content. | user |
| 8 | Filters: **status, event, assignee**. | user |
| 9 | Built fresh; the old branch is abandoned (see above). | user |
| 10 | Event, title and at least one assignee are required. Description, subtasks and due date are optional. | assumption |
| 11 | Red once the due date **and time** have passed; orange while due today and not yet past. | assumption |
| 12 | Tasks stay visible after their event passes. Only the event *picker* is limited to future events. | assumption |
| 13 | No notifications, calendar sync, attachments, templates or recurrence. | assumption |

## Approach

**Subtasks live inside the task document** as an ordered array, not in a
subcollection. One document is one stream emission, the progress count needs no second
query, and the auto-complete rule can be recomputed in the same transaction that flips
a subtask. Subtask lists are a handful of lines; the 1 MiB document limit is not a
concern. A subcollection would buy independent writes at the cost of a second listener
per expanded card, and was rejected.

**Writes are granular backend actions, not one "save the whole task" call.** The
checklist's `checklist.update` accepts a client-built document and then decides which
fields the caller was allowed to touch. That shape cannot stop two assignees who tick
different subtasks at the same moment from overwriting each other, and it trusts the
client's clock. Here each progress change is its own action that runs in a transaction,
changes exactly one thing and stamps the time on the server.

## Data model

Collections: `tasks` (production), `test_tasks` (test), via
`EnvironmentService.instance.collectionPrefix`.

### Task document

| Field | Type | Notes |
|---|---|---|
| `id` | string | client-generated UUID, also the document ID |
| `eventId` | string | required |
| `title` | string | required, trimmed, non-empty |
| `description` | string | `''` when empty |
| `subtasks` | array of `{id, title, isDone}` | ordered; `[]` when none |
| `dueAt` | Timestamp \| null | an instant: date and time |
| `assigneeIds` | string[] | at least one |
| `assigneeUpdate` | string \| null | the shared status note |
| `assigneeUpdateAt` | Timestamp \| null | when the note was last saved |
| `assigneeUpdateById` | string \| null | who saved it |
| `assigneeUpdateByName` | string \| null | denormalised for display |
| `isComplete` | boolean | |
| `completedAt` | Timestamp \| null | set when `isComplete` turns true, cleared when it turns false |
| `completedById` | string \| null | |
| `createdAt` | Timestamp | server time |
| `createdById` | string | |
| `updatedAt` | Timestamp | server time; bumped by **every** write to the task |

`updatedAt` is the "last updated at" field: saving the assignee update bumps it, and so
does ticking a subtask, completing, or editing. `assigneeUpdateAt` exists separately so
the note can carry its own "who and when" without being disturbed by a subtask tick.

### Completion rule

After any write, if `subtasks` is non-empty then `isComplete` is exactly "every subtask
is done". If `subtasks` is empty, `isComplete` is whatever was last set by hand.

Consequences, all enforced on the server:

- Ticking the last open subtask completes the task and stamps `completedAt`.
- Unticking any subtask of a completed task reopens it and clears `completedAt`.
- Editing a completed task to add a new (undone) subtask reopens it.
- Editing a task to remove its only open subtasks completes it.
- Removing every subtask leaves `isComplete` as it was.
- `task.setComplete` is rejected for a task that has subtasks.

### Team member

New boolean `canManageTasks`, default `false`. `teamMemberDocFromJson` reads it as
`member['canManageTasks'] ?? existing?.['canManageTasks'] ?? false`, so a browser still
running an older web build that saves a member without the field cannot silently
revoke it. `applySelfEditableFields` already preserves every field it does not list, so
a member cannot grant the flag to themselves.

### Dart entities

`TaskItem` and `Subtask` in `lib/domain/entities/`, both `Equatable` with every field in
`props`. `TaskItem` carries repository-populated `event: Event?` and
`assignees: List<TeamMember>` as full objects, per the real-time rule in `CLAUDE.md`.
The name is `TaskItem` (parallel to `ChecklistItem`) to stay clear of the many unrelated
`Task` types in the Dart ecosystem.

## Permissions

| Action | Task manager | Assignee of the task | Any other member |
|---|---|---|---|
| Read all tasks | yes | yes | yes |
| Create, edit, delete | yes | no | no |
| Tick or untick a subtask | yes | yes | no |
| Complete or reopen (no subtasks) | yes | yes | no |
| Save the assignee update | yes | yes | no |

"Task manager" is `actor.isAdmin || actor.member.canManageTasks === true`. The UI hides
what the caller cannot do; the backend enforces it regardless.

## Backend — `functions/`

A new pure module `functions/src/tasks.ts` holds all task logic with `now` injected, so
it is unit-tested without Firestore, in the style of `participant_groups.ts`:

- `taskDocFromInput(input, {now, actor})` — validate and build a new document.
- `applyTaskEdit(existing, input, {now})` — replace the editable fields; a subtask keeps
  its `isDone` when its `id` survives the edit; re-derive completion.
- `applySubtaskToggle(existing, subtaskId, isDone, {now, actor})`
- `applySetComplete(existing, isComplete, {now, actor})`
- `applyAssigneeUpdate(existing, text, {now, actor})`
- `canManageTasks(actor)`, `isTaskAssignee(task, actor)`

`index.ts` gains the collection name and six actions. Each runs in a transaction, calls
the pure function, writes, then calls `writeAuditLog` with `before` and `after`.

| Action | Payload | Allowed |
|---|---|---|
| `task.insert` | `{task}` | manager |
| `task.update` | `{task}` | manager |
| `task.delete` | `{taskId}` | manager |
| `task.setSubtaskDone` | `{taskId, subtaskId, isDone}` | manager or assignee |
| `task.setComplete` | `{taskId, isComplete}` | manager or assignee |
| `task.setAssigneeUpdate` | `{taskId, text}` | manager or assignee |

`task.insert` and `task.update` check the target event with
`requireWritableEventInTransaction`. They do **not** require the event to be in the
future: that is a picker rule, and a task whose event has passed must stay editable.

`task.setAssigneeUpdate` logs the saved text in the audit entry (decision 7). An empty
or whitespace-only text clears the note.

**Event deletion cascade.** `deleteEventRelatedDocuments` also deletes the event's
tasks, and `event.delete` adds `deletedTasks` to its audit details next to
`deletedChecklistItems`.

**Member deletion** does not touch tasks. An `assigneeId` that no longer resolves is
dropped from display.

**`firestore.rules`** gains `tasks` and `test_tasks` blocks identical to the
checklist ones: read for an authorised active user, `write: if false`.

Everything here is additive, so Functions and rules can be deployed ahead of the web
build without affecting the live site.

## Client

### Data layer

- `TaskItemModel` — `fromFirestore` / `toJson`.
- `DatabaseInterface` — `watchTasks()` plus one method per backend action. Implemented
  in `FirestoreDatabase` and mirrored in `LoggingDatabase`.
- `TaskRepository.watchTasks()` — combines the tasks, events and team-member streams so
  that renaming an event or a member re-emits the affected tasks. First paint comes
  from the streams; nothing is gated on an awaited `get`.

### State

`TaskBloc` subscribes with `emit.forEach` and emits `TasksLoaded(tasks)`. Mutation
events call the repository; a failure surfaces as a one-shot error the screen shows in
a snackbar. The search text, the mine/all toggle and the filter selection are screen
state, not bloc state, like the other list screens.

### Pure helpers — `lib/core/utils/task_utils.dart`

- `taskDueStatus(task, now)` → `completed | overdue | dueToday | open`. Completed wins;
  then overdue when `dueAt` is before `now`; then dueToday when `dueAt` falls on today's
  date; otherwise open. A task with no `dueAt` is open.
- `filterTasks(tasks, {query, onlyAssigneeId, statuses, eventIds, assigneeIds, now})`.
  The search matches title, description and event name through `normalizeForSearch`.
- `sortTasks(tasks, now)` — overdue, then due today, then open by `dueAt` ascending
  with undated last, then completed by `completedAt` descending.

### Screen — `/tasks`

`lib/presentation/screens/task/tasks_screen.dart`, RTL, Hebrew.

- App bar titled `משימות דו יומי`, with a home button to the member's normal landing
  route.
- A two-segment control: `המשימות שלי` (default) and `כל המשימות`.
- A search field with a filter button and count badge, visually matching
  `EventSearchFilterBar`. The filter opens a modal with three sections: status, event,
  assignee.
- The sorted, filtered list of task cards, with an empty state.
- For task managers, a floating `משימה חדשה` button.

### Task card

- Title; event name and date; due date and time; assignee names.
- A tint by status plus a text chip, so colour is never the only signal:
  completed green with the title struck through, overdue red, due today orange,
  otherwise no tint.
- Subtasks present: a progress bar with an `X/N` label, and the card expands to show
  each subtask as an inner card with a checkbox. Subtasks absent: no chevron, and a
  completion checkbox on the card itself.
- The assignee update with its author and time, and an edit button for those allowed.
- "Last updated" time.
- Task managers get edit and delete in an overflow menu; delete asks for confirmation.

Saving closes the dialog immediately and relies on the stream for the result. No
full-screen loading overlay.

### Task form modal

For task managers, create and edit: event picker (future, non-deactivated events, plus
the task's current event when editing), title, description, due date and due time
(reusing the existing date picker and `EventTimeField`), assignee multi-select over
active non-archived members, and a subtask editor (add, rename, remove).

### Team-member modal

A `ניהול משימות` switch next to the existing access switches, bound to
`canManageTasks`.

### Routing

`/tasks` and `/test/tasks` as top-level routes, outside both shells. Any authenticated
member may open them. The router today always falls back to the member's home after
sign-in, so the link needs explicit handling: when the initial URL targets the tasks
route, the destination is remembered and restored once the member is authenticated,
whether that happens through "מי את/ה?" or through a cached session finishing
validation.

### `/db`

The diagnostic screen lists `tasks` alongside the other collections.

## Testing

- **Functions:** `tasks.test.ts` covers validation, every branch of the completion rule,
  subtask `isDone` preservation across edits, the three progress mutations, and the
  permission predicates. `team_member_self_edit.test.ts` gains a case showing a
  self-edit cannot set `canManageTasks`.
- **Flutter unit:** `TaskItem` equality and `copyWith`; model round trip;
  `taskDueStatus` at each boundary (one minute before and after `dueAt`, midnight);
  `filterTasks` and `sortTasks`.
- **Flutter bloc:** `TaskBloc` emits on stream updates, forwards each mutation, and
  surfaces a failure.
- **Flutter widget:** the card's four colour states, strikethrough, progress label and
  expansion; the screen's mine/all toggle and search; controls hidden for a member who
  is neither manager nor assignee.
- **Gates:** `flutter analyze` with zero new issues, `flutter test`, and
  `cd functions && npm test`.

## Rollout

1. Deploy rules and Functions: `firebase deploy --only firestore:rules,functions`,
   then confirm with `firebase functions:list`.
2. Test the client locally from this worktree.
3. Merge to `main`, which deploys the web build.

## Out of scope

Notifications of any kind, calendar entries for due dates, attachments, task
templates, recurring tasks, an update history view, archiving, per-subtask assignees or
due dates, drag-to-reorder subtasks, and any navigation entry pointing at the screen.
