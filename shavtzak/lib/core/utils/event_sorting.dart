import '../../domain/entities/event.dart';

int compareEventsChronologically(Event a, Event b) {
  final startDateCompare = a.startDate.compareTo(b.startDate);
  if (startDateCompare != 0) {
    return startDateCompare;
  }

  final startTimeCompare =
      _compareTimes(a.startTime, b.startTime, emptyLast: true);
  if (startTimeCompare != 0) {
    return startTimeCompare;
  }

  final endDateCompare = a.endDate.compareTo(b.endDate);
  if (endDateCompare != 0) {
    return endDateCompare;
  }

  final endTimeCompare = _compareTimes(a.endTime, b.endTime, emptyLast: true);
  if (endTimeCompare != 0) {
    return endTimeCompare;
  }

  final nameCompare = a.name.compareTo(b.name);
  if (nameCompare != 0) {
    return nameCompare;
  }

  return a.id.compareTo(b.id);
}

int compareEventsChronologicallyDescending(Event a, Event b) {
  return compareEventsChronologically(b, a);
}

int _compareTimes(
  String left,
  String right, {
  required bool emptyLast,
}) {
  final leftMinutes = _parseTimeToMinutes(left);
  final rightMinutes = _parseTimeToMinutes(right);

  if (leftMinutes == null && rightMinutes == null) {
    return 0;
  }
  if (leftMinutes == null) {
    return emptyLast ? 1 : -1;
  }
  if (rightMinutes == null) {
    return emptyLast ? -1 : 1;
  }

  return leftMinutes.compareTo(rightMinutes);
}

int? _parseTimeToMinutes(String value) {
  final trimmedValue = value.trim();
  if (trimmedValue.isEmpty) {
    return null;
  }

  final parts = trimmedValue.split(':');
  if (parts.length != 2) {
    return null;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }

  return (hour * 60) + minute;
}
