import 'package:flutter/material.dart';

import '../../../../domain/entities/team_task.dart';
import '../../task/task_style.dart';

/// Colours and small formatters of the team tasks screen, on top of the
/// דו יומי [TaskStyle].
abstract final class TeamTaskStyle {
  static Color statusColor(TeamTaskStatus status) => switch (status) {
        TeamTaskStatus.open => TaskStyle.neutralText,
        TeamTaskStatus.inProgress => TaskStyle.mine,
        TeamTaskStatus.done => TaskStyle.doneDark,
        TeamTaskStatus.cancelled => TaskStyle.faintText,
        TeamTaskStatus.duplicate => TaskStyle.faintText,
      };

  static Color statusFill(TeamTaskStatus status) => switch (status) {
        TeamTaskStatus.open => TaskStyle.chip,
        TeamTaskStatus.inProgress => TaskStyle.currentLight,
        TeamTaskStatus.done => TaskStyle.doneLight,
        TeamTaskStatus.cancelled => TaskStyle.chip,
        TeamTaskStatus.duplicate => TaskStyle.chip,
      };

  static const double maxListWidth = TaskStyle.readableWidth;
}

/// `d.M`, the way the team writes a date ("15.11").
String shortDate(DateTime date) => '${date.day}.${date.month}';

/// `d.M.yyyy`.
String fullDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

/// `d.M HH:mm` in local time, for the update log.
String logStamp(DateTime at) {
  final local = at.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${shortDate(local)} $hh:$mm';
}

/// `yyyy-MM-dd` of [date].
String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// A small rounded status chip.
class TeamTaskStatusChip extends StatelessWidget {
  const TeamTaskStatusChip({super.key, required this.status, this.dense = false});

  final TeamTaskStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 1 : 4),
      decoration: BoxDecoration(
        color: TeamTaskStyle.statusFill(status),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.hebrewLabel,
        style: TextStyle(
          fontSize: dense ? TaskStyle.rowMetaSize : 13,
          color: TeamTaskStyle.statusColor(status),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A member's name as a small chip.
class MemberNameChip extends StatelessWidget {
  const MemberNameChip({super.key, required this.name, this.highlight = false});

  final String name;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? TaskStyle.currentLight : TaskStyle.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: TaskStyle.rowMetaSize,
          color: highlight ? TaskStyle.mine : TaskStyle.neutralText,
        ),
      ),
    );
  }
}
