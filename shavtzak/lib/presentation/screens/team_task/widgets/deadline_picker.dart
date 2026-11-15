import 'package:flutter/material.dart';

import '../../../../core/utils/constraint_event_overlap.dart';
import '../../../../domain/entities/event.dart';
import '../../../widgets/date_picker_dialog.dart';

/// Picks a task's deadline in the app's own date picker, the one a member
/// uses for a constraint's dates: days with an event framed in red, days
/// before today dimmed (still selectable, for a task already late).
///
/// Null = cancelled.
Future<DateTime?> pickTeamTaskDeadline(
  BuildContext context, {
  DateTime? initial,
  required List<Event> events,
}) async {
  final now = DateTime.now();
  final result = await showDialog<Map<String, DateTime?>>(
    context: context,
    builder: (_) => DualCalendarDatePicker(
      key: const Key('team-task-deadline-picker'),
      isSingleDate: true,
      initialStartDate: initial,
      title: 'בחירת דד ליין',
      dimBeforeDate: DateTime(now.year, now.month, now.day),
      highlightedDates: getAllEventDates(events),
    ),
  );
  return result?['startDate'];
}
