import '../../../core/utils/task_progress.dart';
import '../../../domain/entities/task_item.dart';
import 'sheet_view.dart';

/// Keeps an open list's rows in place. A row ticked in "חסרות", or a late
/// task finished from the late list, stays where it was, struck through,
/// until the person moves to another list or closes the sheet; a task that
/// starts to match joins in its place.
class RowHold {
  SheetView? _view;
  final Set<String> _ids = <String>{};

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
    }
    _ids.addAll(matching.map((task) => task.id));
    return heldRows(matching: matching, heldIds: _ids, all: all);
  }

  /// Forget everything, as when the sheet closes.
  void clear() {
    _view = null;
    _ids.clear();
  }
}
