import 'package:flutter/material.dart';

import '../../../../core/utils/task_schedule.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/task_item.dart';
import '../../../../domain/entities/team_member.dart';
import '../task_style.dart';

/// What every card and row of the editing screen needs from the screen: the
/// layout, the event's facts, and where each change goes.
class EditContext {
  const EditContext({
    required this.wide,
    required this.event,
    required this.days,
    required this.stages,
    required this.eventAssignees,
    required this.onTaskCommit,
    required this.onStageCommit,
    required this.onMoveTask,
    required this.onDeleteTask,
    required this.onDeleteStage,
    required this.onAddTask,
    required this.highlightId,
    required this.keyFor,
  });

  final bool wide;
  final Event event;

  /// The event's days, the only ones a stage may sit on.
  final List<DateTime> days;

  /// The event's stages in screen order, for "העברה לשלב אחר".
  final List<Stage> stages;

  /// The members assigned to the event, who a task may be given to.
  final List<TeamMember> eventAssignees;

  final ValueChanged<TaskItem> onTaskCommit;
  final ValueChanged<Stage> onStageCommit;
  final void Function(TaskItem task, Stage to) onMoveTask;
  final ValueChanged<TaskItem> onDeleteTask;
  final void Function(Stage stage, int taskCount) onDeleteStage;
  final ValueChanged<Stage> onAddTask;

  /// The task or stage just edited, tinted for a moment.
  final String? highlightId;

  /// A stable key per task or stage, to scroll the one just edited into view.
  final GlobalKey Function(String id) keyFor;
}

/// "יום ג׳ 20/10".
String editDayLabel(DateTime day) =>
    'יום ${hebrewWeekday(day)} ${day.day}/${day.month}';

/// A faint stand-in for an empty value, itself clickable.
Widget editPlaceholder(String text) => Text(
      text,
      style: const TextStyle(color: TaskStyle.editFaint),
    );

/// Asks which of [stages] (other than [current]) a task moves to.
Future<Stage?> pickStage(
  BuildContext context, {
  required List<Stage> stages,
  required String currentStageId,
}) {
  final others = stages.where((stage) => stage.id != currentStageId).toList();
  return showDialog<Stage>(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: SimpleDialog(
        key: const Key('edit-move-dialog'),
        title: const Text('העברה לשלב אחר'),
        children: [
          if (others.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('אין שלבים אחרים באירוע'),
            ),
          for (final stage in others)
            SimpleDialogOption(
              key: Key('edit-move-to-${stage.id}'),
              onPressed: () => Navigator.of(context).pop(stage),
              child: Text('${stage.title} · ${editDayLabel(stage.date)}'
                  '${stageTimeLabel(stage).isEmpty ? '' : ' · ${stageTimeLabel(stage)}'}'),
            ),
        ],
      ),
    ),
  );
}
