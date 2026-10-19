import 'package:equatable/equatable.dart';

/// The lists the sheet can hold besides a single stage.
enum ResultsKind { late, dueSoon, search, removedAssignees, myLate }

/// What the low sheet (or, on a wide screen, the side panel) shows. One of
/// these at a time; replacing it replaces the sheet's content without
/// closing the sheet.
sealed class SheetView extends Equatable {
  const SheetView();
}

/// One stage: all of its tasks, or only the missing ones.
final class StageView extends SheetView {
  const StageView(this.stageId, {this.missingOnly = false});

  final String stageId;
  final bool missingOnly;

  @override
  List<Object?> get props => [stageId, missingOnly];
}

/// Tasks from every stage, grouped by stage: a filter, a search, the
/// managers' assignee check, or the viewer's own late tasks.
final class ResultsView extends SheetView {
  const ResultsView(this.kind, {this.query = ''});

  final ResultsKind kind;

  /// The search text; empty for every other kind.
  final String query;

  @override
  List<Object?> get props => [kind, query];
}

/// One task, opened from [back] when it was opened from a list.
final class TaskView extends SheetView {
  const TaskView(this.taskId, {this.back});

  final String taskId;
  final SheetView? back;

  @override
  List<Object?> get props => [taskId, back];
}
