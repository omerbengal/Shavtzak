import '../../../core/utils/task_progress.dart';
import '../../../domain/entities/task_item.dart';
import 'sheet_view.dart';

/// Keeps an open list's rows in place. A row ticked in "חסרות", or a late
/// task finished from the late list, stays where it was, struck through,
/// until the person moves to another list or closes the sheet; a task that
/// starts to match joins in its place.
///
/// It also keeps which rows had their subtasks opened in place, for as long
/// as it keeps the rows: through new data and through opening a task from
/// the list and coming back.
class RowHold {
  SheetView? _view;
  final Set<String> _ids = <String>{};
  final Set<String> _expandedIds = <String>{};

  /// Whether the row of [taskId] lists its subtasks.
  bool isExpanded(String taskId) => _expandedIds.contains(taskId);

  /// Lists the subtasks of [taskId]'s row in the current view. Opening a
  /// row only grows it; it never changes the order of the rows.
  void expand(String taskId) => _expandedIds.add(taskId);

  /// Folds [taskId]'s subtasks away again.
  void collapse(String taskId) => _expandedIds.remove(taskId);

  /// The rows [view] shows now: [matching] plus every row it has shown since
  /// it opened that still exists in [all].
  List<TaskItem> rows(
    SheetView view, {
    required List<TaskItem> matching,
    required List<TaskItem> all,
  }) {
    if (view != _view) {
      _view = view;
      _ids.clear();
      _expandedIds.clear();
    }
    _ids.addAll(matching.map((task) => task.id));
    return heldRows(matching: matching, heldIds: _ids, all: all);
  }

  /// Forget everything, as when the sheet closes.
  void clear() {
    _view = null;
    _ids.clear();
    _expandedIds.clear();
  }
}
