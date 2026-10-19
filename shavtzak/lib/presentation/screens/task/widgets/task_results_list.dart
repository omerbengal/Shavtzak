import 'package:flutter/material.dart';

import '../../../../core/utils/task_schedule.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';

/// Tasks from several stages, grouped under each stage's title and time, in
/// the order given: filter, search and check results.
class TaskResultsList extends StatelessWidget {
  const TaskResultsList({
    super.key,
    required this.groups,
    required this.rowBuilder,
    this.emptyText = 'אין משימות',
  });

  final List<StageTasks> groups;
  final Widget Function(TaskItem task) rowBuilder;

  /// Shown when there is nothing at all.
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            emptyText,
            style: const TextStyle(color: TaskStyle.neutralText),
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          Padding(
            key: Key('results-stage-${group.stage.id}'),
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 2),
            child: Text(
              _header(group),
              style: theme.textTheme.labelLarge?.copyWith(
                color: TaskStyle.mine,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final task in group.tasks) rowBuilder(task),
        ],
      ],
    );
  }

  String _header(StageTasks group) {
    final time = stageTimeLabel(group.stage);
    return time.isEmpty ? group.stage.title : '${group.stage.title} · $time';
  }
}
