import 'package:flutter/material.dart';

import 'calendar_share_models.dart';

class CalendarShareCard extends StatelessWidget {
  static const double captureWidth = 1080;

  final CalendarShareData data;

  const CalendarShareCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.white,
        child: Container(
          width: captureWidth,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'לוח אירועים',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.rangeTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              if (data.mode == CalendarShareMode.weeks) ...[
                const _WeekdayHeaderRow(),
                const SizedBox(height: 6),
                for (final week in data.weeks) ...[
                  _CalendarGrid(weeks: [week], dense: false),
                  const SizedBox(height: 10),
                ],
              ] else ...[
                for (final month in data.months) ...[
                  Text(
                    month.title,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _WeekdayHeaderRow(),
                  const SizedBox(height: 6),
                  _CalendarGrid(weeks: month.weeks, dense: true),
                  const SizedBox(height: 24),
                ],
              ],
              const SizedBox(height: 8),
              const Text(
                'נוצר משבצק',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekdayHeaderRow extends StatelessWidget {
  static const List<String> _weekdayNames = [
    'ראשון',
    'שני',
    'שלישי',
    'רביעי',
    'חמישי',
    'שישי',
    'שבת',
  ];

  const _WeekdayHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final name in _weekdayNames)
          Expanded(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final List<CalendarShareWeek> weeks;
  final bool dense;

  const _CalendarGrid({required this.weeks, required this.dense});

  @override
  Widget build(BuildContext context) {
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      border: TableBorder.all(color: const Color(0xFFE2E8F0)),
      children: [
        for (final week in weeks)
          TableRow(
            children: [
              for (final day in week.days) _DayCell(day: day, dense: dense),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  static const List<String> _shortDayNames = [
    'א׳',
    'ב׳',
    'ג׳',
    'ד׳',
    'ה׳',
    'ו׳',
    'ש׳',
  ];

  final CalendarShareDay? day;
  final bool dense;

  const _DayCell({required this.day, required this.dense});

  @override
  Widget build(BuildContext context) {
    final minHeight = dense ? 88.0 : 120.0;
    final d = day;
    if (d == null) {
      return Container(
        constraints: BoxConstraints(minHeight: minHeight),
        color: const Color(0xFFF8FAFC),
      );
    }

    final headerColor = !d.inRange
        ? const Color(0xFFCBD5E1)
        : d.isPast
            ? const Color(0xFF94A3B8)
            : const Color(0xFF0F172A);

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.all(6),
      color: d.inRange ? Colors.white : const Color(0xFFF8FAFC),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${d.date.day}',
                style: TextStyle(
                  fontSize: dense ? 15 : 17,
                  fontWeight: FontWeight.w800,
                  color: headerColor,
                ),
              ),
              Text(
                // Dart weekday: Mon=1..Sun=7 → % 7 maps Sunday to index 0.
                _shortDayNames[d.date.weekday % 7],
                style: TextStyle(
                  fontSize: dense ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: headerColor,
                ),
              ),
            ],
          ),
          for (final event in d.events) _EventBlock(event: event, dense: dense),
        ],
      ),
    );
  }
}

class _EventBlock extends StatelessWidget {
  final CalendarShareEvent event;
  final bool dense;

  const _EventBlock({required this.event, required this.dense});

  @override
  Widget build(BuildContext context) {
    final detailStyle = TextStyle(
      fontSize: dense ? 12 : 13.5,
      fontWeight: FontWeight.w500,
      height: 1.3,
      color: const Color(0xFF334155),
    );

    return Opacity(
      // Past events are shown but visually muted (spec: ~45%).
      opacity: event.isPast ? 0.45 : 1.0,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 4 : 6,
          vertical: dense ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              event.isContinuation ? '${event.name} (המשך)' : event.name,
              style: TextStyle(
                fontSize: dense ? 13 : 15,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: const Color(0xFF0F172A),
              ),
            ),
            for (final line in event.timeLines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(line, style: detailStyle),
              ),
            if (event.locationLine.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('📍 ${event.locationLine}', style: detailStyle),
              ),
          ],
        ),
      ),
    );
  }
}
