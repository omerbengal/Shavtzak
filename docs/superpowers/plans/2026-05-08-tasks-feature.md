# משימות Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the new standalone `משימות` feature with admin task management, user task execution, realtime Firestore streams, and backend-only writes.

**Architecture:** Add a new clean-architecture vertical slice: task domain entities, Firestore models, `DatabaseInterface` methods, `TaskRepository`, `TaskBloc`, Cloud Function mutations, Firestore read rules, and dedicated admin/user screens. Reads use Firestore streams; all writes go through the existing `BackendApiService.mutate()` Cloud Functions path.

**Tech Stack:** Flutter Web, Dart, flutter_bloc, Equatable, Firestore streams, Firebase Auth sessions, Cloud Functions TypeScript, Firestore security rules.

---

## Source Spec

Read this first:

- `docs/superpowers/specs/2026-05-08-tasks-feature-design.md`

The spec is authoritative. This plan turns it into implementation steps.

## File Structure

Create:

- `shavtzak/lib/core/constants/task_status.dart`  
  Defines the fixed V1 task statuses and Hebrew display helpers.
- `shavtzak/lib/domain/entities/task.dart`  
  Domain entity for a task, including populated relations and computed flags.
- `shavtzak/lib/domain/entities/task_update.dart`  
  Domain entity for one visible status/note history entry.
- `shavtzak/lib/data/models/task_model.dart`  
  Converts task documents to/from Firestore/backend payload maps.
- `shavtzak/lib/data/models/task_update_model.dart`  
  Converts task update subdocuments to/from Firestore/backend payload maps.
- `shavtzak/lib/data/repositories/task_repository.dart`  
  Streams tasks and task updates, populates relations, and invokes backend mutations.
- `shavtzak/lib/presentation/bloc/task/task_bloc.dart`  
  Task BLoC.
- `shavtzak/lib/presentation/bloc/task/task_event.dart`  
  Task BLoC events.
- `shavtzak/lib/presentation/bloc/task/task_state.dart`  
  Task BLoC states.
- `shavtzak/lib/presentation/screens/task/admin_task_management_screen.dart`  
  Admin task management screen.
- `shavtzak/lib/presentation/screens/task/user_tasks_screen.dart`  
  User task list screen.
- `shavtzak/lib/presentation/screens/task/widgets/task_card.dart`  
  Shared compact task card.
- `shavtzak/lib/presentation/screens/task/widgets/task_detail_sheet.dart`  
  Task detail/update-history bottom sheet.
- `shavtzak/lib/presentation/screens/task/widgets/task_form_sheet.dart`  
  Admin create/edit task sheet.
- `shavtzak/lib/presentation/screens/task/widgets/task_filter_sheet.dart`  
  Admin filter sheet.
- `shavtzak/test/domain/entities/task_test.dart`  
  Entity/computed flag tests.
- `shavtzak/test/data/models/task_model_test.dart`  
  Model serialization tests.
- `shavtzak/test/data/repositories/task_repository_test.dart`  
  Repository validation, sorting, and mutation payload tests.

Modify:

- `shavtzak/lib/data/data_sources/database_interface.dart`  
  Add task read/write method contracts.
- `shavtzak/lib/data/data_sources/firestore_database.dart`  
  Add task collection getters, stream reads, one-shot reads, and backend mutation methods.
- `shavtzak/lib/core/services/environment_aware_factory.dart`  
  Add `createTaskRepository()` and `createTaskBloc()` helpers.
- `shavtzak/lib/core/services/service_locator.dart`  
  Expose `createTaskRepository()` and `createTaskBloc()` helpers.
- `shavtzak/lib/main.dart`  
  Provide `TaskRepository` and `TaskBloc`.
- `shavtzak/lib/core/router/app_router.dart`  
  Add admin and user task routes in production/test shells.
- `shavtzak/lib/presentation/screens/admin/admin_choice_screen.dart`  
  Add the `ניהול משימות` card for full admins.
- `shavtzak/lib/presentation/screens/user/user_navigation_shell.dart`  
  Rename `המשימות שלי` to `השיבוצים`, add `משימות` tab, route branch, and badge.
- `functions/src/index.ts`  
  Add task collections, validators, mutation handlers, and audit details.
- `firestore.rules`  
  Add task and task update read rules with writes denied.

Do not modify the existing checklist feature except where shared app wiring requires another provider/router branch.

## Task 1: Add Task Status And Domain Entities

**Files:**
- Create: `shavtzak/lib/core/constants/task_status.dart`
- Create: `shavtzak/lib/domain/entities/task_update.dart`
- Create: `shavtzak/lib/domain/entities/task.dart`
- Test: `shavtzak/test/domain/entities/task_test.dart`

- [ ] **Step 1: Write entity tests first**

Create `shavtzak/test/domain/entities/task_test.dart` with tests for:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/task_status.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/task.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

void main() {
  group('TaskStatusX', () {
    test('fromKey parses known statuses', () {
      expect(TaskStatusX.fromKey('open'), TaskStatus.open);
      expect(TaskStatusX.fromKey('inProgress'), TaskStatus.inProgress);
      expect(TaskStatusX.fromKey('waiting'), TaskStatus.waiting);
      expect(TaskStatusX.fromKey('blocked'), TaskStatus.blocked);
      expect(TaskStatusX.fromKey('closed'), TaskStatus.closed);
    });

    test('fromKey falls back to open for unknown values', () {
      expect(TaskStatusX.fromKey('bad'), TaskStatus.open);
      expect(TaskStatusX.fromKey(null), TaskStatus.open);
    });

    test('hebrewName returns V1 labels', () {
      expect(TaskStatus.open.hebrewName, 'פתוחה');
      expect(TaskStatus.inProgress.hebrewName, 'בטיפול');
      expect(TaskStatus.waiting.hebrewName, 'ממתינה');
      expect(TaskStatus.blocked.hebrewName, 'חסומה');
      expect(TaskStatus.closed.hebrewName, 'נסגרה');
    });
  });

  group('Task computed flags', () {
    test('isOverdue is false through the end of the deadline day', () {
      final task = _task(
        deadlineDate: DateTime(2026, 5, 8),
        status: TaskStatus.open,
      );

      expect(task.isOverdueAt(DateTime(2026, 5, 8, 23, 59)), isFalse);
      expect(task.isOverdueAt(DateTime(2026, 5, 9)), isTrue);
    });

    test('isOverdue is false for closed tasks', () {
      final task = _task(
        deadlineDate: DateTime(2026, 5, 1),
        status: TaskStatus.closed,
      );

      expect(task.isOverdueAt(DateTime(2026, 5, 9)), isFalse);
    });

    test('hasPastEvent uses populated event end date', () {
      final task = _task(
        event: _event(endDate: DateTime(2026, 5, 1)),
      );

      expect(task.hasPastEventAt(DateTime(2026, 5, 9)), isTrue);
    });

    test('hasInactiveAssignee detects inactive or archived members', () {
      final task = _task(
        assignees: [
          _member(id: 'active', isActive: true, isArchived: false),
          _member(id: 'archived', isActive: true, isArchived: true),
        ],
      );

      expect(task.hasInactiveAssignee, isTrue);
    });
  });
}

Task _task({
  TaskStatus status = TaskStatus.open,
  DateTime? deadlineDate,
  Event? event,
  List<TeamMember> assignees = const [],
}) {
  final now = DateTime(2026, 5, 8, 9);
  return Task(
    id: 'task-1',
    title: 'אישור ספק',
    description: 'לוודא מול הספק',
    eventId: event?.id,
    assigneeIds: assignees.map((member) => member.id).toList(),
    status: status,
    deadlineDate: deadlineDate,
    isArchived: false,
    createdAt: now,
    createdById: 'admin-1',
    updatedAt: now,
    updatedById: 'admin-1',
    latestStatus: status,
    latestUpdatedAt: now,
    latestUpdatedById: 'admin-1',
    latestUpdatedByName: 'מנהל',
    event: event,
    assignees: assignees,
  );
}

Event _event({required DateTime endDate}) {
  return Event(
    id: 'event-1',
    name: 'אירוע',
    startDate: DateTime(2026, 5, 1),
    endDate: endDate,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {},
    createdAt: DateTime(2026, 4, 1),
    updatedAt: DateTime(2026, 4, 1),
  );
}

TeamMember _member({
  required String id,
  required bool isActive,
  required bool isArchived,
}) {
  return TeamMember(
    id: id,
    name: id,
    phoneNumber: '',
    roleCapabilities: const {},
    constraints: const [],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    uniqueKey: 'key-$id',
    isActive: isActive,
    isArchived: isArchived,
  );
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
cd shavtzak
flutter test test/domain/entities/task_test.dart
```

Expected: FAIL because `Task`, `TaskUpdate`, and `TaskStatus` do not exist.

- [ ] **Step 3: Add task status enum**

Create `shavtzak/lib/core/constants/task_status.dart`:

```dart
enum TaskStatus {
  open,
  inProgress,
  waiting,
  blocked,
  closed,
}

extension TaskStatusX on TaskStatus {
  String get key {
    switch (this) {
      case TaskStatus.open:
        return 'open';
      case TaskStatus.inProgress:
        return 'inProgress';
      case TaskStatus.waiting:
        return 'waiting';
      case TaskStatus.blocked:
        return 'blocked';
      case TaskStatus.closed:
        return 'closed';
    }
  }

  String get hebrewName {
    switch (this) {
      case TaskStatus.open:
        return 'פתוחה';
      case TaskStatus.inProgress:
        return 'בטיפול';
      case TaskStatus.waiting:
        return 'ממתינה';
      case TaskStatus.blocked:
        return 'חסומה';
      case TaskStatus.closed:
        return 'נסגרה';
    }
  }

  bool get isClosed => this == TaskStatus.closed;

  static TaskStatus fromKey(String? key) {
    switch (key) {
      case 'open':
        return TaskStatus.open;
      case 'inProgress':
        return TaskStatus.inProgress;
      case 'waiting':
        return TaskStatus.waiting;
      case 'blocked':
        return TaskStatus.blocked;
      case 'closed':
        return TaskStatus.closed;
      default:
        return TaskStatus.open;
    }
  }
}
```

- [ ] **Step 4: Add task update entity**

Create `shavtzak/lib/domain/entities/task_update.dart`:

```dart
import 'package:equatable/equatable.dart';
import '../../core/constants/task_status.dart';

class TaskUpdate extends Equatable {
  final String id;
  final String taskId;
  final TaskStatus status;
  final String? note;
  final DateTime createdAt;
  final String createdById;
  final String createdByName;

  const TaskUpdate({
    required this.id,
    required this.taskId,
    required this.status,
    this.note,
    required this.createdAt,
    required this.createdById,
    required this.createdByName,
  });

  TaskUpdate copyWith({
    String? id,
    String? taskId,
    TaskStatus? status,
    String? note,
    bool clearNote = false,
    DateTime? createdAt,
    String? createdById,
    String? createdByName,
  }) {
    return TaskUpdate(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      status: status ?? this.status,
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt ?? this.createdAt,
      createdById: createdById ?? this.createdById,
      createdByName: createdByName ?? this.createdByName,
    );
  }

  @override
  List<Object?> get props => [
        id,
        taskId,
        status,
        note,
        createdAt,
        createdById,
        createdByName,
      ];
}
```

- [ ] **Step 5: Add task entity**

Create `shavtzak/lib/domain/entities/task.dart` with all fields from the spec. Include `event`, `assignees`, `createdBy`, `closedBy`, `latestUpdatedBy` in `props`, not only IDs. Include methods:

```dart
bool isOverdueAt(DateTime now) {
  if (status == TaskStatus.closed || deadlineDate == null) return false;
  final deadlineEnd = DateTime(
    deadlineDate!.year,
    deadlineDate!.month,
    deadlineDate!.day,
  ).add(const Duration(days: 1));
  return !now.isBefore(deadlineEnd);
}

bool hasPastEventAt(DateTime now) {
  if (event == null) return false;
  return event!.endDate.isBefore(DateTime(now.year, now.month, now.day));
}

bool get hasMissingEvent => eventId != null && event == null;

bool get hasInactiveAssignee {
  return assignees.any((member) => !member.isActive || member.isArchived);
}

bool canBeUpdatedBy(String teamMemberId, bool isAdmin) {
  if (isAdmin) return true;
  return status != TaskStatus.closed && assigneeIds.contains(teamMemberId);
}
```

- [ ] **Step 6: Run entity tests**

Run:

```bash
cd shavtzak
flutter test test/domain/entities/task_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add shavtzak/lib/core/constants/task_status.dart \
  shavtzak/lib/domain/entities/task.dart \
  shavtzak/lib/domain/entities/task_update.dart \
  shavtzak/test/domain/entities/task_test.dart
git commit -m "feat: add task domain entities"
```

## Task 2: Add Task Firestore Models

**Files:**
- Create: `shavtzak/lib/data/models/task_update_model.dart`
- Create: `shavtzak/lib/data/models/task_model.dart`
- Test: `shavtzak/test/data/models/task_model_test.dart`

- [ ] **Step 1: Write model tests**

Create `shavtzak/test/data/models/task_model_test.dart` with tests that verify:

- `TaskModel.fromFirestore()` parses `Timestamp` fields and status keys.
- `TaskModel.toBackendPayload()` serializes dates as ISO-8601 strings for Cloud Functions.
- `TaskUpdateModel.fromFirestore()` sorts through repository later, but parses one update correctly.
- `TaskUpdateModel.toBackendPayload()` trims empty notes to `null`.

Use `fake_cloud_firestore` or `cloud_firestore` `Timestamp` values directly.

- [ ] **Step 2: Run model tests to verify failure**

```bash
cd shavtzak
flutter test test/data/models/task_model_test.dart
```

Expected: FAIL because model files do not exist.

- [ ] **Step 3: Create `TaskUpdateModel`**

Implement:

```dart
static TaskUpdate fromFirestore(DocumentSnapshot doc)
static Map<String, dynamic> toBackendPayload(TaskUpdate update)
static TaskUpdate fromMap(Map<String, dynamic> data, {required String id})
```

Use `TaskStatusX.fromKey(data['status'] as String?)`.

- [ ] **Step 4: Create `TaskModel`**

Implement:

```dart
static Task fromFirestore(
  DocumentSnapshot doc, {
  Event? event,
  required List<TeamMember> assignees,
  TeamMember? createdBy,
  TeamMember? closedBy,
  TeamMember? latestUpdatedBy,
})

static Map<String, dynamic> toBackendPayload(Task task)
```

Serialization rules:

- `eventId` omitted or null when no event.
- `deadlineDate`, `closedAt`, and all date fields serialized as ISO strings in backend payloads.
- `status` and `latestStatus` serialized via `.key`.
- populated objects are never written to backend payloads.

- [ ] **Step 5: Run model tests**

```bash
cd shavtzak
flutter test test/data/models/task_model_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/data/models/task_model.dart \
  shavtzak/lib/data/models/task_update_model.dart \
  shavtzak/test/data/models/task_model_test.dart
git commit -m "feat: add task firestore models"
```

## Task 3: Add Database Interface And Firestore Reads/Mutations

**Files:**
- Modify: `shavtzak/lib/data/data_sources/database_interface.dart`
- Modify: `shavtzak/lib/data/data_sources/firestore_database.dart`
- Test: `shavtzak/test/data/repositories/task_repository_test.dart`

- [ ] **Step 1: Add database interface methods**

Add to `DatabaseInterface`:

```dart
// ========== Tasks ==========
Future<List<Task>> getTasks();
Future<Task?> getTaskById(String id);
Stream<List<Task>> watchTasks();
Stream<List<Task>> watchTasksForAssignee(String teamMemberId);
Stream<Task?> watchTaskById(String taskId);
Stream<List<TaskUpdate>> watchTaskUpdates(String taskId);
Future<void> insertTask(Task task);
Future<void> updateTask(Task task);
Future<void> archiveTask(String taskId);
Future<void> unarchiveTask(String taskId);
Future<void> deleteTask(String taskId);
Future<void> addTaskUpdate({
  required String taskId,
  required TaskStatus status,
  String? note,
});
```

Also import `Task`, `TaskUpdate`, and `TaskStatus`.

- [ ] **Step 2: Add Firestore collection getters**

In `FirestoreDatabase`, add:

```dart
String get _tasksCollection {
  return '${EnvironmentService.instance.collectionPrefix}tasks';
}
```

- [ ] **Step 3: Add relation population helpers**

In `FirestoreDatabase`, add private helpers:

```dart
Future<Task> _populateTaskRelations(DocumentSnapshot doc)
Future<List<Task>> _populateTaskSnapshot(QuerySnapshot snapshot)
```

Implementation reads all events and team members once per snapshot, builds maps, and passes populated objects to `TaskModel.fromFirestore()`.

- [ ] **Step 4: Add Firestore task streams**

Implement:

```dart
@override
Stream<List<Task>> watchTasks() {
  return _firestore
      .collection(_tasksCollection)
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .asyncMap(_populateTaskSnapshot);
}

@override
Stream<List<Task>> watchTasksForAssignee(String teamMemberId) {
  return _firestore
      .collection(_tasksCollection)
      .where('assigneeIds', arrayContains: teamMemberId)
      .where('isArchived', isEqualTo: false)
      .snapshots()
      .asyncMap((snapshot) async {
        final tasks = await _populateTaskSnapshot(snapshot);
        return tasks.where((task) => task.status != TaskStatus.closed).toList();
      });
}
```

If Firestore requires indexes for combined filters later, use a single `arrayContains` query and filter `isArchived/status` client-side for V1 reliability.

- [ ] **Step 5: Add task update stream**

```dart
@override
Stream<List<TaskUpdate>> watchTaskUpdates(String taskId) {
  return _firestore
      .collection(_tasksCollection)
      .doc(taskId)
      .collection('updates')
      .orderBy('createdAt')
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map(TaskUpdateModel.fromFirestore).toList();
      });
}
```

- [ ] **Step 6: Add backend mutation wrappers**

Implement write methods using `_invokeMutation()`:

```dart
await _invokeMutation('task.create', payload: {'task': TaskModel.toBackendPayload(task)});
await _invokeMutation('task.update', payload: {'task': TaskModel.toBackendPayload(task)});
await _invokeMutation('task.archive', payload: {'taskId': taskId});
await _invokeMutation('task.unarchive', payload: {'taskId': taskId});
await _invokeMutation('task.delete', payload: {'taskId': taskId});
await _invokeMutation('task.addUpdate', payload: {
  'taskId': taskId,
  'status': status.key,
  'note': note,
});
```

- [ ] **Step 7: Run analyze**

```bash
cd shavtzak
flutter analyze
```

Expected: PASS. If the repository already has unrelated warnings, document them in the task notes and fix every new task-related error.

- [ ] **Step 8: Commit**

```bash
git add shavtzak/lib/data/data_sources/database_interface.dart \
  shavtzak/lib/data/data_sources/firestore_database.dart
git commit -m "feat: add task database access"
```

## Task 4: Add Task Repository

**Files:**
- Create: `shavtzak/lib/data/repositories/task_repository.dart`
- Test: `shavtzak/test/data/repositories/task_repository_test.dart`

- [ ] **Step 1: Write repository tests**

Cover:

- `watchUserOpenTasks()` excludes archived and closed tasks.
- user tasks sort by overdue, nearest deadline, latest update.
- `createTask()` rejects empty assignee list before backend call.
- `addTaskUpdate()` trims blank notes to `null`.

- [ ] **Step 2: Run repository tests to verify failure**

```bash
cd shavtzak
flutter test test/data/repositories/task_repository_test.dart
```

Expected: FAIL because `TaskRepository` does not exist.

- [ ] **Step 3: Implement repository**

Create methods:

```dart
Stream<List<Task>> watchAdminTasks()
Stream<List<Task>> watchUserOpenTasks(String teamMemberId)
Stream<Task?> watchTaskById(String taskId)
Stream<List<TaskUpdate>> watchTaskUpdates(String taskId)
Future<void> createTask(Task task)
Future<void> updateTask(Task task)
Future<void> archiveTask(String taskId)
Future<void> unarchiveTask(String taskId)
Future<void> deleteTask(String taskId)
Future<void> addTaskUpdate({required String taskId, required TaskStatus status, String? note})
```

Keep sorting in repository helper functions so admin/user screens stay thin.

- [ ] **Step 4: Run repository tests**

```bash
cd shavtzak
flutter test test/data/repositories/task_repository_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/data/repositories/task_repository.dart \
  shavtzak/test/data/repositories/task_repository_test.dart
git commit -m "feat: add task repository"
```

## Task 5: Add Cloud Function Task Mutations And Rules

**Files:**
- Modify: `functions/src/index.ts`
- Modify: `firestore.rules`

- [ ] **Step 1: Extend `Collections`**

Add `tasks: string` to the `Collections` type and to `getCollections()`:

```ts
tasks: `${prefix}tasks`,
```

Also include `collections.tasks` in the `utility.clearAllData` test-mode cleanup list.

- [ ] **Step 2: Add task validators/helpers**

Near `checklistItemDocFromJson`, add:

```ts
const TASK_STATUSES = new Set(['open', 'inProgress', 'waiting', 'blocked', 'closed']);

function requireTaskStatus(value: unknown, fieldName: string): string {
  const status = requireString(value, fieldName);
  if (!TASK_STATUSES.has(status)) {
    throw new HttpError(400, `Invalid ${fieldName}`);
  }
  return status;
}

function taskDocFromJson(task: Record<string, unknown>): Record<string, unknown> {
  const assigneeIds = Array.isArray(task['assigneeIds'])
    ? task['assigneeIds'].map(String).filter((id) => id.trim().length > 0)
    : [];
  if (assigneeIds.length === 0) throw new HttpError(400, 'Task must have assignees');
  const status = requireTaskStatus(task['status'], 'task.status');
  return stripUndefined({
    title: requireString(task['title'], 'task.title'),
    description: requireString(task['description'], 'task.description'),
    eventId: optionalString(task['eventId']),
    assigneeIds,
    status,
    deadlineDate: task['deadlineDate'] == null ? null : toTimestamp(task['deadlineDate'], 'task.deadlineDate'),
    isArchived: task['isArchived'] === true,
    createdAt: toTimestamp(task['createdAt'], 'task.createdAt'),
    createdById: requireString(task['createdById'], 'task.createdById'),
    updatedAt: toTimestamp(task['updatedAt'], 'task.updatedAt'),
    updatedById: requireString(task['updatedById'], 'task.updatedById'),
    closedAt: task['closedAt'] == null ? null : toTimestamp(task['closedAt'], 'task.closedAt'),
    closedById: optionalString(task['closedById']),
    latestStatus: requireTaskStatus(task['latestStatus'], 'task.latestStatus'),
    latestUpdateText: optionalString(task['latestUpdateText']),
    latestUpdatedAt: toTimestamp(task['latestUpdatedAt'], 'task.latestUpdatedAt'),
    latestUpdatedById: requireString(task['latestUpdatedById'], 'task.latestUpdatedById'),
    latestUpdatedByName: requireString(task['latestUpdatedByName'], 'task.latestUpdatedByName'),
  });
}
```

- [ ] **Step 3: Add active-assignee validation**

Add `assertActiveAssignees(db, collections, assigneeIds)` that reads each `teamMembers` document and verifies `isActive == true` and `isArchived != true`. Use it in `task.create` for all assignees and in `task.update` for every assignee ID added compared with the existing document.

- [ ] **Step 4: Add mutation cases**

Add these exact cases to the `mutate` switch:

- `task.create`: admin only, validate active assignees, create task doc, create initial `updates` doc, write audit.
- `task.update`: admin only, update editable fields, preserve user-facing history, write audit.
- `task.archive`: admin only, set `isArchived: true`, write audit.
- `task.unarchive`: admin only, set `isArchived: false`, write audit.
- `task.delete`: admin only, recursively delete `updates` subcollection, delete task doc, write minimal audit metadata.
- `task.addUpdate`: admin or assigned non-closed user, write update doc, update status/latest fields, set/clear `closedAt` and `closedById`, write audit.

Use `db.runTransaction()` for `task.addUpdate` so the task doc and update doc are consistent.

- [ ] **Step 5: Add Firestore rules**

Add to `firestore.rules`:

```rules
match /tasks/{taskId} {
  allow read: if isAuthorizedProdUser();
  allow write: if false;

  match /updates/{updateId} {
    allow read: if isAuthorizedProdUser();
    allow write: if false;
  }
}

match /test_tasks/{taskId} {
  allow read: if isAuthorizedTestUser();
  allow write: if false;

  match /updates/{updateId} {
    allow read: if isAuthorizedTestUser();
    allow write: if false;
  }
}
```

Client-side visibility is further restricted by queries and backend auth. Firestore rules remain collection-level readable for authorized users, matching existing app collection rules.

- [ ] **Step 6: Build functions**

```bash
cd functions
npm run build
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add functions/src/index.ts firestore.rules
git commit -m "feat: add task backend mutations"
```

## Task 6: Add TaskBloc

**Files:**
- Create: `shavtzak/lib/presentation/bloc/task/task_bloc.dart`
- Create: `shavtzak/lib/presentation/bloc/task/task_event.dart`
- Create: `shavtzak/lib/presentation/bloc/task/task_state.dart`

- [ ] **Step 1: Add task events**

Events:

- `LoadAdminTasks`
- `LoadUserTasks(teamMemberId)`
- `LoadTaskDetail(taskId)`
- `CreateTask(task, completion)`
- `UpdateTask(task, completion)`
- `ArchiveTask(taskId, completion)`
- `UnarchiveTask(taskId, completion)`
- `DeleteTask(taskId, completion)`
- `AddTaskUpdate(taskId, status, note, completion)`
- `ClearTaskActionState`

Event props must include full `Task` objects where present.

- [ ] **Step 2: Add task states**

States:

- `TaskInitial`
- `TaskLoading`
- `TasksLoaded(tasks)`
- `UserTasksLoaded(tasks)`
- `TaskDetailLoaded(task, updates)`
- `TaskOperationSuccess(message)`
- `TaskError(message)`

State props must include full `Task` and `TaskUpdate` objects, not only IDs.

- [ ] **Step 3: Implement bloc stream handlers**

Use `emit.forEach`:

```dart
await emit.forEach<List<Task>>(
  _repository.watchAdminTasks(),
  onData: (tasks) => TasksLoaded(tasks),
  onError: (error, stackTrace) => TaskError('שגיאה בטעינת משימות: $error'),
);
```

For detail, use `Rx.combineLatest2` from existing `rxdart` dependency to combine task and updates streams.

- [ ] **Step 4: Implement mutation handlers**

Follow existing `CrudActionCompleter` pattern. Do not emit a full-screen loading state for short writes; complete the action and rely on streams.

- [ ] **Step 5: Run analyze**

```bash
cd shavtzak
flutter analyze
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/bloc/task
git commit -m "feat: add task bloc"
```

## Task 7: Wire Repository, Bloc, And Routes

**Files:**
- Modify: `shavtzak/lib/main.dart`
- Modify: `shavtzak/lib/core/services/environment_aware_factory.dart`
- Modify: `shavtzak/lib/core/services/service_locator.dart`
- Modify: `shavtzak/lib/core/router/app_router.dart`
- Modify: `shavtzak/lib/presentation/screens/admin/admin_choice_screen.dart`
- Modify: `shavtzak/lib/presentation/screens/user/user_navigation_shell.dart`

- [ ] **Step 1: Add providers**

In `main.dart`, create and provide `TaskRepository`, then add `BlocProvider<TaskBloc>`.

- [ ] **Step 2: Add routes**

Production:

- `/admin/tasks`
- `/user/tasks`

Test:

- `/test/admin/tasks`
- `/test/user/tasks`

Admin route should be full-admin protected by the existing admin route shell or a new standalone admin route if the choice card should navigate outside the swipeable management shell.

- [ ] **Step 3: Add admin choice card**

In `AdminChoiceScreen`, add a full-admin-only card:

```dart
_buildChoiceCard(
  width: cardWidth,
  icon: Icons.task_alt,
  iconColor: Colors.teal,
  title: 'ניהול משימות',
  subtitle: 'יצירה ומעקב אחרי משימות צוות',
  isCompact: isCompact,
  onTap: () => context.go('$envPrefix/admin/tasks'),
)
```

- [ ] **Step 4: Update user bottom navigation**

Rename existing first label to `השיבוצים`. Add a fourth branch item:

```dart
const BottomNavigationBarItem(
  icon: Icon(Icons.task_alt_outlined),
  activeIcon: Icon(Icons.task_alt),
  label: 'משימות',
)
```

Use a `BlocSelector<TaskBloc, TaskState, int>` or a lightweight badge widget to show open task count after user tasks load.

- [ ] **Step 5: Run analyze**

```bash
cd shavtzak
flutter analyze
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/main.dart \
  shavtzak/lib/core/services/environment_aware_factory.dart \
  shavtzak/lib/core/services/service_locator.dart \
  shavtzak/lib/core/router/app_router.dart \
  shavtzak/lib/presentation/screens/admin/admin_choice_screen.dart \
  shavtzak/lib/presentation/screens/user/user_navigation_shell.dart
git commit -m "feat: wire task feature navigation"
```

## Task 8: Build Admin Task Management UI

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/admin_task_management_screen.dart`
- Create: `shavtzak/lib/presentation/screens/task/widgets/task_card.dart`
- Create: `shavtzak/lib/presentation/screens/task/widgets/task_filter_sheet.dart`
- Create: `shavtzak/lib/presentation/screens/task/widgets/task_form_sheet.dart`

- [ ] **Step 1: Build shared task card**

Card must show title, status chip, event/`ללא אירוע`, deadline, assignees, latest update, and warning rows. Use Material icons, not emoji. Use text plus icon for warnings.

- [ ] **Step 2: Build admin screen scaffold**

Use RTL `Scaffold`, app bar title `ניהול משימות`, search field, filter button, list grouped by event, and orange FAB/button for create.

- [ ] **Step 3: Add grouping**

Group by `task.eventId ?? '__no_event__'`. Label missing events as `אירוע נמחק`, no-event group as `ללא אירוע`, and past events with visible marker `אירוע עבר`.

- [ ] **Step 4: Add filters**

Filter state:

```dart
String _searchQuery = '';
TaskStatus? _statusFilter;
String? _assigneeIdFilter;
bool? _eventLinkedFilter;
_DeadlineFilter _deadlineFilter = _DeadlineFilter.all;
bool _showClosed = false;
bool _showArchived = false;
```

- [ ] **Step 5: Add create/edit sheet**

Required fields: title, description, assignees. Optional: event, deadline. Validate before dispatching `CreateTask`/`UpdateTask`.

- [ ] **Step 6: Add archive/delete confirmations**

Archive: standard confirmation. Delete: strong confirmation with title in dialog and clear permanent deletion warning.

- [ ] **Step 7: Run analyze**

```bash
cd shavtzak
flutter analyze
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add shavtzak/lib/presentation/screens/task/admin_task_management_screen.dart \
  shavtzak/lib/presentation/screens/task/widgets/task_card.dart \
  shavtzak/lib/presentation/screens/task/widgets/task_filter_sheet.dart \
  shavtzak/lib/presentation/screens/task/widgets/task_form_sheet.dart
git commit -m "feat: add admin task management UI"
```

## Task 9: Build User Task List And Detail Sheet

**Files:**
- Create: `shavtzak/lib/presentation/screens/task/user_tasks_screen.dart`
- Create: `shavtzak/lib/presentation/screens/task/widgets/task_detail_sheet.dart`
- Modify: `shavtzak/lib/presentation/screens/task/widgets/task_card.dart`

- [ ] **Step 1: Build user task screen**

On init and on authenticated user changes, dispatch `LoadUserTasks(currentUser.id)`. Show empty state text when there are no open tasks.

- [ ] **Step 2: Build detail sheet**

Show title, description, event details, assignees, deadline, current status, latest update, and full update history. Use a status dropdown/segmented list and optional note field for updates.

- [ ] **Step 3: Enforce user update affordance**

Only show update controls when:

```dart
task.canBeUpdatedBy(currentUser.id, currentUser.isAdmin)
```

Backend remains the source of truth for enforcement.

- [ ] **Step 4: Add event details action**

Clicking the event name opens a read-only detail card for regular users. Admins get an edit icon/action; implement it by opening the existing `EventFormModal` when `EventBloc` and the populated `Event` are available in the task detail context.

- [ ] **Step 5: Run analyze**

```bash
cd shavtzak
flutter analyze
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/screens/task/user_tasks_screen.dart \
  shavtzak/lib/presentation/screens/task/widgets/task_detail_sheet.dart \
  shavtzak/lib/presentation/screens/task/widgets/task_card.dart
git commit -m "feat: add user task experience"
```

## Task 10: End-To-End Verification, Deployment, And Cleanup

**Files:**
- No planned file changes. If verification exposes defects, patch only the task feature files introduced or modified in Tasks 1-9.

- [ ] **Step 1: Run Flutter tests**

```bash
cd shavtzak
flutter test test/domain/entities/task_test.dart \
  test/data/models/task_model_test.dart \
  test/data/repositories/task_repository_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run Flutter analyze**

```bash
cd shavtzak
flutter analyze
```

Expected: PASS.

- [ ] **Step 3: Build functions**

```bash
cd functions
npm run build
```

Expected: PASS.

- [ ] **Step 4: Verify backend-only writes manually**

In test mode:

1. Create a task as admin through UI.
2. Confirm document appears under `test_tasks`.
3. Confirm update appears under `test_tasks/{taskId}/updates`.
4. Try regular-user forbidden actions from UI and confirm backend rejects them.
5. Confirm direct Firestore client writes are denied by rules.

- [ ] **Step 5: Verify realtime manually**

Use two browser sessions in `/test`:

1. Admin creates a task assigned to user A.
2. User A sees it appear without refresh.
3. User A updates status.
4. Admin sees latest status/update without refresh.
5. Admin closes task.
6. User A sees it disappear from open list without refresh.

- [ ] **Step 6: Verify environment isolation**

Confirm production routes read `tasks` and test routes read `test_tasks`. No test task appears in production.

- [ ] **Step 7: Deploy functions and rules**

Because this feature modifies `functions/` and `firestore.rules`, deploy before finishing implementation:

```bash
firebase deploy --only functions,firestore:rules
```

Expected: deploy succeeds.

- [ ] **Step 8: Final commit**

```bash
git status --short
git add .
git commit -m "feat: add tasks feature"
```

Before this commit, inspect `git status --short` and do not stage unrelated user changes.

## Self-Review Checklist

- Spec coverage: foundation, data model, backend writes, realtime streams, admin UX, user UX, archive/delete, audit, and deployment are covered.
- No product scope gaps remain from the spec.
- The plan keeps checklist separate.
- The plan preserves backend-only writes.
- The plan requires realtime manual verification.
- The plan requires `flutter analyze`.
- The plan requires Cloud Functions/rules deployment after `functions/` changes.
