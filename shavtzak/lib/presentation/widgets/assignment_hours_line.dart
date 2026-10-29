import 'package:flutter/material.dart';

import '../../core/utils/custom_hours.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';

/// A member's own hours for one assignment, as a line under their name in the
/// assignment dialogs: `שעות: 12:00–14:30`, days by weekday name
/// ([formatCustomHoursByWeekday]) against [event], or the assignment's own
/// event when none is given. Without either, the days read as dates
/// ([formatCustomHours]).
///
/// Empty when the assignment has no hours of its own, or hours that cannot be
/// read (the member is then held for the whole event, as the dialog already
/// shows). Text only, set apart from the notes box below it by the same
/// padding.
class AssignmentHoursLine extends StatelessWidget {
  const AssignmentHoursLine({super.key, required this.assignment, this.event});

  final Assignment assignment;
  final Event? event;

  @override
  Widget build(BuildContext context) {
    final window = assignment.customWindow;
    if (window == null) return const SizedBox.shrink();

    final onEvent = event ?? assignment.event;
    final hours = onEvent == null
        ? formatCustomHours(window)
        : formatCustomHoursByWeekday(window, onEvent);
    return Padding(
      padding: const EdgeInsets.only(right: 26, top: 4),
      child: Text(
        'שעות: $hours',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }
}
