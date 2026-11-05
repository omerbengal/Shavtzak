# דו יומי editing screen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A managers-only "עריכה" screen per דו יומי event: soft stage cards showing every stage and task detail, each value edited in place and saved immediately; laptop table + phone cards.

**Architecture:** A new route `<eventRoute>/edit` renders `EventEditScreen` from the live `TaskBloc` `TasksLoaded`, with a screen-local "last sent" overlay so quick successive edits build on each other. One generic `EditableValue<T>` host renders a display, and on click edits in place (wide) or in a bottom sheet (narrow), calling an `onCommit` that dispatches `UpdateTask`/`UpdateStage`. Backend: `task.update` may change `stageId` (done, commit c884368).

**Tech Stack:** Flutter web, flutter_bloc, go_router, Cloud Functions (TypeScript).

**Spec:** `docs/superpowers/specs/2026-11-05-du-yomi-edit-screen-design.md`

## Global Constraints

- Hebrew UI, RTL (`Directionality(textDirection: TextDirection.rtl)`), Rubik (app theme).
- Every size and colour of the new screen lives in `task_style.dart` (new `// ---- editing screen ----` section).
- Wide layout when window width ≥ `TaskStyle.wideBreakpoint` (1000). Content max width 1280, centred.
- Managers only: `canManageTasks(user)`.
- Mutations only via `TaskBloc` events with a `CrudActionCompleter` (`TaskScreenActions.sendTaskEvent`).
- No progress UI anywhere on this screen (no ticks, bars, counts, late/soon colours).
- `flutter analyze`: zero new issues. Run Flutter commands from `shavtzak/`.

## Review Focus

1. Two edits to the same task within a second (e.g. title then description) — the second must not revert the first. (Task 1 test `overlay keeps the newer sent version as the base`.)
2. A save the backend refuses (e.g. empty assignee list, network) — the value shown returns to the stored one and a red snackbar shows. (Task 1 test `failed entry is dropped`; Task 4 widget test.)
3. Opening the time field's clock dialog / the day drop-down while editing inline must not count as "click outside → save". (Task 2: ignore tap-outside while `ModalRoute.of(context)?.isCurrent == false`; test `tap outside saves`.)
4. A non-manager opening `/du-yomi/<id>/edit` by URL sees "אין הרשאה", not the editors. (Task 4 test.)
5. Clearing a stage's start time while it has an end time → refused with "שעת סיום דורשת שעת התחלה." (Task 3 `validateStageTimes` test.)

---

### Task 1: Edit overlay (pure)

**Files:** Create `shavtzak/lib/core/utils/task_edit_overlay.dart`; Test `shavtzak/test/core/utils/task_edit_overlay_test.dart`

**Produces:**
- `bool sameTaskEdit(TaskItem a, TaskItem b)` — equal on stageId, title, description, assemblyTime, assigneeIds, subtask (id,title) list.
- `bool sameStageEdit(Stage a, Stage b)` — equal on title, date, startTime, endTime, requirements, hotelLocation, notes, contacts.
- `class EditOverlay<T>` with `T resolve(String id, T live)`, `void sent(String id, T value)`, `void failed(String id)`, `void reconcile(Map<String,T> liveById)` (drops entries whose live version matches via injected `bool Function(T,T) same`), `bool get isEmpty`.

- [ ] Tests: `resolve returns live when nothing sent`; `overlay keeps the newer sent version as the base` (sent A then B → resolve = B); `reconcile drops a matching entry`; `reconcile keeps a non-matching entry`; `failed entry is dropped`.
- [ ] Implement; run `flutter test test/core/utils/task_edit_overlay_test.dart` → PASS; commit.

### Task 2: `EditableValue<T>` host + editors

**Files:** Create `shavtzak/lib/presentation/screens/task/edit/editable_value.dart`, `.../edit/value_editors.dart`; Test `shavtzak/test/presentation/screens/task/edit/editable_value_test.dart`

**Produces:**
- `EditableValue<T>({required T value, required Widget display, required String sheetTitle, required bool wide, required EditorBuilder<T> editor, required Future<String?> Function(T) onCommit, String? Function(T)? validate, Key? key})`; `typedef EditorBuilder<T> = Widget Function(BuildContext, T draft, ValueChanged<T> onChanged, VoidCallback onSubmit)`. `onCommit` returns an error message or null. Unchanged draft → no commit. Wide: hover tint + ✎, click → editor in place; Enter (via `onSubmit`) / tap outside saves, Esc cancels. Narrow: tap → modal bottom sheet with the editor and "שמירה"/"ביטול".
- Editors (stateless/stateful widgets matching `EditorBuilder` shape): `TextValueEditor(multiline: bool)`, `TimeValueEditor` (wraps `EventTimeField`, value `String` '' = none), `StageTimesEditor` (value `({String start, String end})`), `DayValueEditor(days: List<DateTime>)` (selecting submits), `AssigneesEditor(offered: List<TeamMember>)` (value `List<String>` ids), `SubtasksEditor` (value `List<Subtask>`; Enter adds line after current, Backspace on empty removes, ✕ removes, reorder via `ReorderableListView`), `ContactsEditor` (value `List<StageContact>`).
- [ ] Widget tests: `click turns the value into an editor (wide)`; `Enter commits the typed text`; `Esc cancels without commit`; `tap outside saves`; `unchanged value does not commit`; `validate error keeps the editor open`; `narrow tap opens a sheet and שמירה commits`.
- [ ] Implement; tests PASS; commit.

### Task 3: Screen pieces (stage card heading, task row, task card)

**Files:** Create `.../edit/stage_edit_card.dart`, `.../edit/task_edit_row.dart` (wide), `.../edit/task_edit_card.dart` (narrow), `.../edit/edit_rules.dart` (pure: `String? validateStageTimes(String start, String end)`, `String? validateContacts(List<StageContact>)`, `List<TeamMember> assigneeFilterMembers(EventTaskBoard, List<TeamMember> eventAssignees)`, `Color avatarColor(String memberId)` in task_style); Modify `task_style.dart`.
- Stage card: blue right edge, heading line (title · day · times · ⋯/🗑 "מחיקת השלב"), grid מיקום/הערות/דרישות/אנשי קשר — narrow folds דרישות+אנשי קשר under "▾ עוד פרטים". Wide body: header row + `TaskEditRow`s; narrow: `TaskEditCard`s. "+ משימה" at bottom. Card is a `DragTarget<TaskItem>` (wide) that highlights while a task of another stage hovers.
- Row: `⋮⋮` (`Draggable<TaskItem>`, wide) | time | title | description | assignees (initial circles + first names) | subtasks list | ⋯ menu ("העברה לשלב אחר…", "מחיקה").
- Callbacks out (owned by the screen): `onTaskCommit(TaskItem next) → Future<String?>`, `onStageCommit(Stage next) → Future<String?>`, `onMoveTask(TaskItem, Stage)`, `onDeleteTask`, `onDeleteStage`, `onAddTask(Stage)`.
- [ ] Tests (`edit_rules_test.dart`): `validateStageTimes` (end without start → 'שעת סיום דורשת שעת התחלה.'; end ≤ start → 'שעת הסיום חייבת להיות אחרי שעת ההתחלה.'; bad format; valid); `validateContacts` (name missing → 'לכל איש קשר נדרש שם.'); `assigneeFilterMembers` includes a removed member still on a task.
- [ ] Implement; tests PASS; commit.

### Task 4: `EventEditScreen`, route, entry button

**Files:** Create `.../edit/event_edit_screen.dart`; Modify `core/router/app_router.dart` (`_tasksRoute`: child `GoRoute(path: 'edit')` under `:eventId`), `tasks_place.dart` (`String editRoute(String eventId)`), `event_tasks_screen.dart` (an "עריכה" `TextButton.icon` with `Key('tasks-edit')` beside the "אקסל" menu, managers only); Test `shavtzak/test/presentation/screens/task/edit/event_edit_screen_test.dart`.
- Screen: `with TaskScreenActions`; `LoadTasks` on init; subscribes `watchEventAssignees`; overlays from Task 1 applied before `eventTaskBoard`; toolbar (search, assignee filter, "⬇ אקסל" → `downloadExport`, "+ שלב חדש" → `createStage`); "+ משימה" → `createTask(event, stage, user)`; delete → `deleteTask`/`deleteStage`; move → overlay + `UpdateTask(task.copyWith(stageId:))`; drag uses the same path. After a commit, the edited item is scrolled into view (`Scrollable.ensureVisible` on its `GlobalKey`) and tinted for 2 s. Commit failure → overlay `failed` + red snackbar.
- [ ] Widget tests: `manager sees every stage and task detail`; `non-manager sees אין הרשאה`; `editing a title dispatches UpdateTask with the new title`; `narrow window shows task cards`; `the event screen shows עריכה to managers only`.
- [ ] Implement; run full `flutter test` + `flutter analyze` (zero new); commit.

### Task 5: Docs + verify

- [ ] CLAUDE.md: route list + TaskBloc paragraph mention the editing screen and the stage move.
- [ ] `cd functions && npm test` PASS, `cd shavtzak && flutter test` PASS, analyze clean; commit.
