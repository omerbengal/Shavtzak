import '../../domain/entities/event.dart';
import 'search_utils.dart';

/// Pure helpers shared by the availability screen, the admin availability
/// dialog, and the assignment-export dialog so they filter/select events
/// identically.

/// Filter [events] by a normalized name/location search [query] and a set of
/// selected [categoryIds].
///
/// - Empty [categoryIds] ⇒ no category restriction.
/// - Empty [query] ⇒ no text restriction.
/// - Category match uses [Event.categoryId]; text match uses
///   [normalizeForSearch] against the event name and location.
List<Event> filterEventsBySearchAndCategory(
  List<Event> events, {
  required String query,
  required Set<String> categoryIds,
}) {
  final normalizedQuery = normalizeForSearch(query.trim());
  return events.where((event) {
    if (categoryIds.isNotEmpty &&
        (event.categoryId == null ||
            !categoryIds.contains(event.categoryId))) {
      return false;
    }
    if (normalizedQuery.isEmpty) return true;
    final name = normalizeForSearch(event.name);
    final location = normalizeForSearch(event.location);
    return name.contains(normalizedQuery) ||
        location.contains(normalizedQuery);
  }).toList();
}

/// The IDs of every event in [events] whose date span overlaps the inclusive,
/// date-only range [start]..[end]. A multi-day event is included when any of
/// its days fall inside the range.
Set<String> eventIdsInDateRange(
  List<Event> events,
  DateTime start,
  DateTime end,
) {
  final rangeStart = _dateOnly(start);
  final rangeEnd = _dateOnly(end);
  return events
      .where((event) {
        final eventStart = _dateOnly(event.startDate);
        final eventEnd = _dateOnly(event.endDate);
        // Overlap: event starts on/before the range end AND
        // ends on/after the range start.
        return !eventStart.isAfter(rangeEnd) && !eventEnd.isBefore(rangeStart);
      })
      .map((event) => event.id)
      .toSet();
}

/// The set of individual days (date-only) covered by [events]. Used to
/// red-frame dates that contain events inside the range picker.
Set<DateTime> eventCoverageDays(List<Event> events) {
  final days = <DateTime>{};
  for (final event in events) {
    var day = _dateOnly(event.startDate);
    final end = _dateOnly(event.endDate);
    while (!day.isAfter(end)) {
      days.add(day);
      day = day.add(const Duration(days: 1));
    }
  }
  return days;
}

/// Split [events] into events that have not finished yet and events that are
/// over, relative to [today].
///
/// An event whose `endDate` falls on [today] counts as future — it is still
/// happening. `future` is ordered ascending (start date, then start time, then
/// name) to match the export list; `past` is ordered newest-first, because the
/// most recent history is what an admin reaches for.
///
/// Callers must exclude deactivated events before calling: this helper is
/// purely about dates.
({List<Event> future, List<Event> past}) splitEventsByPast(
  List<Event> events,
  DateTime today,
) {
  final todayDate = _dateOnly(today);
  final future = <Event>[];
  final past = <Event>[];

  for (final event in events) {
    if (_dateOnly(event.endDate).isBefore(todayDate)) {
      past.add(event);
    } else {
      future.add(event);
    }
  }

  future.sort((a, b) {
    final dateCompare = _dateOnly(a.startDate).compareTo(_dateOnly(b.startDate));
    if (dateCompare != 0) return dateCompare;
    final timeCompare = a.startTime.compareTo(b.startTime);
    if (timeCompare != 0) return timeCompare;
    return a.name.compareTo(b.name);
  });

  past.sort((a, b) {
    final dateCompare = _dateOnly(b.startDate).compareTo(_dateOnly(a.startDate));
    if (dateCompare != 0) return dateCompare;
    return a.name.compareTo(b.name);
  });

  return (future: future, past: past);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
