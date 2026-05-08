# משימות Feature Design

Date: 2026-05-08
Status: Design approved in conversation, pending written-spec review

## Summary

`משימות` is a new standalone task-management feature for Shavtzak. It replaces the team's current Google Sheets task workflow with a mobile-first, realtime, Firebase-backed experience. It is separate from checklist and separate from event assignments.

The feature is event-oriented by default because management thinks about work through events, but it also supports general tasks with no linked event.

## Goals

- Give admins a clean way to create, assign, track, close, archive, and delete operational tasks.
- Give regular users a focused mobile list of open tasks assigned to them.
- Preserve realtime updates across all task screens.
- Preserve the app's backend-write architecture: no direct client writes to task collections.
- Avoid shared-filter problems from Google Sheets.
- Keep V1 intentionally small enough to ship and test with real users.

## Non-Goals For V1

- No email, push, or in-app notification system beyond passive task count badges.
- No attachments, photos, or files.
- No task tags, categories, or priority levels.
- No templates or recurring tasks.
- No bulk task creation.
- No automated Google Sheets import. Active tasks can be migrated manually if needed.
- No user-side search/filter controls in V1.
- No merging with or replacement of the existing checklist feature.

## Product Scope

### Task Basics

Each task has:

- short title
- longer plain-text description
- zero or one linked event
- one or more assignees
- fixed status
- optional date-only deadline
- latest update summary
- append-only update history
- archive state
- creation/update/closure metadata

Every task must have at least one assignee. A task can be linked to no event; those tasks are shown as `ללא אירוע`.

### Statuses

V1 uses a fixed status list:

- `פתוחה`
- `בטיפול`
- `ממתינה`
- `חסומה`
- `נסגרה`

`נסגרה` is the closing status. Choosing it closes the task and fills `closedBy` and `closedAt`. Reopening means changing status away from `נסגרה`, which clears `closedBy` and `closedAt`.

### Closing Rule

If a task is assigned to multiple people, the task closes when any assigned user or any admin changes the status to `נסגרה`.

### Deadlines

Deadlines are optional and date-only. A task is overdue only after the deadline day ends. For example, a task due on `2026-05-08` becomes overdue on `2026-05-09`.

Overdue tasks are highlighted and filterable for admins. Regular users do not get deadline filters in V1, but the default ordering should surface urgent tasks first.

### Update History

Visible history contains status/note updates only. Admin field edits such as title, deadline, assignees, or event changes are not mixed into the user-facing history feed.

Each update stores:

- status
- optional note
- updater ID
- updater display name
- timestamp

Updates are append-only in V1. Users cannot edit or delete posted updates. If someone made a mistake, they add another update.

Task creation writes an initial update with status `פתוחה`.

## Data Model

### Collections

Production:

- `tasks`
- `tasks/{taskId}/updates`

Test:

- `test_tasks`
- `test_tasks/{taskId}/updates`

All collection names must use `EnvironmentService.instance.collectionPrefix`.

### Task Document

Fields:

- `id: string`
- `title: string`
- `description: string`
- `eventId: string?`
- `assigneeIds: string[]`
- `status: string`
- `deadlineDate: Timestamp?`
- `isArchived: boolean`
- `createdAt: Timestamp`
- `createdById: string`
- `updatedAt: Timestamp`
- `updatedById: string`
- `closedAt: Timestamp?`
- `closedById: string?`
- `latestStatus: string`
- `latestUpdateText: string?`
- `latestUpdatedAt: Timestamp`
- `latestUpdatedById: string`
- `latestUpdatedByName: string`

Repository-populated fields for UI:

- `event: Event?`
- `assignees: List<TeamMember>`
- `createdBy: TeamMember?`
- `closedBy: TeamMember?`
- `latestUpdatedBy: TeamMember?`

Computed UI flags:

- `isOverdue`
- `hasPastEvent`
- `hasMissingEvent`
- `hasInactiveAssignee`

### Task Update Document

Path: `tasks/{taskId}/updates/{updateId}`

Fields:

- `id: string`
- `taskId: string`
- `status: string`
- `note: string?`
- `createdAt: Timestamp`
- `createdById: string`
- `createdByName: string`

### Data Integrity Rules

- New tasks can only be assigned to active team members.
- Existing tasks may reference inactive/archived members if those members became inactive later.
- Admin UI must clearly flag inactive/archived assignees.
- If a linked event is deleted, the task remains and the UI flags the missing/deleted event.
- Tasks linked to past events remain visible if open, but UI clearly marks that the event is in the past.
- Closed tasks are hidden by default.
- Archived tasks are hidden from regular users and from normal admin views unless the admin enables an archive filter.

## Permissions

### Admins

Full admins can:

- create tasks
- edit all task fields
- archive and unarchive tasks
- permanently delete tasks after strong confirmation
- close and reopen any task
- add status/note updates to any task
- view all open, closed, and archived tasks through filters

### Regular Users

Regular users can:

- read open, non-archived tasks where their `teamMember.id` is in `assigneeIds`
- see the full assignee list for those tasks
- open task detail and update history
- add status/note updates only while assigned and only while the task is not closed

Regular users cannot:

- create tasks
- see unassigned tasks
- see archived tasks
- see closed tasks in V1's default user UI
- edit title, description, event, assignees, deadline, archive state, or deletion
- update a task after it is closed

## Backend And Security Architecture

This feature must follow the current backend-write migration:

- Flutter client reads from Firestore streams.
- Flutter client does not write directly to task collections.
- All mutations go through Cloud Functions.
- Firestore rules allow authorized reads and deny direct client writes for task documents and update subcollections.
- Cloud Functions enforce permissions, write audit logs, and perform atomic multi-document mutations.

Required Cloud Function operations:

- `task.create`
- `task.update`
- `task.archive`
- `task.unarchive`
- `task.delete`
- `task.addUpdate`

`task.addUpdate` handles status changes, latest-update fields, close/reopen metadata, and creation of the `updates` subdocument.

Permanent deletion:

- removes the task document from normal data
- removes its update subcollection
- writes minimal audit metadata: task ID, title, linked event ID, assignee IDs, deleted by, deleted at

## Realtime Architecture

Realtime updates are mandatory.

Required streams:

- Admin task list watches task documents in realtime.
- User task list watches open non-archived tasks assigned to the current user.
- Task detail watches one task document in realtime.
- Task detail watches `tasks/{taskId}/updates` ordered by `createdAt`.

BLoC states and task-related UI view models must use full Equatable objects in `props`, not only IDs. For example, use `event`, `assignees`, and `task`, not only `event.id`, `assigneeIds`, or `task.id`.

The UI should rely on stream updates after backend mutations. Avoid full-screen white loading overlays for short save/update actions.

## UI/UX Direction

The approved direction uses `ui-ux-pro-max` guidance adapted to Shavtzak:

- flat, functional Material UI
- mobile-first task execution
- dense but readable operational lists
- Shavtzak-native colors: existing blue/orange theme, neutral surfaces, semantic warning/error/success colors
- Hebrew/RTL-first layout
- Rubik/Noto Sans Hebrew-compatible typography
- no decorative effects
- no emoji icons
- status chips and text labels, not color-only indicators
- clear touch targets and accessibility semantics
- support large fonts where practical

The first quick wireframe was rejected as too generic. The approved redesign emphasizes compact operational cards, status chips, event grouping, bottom-sheet details, and visible warnings.

### User Navigation

Rename the current first user tab from `המשימות שלי` to `השיבוצים`.

Add a dedicated fourth user bottom-nav tab:

- `השיבוצים`
- `משימות`
- `המגבלות שלי` or `הזמינות שלי`
- `צ'קליסט`

The `משימות` tab shows a passive badge count of open tasks assigned to the current user.

### User Task Screen

V1 user task screen is a focused list, with no visible filters/search/sort controls.

It shows open, non-archived tasks assigned to the current user. Default ordering:

1. overdue tasks
2. nearest deadline
3. latest update

Task cards show:

- title
- event name or `ללא אירוע`
- past-event marker if relevant
- deadline if present
- status chip
- assignees
- latest update summary

Tapping a task opens a detail bottom sheet.

### User Task Detail

The detail bottom sheet shows:

- title
- full description
- linked event details
- assignees
- deadline
- status
- latest update
- full update history
- status update action if current user can update the task

Users can update status with an optional note. They cannot update closed tasks.

Clicking the event name opens an event details card. Regular users see read-only event details. Admins see an edit affordance.

### Admin Entry

Add a new full-admin-only card to `AdminChoiceScreen`:

- `ניהול משימות`

It sits alongside cards like `איזור אישי`, `ניהול שבצק`, and `מסך מנהלים`.

### Admin Task Screen

Default admin view is grouped by event, with a `ללא אירוע` group for general tasks.

Event groups sort by event date. Tasks inside each group sort by:

1. overdue
2. nearest deadline
3. latest update

Admin controls:

- text search
- status filter
- assignee filter
- event/no-event filter
- deadline state filter
- show closed toggle
- show archived toggle
- create task
- edit task
- archive/unarchive
- permanent delete
- add status/note update
- close/reopen

Admin task cards must visually flag:

- overdue task
- linked event is in the past
- missing/deleted linked event
- inactive/archived assignee

### Create/Edit UX

Admin task creation/editing should use a mobile-friendly modal or bottom sheet.

Required fields:

- title
- description
- assignees

Optional fields:

- linked event
- deadline

Assignee picker should show active members only for new assignments. Existing inactive assignees remain visible and clearly flagged in edit mode.

## Implementation Checkpoints

### Checkpoint 1: Foundation

- Add task status constants.
- Add `Task` and `TaskUpdate` domain entities.
- Add Firestore models.
- Add task repository interfaces.
- Add environment-aware collections: `tasks` / `test_tasks`.
- Add Firestore read streams and backend mutation calls.

### Checkpoint 2: Backend Writes And Security

- Add Cloud Function mutation operations for create/edit/archive/delete/update status.
- Enforce admin/user permissions in backend.
- Write audit logs for create/edit/archive/delete/status update.
- Add Firestore rules: authorized reads, no direct client writes.
- Include recursive deletion of update subcollection on permanent delete.

### Checkpoint 3: Realtime BLoC

- Add `TaskBloc`.
- Admin watches all tasks.
- User watches assigned open tasks.
- Detail watches one task and its updates.
- State props use full Equatable objects, not IDs.
- Avoid fake refresh patterns; rely on streams.

### Checkpoint 4: Admin UX

- Add `ניהול משימות` card on choice screen.
- Build admin task screen with event grouping, `ללא אירוע`, filters, show closed/archive toggles.
- Build create/edit task modal/sheet.
- Add archive/delete confirmations.
- Add visual warnings for overdue, past event, missing event, inactive assignee.

### Checkpoint 5: User UX

- Rename current assignment tab to `השיבוצים`.
- Add `משימות` bottom-nav tab and badge count.
- Build focused user task list with no visible filters.
- Build task detail bottom sheet with update action and history.
- Enforce regular-user update rules in UI and backend.

### Checkpoint 6: Verification And Polish

- Validate realtime task updates across two browser sessions.
- Verify backend rejects forbidden writes.
- Verify test/prod collection isolation.
- Verify admin/user read visibility.
- Verify archive/delete behavior.
- Run `flutter analyze`.
- Deploy Cloud Functions because this feature changes `functions/`.

## Implementation Planning Notes

No product decisions remain open for V1. The implementation plan will decide exact file-level sequencing and the final BLoC structure for task list/detail streams.
