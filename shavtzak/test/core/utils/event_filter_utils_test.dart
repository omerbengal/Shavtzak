import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/event_filter_utils.dart';
import 'package:shavtzak/domain/entities/event.dart';

void main() {
  group('filterEventsBySearchAndCategory', () {
    final events = [
      _event(id: 'a', name: 'הופעה בפארק', location: 'תל אביב', categoryId: 'c1'),
      _event(id: 'b', name: 'טקס זיכרון', location: 'ירושלים', categoryId: 'c2'),
      _event(id: 'c', name: 'הופעה באולם', location: 'חיפה', categoryId: null),
    ];

    test('empty query and empty categories returns all', () {
      final result = filterEventsBySearchAndCategory(
        events,
        query: '',
        categoryIds: <String>{},
      );
      expect(result.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('search matches event name', () {
      final result = filterEventsBySearchAndCategory(
        events,
        query: 'הופעה',
        categoryIds: <String>{},
      );
      expect(result.map((e) => e.id), ['a', 'c']);
    });

    test('search matches event location', () {
      final result = filterEventsBySearchAndCategory(
        events,
        query: 'ירושלים',
        categoryIds: <String>{},
      );
      expect(result.map((e) => e.id), ['b']);
    });

    test('search is punctuation-insensitive via normalizeForSearch', () {
      final withApostrophe = [
        _event(id: 'x', name: "מג'יק", location: ''),
      ];
      final result = filterEventsBySearchAndCategory(
        withApostrophe,
        query: 'מגיק',
        categoryIds: <String>{},
      );
      expect(result.map((e) => e.id), ['x']);
    });

    test('category filter keeps only matching categories', () {
      final result = filterEventsBySearchAndCategory(
        events,
        query: '',
        categoryIds: {'c1', 'c2'},
      );
      expect(result.map((e) => e.id), ['a', 'b']);
    });

    test('uncategorized events are excluded when a category filter is active', () {
      final result = filterEventsBySearchAndCategory(
        events,
        query: '',
        categoryIds: {'c1'},
      );
      expect(result.map((e) => e.id), ['a']);
    });

    test('search and category filter combine (AND)', () {
      final result = filterEventsBySearchAndCategory(
        events,
        query: 'הופעה',
        categoryIds: {'c1'},
      );
      // Only 'a' is both "הופעה" and category c1 ('c' is uncategorized).
      expect(result.map((e) => e.id), ['a']);
    });
  });

  group('eventIdsInDateRange', () {
    test('single-day event inside the range is included', () {
      final events = [_event(id: 'a', start: DateTime(2026, 7, 15))];
      final result = eventIdsInDateRange(
        events,
        DateTime(2026, 7, 10),
        DateTime(2026, 7, 20),
      );
      expect(result, {'a'});
    });

    test('event outside the range is excluded', () {
      final events = [_event(id: 'a', start: DateTime(2026, 7, 25))];
      final result = eventIdsInDateRange(
        events,
        DateTime(2026, 7, 10),
        DateTime(2026, 7, 20),
      );
      expect(result, isEmpty);
    });

    test('range boundaries are inclusive (start and end days match)', () {
      final events = [
        _event(id: 'start', start: DateTime(2026, 7, 10)),
        _event(id: 'end', start: DateTime(2026, 7, 20)),
      ];
      final result = eventIdsInDateRange(
        events,
        DateTime(2026, 7, 10),
        DateTime(2026, 7, 20),
      );
      expect(result, {'start', 'end'});
    });

    test('boundary comparison ignores time-of-day', () {
      final events = [
        _event(id: 'a', start: DateTime(2026, 7, 20, 23, 30)),
      ];
      final result = eventIdsInDateRange(
        events,
        DateTime(2026, 7, 10, 8),
        DateTime(2026, 7, 20, 6),
      );
      expect(result, {'a'});
    });

    test('multi-day event overlapping the range edge is included', () {
      final events = [
        // Spans 8–12; range is 10–20 → overlaps on 10–12.
        _event(
          id: 'span',
          start: DateTime(2026, 7, 8),
          end: DateTime(2026, 7, 12),
        ),
      ];
      final result = eventIdsInDateRange(
        events,
        DateTime(2026, 7, 10),
        DateTime(2026, 7, 20),
      );
      expect(result, {'span'});
    });

    test('single-day range selects only that day', () {
      final events = [
        _event(id: 'hit', start: DateTime(2026, 7, 15)),
        _event(id: 'miss', start: DateTime(2026, 7, 16)),
      ];
      final result = eventIdsInDateRange(
        events,
        DateTime(2026, 7, 15),
        DateTime(2026, 7, 15),
      );
      expect(result, {'hit'});
    });
  });

  group('eventCoverageDays', () {
    test('single-day event contributes one day', () {
      final days = eventCoverageDays([
        _event(id: 'a', start: DateTime(2026, 7, 15, 18)),
      ]);
      expect(days, {DateTime(2026, 7, 15)});
    });

    test('multi-day event contributes every day inclusive', () {
      final days = eventCoverageDays([
        _event(
          id: 'a',
          start: DateTime(2026, 7, 10),
          end: DateTime(2026, 7, 12),
        ),
      ]);
      expect(days, {
        DateTime(2026, 7, 10),
        DateTime(2026, 7, 11),
        DateTime(2026, 7, 12),
      });
    });
  });

  group('splitEventsByPast', () {
    final today = DateTime(2026, 8, 13);

    test('event ending today is future, event ending yesterday is past', () {
      final result = splitEventsByPast([
        _event(id: 'ends-today', start: DateTime(2026, 8, 13)),
        _event(id: 'ended-yesterday', start: DateTime(2026, 8, 12)),
      ], today);

      expect(result.future.map((e) => e.id), ['ends-today']);
      expect(result.past.map((e) => e.id), ['ended-yesterday']);
    });

    test('multi-day event spanning today is future', () {
      final result = splitEventsByPast([
        _event(
          id: 'spans',
          start: DateTime(2026, 8, 10),
          end: DateTime(2026, 8, 15),
        ),
      ], today);

      expect(result.future.map((e) => e.id), ['spans']);
      expect(result.past, isEmpty);
    });

    test('future list is ascending by date', () {
      final result = splitEventsByPast([
        _event(id: 'later', start: DateTime(2026, 9, 1)),
        _event(id: 'sooner', start: DateTime(2026, 8, 20)),
      ], today);

      expect(result.future.map((e) => e.id), ['sooner', 'later']);
    });

    test('past list is newest-first', () {
      final result = splitEventsByPast([
        _event(id: 'older', start: DateTime(2026, 7, 1)),
        _event(id: 'newer', start: DateTime(2026, 8, 1)),
      ], today);

      expect(result.past.map((e) => e.id), ['newer', 'older']);
    });

    test('same-day future events tie-break on start time then name', () {
      final result = splitEventsByPast([
        _event(id: 'b', start: DateTime(2026, 8, 20), name: 'ב'),
        _event(id: 'a', start: DateTime(2026, 8, 20), name: 'א'),
      ], today);

      expect(result.future.map((e) => e.id), ['a', 'b']);
    });

    test('same-date future events sort by start time before name', () {
      // Names deliberately sort opposite to start time ('א' < 'ב'), so this
      // only passes if the time tie-break actually runs before the name one.
      final result = splitEventsByPast([
        _event(
          id: 'later',
          start: DateTime(2026, 8, 20),
          name: 'א',
          startTime: '20:00',
        ),
        _event(
          id: 'earlier',
          start: DateTime(2026, 8, 20),
          name: 'ב',
          startTime: '09:00',
        ),
      ], today);

      expect(result.future.map((e) => e.id), ['earlier', 'later']);
    });

    test('same-date past events tie-break on name ascending', () {
      final result = splitEventsByPast([
        _event(id: 'b', start: DateTime(2026, 7, 1), name: 'ב'),
        _event(id: 'a', start: DateTime(2026, 7, 1), name: 'א'),
      ], today);

      expect(result.past.map((e) => e.id), ['a', 'b']);
    });

    test('empty input yields two empty lists', () {
      final result = splitEventsByPast(const [], today);

      expect(result.future, isEmpty);
      expect(result.past, isEmpty);
    });
  });
}

Event _event({
  required String id,
  DateTime? start,
  DateTime? end,
  String name = 'אירוע',
  String location = '',
  String? categoryId,
  String startTime = '18:00',
}) {
  final now = DateTime(2026, 7, 1);
  final startDate = start ?? DateTime(2026, 7, 15);
  return Event(
    id: id,
    name: name,
    startDate: startDate,
    endDate: end ?? startDate,
    startTime: startTime,
    endTime: '22:00',
    assemblyTime: '17:00',
    location: location,
    requiresArmed: false,
    categoryId: categoryId,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}
