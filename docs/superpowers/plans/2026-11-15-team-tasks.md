# משימות צוות (team tasks) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "משימות" screen for the headquarters team's tasks: each task linked to an event, a category or a topic, with owners, subtasks (each with its own owner), contacts, an optional date deadline, five statuses and an update log.

**Architecture:** A new `teamTasks` collection (own backend operations `teamTask.*`, read rule by `ownerIds`), a managed `TaskTopics` list in `utilities/Lists` (operations `taskTopic.*`), pure rule modules on both sides (TS + Dart) with unit tests, one `TeamTaskBloc`, and screens that reuse the דו יומי editors (`ContactsEditor`, `AssigneesEditor`, `TextValueEditor`). דו יומי code and collections are not changed.

**Tech Stack:** Flutter Web 3.50 (flutter_bloc, go_router, fake_cloud_firestore, bloc_test), Firebase Functions (TypeScript, `node:test`), Firestore rules.

**Spec:** `docs/superpowers/specs/2026-11-15-team-tasks-design.md`

## Global Constraints

- Every user-facing string in Hebrew, every screen RTL. App terms: "משימות", "חבר צוות", "אחראים", "קטגוריה", "נושא", "אנשי קשר", "יומן עדכונים", "ניהול נושאים", "ניהול משימות".
- Statuses and their labels, exactly: `open` "פתוחה", `inProgress` "בטיפול", `done` "בוצעה", `cancelled` "לא רלוונטי/בוטל", `duplicate` "כפילות".
- Deadline: optional, `yyyy-MM-dd` date only. Late = deadline before today's Israel date and status `open`/`inProgress`.
- Managers = `isAdmin || canManageTasks`. A non-manager reads only tasks whose `ownerIds` contain their member id.
- `ownerIds` = `assigneeIds` when the task has no subtasks, else the distinct non-null subtask `assigneeId`s. A task with subtasks stores `assigneeIds: []`.
- Contacts on a task and on a subtask have the `StageContact` shape `{id, name, role, phone}`.
- All writes through the backend; collections are environment-prefixed (`test_teamTasks`). The topics list lives in `utilities/Lists` field `TaskTopics`, like `EventItems`.
- Equatable entities/states carry full objects in `props` (repo CLAUDE.md "The Golden Rule").
- No Excel import/export, no notifications, no change to `tasks`/`stages` or the דו יומי screens.
- Functions are tested against a parallel function `apiPreview` before merge; the production `api` keeps running the old code until the merge (memory: feature process).

## Auth finding (resolves the spec's open point)

`/auth/login` (`functions/src/index.ts` ~6739) signs the member in with `auth.createCustomToken(memberResult.id, {uniqueKey, isAdmin})`, and the client calls `signInWithCustomToken` (`user_selection_repository.dart:45`). So `request.auth.uid` **is** the team member document id, which is what `isAuthorizedProdUser()` already relies on. `canManageTasks` is not a claim, so the rule reads it from the member document:

```
function teamTaskManager(membersPath) {   // membersPath: teamMembers / test_teamMembers
  let m = get(/databases/$(database)/documents/$(membersPath)/$(request.auth.uid)).data;
  return m.isAdmin == true || m.canManageTasks == true;
}
match /teamTasks/{id} {
  allow read: if isAuthorizedProdUser()
    && (teamTaskManager('teamMembers') || request.auth.uid in resource.data.ownerIds);
  allow write: if false;
}
// test_teamTasks: same with isAuthorizedTestUser() and 'test_teamMembers'
```

Consequence for the client: a non-manager's listener **must** be the query `where('ownerIds', arrayContains: me)`; a query over the whole collection is refused by the rule.

## Review Focus

1. A non-manager opening the screen: the repository uses the `ownerIds` query (else permission-denied and an empty screen). Test in Task 6.
2. A subtask's owner or a task's owner who was archived/deleted as a member: the row shows "חבר צוות לא ידוע", `ownerIds` keeps the id, nothing crashes. Test in Task 7.
3. A linked event deleted, or a category/topic archived: the task still shows, under a group labelled "אירוע שנמחק" / the archived name. Test in Task 7.
4. Auto status never overrides `cancelled`/`duplicate`: ticking the last subtask of a cancelled task leaves it cancelled. Test in Task 1.
5. `duplicateOfId`: refused when it equals the task's own id or names a task that does not exist; a duplicate whose original was later deleted shows "(המקורית נמחקה)". Tests in Tasks 1, 2, 7.

---

### Task 1: Backend pure rules — `team_tasks.ts`

**Files:**
- Create: `functions/src/team_tasks.ts`
- Test: `functions/src/team_tasks.test.ts`

**Interfaces:**
- Consumes: `TaskActor`, `canManageTasks`, `TaskError` from `functions/src/tasks.ts`; `StageContact` from `functions/src/stages.ts`.
- Produces:
  - `type TeamTaskStatus = 'open' | 'inProgress' | 'done' | 'cancelled' | 'duplicate'`
  - `type TaskLink = {type: 'event' | 'category' | 'topic'; id: string} | null`
  - `type TeamSubtask = {id; title; isDone; assigneeId: string | null; contacts: StageContact[]}`
  - `type TaskUpdateEntry = {id; text; at: Timestamp; byId; byName: string | null}`
  - `type TeamTaskDoc = {id; title; description; link: TaskLink; assigneeIds: string[]; subtasks: TeamSubtask[]; contacts: StageContact[]; deadline: string | null; status: TeamTaskStatus; duplicateOfId: string | null; updates: TaskUpdateEntry[]; ownerIds: string[]; completedAt: Timestamp | null; createdAt; createdById; updatedAt}`
  - `deriveOwnerIds(task: Pick<TeamTaskDoc,'assigneeIds'|'subtasks'>): string[]`
  - `teamTaskFromStored(id: string, raw: Record<string, unknown>): TeamTaskDoc`
  - `buildNewTeamTask(input: Record<string, unknown>, ctx: {now: Timestamp; actor: TaskActor}): TeamTaskDoc` (manager only)
  - `applyTeamTaskEdit(task: TeamTaskDoc, input: Record<string, unknown>, ctx): TeamTaskDoc` (manager only; title, description, link, assigneeIds, subtasks, contacts, deadline)
  - `applyTeamTaskStatus(task, status: TeamTaskStatus, duplicateOfId: string | null, ctx): TeamTaskDoc` (manager or owner)
  - `applyTeamSubtaskToggle(task, subtaskId: string, isDone: boolean, ctx): TeamTaskDoc` (manager or that subtask's owner)
  - `appendTeamTaskUpdate(task, text: string, ctx): TeamTaskDoc` (manager or owner)
  - `isTeamTaskOwner(task, actor): boolean`; `teamTaskAuditDetails(task)`

- [ ] **Step 1: Write the failing tests** (`node:test`, like `tasks.test.ts`), named:
  - `deriveOwnerIds uses assigneeIds without subtasks` → `['a','b']`
  - `deriveOwnerIds is the distinct subtask owners when there are subtasks` → subtasks owned `a, b, a, null` give `['a','b']`
  - `buildNewTeamTask clears assigneeIds when subtasks exist`
  - `buildNewTeamTask refuses a non-manager` → `TaskError` 403
  - `buildNewTeamTask refuses an empty title` → 400 "חובה להזין כותרת"
  - `deadline must be yyyy-MM-dd or null` → `'15.11'` gives 400
  - `link type must be event, category or topic` → `{type:'stage'}` gives 400
  - `ticking the last open subtask sets done and completedAt`
  - `unticking a subtask of a done task sets inProgress and clears completedAt`
  - `ticking the last subtask of a cancelled task keeps cancelled` (Review Focus 4)
  - `duplicate requires duplicateOfId and refuses the task's own id` (Review Focus 5)
  - `a non-duplicate status clears duplicateOfId`
  - `an owner may set status, a stranger may not` → 403
  - `only the subtask's owner or a manager ticks it` → another owner of the task gets 403
  - `appendTeamTaskUpdate puts the newest first with author and time`; `refuses blank text`

- [ ] **Step 2: Run** `cd functions && npm test` — the new tests FAIL (module missing).
- [ ] **Step 3: Implement** the module. Every builder recomputes `ownerIds` with `deriveOwnerIds` and bumps `updatedAt`. Status change to `done` sets `completedAt = now`; away from `done` clears it.
- [ ] **Step 4: Run** `npm test` — all pass, including the 479 existing.
- [ ] **Step 5: Commit** `feat(team-tasks): backend rules for team tasks`

### Task 2: Backend operations, topics and the parallel function

**Files:**
- Modify: `functions/src/index.ts` (`Collections` + `getCollections`: `teamTasks`; the operation `switch`: new cases; a new export `apiPreview`)
- Create: `functions/src/task_topics.ts` (`applyTaskTopicMutation(catalogue, operation, payload, nowIso)` mirroring `applyEventItemCatalogueMutation`, items `{id, name, sortOrder, isArchived}`)
- Test: `functions/src/task_topics.test.ts`, `functions/src/team_tasks_api.test.ts` (follow `assignment_custom_hours_api.test.ts` for the in-memory db pattern)

**Interfaces:**
- Consumes: Task 1's builders; `requireTaskAssigneesInTransaction` (active members); `getCategoriesArray`; `getUtilitiesListsDoc`; `writeAuditLog`.
- Produces backend operations (payload keys in brackets):
  - `teamTask.insert` [`task`], `teamTask.update` [`task` with `id`], `teamTask.delete` [`id`] — manager
  - `teamTask.setStatus` [`id`, `status`, `duplicateOfId`] — manager or owner
  - `teamTask.setSubtaskDone` [`id`, `subtaskId`, `isDone`] — manager or subtask owner
  - `teamTask.addUpdate` [`id`, `text`] — manager or owner
  - `taskTopic.insert|update|delete|permanentlyDelete|restore` [`topic`] — manager (`requireTaskManager`, not admin-only)
  - Export `apiPreview` = the same Express app as `api` (same options).

- [ ] **Step 1: Failing tests**:
  - `insert checks the link exists` → event id missing from `events` gives 404 "האירוע לא נמצא"; unknown category id 404; unknown topic id 404
  - `insert refuses an inactive owner` (via `requireTaskAssigneesInTransaction`)
  - `setStatus duplicate refuses a missing original` → 404 (Review Focus 5)
  - `writes go to test_teamTasks in the test environment`
  - `taskTopic insert/rename/archive/restore`, `a non-manager cannot add a topic` → 403
- [ ] **Step 2: Run** `npm test` — FAIL.
- [ ] **Step 3: Implement** the cases inside one transaction each (read task, check, write), audit-logged like `task.*`.
- [ ] **Step 4: Run** `npm run build && npm test` — PASS.
- [ ] **Step 5: Commit** `feat(team-tasks): teamTask and taskTopic operations, apiPreview function`

### Task 3: Firestore rules and the preview wiring

**Files:**
- Modify: `firestore.rules` (the block in "Auth finding" for `teamTasks` and `test_teamTasks`)
- Modify: `shavtzak/lib/core/services/backend_api_service.dart` `_buildUri`: function name from `const String.fromEnvironment('SHAVTZAK_API_FUNCTION', defaultValue: 'api')`
- Modify: `scripts/preview.sh`: build with `--dart-define=SHAVTZAK_API_FUNCTION=apiPreview` when `PREVIEW_API=1`
- Test: `shavtzak/test/core/services/backend_api_service_uri_test.dart` → default build targets `/api`

- [ ] **Step 1:** failing test `default function is api`.
- [ ] **Step 2:** implement; `flutter test test/core/services/backend_api_service_uri_test.dart` PASS.
- [ ] **Step 3:** no rules test harness exists in the repo; the rule is checked on the preview (Task 10) by a non-manager login (sees only own tasks) and a manager login (sees all).
- [ ] **Step 4: Commit** `feat(team-tasks): read rule by ownerIds; preview build can target apiPreview`

### Task 4: Dart domain and models

**Files:**
- Create: `shavtzak/lib/domain/entities/team_task.dart` (`TeamTask`, `TeamSubtask`, `TaskLink`, `TaskLinkType`, `TeamTaskStatus` with `hebrewLabel`, `TaskUpdateEntry`), `shavtzak/lib/domain/entities/task_topic.dart`
- Create: `shavtzak/lib/data/models/team_task_model.dart` (`fromFirestore`/`toBackendPayload`), `task_topic` parsing like `EventItem.listFromJson`
- Test: `shavtzak/test/data/models/team_task_model_test.dart`

**Interfaces:**
- Produces: `TeamTask` (Equatable, `copyWith`, all fields of `TeamTaskDoc` + joined `Event? event`, `Category? category`, `TaskTopic? topic`, `List<TeamMember> owners`); `TeamSubtask` (+ `TeamMember? assignee`); `contacts: List<StageContact>` (existing entity); `TeamTaskStatus.fromKey(String)`.

- [ ] Step 1 failing tests: `round-trips every field`, `unknown status key reads as open`, `missing contacts read as empty`, `deadline stays a plain date string`.
- [ ] Step 2 run FAIL → Step 3 implement → Step 4 `flutter test test/data/models/team_task_model_test.dart` PASS → Step 5 commit `feat(team-tasks): entities and models`.

### Task 5: Pure rules — `team_task_rules.dart`

**Files:**
- Create: `shavtzak/lib/core/utils/team_task_rules.dart`
- Test: `shavtzak/test/core/utils/team_task_rules_test.dart`

**Interfaces:**
- Produces:
  - `bool isTeamTaskLate(TeamTask t, DateTime now)` (Israel date, Global Constraints)
  - `bool canManageTeamTasks(TeamMember m)`; `bool isTeamTaskOwner(TeamTask t, String memberId)`
  - `List<TeamTaskGroup> groupTeamTasks(List<TeamTask> tasks, DateTime now)`; `TeamTaskGroup {String key; String label; TaskLinkType? type; List<TeamTask> tasks}`; groups ordered by their nearest open deadline (none last), then label; inside: deadline asc (none last), done at the bottom, then title; ungrouped = "ללא שיוך"
  - `class TeamTaskFilter {Set<TeamTaskStatus> statuses; String? ownerId; TaskLink? link}` with `TeamTaskFilter.initial` = every status but `cancelled`, `duplicate`
  - `List<TeamTask> applyTeamTaskFilter(List<TeamTask>, TeamTaskFilter, Map<String,String?> eventCategoryById)` — a category link also matches tasks linked to events of that category
  - `bool showTeamTasksTab(TeamMember m, List<TeamTask> myTasks)` = manager or any of `myTasks` not cancelled/duplicate

- [ ] Step 1 failing tests: one per bullet, with `now` injected; plus `late is false on the deadline day itself`, `late is false for done/cancelled`.
- [ ] Steps 2-5 as usual; commit `feat(team-tasks): grouping, sorting, filter and late rules`.

### Task 6: Data layer — interface, Firestore, repository

**Files:**
- Modify: `shavtzak/lib/data/data_sources/database_interface.dart`, `firestore_database.dart` (section "Team tasks")
- Create: `shavtzak/lib/data/repositories/team_task_repository.dart`
- Create: `shavtzak/test/support/fake_team_task_repository.dart`
- Test: `shavtzak/test/data/repositories/team_task_repository_test.dart` (fake_cloud_firestore)

**Interfaces:**
- Produces on `DatabaseInterface`: `Stream<List<TeamTask>> watchAllTeamTasks()`, `Stream<List<TeamTask>> watchOwnedTeamTasks(String memberId)` (the `arrayContains` query), `insertTeamTask(TeamTask)`, `updateTeamTask(TeamTask)`, `deleteTeamTask(String id)`, `setTeamTaskStatus(String id, TeamTaskStatus s, {String? duplicateOfId})`, `setTeamSubtaskDone(String id, String subtaskId, bool isDone)`, `addTeamTaskUpdate(String id, String text)`, `Stream<List<TaskTopic>> watchTaskTopics()`, `insertTaskTopic/updateTaskTopic/archiveTaskTopic/restoreTaskTopic`.
- `TeamTaskRepository.watchTasksFor(TeamMember viewer)` → all for a manager, owned otherwise; joins events, categories, topics, members (pattern of `TaskRepository`).

- [ ] Step 1 failing tests: `a non-manager watches only the ownerIds query` (Review Focus 1: asserts the fake sees no task of another member), `writes go through BackendApiService with the operation names of Task 2`, `collection is test_teamTasks in test mode`.
- [ ] Steps 2-5; commit `feat(team-tasks): data layer`.

### Task 7: `TeamTaskBloc`

**Files:**
- Create: `shavtzak/lib/presentation/bloc/team_task/team_task_bloc.dart`, `_event.dart`, `_state.dart`; register in the service locator like `TaskBloc`
- Test: `shavtzak/test/presentation/bloc/team_task_bloc_test.dart` (bloc_test + the fake repository)

**Interfaces:**
- Events: `TeamTasksSubscribe(TeamMember viewer)`, `TeamTaskFilterChanged(TeamTaskFilter)`, `CreateTeamTask`, `UpdateTeamTask`, `DeleteTeamTask`, `SetTeamTaskStatus`, `ToggleTeamSubtask`, `AddTeamTaskUpdate` (mutations carry a `Completer<void>` like `TaskBloc`).
- State: `TeamTasksLoaded {List<TeamTask> all; List<TeamTask> mine; List<TeamTaskGroup> groups; TeamTaskFilter filter; bool canManage}`.
- Optimistic subtask tick and status, rolled back on a backend error (the `_pending` pattern of `TaskBloc`).

- [ ] Step 1 failing tests: `manager gets all and mine`, `owner gets only mine and canManage false`, `optimistic tick then rollback on error`, `an owner archived as a member shows as unknown` (Review Focus 2), `a task of a deleted event lands in the "אירוע שנמחק" group` (Review Focus 3), `a duplicate of a deleted task is labelled (המקורית נמחקה)` (Review Focus 5).
- [ ] Steps 2-5; commit `feat(team-tasks): TeamTaskBloc`.

### Task 8: Screens — list, task sheet, new task

**Files:**
- Create: `shavtzak/lib/presentation/screens/team_task/team_tasks_screen.dart` (tabs "המשימות שלי" / "כל המשימות" (managers), filter bar, grouped list, "+ משימה חדשה" FAB for managers, ⋯ menu "ניהול נושאים")
- Create: `.../team_task/widgets/team_task_row.dart` (status chip, title, deadline red when late, owner chips, `x/y` subtasks)
- Create: `.../team_task/widgets/team_task_sheet.dart` (bottom sheet on a phone, centred ≤ 960 px on ≥ 1000 px; sections in the spec's order: link, status, deadline, description, owners, contacts, subtasks with owner chip and their contacts, update log with "+ עדכון")
- Create: `.../team_task/widgets/task_link_picker.dart` (segments אירוע / קטגוריה / נושא + list + "+ נושא חדש")
- Create: `.../team_task/widgets/team_subtasks_editor.dart` (title, owner picker, contacts per subtask; built on `SubtasksEditor`'s lines + `ContactsEditor`)
- Modify: `shavtzak/lib/presentation/screens/task/edit/value_editors.dart` only if `AssigneesEditor`/`ContactsEditor` need a public tweak (no behaviour change for דו יומי)
- Test: `shavtzak/test/presentation/screens/team_task/team_tasks_screen_test.dart`, `team_task_sheet_test.dart`

**Interfaces:**
- Consumes: Task 7 bloc; `ContactsEditor`, `AssigneesEditor` (`offered` = all active team members), `TextValueEditor`, `RtlArrowKeys`, `RowHold`; Flutter `showDatePicker` for the deadline (clearable).
- A manager edits each value in place (saved at once via `UpdateTeamTask`); an owner sees status, own-subtask ticks and the log box enabled, the rest read-only. Contacts: tap the phone = the "להתקשר ל…?" confirm used for assignees.

- [ ] Step 1 failing widget tests: `owner sees no FAB and no all-tasks tab`, `manager sees both`, `late deadline is red`, `status menu shows the five Hebrew labels`, `choosing כפילות asks for the original`, `owner can tick only their own subtask`, `adding an update shows it first`, `new task saves with a topic link`, `manager deletes only after the confirm`.
- [ ] Steps 2-5; commit `feat(team-tasks): tasks list and task sheet`.

### Task 9: Topic management and navigation

**Files:**
- Create: `shavtzak/lib/presentation/screens/team_task/widgets/topic_management_dialog.dart` (mirror `event_item_management_dialog.dart`: add, rename, archive, restore)
- Modify: `shavtzak/lib/core/router/app_router.dart` (routes `/team-tasks`, `/user/team-tasks`, `/test/team-tasks`, `/test/user/team-tasks`; non-managers on `/team-tasks` go to the tab)
- Modify: `shavtzak/lib/presentation/screens/admin/admin_choice_screen.dart` (card "משימות", subtitle "משימות הצוות לפי אירוע, קטגוריה ונושא", after "דו יומי")
- Modify: `shavtzak/lib/presentation/screens/user/user_navigation_shell.dart` (4th tab "משימות" when `showTeamTasksTab`; `_kUserTabRoutes` built per member so indexes stay right)
- Test: `shavtzak/test/core/router/team_tasks_routes_test.dart`, `shavtzak/test/presentation/screens/user/user_shell_tasks_tab_test.dart`

- [ ] Step 1 failing tests: `admin card opens /team-tasks`, `tab hidden for a member with no tasks`, `tab shown for an owner and for canManageTasks`, `test prefix routes work`, `topic dialog archives and restores`.
- [ ] Steps 2-5; commit `feat(team-tasks): topics dialog, admin card and member tab`.

### Task 10: Docs, full checks, preview

**Files:**
- Modify: `CLAUDE.md` (collections list: `teamTasks`; routes table; a short "TeamTaskBloc" paragraph; user shell now has up to 4 tabs)

- [ ] Step 1: `cd shavtzak && flutter analyze` → no error or warning; info count equal to `main` (342).
- [ ] Step 2: `flutter test` → all pass (2140 on main + the new ones).
- [ ] Step 3: `flutter build web --release --base-href /Shavtzak/` → succeeds.
- [ ] Step 4: `cd functions && npm run build && npm test` → pass.
- [ ] Step 5: with Omer's ✅ (guard): `firebase deploy --only functions:apiPreview,firestore:rules`; then `PREVIEW_API=1 bash scripts/preview.sh` → preview URL on production data. Check read-only as a non-manager and as a manager (Task 3 step 3).
- [ ] Step 6: commit `docs: CLAUDE.md describes team tasks`; push the branch; send the review with the preview link.
- [ ] After merge (separate approval): `firebase deploy --only functions` (ships `teamTask.*` in `api`), then delete `apiPreview`.
