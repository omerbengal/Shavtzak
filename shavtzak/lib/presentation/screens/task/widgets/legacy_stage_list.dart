import 'package:flutter/material.dart';

import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/task_item.dart';
import 'stage_card.dart';

/// Today's list of stage cards, kept on "כל השלבים" until the day calendar
/// replaces it. Holds which cards and detail folds are open: the list
/// re-sorts on every change, and a card that moved would otherwise close.
class LegacyStageList extends StatefulWidget {
  const LegacyStageList({
    super.key,
    required this.groups,
    required this.eventTasks,
    required this.canManage,
    required this.onEditStage,
    required this.onDeleteStage,
    required this.onAddTask,
    required this.onCallPhone,
    required this.taskBuilder,
  });

  final List<StageTasks> groups;

  /// Every task of the event, for each stage's done count.
  final List<TaskItem> eventTasks;

  final bool canManage;
  final ValueChanged<Stage> onEditStage;
  final void Function(Stage stage, int taskCount) onDeleteStage;
  final ValueChanged<Stage> onAddTask;
  final ValueChanged<String> onCallPhone;
  final Widget Function(TaskItem task, Stage stage) taskBuilder;

  @override
  State<LegacyStageList> createState() => _LegacyStageListState();
}

class _LegacyStageListState extends State<LegacyStageList> {
  final Set<String> _openStageIds = <String>{};
  final Set<String> _openStageDetails = <String>{};

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // Room for the floating button below the last card.
      padding: const EdgeInsets.only(top: 4, bottom: 96),
      itemCount: widget.groups.length,
      itemBuilder: (context, index) {
        final group = widget.groups[index];
        final stage = group.stage;
        final stageTasks =
            widget.eventTasks.where((task) => task.stageId == stage.id).toList();
        return StageCard(
          key: ValueKey(stage.id),
          stage: stage,
          tasks: group.tasks,
          allTasks: stageTasks,
          canManage: widget.canManage,
          isOpen: _openStageIds.contains(stage.id),
          onToggleOpen: () => setState(() {
            if (!_openStageIds.remove(stage.id)) _openStageIds.add(stage.id);
          }),
          isDetailsOpen: _openStageDetails.contains(stage.id),
          onToggleDetails: () => setState(() {
            if (!_openStageDetails.remove(stage.id)) {
              _openStageDetails.add(stage.id);
            }
          }),
          onEdit: () => widget.onEditStage(stage),
          onDelete: () => widget.onDeleteStage(stage, stageTasks.length),
          onAddTask: () => widget.onAddTask(stage),
          onCallPhone: widget.onCallPhone,
          taskBuilder: (task) => widget.taskBuilder(task, stage),
        );
      },
    );
  }
}
