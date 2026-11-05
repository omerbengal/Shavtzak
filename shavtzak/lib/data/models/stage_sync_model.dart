import '../../domain/entities/stage_sync_plan.dart';
import 'stage_model.dart';
import 'task_item_model.dart';

/// The payload of the backend's `stage.sync`: every create and update in
/// exactly the shape `stage.insert` / `task.insert` take, and the ids to
/// delete. No progress is sent; the backend keeps it.
class StageSyncModel {
  static Map<String, dynamic> toMutationPayload(
    String eventId,
    StageSyncPlan plan,
  ) {
    return {
      'eventId': eventId,
      'stages': {
        'create':
            plan.stagesToCreate.map(StageModel.toMutationPayload).toList(),
        'update':
            plan.stagesToUpdate.map(StageModel.toMutationPayload).toList(),
        'delete': plan.stageIdsToDelete,
      },
      'tasks': {
        'create':
            plan.tasksToCreate.map(TaskItemModel.toMutationPayload).toList(),
        'update':
            plan.tasksToUpdate.map(TaskItemModel.toMutationPayload).toList(),
        'delete': plan.taskIdsToDelete,
      },
    };
  }
}
