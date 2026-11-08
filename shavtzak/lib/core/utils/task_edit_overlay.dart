import 'package:collection/collection.dart';

import '../../domain/entities/stage.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/entities/team_member.dart';

/// Whether [a] and [b] carry the same fields a manager edits on the editing
/// screen: what `task.update` and `task.reorder` write, ignoring ticks and
/// timestamps.
bool sameTaskEdit(TaskItem a, TaskItem b) {
  const list = ListEquality<String>();
  return a.stageId == b.stageId &&
      a.order == b.order &&
      a.title == b.title &&
      a.description == b.description &&
      (a.assemblyTime ?? '') == (b.assemblyTime ?? '') &&
      list.equals(a.assigneeIds, b.assigneeIds) &&
      list.equals(
        [for (final subtask in a.subtasks) '${subtask.id}\u0000${subtask.title}'],
        [for (final subtask in b.subtasks) '${subtask.id}\u0000${subtask.title}'],
      );
}

/// Whether [a] and [b] carry the same fields `stage.update` writes.
bool sameStageEdit(Stage a, Stage b) {
  return a.title == b.title &&
      a.date == b.date &&
      (a.startTime ?? '') == (b.startTime ?? '') &&
      (a.endTime ?? '') == (b.endTime ?? '') &&
      a.requirements == b.requirements &&
      a.hotelLocation == b.hotelLocation &&
      a.notes == b.notes &&
      const ListEquality<StageContact>().equals(a.contacts, b.contacts);
}

/// The versions the editing screen has sent but the live stream has not
/// brought back yet.
///
/// The screen shows, and builds the next edit on, the sent version, so two
/// quick edits to one task never undo each other while the first is still on
/// its way. An entry goes once the stream carries the same fields, or when the
/// backend refuses it.
class EditOverlay<T> {
  EditOverlay(this._same);

  final bool Function(T a, T b) _same;
  final Map<String, T> _sent = {};

  bool get isEmpty => _sent.isEmpty;

  /// What to show for [id]: the version sent last, else [live].
  T resolve(String id, T live) => _sent[id] ?? live;

  void sent(String id, T value) => _sent[id] = value;

  void failed(String id) => _sent.remove(id);

  /// Drops every entry the stream has caught up with. An entry whose item is
  /// gone from [liveById] (deleted elsewhere) is dropped too.
  void reconcile(Map<String, T> liveById) {
    _sent.removeWhere((id, value) {
      final live = liveById[id];
      return live == null || _same(live, value);
    });
  }
}

/// [live] with the fields a task edit writes taken from [edit]: title,
/// description, assembly time, assignees and the subtask list.
///
/// Everything else stays as [live] has it, so ticks made meanwhile still show.
/// A subtask kept by the edit keeps its live tick; a new one starts open.
/// [assignees] are the members [edit] names, already looked up.
TaskItem withTaskEdit(
  TaskItem live,
  TaskItem edit, {
  required List<TeamMember> assignees,
}) {
  final liveDone = {
    for (final subtask in live.subtasks) subtask.id: subtask.isDone,
  };
  return live.copyWith(
    stageId: edit.stageId,
    title: edit.title,
    description: edit.description,
    assemblyTime: edit.assemblyTime,
    clearAssemblyTime: edit.assemblyTime == null,
    order: edit.order,
    assigneeIds: edit.assigneeIds,
    assignees: assignees,
    subtasks: [
      for (final subtask in edit.subtasks)
        subtask.copyWith(isDone: liveDone[subtask.id] ?? false),
    ],
  );
}
