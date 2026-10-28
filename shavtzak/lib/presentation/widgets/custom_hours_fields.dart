import 'package:flutter/material.dart';

import '../../core/debug/logger.dart';
import '../../core/utils/custom_hours.dart';
import '../../core/utils/event_stretch.dart';
import '../../core/utils/validators.dart';
import '../../domain/entities/event.dart';
import '../screens/event/widgets/event_time_field.dart';
import 'date_picker_dialog.dart';

const String _arrivalLabel = 'מגיע/ה';
const String _departureLabel = 'עוזב/ת';
const String _missingMessage = 'יש למלא תאריך ושעה';
const String _orderMessage = 'העזיבה חייבת להיות אחרי ההגעה';

/// Hebrew weekday letters, indexed by `DateTime.weekday` (1 = Monday).
const List<String> _weekdayLetters = [
  '',
  'ב׳',
  'ג׳',
  'ד׳',
  'ה׳',
  'ו׳',
  'ש׳',
  'א׳',
];

/// The member's own hours on one assignment: an arrival and a departure, each a
/// date and a time. It starts from [initial] and reports the whole interval on
/// every edit ([onChanged]), or null while a part is missing or the departure
/// is not after the arrival; the matching message shows under the rows.
///
/// All values are Israel wall-clock moments (`DateTime.utc` holding the clock
/// fields). A day picked in the calendar comes back as a local date and is read
/// by its year, month and day only, never converted.
class CustomHoursFields extends StatefulWidget {
  /// The event the hours belong to: its stretch is shown as a hint and its
  /// first and last day are marked in the calendar.
  final Event event;

  final WallInterval initial;

  final ValueChanged<WallInterval?> onChanged;

  const CustomHoursFields({
    super.key,
    required this.event,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<CustomHoursFields> createState() => _CustomHoursFieldsState();
}

class _CustomHoursFieldsState extends State<CustomHoursFields> {
  // Intentionally not disposed. On Flutter Web the editable subtree can still
  // be unwinding for a frame after the dialog pops, and disposing here causes
  // use-after-dispose assertions (same reason as the notes dialog's own).
  late final TextEditingController _arrivalTime;
  late final TextEditingController _departureTime;

  /// Midnight (`DateTime.utc`) of the arrival and departure day.
  DateTime? _arrivalDay;
  DateTime? _departureDay;

  @override
  void initState() {
    super.initState();
    final start = widget.initial.start;
    final end = widget.initial.end;
    _arrivalDay = DateTime.utc(start.year, start.month, start.day);
    _departureDay = DateTime.utc(end.year, end.month, end.day);
    _arrivalTime = TextEditingController(text: _clock(start));
    _departureTime = TextEditingController(text: _clock(end));
  }

  static String _clock(DateTime moment) =>
      '${moment.hour.toString().padLeft(2, '0')}:'
      '${moment.minute.toString().padLeft(2, '0')}';

  static int? _minutesOfDay(String text) {
    final trimmed = text.trim();
    if (!Validators.timeOfDayPattern.hasMatch(trimmed)) return null;
    final parts = trimmed.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// What the fields hold now: the interval, or the reason there is none.
  ({WallInterval? value, String? error}) _evaluate() {
    final arrivalMinutes = _minutesOfDay(_arrivalTime.text);
    final departureMinutes = _minutesOfDay(_departureTime.text);
    final arrivalDay = _arrivalDay;
    final departureDay = _departureDay;
    if (arrivalDay == null ||
        departureDay == null ||
        arrivalMinutes == null ||
        departureMinutes == null) {
      return (value: null, error: _missingMessage);
    }
    final start = arrivalDay.add(Duration(minutes: arrivalMinutes));
    final end = departureDay.add(Duration(minutes: departureMinutes));
    if (!end.isAfter(start)) return (value: null, error: _orderMessage);
    return (value: WallInterval(start, end), error: null);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    widget.onChanged(_evaluate().value);
  }

  Future<void> _pickDay({required bool arrival}) async {
    Logger.action('open:customHoursDatePicker', {
      'part': arrival ? 'arrival' : 'departure',
    });
    // Let a focused time field finish its blur before the calendar opens.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final current = arrival ? _arrivalDay : _departureDay;
    final event = widget.event;
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (_) => DualCalendarDatePicker(
        isSingleDate: true,
        title: arrival ? 'תאריך הגעה' : 'תאריך עזיבה',
        initialStartDate: current == null
            ? null
            : DateTime(current.year, current.month, current.day),
        minDate: null,
        highlightedDates: {
          DateTime(event.startDate.year, event.startDate.month,
              event.startDate.day),
          DateTime(
              event.endDate.year, event.endDate.month, event.endDate.day),
        },
        highlightLegend: 'מסגרת = תחילת האירוע וסופו',
      ),
    );
    final picked = result?['startDate'];
    if (picked == null || !mounted) return;

    final day = DateTime.utc(picked.year, picked.month, picked.day);
    if (arrival) {
      _arrivalDay = day;
    } else {
      _departureDay = day;
    }
    _changed();
  }

  String _dayLabel(DateTime day) =>
      '${_weekdayLetters[day.weekday]} ${day.day}.${day.month}';

  Widget _dateField({required bool arrival}) {
    final day = arrival ? _arrivalDay : _departureDay;
    return InkWell(
      onTap: () => _pickDay(arrival: arrival),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: day == null,
        decoration: const InputDecoration(
          labelText: 'תאריך',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(day == null ? '' : _dayLabel(day)),
      ),
    );
  }

  Widget _row({required bool arrival}) {
    final dateField = _dateField(arrival: arrival);
    final timeField = EventTimeField(
      controller: arrival ? _arrivalTime : _departureTime,
      label: 'שעה',
      hint: 'למשל 14:00',
      logKey: arrival ? 'customArrival' : 'customDeparture',
      onChanged: _changed,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          arrival ? _arrivalLabel : _departureLabel,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 300) {
              return Column(
                children: [dateField, const SizedBox(height: 8), timeField],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: dateField),
                const SizedBox(width: 8),
                Expanded(child: timeField),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _evaluate().error;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(arrival: true),
          const SizedBox(height: 12),
          _row(arrival: false),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'שעות האירוע: ${formatCustomHours(eventStretch(widget.event))}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
