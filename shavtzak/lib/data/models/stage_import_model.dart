import '../../domain/entities/imported_stage.dart';
import 'stage_model.dart';
import 'task_item_model.dart';

/// The payload of the backend's `stage.import`: each stage and its tasks in
/// exactly the shape `stage.insert` and `task.insert` take.
class StageImportModel {
  static Map<String, dynamic> toMutationPayload(
    String eventId,
    List<ImportedStage> stages,
  ) {
    return {
      'eventId': eventId,
      'stages': [
        for (final imported in stages)
          {
            'stage': StageModel.toMutationPayload(imported.stage),
            'tasks': [
              for (final task in imported.tasks)
                TaskItemModel.toMutationPayload(task),
            ],
          },
      ],
    };
  }
}
