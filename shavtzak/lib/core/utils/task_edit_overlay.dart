import 'package:collection/collection.dart';

import '../../domain/entities/stage.dart';
import '../../domain/entities/task_item.dart';

/// Whether [a] and [b] carry the same fields a manager edits on the editing
/// screen: what `task.update` writes, ignoring ticks and timestamps.
bool sameTaskEdit(TaskItem a, TaskItem b) {
  const list = ListEquality<String>();
  return a.stageId == b.stageId &&
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
