# דו יומי Task Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A link-only `/tasks` screen where task managers create event-bound tasks with subtasks, a due date and time and assignees, and assignees tick progress and post a status note.

**Architecture:** Tasks are documents in a new `tasks` collection with subtasks embedded as an array. The client reads through a Firestore stream and writes only through six new granular actions on the existing `api` Cloud Function, each of which runs a pure, unit-tested transition function inside a transaction and stamps server time. A `TaskBloc` feeds one screen; search, filters and the mine/all toggle are screen state.

**Tech Stack:** Flutter Web, `flutter_bloc`, `go_router`, `rxdart`, Cloud Firestore; Cloud Functions (TypeScript, `node:test`).

**Spec:** `docs/superpowers/specs/2026-10-11-du-yomi-tasks-design.md`

## Global Constraints

- Worktree: `/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/feat-du-yomi-tasks`. Flutter commands run from its `shavtzak/` subdirectory; Functions commands from `functions/`.
- All UI text is Hebrew, every screen and dialog is RTL, code comments are English.
- No direct client writes: every mutation goes through `_invokeMutation('task.*')`.
- Collection name comes from `EnvironmentService.instance.collectionPrefix` + `tasks`.
- Equatable `props` hold full objects (`event`, `assignees`), never just IDs.
- No full-screen loading overlay on save: close the dialog, rely on the stream.
- Backend changes are additive so Functions and rules can be deployed before the web build.
- Dates sent to the backend are UTC ISO strings (`toUtc().toIso8601String()`); a local ISO string with no zone is parsed as UTC by the server and lands three hours off.
- `flutter analyze` must show zero **new** issues (the baseline carries roughly 107 infos).
- Do not run the app; do not deploy. Both are the user's call.

## Review Focus

1. **A task whose event no longer resolves** (deleted, or not yet loaded): the card shows `אירוע לא נמצא` and still renders, filters and sorts. Test in Task 7.
2. **A stored document missing optional fields** (`subtasks`, `dueAt`, `assigneeUpdate*`, `completedAt` absent rather than null): the model parses it with defaults instead of throwing and blanking the whole list. Test in Task 5.
3. **Two assignees ticking different subtasks at once:** a toggle changes exactly one subtask and derives the rest from the stored document, never from a client copy. Test in Task 1.
4. **A stale client acting on something that changed underneath it** (subtask removed by a manager, member dropped from the assignees): the backend answers 404 or 403 and the screen shows the message in a snackbar. Tests in Task 1 (errors) and Task 6 (surfacing).
5. **Due-time boundaries:** due today but already past is red, not orange; due at 00:00 tomorrow is neither; a task with no due date is never coloured. Test in Task 4.

## File Structure

**Backend**

| File | Responsibility |
|---|---|
| `functions/src/tasks.ts` (new) | Pure task transitions, validation and permission predicates |
| `functions/src/tasks.test.ts` (new) | Unit tests for the above |
| `functions/src/index.ts` | Collection name, six `task.*` actions, event-delete cascade, `canManageTasks` on the member serializer |
| `functions/src/team_member_self_edit.test.ts` | One case: a self-edit cannot grant `canManageTasks` |
| `firestore.rules` | Read rules for `tasks` and `test_tasks` |

**Client** (paths under `shavtzak/`)

| File | Responsibility |
|---|---|
| `lib/domain/entities/subtask.dart`, `task_item.dart` (new) | Entities |
| `lib/domain/entities/team_member.dart`, `lib/data/models/team_member_model.dart` | `canManageTasks` |
| `lib/core/utils/task_utils.dart` (new) | Due status, filter, sort, permission predicates |
| `lib/data/models/task_item_model.dart` (new) | Firestore map ↔ entity, backend payload |
| `lib/data/data_sources/database_interface.dart`, `firestore_database.dart`, `logging_database.dart` | `watchTasks` and six mutations |
| `lib/data/repositories/task_repository.dart` (new) | Populated task stream, mutation pass-through |
| `lib/presentation/bloc/task/task_bloc.dart`, `task_event.dart`, `task_state.dart` (new) | State |
| `lib/presentation/screens/task/tasks_screen.dart` (new) | The screen |
| `lib/presentation/screens/task/widgets/task_card.dart` (new) | One task card with subtasks |
| `lib/presentation/screens/task/widgets/task_form_modal.dart` (new) | Create and edit |
| `lib/presentation/screens/task/widgets/task_filter_modal.dart` (new) | Status, event, assignee filter |
| `lib/presentation/screens/task/widgets/assignee_update_dialog.dart` (new) | Edit the status note |
| `lib/core/router/app_router.dart` | `/tasks`, `/test/tasks`, deep link through sign-in |
| `lib/main.dart` | Repository and bloc providers, auth-rebuild predicate |
| `lib/presentation/bloc/user_selection/user_selection_bloc.dart` | Re-emit on `canManageTasks` change |
| `lib/presentation/screens/team/team_list_screen.dart` | `ניהול משימות` switch |
| `lib/presentation/screens/db/db_preview_screen.dart` | List the `tasks` collection |

---

### Task 1: Backend task logic (pure)

**Files:**
- Create: `functions/src/tasks.ts`, `functions/src/tasks.test.ts`

**Interfaces — produces:**

```ts
export class TaskError extends Error { status: number; constructor(status: number, message: string) }
export type TaskActor = {memberId: string; name: string | null; isAdmin: boolean; canManageTasks: boolean};
export type Subtask = {id: string; title: string; isDone: boolean};
export type TaskDoc = {
  id: string; eventId: string; title: string; description: string;
  subtasks: Subtask[]; dueAt: Timestamp | null; assigneeIds: string[];
  assigneeUpdate: string | null; assigneeUpdateAt: Timestamp | null;
  assigneeUpdateById: string | null; assigneeUpdateByName: string | null;
  isComplete: boolean; completedAt: Timestamp | null; completedById: string | null;
  createdAt: Timestamp; createdById: string; updatedAt: Timestamp;
};
type Ctx = {now: Timestamp; actor: TaskActor};

export function canManageTasks(actor: TaskActor): boolean;
export function isTaskAssignee(task: Pick<TaskDoc, 'assigneeIds'>, actor: TaskActor): boolean;
export function requireTaskManager(actor: TaskActor): void;            // 403
export function requireTaskParticipant(task: TaskDoc, actor: TaskActor): void; // 403
export function taskFromStored(id: string, raw: Record<string, unknown>): TaskDoc; // tolerant of missing fields
export function buildNewTask(input: Record<string, unknown>, ctx: Ctx): TaskDoc;
export function applyTaskEdit(existing: TaskDoc, input: Record<string, unknown>, ctx: Ctx): TaskDoc;
export function applySubtaskToggle(existing: TaskDoc, subtaskId: string, isDone: boolean, ctx: Ctx): TaskDoc;
export function applySetComplete(existing: TaskDoc, isComplete: boolean, ctx: Ctx): TaskDoc;
export function applyAssigneeUpdate(existing: TaskDoc, text: string, ctx: Ctx): TaskDoc;
```

Input shape for `buildNewTask` and `applyTaskEdit`:
`{id, eventId, title, description, dueAt: string | null, assigneeIds: string[], subtasks: {id, title}[]}`.

**Rules the implementation must hold** (each is a test):

- Validation (all `TaskError(400, …)` with a Hebrew message): `title` trimmed and 1–200 chars; `description` ≤ 5000; `eventId` non-empty; `assigneeIds` de-duplicated, 1–100 entries; ≤ 50 subtasks, each title trimmed and 1–200 chars with a non-empty unique `id`; `dueAt` null or a parseable instant; update text ≤ 2000.
- `buildNewTask`: every subtask starts `isDone: false`; `isComplete` false; `createdAt` = `updatedAt` = `now`; `createdById` = actor.
- `applyTaskEdit`: replaces `eventId`, `title`, `description`, `dueAt`, `assigneeIds` and the subtask list; a subtask keeps its `isDone` when its `id` survives, a new one starts undone; never touches `createdAt`, `createdById` or the `assigneeUpdate*` fields.
- Completion is re-derived after every transition: with subtasks, `isComplete` is "all done"; without, it keeps its previous value. Turning true stamps `completedAt` = `now` and `completedById` = actor; turning false nulls both; staying true leaves both alone.
- `applySubtaskToggle`: unknown `subtaskId` → `TaskError(404, 'תת-המשימה לא נמצאה')`; changes only that subtask.
- `applySetComplete`: a task with subtasks → `TaskError(400, 'משימה עם תתי-משימות מסתיימת אוטומטית')`.
- `applyAssigneeUpdate`: trims; a non-empty text sets `assigneeUpdate`, `assigneeUpdateAt` = `now`, `assigneeUpdateById` and `assigneeUpdateByName` from the actor; an empty text nulls all four.
- Every transition sets `updatedAt` = `now`.
- `taskFromStored` fills defaults for any absent field (`subtasks: []`, nullables `null`, `isComplete: false`, `description: ''`).

- [ ] **Step 1: Write `tasks.test.ts`** with one `node:test` case per rule above, plus these Review Focus cases:
  - toggling subtask `b` on a stored task where `a` is already done leaves `a` done and completes the task (Focus 3);
  - toggling a subtask ID that is not in the stored task throws a `TaskError` with status 404 (Focus 4);
  - `requireTaskParticipant` throws 403 for a member who is neither manager nor assignee, and passes for an assignee and for a non-admin with `canManageTasks` (Focus 4).

  Test helpers: `const now = Timestamp.fromMillis(1_800_000_000_000)`, `const manager: TaskActor = {memberId: 'm-admin', name: 'מנהל', isAdmin: true, canManageTasks: false}`, `const assignee: TaskActor = {memberId: 'm1', name: 'דנה', isAdmin: false, canManageTasks: false}`, and a `baseInput()` returning a valid input with two subtasks `a` and `b`.

- [ ] **Step 2:** `cd functions && npm test` — expect compile failure (`Cannot find module './tasks'`).
- [ ] **Step 3: Implement `tasks.ts`** to the interface and rules above. No Firestore reads or writes in this file; `Timestamp` is imported from `firebase-admin/firestore` for values only.
- [ ] **Step 4:** `cd functions && npm test` — all pass, including the existing suites.
- [ ] **Step 5:** Commit `feat(functions): add pure task transition logic`.

---

### Task 2: Backend wiring, cascade, member flag, rules

**Files:**
- Modify: `functions/src/index.ts` (`Collections` type ~L79, `getCollections` ~L183, `deleteEventRelatedDocuments` ~L454, `teamMemberDocFromJson` ~L2706, `event.delete` ~L4163, `executeMutation` switch after the `checklist.*` cases ~L5207, test exports ~L6531)
- Modify: `functions/src/team_member_self_edit.test.ts`, `firestore.rules`

**Interfaces — consumes:** everything exported by Task 1.
**Interfaces — produces** (the wire contract the client relies on):

| Operation | Payload | Guard |
|---|---|---|
| `task.insert` | `{task}` | `requireTaskManager` |
| `task.update` | `{task}` | `requireTaskManager` |
| `task.delete` | `{taskId}` | `requireTaskManager` |
| `task.setSubtaskDone` | `{taskId, subtaskId, isDone}` | `requireTaskParticipant` |
| `task.setComplete` | `{taskId, isComplete}` | `requireTaskParticipant` |
| `task.setAssigneeUpdate` | `{taskId, text}` | `requireTaskParticipant` |

All return `{ok: true}`. A missing task is `HttpError(404, 'המשימה לא נמצאה')`.

- [ ] **Step 1: Failing test** in `team_member_self_edit.test.ts`: `applySelfEditableFields(buildExisting({canManageTasks: false}), {...existing, canManageTasks: true, updatedAt: 'ts'})` returns `canManageTasks === false`. Add a second test for a new export `__testTeamMemberDocFromJson`: a payload without `canManageTasks` and an `existing` with `canManageTasks: true` keeps `true`; a payload with `false` yields `false`.
- [ ] **Step 2:** `npm test` — the second test fails (export missing).
- [ ] **Step 3: Implement in `index.ts`:**
  - `Collections.tasks: string` and `tasks: \`${prefix}tasks\`` in `getCollections`.
  - `teamMemberDocFromJson`: `canManageTasks: member['canManageTasks'] ?? existing?.['canManageTasks'] ?? false`; export it as `__testTeamMemberDocFromJson`.
  - A local `taskActor(actor: ActorContext): TaskActor` reading `actor.member['name']` and `actor.member['canManageTasks'] === true`, and `runTaskLogic<T>(fn: () => T): T` that rethrows a `TaskError` as `HttpError(e.status, e.message)`.
  - The six `case 'task.*'` blocks. Each: build `taskActor`, open `db.runTransaction`, read the task doc (insert uses `transaction.create`), run the guard and the Task 1 transition with `now = Timestamp.now()`, write the full resulting document with `transaction.set`, then `writeAuditLog(db, collections, actor, operation, 'task', taskId, details, {before, after})`.
  - `task.insert` and `task.update` additionally call `requireWritableEventInTransaction` for the target event and verify every `assigneeId` exists in `collections.teamMembers` (`HttpError(400, 'חבר צוות לא נמצא')`). Firestore requires all transaction reads before writes: do the reads first.
  - Audit `details`: always `{title, eventId}`; `task.setAssigneeUpdate` adds `assigneeUpdate: <saved text or null>`; `task.setSubtaskDone` adds `subtaskTitle` and `isDone`.
  - `deleteEventRelatedDocuments`: add `tasks` as a third query in the loop.
  - `event.delete`: read the event's tasks alongside the checklist snapshot and add `deletedTasks: [{id, title}]` to the audit details when non-empty.
- [ ] **Step 4: `firestore.rules`:** add after the `test_checklist_presets` block:

```
    match /tasks/{document=**} {
      allow read: if isAuthorizedProdUser();
      allow write: if false;
    }

    match /test_tasks/{document=**} {
      allow read: if isAuthorizedTestUser();
      allow write: if false;
    }
```

- [ ] **Step 5:** `cd functions && npm test` — all pass. `npm run build` reports no type errors.
- [ ] **Step 6:** Commit `feat(functions): add task actions, cascade and canManageTasks`.

---

### Task 3: Dart entities and the member flag

**Files:**
- Create: `lib/domain/entities/subtask.dart`, `lib/domain/entities/task_item.dart`
- Modify: `lib/domain/entities/team_member.dart`, `lib/data/models/team_member_model.dart`
- Test: `test/domain/entities/task_item_test.dart`, add cases to the existing team-member model test

**Interfaces — produces:**

```dart
class Subtask extends Equatable {
  final String id; final String title; final bool isDone;
  const Subtask({required this.id, required this.title, this.isDone = false});
  Subtask copyWith({String? id, String? title, bool? isDone});
}

class TaskItem extends Equatable {
  final String id; final String eventId; final String title; final String description;
  final List<Subtask> subtasks; final DateTime? dueAt; final List<String> assigneeIds;
  final String? assigneeUpdate; final DateTime? assigneeUpdateAt;
  final String? assigneeUpdateById; final String? assigneeUpdateByName;
  final bool isComplete; final DateTime? completedAt; final String? completedById;
  final DateTime createdAt; final String createdById; final DateTime updatedAt;
  final Event? event; final List<TeamMember> assignees;       // populated by the repository
  bool get hasSubtasks; int get doneSubtaskCount; double get progress; // 0..1, 0 when no subtasks
  bool isAssignedTo(String memberId);
  TaskItem copyWith({... , bool clearDueAt = false});
}
```

`TeamMember.canManageTasks` (default `false`) in the entity (`copyWith`, `props`) and in `TeamMemberModel` (`fromEntity`, `toEntity`, both Firestore and JSON readers default to `false`, both writers emit it).

- [ ] **Step 1: Tests:** equality changes when any single field changes, including a populated `event` whose `location` changed and a subtask's `isDone`; `doneSubtaskCount`/`progress` for 0, 1 of 3 and 3 of 3; `copyWith(clearDueAt: true)`; the member model round-trips `canManageTasks` and defaults it to `false` when the key is absent.
- [ ] **Step 2:** `flutter test test/domain/entities/task_item_test.dart` — fails to compile.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** Commit `feat: add task entities and canManageTasks member flag`.

---

### Task 4: Pure task helpers

**Files:**
- Create: `lib/core/utils/task_utils.dart`
- Test: `test/core/utils/task_utils_test.dart`

**Interfaces — produces:**

```dart
enum TaskDueStatus { completed, overdue, dueToday, open }

TaskDueStatus taskDueStatus(TaskItem task, DateTime now);
bool canManageTasks(TeamMember user);                       // isAdmin || canManageTasks
bool canUpdateTaskProgress(TaskItem task, TeamMember user); // manager or assignee
List<TaskItem> filterTasks(
  List<TaskItem> tasks, {
  required DateTime now,
  String query = '',
  String? onlyAssigneeId,                 // the "my tasks" toggle
  Set<TaskDueStatus> statuses = const {},  // empty = no restriction
  Set<String> eventIds = const {},
  Set<String> assigneeIds = const {},
});
List<TaskItem> sortTasks(List<TaskItem> tasks, DateTime now);
```

Rules: completed wins; overdue when `dueAt` is before `now`; dueToday when `dueAt` is on `now`'s calendar date and not yet past; otherwise open; no `dueAt` is open. Search uses `normalizeForSearch` over title, description and `event?.name`. Sort order: overdue, dueToday, open (by `dueAt` ascending, undated last), completed (by `completedAt` descending); ties break on `title`.

- [ ] **Step 1: Tests**, including Review Focus 5 as explicit cases with `now = DateTime(2026, 10, 11, 14, 0)`: `dueAt` 13:59 today → overdue; 14:01 today → dueToday; 23:59 today → dueToday; 00:00 on the 12th → open; null → open; completed with a past `dueAt` → completed. Filter cases: each parameter alone, two combined, the query matching the event name, and a task with `event == null` surviving an empty filter but dropping out of an `eventIds` filter for another event.
- [ ] **Step 2:** Run — fails to compile.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** Commit `feat: add task status, filter and sort helpers`.

---

### Task 5: Data layer

**Files:**
- Create: `lib/data/models/task_item_model.dart`, `lib/data/repositories/task_repository.dart`
- Modify: `lib/data/data_sources/database_interface.dart`, `firestore_database.dart`, `logging_database.dart`
- Test: `test/data/models/task_item_model_test.dart`, `test/data/repositories/task_repository_test.dart`

**Interfaces — produces:**

```dart
class TaskItemModel {
  static TaskItem fromMap(String id, Map<String, dynamic> data,
      {Event? event, List<TeamMember> assignees = const []});
  static Map<String, dynamic> toMutationPayload(TaskItem task); // {id,eventId,title,description,dueAt,assigneeIds,subtasks:[{id,title}]}
}

// DatabaseInterface
Stream<List<TaskItem>> watchTasks();   // unpopulated: event == null, assignees == []
Future<void> insertTask(TaskItem task);
Future<void> updateTask(TaskItem task);
Future<void> deleteTask(String taskId);
Future<void> setSubtaskDone(String taskId, String subtaskId, bool isDone);
Future<void> setTaskComplete(String taskId, bool isComplete);
Future<void> setTaskAssigneeUpdate(String taskId, String text);

class TaskRepository {
  TaskRepository(DatabaseInterface database);
  Stream<List<TaskItem>> watchTasks();   // populated
  // the six mutations, same names and signatures as the interface
}
```

`toMutationPayload` writes `dueAt` as `task.dueAt?.toUtc().toIso8601String()`.
`TaskRepository.watchTasks()` is `Rx.combineLatest3(_database.watchTasks(), _database.watchEvents(), _database.watchTeamMembers(), …)`; assignees keep `assigneeIds` order and silently drop IDs that do not resolve.

- [ ] **Step 1: Tests.** Model: a full map round-trips; a map with only `eventId`, `title`, `assigneeIds`, `createdAt`, `createdById`, `updatedAt` parses with defaults (Review Focus 2); a subtask entry that is not a map is skipped; `toMutationPayload` emits a `Z`-suffixed `dueAt` and no `isDone`. Repository (stream controllers standing in for the three sources, a mockito `MockDatabaseInterface` generated with `@GenerateMocks`): emits populated tasks; re-emits with the new name when the events stream delivers a renamed event; drops an unknown assignee ID; each mutation forwards its arguments.
- [ ] **Step 2:** Run — fails to compile.
- [ ] **Step 3:** Implement. In `FirestoreDatabase`, `watchTasks()` is `collection('${prefix}tasks').snapshots()` mapped through `TaskItemModel.fromMap(doc.id, doc.data())`; each mutation wraps `_invokeMutation` and rethrows as `DatabaseException` like the checklist methods. In `LoggingDatabase`, `watchTasks` uses `_wrapStream` and the mutations use `_runFuture` with `ctx: {'collection': 'tasks', 'id': …}`.
- [ ] **Step 4:** `dart run build_runner build --delete-conflicting-outputs` for the new mock, then `flutter test` — everything passes. Any hand-written `DatabaseInterface` fake that no longer compiles gets the seven new members.
- [ ] **Step 5:** Commit `feat: add task data layer`.

---

### Task 6: TaskBloc

**Files:**
- Create: `lib/presentation/bloc/task/task_bloc.dart`, `task_event.dart`, `task_state.dart`
- Modify: `lib/main.dart` (repository record, `MyApp` field, `RepositoryProvider`, `BlocProvider`)
- Test: `test/presentation/bloc/task_bloc_test.dart`

**Interfaces — produces:**

```dart
// events — every mutation carries `CrudActionCompleter? completion`
LoadTasks()
CreateTask(TaskItem task, {completion})
UpdateTask(TaskItem task, {completion})
DeleteTask(String taskId, {completion})
ToggleSubtask({required String taskId, required String subtaskId, required bool isDone, completion})
SetTaskComplete({required String taskId, required bool isComplete, completion})
SaveAssigneeUpdate({required String taskId, required String text, completion})

// states
TasksInitial, TasksLoading, TasksLoaded(List<TaskItem> tasks), TasksError(String message)
```

`LoadTasks` uses `emit.forEach(repository.watchTasks())` with `restartable`-free default handling: a second `LoadTasks` while one is running is ignored. A mutation failure completes the completer with `CrudActionResult.failure(<Hebrew message>)` and does **not** replace `TasksLoaded`. The backend's Hebrew message is extracted from the exception text when present; otherwise a generic `הפעולה נכשלה`.

- [ ] **Step 1: Tests** with `bloc_test` and a mocked repository: `LoadTasks` emits `[TasksLoading, TasksLoaded]` and a second emission on stream update; each mutation calls the matching repository method once and completes with success; a repository throw completes with failure and leaves the state at `TasksLoaded` (Review Focus 4); a stream error emits `TasksError`.
- [ ] **Step 2:** Run — fails to compile.
- [ ] **Step 3:** Implement, then wire `TaskRepository` and `TaskBloc` into `main.dart` next to the checklist ones.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** Commit `feat: add TaskBloc`.

---

### Task 7: Task card

**Files:**
- Create: `lib/presentation/screens/task/widgets/task_card.dart`
- Test: `test/presentation/screens/task/widgets/task_card_test.dart`

**Interfaces — produces:**

```dart
class TaskCard extends StatefulWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.now,
    required this.canManage,
    required this.canUpdateProgress,
    required this.onToggleSubtask,   // void Function(Subtask subtask, bool isDone)
    required this.onSetComplete,     // ValueChanged<bool>
    required this.onEditUpdate,      // VoidCallback
    required this.onEdit,            // VoidCallback
    required this.onDelete,          // VoidCallback
  });
}
```

Layout, top to bottom: title row (completion checkbox only when there are no subtasks; status chip `הושלמה` / `באיחור` / `להיום`; overflow menu `עריכה` / `מחיקה` for managers; chevron when there are subtasks); event line (`event.name` and date, or `אירוע לא נמצא`); due line (`dd/MM/yyyy HH:mm`, or omitted); assignee names joined with `, ` (or `ללא אחראים`); description; progress row (`LinearProgressIndicator` + `X/N`) when there are subtasks; the update block (text, `— name, time`, and a `עדכון` button when `canUpdateProgress`); `עודכן לאחרונה: …`. Expanded: one inner `Card` per subtask with a checkbox, its title struck through when done. Tint: completed `Colors.green.shade50`, overdue `Colors.red.shade50`, dueToday `Colors.orange.shade50`, open none; a 4px leading border in the matching `shade400`. Completed titles use `TextDecoration.lineThrough`.

Widget keys used by tests: `Key('task-card-<id>')`, `Key('task-complete-<id>')`, `Key('subtask-<id>')`, `Key('task-progress-<id>')`, `Key('task-update-<id>')`.

- [ ] **Step 1: Tests:** each of the four statuses renders its chip text and tint; a completed title is struck through; `2/3` appears for two done of three and the card expands to show three subtask checkboxes; a task without subtasks shows the completion checkbox and no chevron; with `canUpdateProgress: false` the checkboxes are disabled and the `עדכון` button is absent; with `canManage: false` the overflow menu is absent; a task with `event == null` renders `אירוע לא נמצא` (Review Focus 1); tapping a subtask checkbox calls `onToggleSubtask` with that subtask and the new value.
- [ ] **Step 2:** Run — fails to compile.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** Commit `feat: add task card`.

---

### Task 8: Form, filter and update dialogs

**Files:**
- Create: `lib/presentation/screens/task/widgets/task_form_modal.dart`, `task_filter_modal.dart`, `assignee_update_dialog.dart`
- Test: `test/presentation/screens/task/widgets/task_form_modal_test.dart`, `task_filter_modal_test.dart`

**Interfaces — produces:**

```dart
/// Returns the task to save, or null when cancelled. `existing == null` means create.
Future<TaskItem?> showTaskFormModal(
  BuildContext context, {
  TaskItem? existing,
  required List<Event> events,          // all events; the modal filters to pickable ones
  required List<TeamMember> members,    // all members; the modal filters to active, non-archived
  required String currentUserId,
  DateTime? now,
});

class TaskFilterSelection extends Equatable {
  final Set<TaskDueStatus> statuses; final Set<String> eventIds; final Set<String> assigneeIds;
  const TaskFilterSelection({this.statuses = const {}, this.eventIds = const {}, this.assigneeIds = const {}});
  int get activeCount;   // number of non-empty groups
  bool get isEmpty;
}
Future<TaskFilterSelection?> showTaskFilterModal(
  BuildContext context, {
  required TaskFilterSelection current,
  required List<Event> events,        // events that have at least one task
  required List<TeamMember> members,  // members assigned to at least one task
});

Future<String?> showAssigneeUpdateDialog(BuildContext context, {String? initialText}); // null = cancelled, '' = clear
```

Form rules: pickable events are those whose `endDate` is today or later and that are not deactivated, plus `existing.event` when editing; save is disabled until event, non-empty title and at least one assignee are set; due date uses the existing `DualCalendarDatePicker` dialog and due time uses `EventTimeField`, with a clear button; a time without a date is ignored and a date without a time defaults to 23:59; subtask rows can be added, renamed and removed, new rows get a UUID, existing rows keep their `id` and `isDone`; blank subtask rows are dropped on save. `AlertDialog(scrollable: true)` must not wrap a `ListView`: put a `SingleChildScrollView` inside a width-constrained `SizedBox`.

- [ ] **Step 1: Tests.** Form: save disabled until the three required fields are set; editing preserves a subtask's `id` and `isDone` after its title is changed; a removed subtask is absent from the result; a past event is not offered on create but the task's own past event is offered on edit; an archived member is not offered. Filter: toggling entries in each group returns the matching `TaskFilterSelection`; `ניקוי` returns an empty selection.
- [ ] **Step 2:** Run — fails to compile.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** Commit `feat: add task form, filter and update dialogs`.

---

### Task 9: Screen, route and deep link

**Files:**
- Create: `lib/presentation/screens/task/tasks_screen.dart`
- Modify: `lib/core/router/app_router.dart`, `lib/presentation/screens/db/db_preview_screen.dart`
- Test: `test/presentation/screens/task/tasks_screen_test.dart`, `test/core/router/tasks_deep_link_test.dart`

**Interfaces — consumes:** `TaskBloc`, `UserSelectionBloc`, `EventBloc`/`TeamBloc` state for the form's pick lists, everything from Tasks 4, 7 and 8.

Screen behaviour: dispatches `LoadTasks` in `initState`; app bar `משימות דו יומי` with a home `IconButton` going to `/admin`, `/choice` or `/user/assignments` (with the env prefix) by the same rule the router uses; `SegmentedButton` `המשימות שלי` / `כל המשימות`, default mine; a search `TextField` plus a filter `IconButton` with a count badge, styled like `EventSearchFilterBar`; the list is `sortTasks(filterTasks(…))` rebuilt on a one-minute `Timer` so colours roll over without a data change; empty states `אין לך משימות פתוחות` (mine, nothing at all), `אין משימות` (all) and `לא נמצאו משימות תואמות` (filters active); a `FloatingActionButton.extended` `משימה חדשה` for managers. Every mutation is dispatched with a `CrudActionCompleter`; a failure shows its message in a `SnackBar`. Delete asks for confirmation first.

Routing: `GoRoute(path: '/tasks')` and `GoRoute(path: '/test/tasks')` beside `/summary`. No extra redirect rule is needed for authenticated members. For the signed-out case add a pure, testable helper:

```dart
/// The route to restore after sign-in when the app was opened on the tasks link, else null.
static String? pendingTasksLinkFor(String? initialHash); // '/tasks', '/test/tasks' or null
```

`router()` stores the result in a static `_pendingDeepLink` when `capturedInitialHash` targets the tasks route. In both places that send a freshly authenticated member from `/whoami` or `/` to their home (the `redirect` callback and the bloc-stream listener), a non-null `_pendingDeepLink` is used instead and then cleared. Signing out clears it.

`db_preview_screen.dart`: add `_CollectionConfig('tasks', 'משימות', Icons.task_alt, true)` after the checklist presets entry.

- [ ] **Step 1: Tests.** Deep link: `pendingTasksLinkFor('#/tasks')` → `/tasks`; `'#/test/tasks'` → `/test/tasks`; `'#/tasks?x=1'` → `/tasks`; `'#/admin/events'`, `'#/user/tasks-old'`, `null` and `''` → `null`. Screen (a `MockTaskBloc` via `bloc_test`'s `MockBloc`, seeded `UserSelectionBloc` state): defaults to only the current member's tasks; switching to `כל המשימות` shows the rest; typing a query narrows the list; the FAB is present for an admin and for a non-admin with `canManageTasks`, absent otherwise; a failed toggle shows the failure message in a snackbar (Review Focus 4).
- [ ] **Step 2:** Run — fails to compile.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** Commit `feat: add the tasks screen and its link-only route`.

---

### Task 10: Team-member switch and live flag updates

**Files:**
- Modify: `lib/presentation/screens/team/team_list_screen.dart` (state field ~L1094, init ~L1130, save ~L1256, switch after the constraints-examining one ~L2234), `lib/presentation/bloc/user_selection/user_selection_bloc.dart` (~L123), `lib/main.dart` (~L484), `lib/core/router/app_router.dart` (auth signature ~L179)

- [ ] **Step 1:** Add `_canManageTasks`, initialise it from the member, pass it to the saved member, and add:

```dart
SwitchListTile(
  title: const Text('ניהול משימות'),
  subtitle: const Text(
    'מאפשר לחבר צוות ליצור, לערוך ולמחוק משימות במסך המשימות',
  ),
  value: _canManageTasks,
  onChanged: (value) {
    Logger.action('toggle:canManageTasks', {'on': value});
    setState(() {
      _canManageTasks = value;
      _isDirty = true;
    });
  },
),
```

- [ ] **Step 2:** Add `canManageTasks` to the three change predicates that list the other `canAccess*` flags (`user_selection_bloc.dart`, `main.dart`, the router's auth signature), so toggling it for a signed-in member updates their tasks screen without a reload.
- [ ] **Step 3:** If a `UserSelectionBloc` test already covers the flag-change predicate, add a `canManageTasks` case beside it.
- [ ] **Step 4:** `flutter test` — all pass.
- [ ] **Step 5:** Commit `feat: add the task-manager switch to the team member modal`.

---

### Task 11: Gates and docs

- [ ] **Step 1:** `cd shavtzak && flutter analyze` — zero new issues against the baseline.
- [ ] **Step 2:** `cd shavtzak && flutter test` — all pass.
- [ ] **Step 3:** `cd functions && npm test` — all pass.
- [ ] **Step 4:** Update `CLAUDE.md`: add `tasks` to the collections list, `/tasks` and `/test/tasks` to the route table with a note that it is link-only, `TaskBloc` to the BLoC list, and the new test count.
- [ ] **Step 5:** Commit `docs: document the tasks screen`.
- [ ] **Step 6:** Report the deploy commands. Deploying is the user's action:
  `firebase deploy --only firestore:rules,functions`, then `firebase functions:list`.
