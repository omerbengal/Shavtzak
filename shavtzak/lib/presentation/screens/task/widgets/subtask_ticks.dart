import 'package:flutter/material.dart';

import '../../../../domain/entities/subtask.dart';
import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';

/// A task's subtasks inside its row, one line each with its tick box.
///
/// The list is keyed `<keyPrefix>-subtasks-<taskId>` and each tick box
/// `<tickKeyPrefix>-<taskId>-<subtaskId>`, so tests and the rows find them
/// by the task and subtask, not by position.
class SubtaskTicks extends StatelessWidget {
  const SubtaskTicks({
    super.key,
    required this.task,
    required this.canTick,
    required this.onToggle,
    required this.listKeyPrefix,
    required this.tickKeyPrefix,
  });

  final TaskItem task;
  final bool canTick;
  final void Function(Subtask subtask, bool isDone) onToggle;
  final String listKeyPrefix;
  final String tickKeyPrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('$listKeyPrefix-subtasks-${task.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final subtask in task.subtasks)
          Row(
            children: [
              Checkbox(
                key: Key('$tickKeyPrefix-${task.id}-${subtask.id}'),
                value: subtask.isDone,
                visualDensity: VisualDensity.compact,
                onChanged: canTick
                    ? (value) => onToggle(subtask, value ?? false)
                    : null,
              ),
              // Wraps in full: a name never collapses into "…".
              Expanded(
                child: Text(
                  subtask.title,
                  style: TextStyle(
                    fontSize: TaskStyle.subtaskSize,
                    decoration: subtask.isDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    color: subtask.isDone ? TaskStyle.faintText : null,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
