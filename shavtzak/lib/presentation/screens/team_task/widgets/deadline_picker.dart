import 'package:flutter/material.dart';

import '../../../widgets/date_picker_dialog.dart';

/// Picks a task's deadline in the app's own date picker, the one a member
/// uses for a constraint's dates. Only today and later can be picked, and
/// events are not marked (Omer, round 2: a deadline is not about events).
///
/// Null = cancelled.
Future<DateTime?> pickTeamTaskDeadline(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final result = await showDialog<Map<String, DateTime?>>(
    context: context,
    builder: (_) => DualCalendarDatePicker(
      key: const Key('team-task-deadline-picker'),
      isSingleDate: true,
      // A late task's old deadline is not offered again: the calendar
      // opens on today.
      initialStartDate: initial != null && !initial.isBefore(today) ? initial : null,
      title: 'בחירת דד ליין',
      minDate: today,
    ),
  );
  return result?['startDate'];
}
