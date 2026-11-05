import 'package:equatable/equatable.dart';

import '../../../domain/entities/imported_stage.dart';
import '../../../domain/entities/stage.dart';
import '../../../domain/entities/stage_sync_plan.dart';
import '../../../domain/entities/subtask.dart';
import '../../../domain/entities/task_item.dart';
import '../task_progress.dart';
import '../task_utils.dart';
import 'cell_values.dart';
import 'task_import_parser.dart';
import 'task_import_template.dart';

/// The difference between an event's stages and tasks and an updated import
/// file, and the writes that bring the event in line with the file.
///
/// Matching, all on text with spaces trimmed and joined:
/// - a stage by its name, the way the export writes it (a repeated title
///   gets " (2)"), see [exportStageNames];
/// - a task by its title, first under its matched stage, then under any
///   other stage, which makes it a move;
/// - a subtask by its title within its task.
///
/// A matched task keeps its id, so it keeps its completion and the assignees'
/// note, and a matched subtask keeps its id and so its tick. A renamed task
/// cannot be told from a new one: it is removed and added. Repeated titles
/// pair up in order.

enum ChangeKind { added, removed, changed, unchanged }

/// One field that differs, as text for the preview. An empty side is "".
class FieldChange extends Equatable {
  const FieldChange(this.label, this.before, this.after);

  final String label;
  final String before;
  final String after;

  @override
  List<Object?> get props => [label, before, after];
}

/// What happens to one task. [before] is the task in the event, [after] the
/// task as it will be saved; one of them is null for an added or a removed
/// task.
class TaskChange extends Equatable {
  const TaskChange({
    required this.kind,
    this.before,
    this.after,
    this.fields = const [],
    this.movedFrom,
    this.addedSubtasks = const [],
    this.removedSubtasks = const [],
  });

  final ChangeKind kind;
  final TaskItem? before;
  final TaskItem? after;
  final List<FieldChange> fields;

  /// The stage the task moves away from, by its title.
  final String? movedFrom;
  final List<String> addedSubtasks;
  final List<Subtask> removedSubtasks;

  String get title => (after ?? before)!.title;

  /// The progress a removal or a change throws away, as text; empty when
  /// nothing is lost.
  List<String> get lostProgress {
    final task = before;
    if (task == null) return const [];
    if (kind == ChangeKind.removed) {
      return [
        if (task.isComplete) 'המשימה סומנה כבוצעה',
        if (!task.isComplete && task.doneSubtaskCount > 0)
          'סומנו ${task.doneSubtaskCount} מתוך ${task.subtasks.length} תתי משימות',
        if ((task.assigneeUpdate ?? '').trim().isNotEmpty)
          'יש עדכון מהאחראים',
      ];
    }
    final ticked = removedSubtasks.where((subtask) => subtask.isDone).toList();
    return [
      for (final subtask in ticked) 'תת המשימה "${subtask.title}" סומנה',
    ];
  }

  @override
  List<Object?> get props =>
      [kind, before, after, fields, movedFrom, addedSubtasks, removedSubtasks];
}

/// What happens to one stage, with the changes to the tasks shown under it.
class StageChange extends Equatable {
  const StageChange({
    required this.kind,
    this.before,
    this.after,
    this.fields = const [],
    this.tasks = const [],
  });

  final ChangeKind kind;
  final Stage? before;
  final Stage? after;
  final List<FieldChange> fields;
  final List<TaskChange> tasks;

  Stage get stage => (after ?? before)!;

  /// Whether the stage or any of its tasks changes.
  bool get hasChanges =>
      kind != ChangeKind.unchanged ||
      tasks.any((task) => task.kind != ChangeKind.unchanged);

  @override
  List<Object?> get props => [kind, before, after, fields, tasks];
}

class TaskImportDiff extends Equatable {
  const TaskImportDiff({required this.stages, required this.plan});

  /// In screen order of the result, then the removed stages.
  final List<StageChange> stages;
  final StageSyncPlan plan;

  bool get hasChanges => !plan.isEmpty;

  Iterable<TaskChange> get _tasks => stages.expand((stage) => stage.tasks);

  int stageCount(ChangeKind kind) =>
      stages.where((stage) => stage.kind == kind).length;

  int taskCount(ChangeKind kind) =>
      _tasks.where((task) => task.kind == kind && task.movedFrom == null).length;

  int get movedTaskCount => _tasks.where((task) => task.movedFrom != null).length;

  /// Changes that throw away progress someone made.
  int get lostProgressCount =>
      _tasks.where((task) => task.lostProgress.isNotEmpty).length;

  @override
  List<Object?> get props => [stages, plan];
}

String _key(String text) => cleanText(text).replaceAll(RegExp(r'\s+'), ' ').trim();

/// Pairs up items by key, in order: each [take] hands out the next unused
/// item with that key.
class _Pool<T> {
  _Pool(Iterable<T> items, String Function(T) keyOf) {
    for (final item in items) {
      _byKey.putIfAbsent(keyOf(item), () => []).add(item);
    }
  }

  final Map<String, List<T>> _byKey = {};
  final Set<T> taken = Set.identity();

  T? take(String key, {bool Function(T)? where}) {
    for (final item in _byKey[key] ?? <T>[]) {
      if (taken.contains(item)) continue;
      if (where != null && !where(item)) continue;
      taken.add(item);
      return item;
    }
    return null;
  }
}

TaskImportDiff diffTaskImport(
  EventTaskBoard board,
  List<ImportedStage> imported,
) {
  final names = exportStageNames(board.stages);
  final stagePool = _Pool<Stage>(board.stages, (stage) => names[stage.id]!);

  // Imported stage id -> the existing stage it updates, if any.
  final matchedStage = <String, Stage>{};
  for (final entry in imported) {
    final existing = stagePool.take(_key(entry.stage.title));
    if (existing != null) matchedStage[entry.stage.id] = existing;
  }

  // Stage id to save under, for each imported stage.
  String savedStageId(Stage importedStage) =>
      matchedStage[importedStage.id]?.id ?? importedStage.id;

  // Tasks: first under the matched stage, then anywhere.
  final taskPool = _Pool<TaskItem>(board.tasks, (task) => _key(task.title));
  final matchedTask = <String, TaskItem>{};
  for (final entry in imported) {
    final stageId = matchedStage[entry.stage.id]?.id;
    if (stageId == null) continue;
    for (final task in entry.tasks) {
      final existing =
          taskPool.take(_key(task.title), where: (t) => t.stageId == stageId);
      if (existing != null) matchedTask[task.id] = existing;
    }
  }
  for (final entry in imported) {
    for (final task in entry.tasks) {
      if (matchedTask.containsKey(task.id)) continue;
      final existing = taskPool.take(_key(task.title));
      if (existing != null) matchedTask[task.id] = existing;
    }
  }

  final stagesToCreate = <Stage>[];
  final stagesToUpdate = <Stage>[];
  final tasksToCreate = <TaskItem>[];
  final tasksToUpdate = <TaskItem>[];
  final changes = <StageChange>[];
  final changeOfSavedStage = <String, _StageChangeDraft>{};

  for (final entry in imported) {
    final existing = matchedStage[entry.stage.id];
    final _StageChangeDraft draft;
    if (existing == null) {
      stagesToCreate.add(entry.stage);
      draft = _StageChangeDraft(ChangeKind.added, null, entry.stage, const []);
    } else {
      final next = _updatedStage(existing, entry.stage, names[existing.id]!);
      final fields = _stageFields(existing, next);
      if (fields.isNotEmpty) stagesToUpdate.add(next);
      draft = _StageChangeDraft(
        fields.isEmpty ? ChangeKind.unchanged : ChangeKind.changed,
        existing,
        fields.isEmpty ? existing : next,
        fields,
      );
    }
    changeOfSavedStage[savedStageId(entry.stage)] = draft;

    final savedStage = draft.after!;
    for (final task in entry.tasks) {
      final before = matchedTask[task.id];
      if (before == null) {
        final created = task.copyWith(stageId: savedStage.id, stage: savedStage);
        tasksToCreate.add(created);
        draft.tasks.add(TaskChange(kind: ChangeKind.added, after: created));
        continue;
      }
      final merge = _mergeSubtasks(before.subtasks, task.subtasks);
      final after = TaskItem(
        id: before.id,
        eventId: before.eventId,
        stageId: savedStage.id,
        // Matched by title, so only spacing can differ: keep the stored one.
        title: before.title,
        description: task.description,
        subtasks: merge.subtasks,
        assemblyTime: task.assemblyTime,
        assigneeIds: task.assigneeIds,
        assigneeUpdate: before.assigneeUpdate,
        assigneeUpdateAt: before.assigneeUpdateAt,
        assigneeUpdateById: before.assigneeUpdateById,
        assigneeUpdateByName: before.assigneeUpdateByName,
        isComplete: before.isComplete,
        completedAt: before.completedAt,
        completedById: before.completedById,
        createdAt: before.createdAt,
        createdById: before.createdById,
        updatedAt: before.updatedAt,
        event: before.event,
        stage: savedStage,
        assignees: task.assignees,
      );
      final moved = before.stageId != savedStage.id;
      final fields = _taskFields(before, after, merge);
      final changed = moved || fields.isNotEmpty;
      if (changed) tasksToUpdate.add(after);
      draft.tasks.add(TaskChange(
        kind: changed ? ChangeKind.changed : ChangeKind.unchanged,
        before: before,
        after: after,
        fields: fields,
        movedFrom: moved ? board.stageById(before.stageId)?.title : null,
        addedSubtasks: merge.added,
        removedSubtasks: merge.removed,
      ));
    }
  }

  // What the file no longer has.
  final stageIdsToDelete = <String>[];
  final removedStages = <_StageChangeDraft>[];
  for (final stage in board.stages) {
    if (stagePool.taken.contains(stage)) continue;
    stageIdsToDelete.add(stage.id);
    final draft = _StageChangeDraft(ChangeKind.removed, stage, null, const []);
    changeOfSavedStage[stage.id] = draft;
    removedStages.add(draft);
  }
  final taskIdsToDelete = <String>[];
  for (final task in board.tasks) {
    if (taskPool.taken.contains(task)) continue;
    taskIdsToDelete.add(task.id);
    changeOfSavedStage[task.stageId]
        ?.tasks
        .add(TaskChange(kind: ChangeKind.removed, before: task));
  }

  final kept = [
    for (final entry in imported) changeOfSavedStage[savedStageId(entry.stage)]!,
  ];
  final keptOrder = sortStages([for (final draft in kept) draft.after!]);
  final byId = {for (final draft in kept) draft.after!.id: draft};
  for (final stage in keptOrder) {
    changes.add(byId[stage.id]!.build());
  }
  for (final draft in removedStages) {
    changes.add(draft.build());
  }

  return TaskImportDiff(
    stages: changes,
    plan: StageSyncPlan(
      stagesToCreate: stagesToCreate,
      stagesToUpdate: stagesToUpdate,
      stageIdsToDelete: stageIdsToDelete,
      tasksToCreate: tasksToCreate,
      tasksToUpdate: tasksToUpdate,
      taskIdsToDelete: taskIdsToDelete,
    ),
  );
}

class _StageChangeDraft {
  _StageChangeDraft(this.kind, this.before, this.after, this.fields);

  final ChangeKind kind;
  final Stage? before;
  final Stage? after;
  final List<FieldChange> fields;
  final List<TaskChange> tasks = [];

  StageChange build() => StageChange(
        kind: kind,
        before: before,
        after: after,
        fields: fields,
        tasks: List.unmodifiable(tasks),
      );
}

/// [existing] with the file's fields. A title that is the export's name for
/// a repeated title (" (2)") keeps the stored title.
Stage _updatedStage(Stage existing, Stage fromFile, String exportName) {
  final title =
      _key(fromFile.title) == exportName ? existing.title : fromFile.title;
  // Contacts keep their ids by name, so an unchanged list stays equal.
  final pool = _Pool<StageContact>(existing.contacts, (c) => _key(c.name));
  final contacts = [
    for (final contact in fromFile.contacts)
      contact.copyWith(id: pool.take(_key(contact.name))?.id ?? contact.id),
  ];
  return Stage(
    id: existing.id,
    eventId: existing.eventId,
    title: title,
    date: fromFile.date,
    startTime: fromFile.startTime,
    endTime: fromFile.endTime,
    requirements: fromFile.requirements,
    hotelLocation: fromFile.hotelLocation,
    notes: fromFile.notes,
    contacts: contacts,
    createdAt: existing.createdAt,
    createdById: existing.createdById,
    updatedAt: existing.updatedAt,
  );
}

List<FieldChange> _stageFields(Stage before, Stage after) {
  final fields = <FieldChange>[];
  void compare(String label, String a, String b) {
    if (a.trim() != b.trim()) fields.add(FieldChange(label, a.trim(), b.trim()));
  }

  compare(StageColumns.title, before.title, after.title);
  compare(StageColumns.date, formatImportDay(before.date),
      formatImportDay(after.date));
  compare(StageColumns.start, before.startTime ?? '', after.startTime ?? '');
  compare(StageColumns.end, before.endTime ?? '', after.endTime ?? '');
  compare(StageColumns.requirements, before.requirements, after.requirements);
  compare(StageColumns.location, before.hotelLocation, after.hotelLocation);
  compare(StageColumns.notes, before.notes, after.notes);
  compare(StageColumns.contacts, _contactsText(before.contacts),
      _contactsText(after.contacts));
  return fields;
}

String _contactsText(List<StageContact> contacts) => [
      for (final contact in contacts)
        [
          contact.name,
          if (contact.phone.isNotEmpty) contact.phone,
          if (contact.role.isNotEmpty) contact.role,
        ].join(', '),
    ].join('\n');

class _SubtaskMerge {
  const _SubtaskMerge(this.subtasks, this.added, this.removed);

  /// The file's subtasks; a matched one carries the stored id and tick.
  final List<Subtask> subtasks;
  final List<String> added;
  final List<Subtask> removed;
}

_SubtaskMerge _mergeSubtasks(List<Subtask> before, List<Subtask> fromFile) {
  final pool = _Pool<Subtask>(before, (subtask) => _key(subtask.title));
  final added = <String>[];
  final subtasks = <Subtask>[];
  for (final subtask in fromFile) {
    final existing = pool.take(_key(subtask.title));
    if (existing == null) {
      added.add(subtask.title);
      subtasks.add(subtask);
    } else {
      subtasks.add(existing.copyWith(title: subtask.title));
    }
  }
  return _SubtaskMerge(
    subtasks,
    added,
    [for (final subtask in before) if (!pool.taken.contains(subtask)) subtask],
  );
}

List<FieldChange> _taskFields(
  TaskItem before,
  TaskItem after,
  _SubtaskMerge merge,
) {
  final fields = <FieldChange>[];
  void compare(String label, String a, String b) {
    if (a.trim() != b.trim()) fields.add(FieldChange(label, a.trim(), b.trim()));
  }

  compare(TaskColumns.title, before.title, after.title);
  compare(TaskColumns.description, before.description, after.description);
  if (!_sameSet(before.assigneeIds, after.assigneeIds)) {
    fields.add(FieldChange(
      TaskColumns.assignees,
      _names(before),
      _names(after),
    ));
  }
  compare(TaskColumns.assembly, before.assemblyTime ?? '',
      after.assemblyTime ?? '');
  final sameSubtasks = merge.added.isEmpty &&
      merge.removed.isEmpty &&
      _sameOrder(before.subtasks, after.subtasks);
  if (!sameSubtasks) {
    fields.add(FieldChange(
      TaskColumns.subtasks,
      before.subtasks.map((s) => s.title).join('\n'),
      after.subtasks.map((s) => s.title).join('\n'),
    ));
  }
  return fields;
}

bool _sameSet(List<String> a, List<String> b) =>
    a.toSet().length == b.toSet().length && a.toSet().containsAll(b);

bool _sameOrder(List<Subtask> a, List<Subtask> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id || a[i].title != b[i].title) return false;
  }
  return true;
}

String _names(TaskItem task) {
  if (task.assignees.isNotEmpty) {
    return task.assignees.map((member) => member.name).join(', ');
  }
  return task.assigneeIds.join(', ');
}
