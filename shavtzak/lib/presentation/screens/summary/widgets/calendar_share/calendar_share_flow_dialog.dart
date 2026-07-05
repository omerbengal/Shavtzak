import 'package:flutter/material.dart';

import '../../../../../core/debug/logger.dart';
import '../../../../../core/utils/israel_calendar.dart';
import '../../../../../domain/entities/category.dart';
import '../../../../../domain/entities/event.dart';
import '../../../../widgets/date_picker_dialog.dart';
import 'calendar_share_data_builder.dart';
import 'calendar_share_models.dart';
import 'calendar_share_preview_dialog.dart';

/// Range cap: rangeEnd must be strictly before rangeStart + 6 months.
bool calendarShareRangeExceedsMax(DateTime start, DateTime end) {
  final cap = DateTime(start.year, start.month + 6, start.day);
  return !end.isBefore(cap);
}

/// Runs the calendar-share flow: date range picker → weeks/months choice →
/// share preview. Re-opens the range picker when the range exceeds the cap.
Future<void> startCalendarShareFlow(
  BuildContext context,
  List<Event> events, {
  required List<Category> categories,
}) async {
  DateTime? initialStart;
  DateTime? initialEnd;

  while (true) {
    if (!context.mounted) {
      return;
    }
    final rangeResult = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (_) => DualCalendarDatePicker(
        isSingleDate: false,
        initialStartDate: initialStart,
        initialEndDate: initialEnd,
        title: 'בחר טווח תאריכים ללוח',
        highlightedDates: _collectEventDates(events),
      ),
    );
    if (!context.mounted ||
        rangeResult == null ||
        rangeResult['startDate'] == null) {
      return;
    }

    final start = _dateOnly(rangeResult['startDate']!);
    // Start-only selection means a single-day range (same as constraints flow).
    final end = _dateOnly(rangeResult['endDate'] ?? rangeResult['startDate']!);

    if (calendarShareRangeExceedsMax(start, end)) {
      Logger.action('calendarShare:rangeTooLong');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('טווח התאריכים המקסימלי הוא 6 חודשים')),
      );
      initialStart = start;
      initialEnd = end;
      continue;
    }

    final mode = await showDialog<CalendarShareMode>(
      context: context,
      builder: (_) => const CalendarShareModeDialog(),
    );
    if (!context.mounted || mode == null) {
      return;
    }

    Logger.action('open:calendarSharePreview', {
      'mode': mode.name,
      'days': end.difference(start).inDays + 1,
    });
    final data = CalendarShareDataBuilder.build(
      events: events,
      rangeStart: start,
      rangeEnd: end,
      mode: mode,
      today: IsraelCalendar.calendarDay(DateTime.now()),
      categories: categories,
    );
    await showDialog(
      context: context,
      builder: (_) => CalendarSharePreviewDialog(
        data: data,
        rangeStart: start,
        rangeEnd: end,
      ),
    );
    return;
  }
}

Set<DateTime> _collectEventDates(List<Event> events) {
  final dates = <DateTime>{};
  for (final event in events) {
    if (event.isDeactivated) {
      continue;
    }
    var day = _dateOnly(event.startDate);
    final last = _dateOnly(event.endDate);
    // Defensive bound: corrupt endDate must not freeze the UI building rings.
    var guard = 0;
    while (!day.isAfter(last) && guard < 370) {
      dates.add(day);
      day = DateTime(day.year, day.month, day.day + 1);
      guard++;
    }
  }
  return dates;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

class CalendarShareModeDialog extends StatelessWidget {
  const CalendarShareModeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('איך להציג את הלוח?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            _ModeTile(
              icon: Icons.view_week,
              title: 'שבועי',
              subtitle: 'רצועה לכל שבוע — תאים מרווחים',
              mode: CalendarShareMode.weeks,
            ),
            SizedBox(height: 8),
            _ModeTile(
              icon: Icons.calendar_month,
              title: 'חודשי',
              subtitle: 'לוח חודשי מלא — תצוגה צפופה',
              mode: CalendarShareMode.months,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.action('tap:cancel:calendarShareMode');
              Navigator.of(context).pop();
            },
            child: const Text('ביטול'),
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final CalendarShareMode mode;

  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        onTap: () {
          Logger.action('tap:calendarShareMode', {'mode': mode.name});
          Navigator.of(context).pop(mode);
        },
      ),
    );
  }
}
