import '../../../../../domain/entities/event.dart';
import '../../../../widgets/map_location_picker.dart';
import 'calendar_share_models.dart';

/// Builds the pure CalendarShareData snapshot from domain events.
///
/// Time semantics mirror calendar_sync_service.syncAppEventToCalendar:
///   separator = actualShowStartTime if non-empty, else startTime
///   allDay    = assemblyTime.isEmpty || endTime.isEmpty
class CalendarShareDataBuilder {
  static CalendarShareEvent buildShareEvent(
    Event event, {
    required DateTime today,
    required bool isContinuation,
  }) {
    final isPast = _dateOnly(event.endDate).isBefore(today);
    if (isContinuation) {
      return CalendarShareEvent(
        name: event.name,
        isPast: isPast,
        isContinuation: true,
      );
    }
    final location = event.location.trim().isEmpty
        ? ''
        : MapLocationResult.stripCoordinates(event.location).trim();
    return CalendarShareEvent(
      name: event.name,
      timeLines: _buildTimeLines(event),
      locationLine: location,
      isPast: isPast,
    );
  }

  static List<String> _buildTimeLines(Event event) {
    final assemblyTime = event.assemblyTime.trim();
    final endTime = event.endTime.trim();
    final actualShowStartTime = event.actualShowStartTime.trim();
    final startTime = event.startTime.trim();

    final separator =
        actualShowStartTime.isNotEmpty ? actualShowStartTime : startTime;
    final allDay = assemblyTime.isEmpty || endTime.isEmpty;
    if (allDay) {
      return const ['כל היום'];
    }

    final lines = <String>[];
    if (assemblyTime.isNotEmpty && separator.isNotEmpty) {
      lines.add('התייצבות $assemblyTime–$separator');
    }
    if (endTime.isNotEmpty &&
        (separator.isNotEmpty || assemblyTime.isNotEmpty)) {
      lines.add(
        separator.isNotEmpty ? 'מופע $separator–$endTime' : 'מופע עד $endTime',
      );
    }
    return lines;
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
