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

/// Asks which stage of the event a task moves to: the stages grouped by
/// day, each a row with its time and title. The task's own stage stays in
/// the list, marked and not choosable, so the order reads like the screen.
Future<Stage?> pickStage(
  BuildContext context, {
  required List<Stage> stages,
  required String currentStageId,
}) {
  final byDay = <DateTime, List<Stage>>{};
  for (final stage in stages) {
    final day = DateTime(stage.date.year, stage.date.month, stage.date.day);
    byDay.putIfAbsent(day, () => []).add(stage);
  }
  final hasOthers = stages.any((stage) => stage.id != currentStageId);
  return showDialog<Stage>(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        key: const Key('edit-move-dialog'),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TaskStyle.editCardRadius)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text('העברה לשלב אחר',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text('לאיזה שלב להעביר את המשימה?',
                    style: TextStyle(color: TaskStyle.editMuted)),
              ),
              const Divider(height: 1, color: TaskStyle.editTaskLine),
              Flexible(
                child: !hasOthers
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('אין שלבים אחרים באירוע'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 6),
                        children: [
                          for (final entry in byDay.entries) ...[
                            _MoveDayHeading(day: entry.key),
                            for (final stage in entry.value)
                              _MoveStageOption(
                                stage: stage,
                                current: stage.id == currentStageId,
                              ),
                          ],
                        ],
                      ),
              ),
              const Divider(height: 1, color: TaskStyle.editTaskLine),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton(
                    key: const Key('edit-move-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ביטול'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A day's heading in the move list.
class _MoveDayHeading extends StatelessWidget {
  const _MoveDayHeading({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) => Container(
        color: TaskStyle.editRowStripe,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(
          editDayLabel(day),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: TaskStyle.editCardEdge,
          ),
        ),
      );
}

/// One stage in the move list: its time in a fixed column, then its title.
class _MoveStageOption extends StatelessWidget {
  const _MoveStageOption({required this.stage, required this.current});

  final Stage stage;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final time = stageTimeLabel(stage);
    final faded = current ? TaskStyle.editFaint : null;
    return InkWell(
      key: Key('edit-move-to-${stage.id}'),
      onTap: current ? null : () => Navigator.of(context).pop(stage),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: TaskStyle.editRowLine)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                time.isEmpty ? '—' : time,
                style: TextStyle(
                  color: faded ?? TaskStyle.editMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Text(
                stage.title,
                style: TextStyle(fontWeight: FontWeight.w500, color: faded),
              ),
            ),
            if (current)
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 8),
                child: Text('השלב הנוכחי',
                    style:
                        TextStyle(fontSize: 12, color: TaskStyle.editMuted)),
              ),
          ],
        ),
      ),
    );
  }
}
