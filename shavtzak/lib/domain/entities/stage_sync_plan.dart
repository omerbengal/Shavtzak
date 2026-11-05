import 'package:equatable/equatable.dart';

import 'stage.dart';
import 'task_item.dart';

/// What an updated Excel file changes in an event that already has stages:
/// every write spelled out, with every id chosen already, so sending the same
/// plan twice changes nothing more. Updated tasks carry their existing ids
/// (subtasks too), which is how they keep their ticks.
class StageSyncPlan extends Equatable {
  const StageSyncPlan({
    this.stagesToCreate = const [],
    this.stagesToUpdate = const [],
    this.stageIdsToDelete = const [],
    this.tasksToCreate = const [],
    this.tasksToUpdate = const [],
    this.taskIdsToDelete = const [],
  });

  final List<Stage> stagesToCreate;
  final List<Stage> stagesToUpdate;
  final List<String> stageIdsToDelete;
  final List<TaskItem> tasksToCreate;
  final List<TaskItem> tasksToUpdate;
  final List<String> taskIdsToDelete;

  bool get isEmpty =>
      stagesToCreate.isEmpty &&
      stagesToUpdate.isEmpty &&
      stageIdsToDelete.isEmpty &&
      tasksToCreate.isEmpty &&
      tasksToUpdate.isEmpty &&
      taskIdsToDelete.isEmpty;

  @override
  List<Object?> get props => [
        stagesToCreate,
        stagesToUpdate,
        stageIdsToDelete,
        tasksToCreate,
        tasksToUpdate,
        taskIdsToDelete,
      ];
}
