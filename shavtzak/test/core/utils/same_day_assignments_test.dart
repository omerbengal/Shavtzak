import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/same_day_assignments.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';

void main() {
  group('eventsShareDay', () {
    test('two single-day events on the same date share a day', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 12)),
          _event(id: 'b', start: DateTime(2026, 7, 12)),
        ),
        isTrue,
      );
    });

    test('two single-day events on different dates do not share a day', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 12)),
          _event(id: 'b', start: DateTime(2026, 7, 13)),
        ),
        isFalse,
      );
    });

    test('a multi-day event overlapping by one day shares a day', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 5), end: DateTime(2026, 7, 7)),
          _event(id: 'b', start: DateTime(2026, 7, 7)),
        ),
        isTrue,
      );
    });

    test('back-to-back events do not share a day', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 5), end: DateTime(2026, 7, 6)),
          _event(id: 'b', start: DateTime(2026, 7, 7)),
        ),
        isFalse,
      );
    });

    test('times of day are ignored', () {
      expect(
        eventsShareDay(
          _event(id: 'a', start: DateTime(2026, 7, 12, 8), end: DateTime(2026, 7, 12, 11)),
          _event(id: 'b', start: DateTime(2026, 7, 12, 20), end: DateTime(2026, 7, 12, 23)),
        ),
        isTrue,
      );
    });
  });

  group('sameDayOtherEventsByMember', () {
    test('maps a member assigned to another event on the same day', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final evening =
          _event(id: 'evening', name: 'מופע ערב', start: DateTime(2026, 7, 12));

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm1'),
        ],
      );

      expect(result.keys, ['m1']);
      expect(result['m1']!.map((e) => e.id), ['evening']);
    });

    test('omits a member who is only assigned to this event, and one who is '
        'only assigned to the other', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final evening = _event(id: 'evening', start: DateTime(2026, 7, 12));

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm2'),
        ],
      );

      // m1 is in summer but nowhere else. m2 is in evening but NOT in summer —
      // m2 must not be credited to summer at all: the map answers "who, of the
      // people assigned to THIS event, is also booked elsewhere".
      expect(result, isEmpty);
    });

    test('omits a member whose other event is on a different day', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final nextDay = _event(id: 'nextDay', start: DateTime(2026, 7, 13));

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, nextDay],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'nextDay', memberId: 'm1'),
        ],
      );

      expect(result, isEmpty);
    });

    test('never counts a deactivated event as the other event', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final onHold = _event(
        id: 'onHold',
        start: DateTime(2026, 7, 12),
        isDeactivated: true,
      );

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, onHold],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'onHold', memberId: 'm1'),
        ],
      );

      expect(result, isEmpty);
    });

    test('lists the other event once even when the member holds two roles in it',
        () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final evening = _event(id: 'evening', start: DateTime(2026, 7, 12));

      final result = sameDayOtherEventsByMember(
        event: summer,
        allEvents: [summer, evening],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm1', roleType: 'medic'),
          _assignment(id: 'a3', eventId: 'evening', memberId: 'm1', roleType: 'commander'),
        ],
      );

      expect(result['m1']!.map((e) => e.id), ['evening']);
    });

    test('sorts other events by start date, then by name', () {
      final anchor = _event(
        id: 'anchor',
        start: DateTime(2026, 7, 12),
        end: DateTime(2026, 7, 14),
      );
      final late = _event(id: 'late', name: 'אאא', start: DateTime(2026, 7, 14));
      final earlyB = _event(id: 'earlyB', name: 'בבב', start: DateTime(2026, 7, 12));
      final earlyA = _event(id: 'earlyA', name: 'aaa', start: DateTime(2026, 7, 12));

      final result = sameDayOtherEventsByMember(
        event: anchor,
        allEvents: [anchor, late, earlyB, earlyA],
        allAssignments: [
          _assignment(id: 'a1', eventId: 'anchor', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'late', memberId: 'm1'),
          _assignment(id: 'a3', eventId: 'earlyB', memberId: 'm1'),
          _assignment(id: 'a4', eventId: 'earlyA', memberId: 'm1'),
        ],
      );

      expect(result['m1']!.map((e) => e.id), ['earlyA', 'earlyB', 'late']);
    });
  });

  group('buildSameDayOtherEventsIndex', () {
    test('is symmetric: each event names the other', () {
      final summer = _event(id: 'summer', name: 'אירוע קיץ', start: DateTime(2026, 7, 12));
      final evening = _event(id: 'evening', name: 'מופע ערב', start: DateTime(2026, 7, 12));

      final index = buildSameDayOtherEventsIndex(
        events: [summer, evening],
        assignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm1'),
        ],
      );

      expect(index['summer']!['m1']!.map((e) => e.id), ['evening']);
      expect(index['evening']!['m1']!.map((e) => e.id), ['summer']);
    });

    test('omits events that have no double-booked member', () {
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final evening = _event(id: 'evening', start: DateTime(2026, 7, 12));

      final index = buildSameDayOtherEventsIndex(
        events: [summer, evening],
        assignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'evening', memberId: 'm2'),
        ],
      );

      expect(index, isEmpty);
    });

    test('a deactivated event never appears as an anchor (no index entry for it)',
        () {
      // Both callers of this function pre-filter isDeactivated today, which
      // makes this unreachable in practice — but the function is public, its
      // own doc only promises "deactivated events never count as the OTHER
      // event", says nothing about the anchor, and the TypeScript port
      // (buildSameDayOtherEventNames) filters both sides. This pins the Dart
      // side to the same contract.
      //
      // Without the anchor-side skip, iterating onHold as an anchor would
      // still find summer as its OTHER event (the candidate-side filter only
      // excludes a deactivated CANDIDATE, and summer is not deactivated), and
      // m1 is assigned to both — so index['onHold'] would wrongly appear. This
      // is NOT symmetric with summer's own (correctly absent) entry: summer is
      // absent because onHold is filtered out as its candidate, a mechanism
      // this test does not touch. Only onHold's presence/absence depends on
      // the anchor-side skip under test.
      final summer = _event(id: 'summer', start: DateTime(2026, 7, 12));
      final onHold = _event(
        id: 'onHold',
        start: DateTime(2026, 7, 12),
        isDeactivated: true,
      );

      final index = buildSameDayOtherEventsIndex(
        events: [summer, onHold],
        assignments: [
          _assignment(id: 'a1', eventId: 'summer', memberId: 'm1'),
          _assignment(id: 'a2', eventId: 'onHold', memberId: 'm1'),
        ],
      );

      expect(index.containsKey('onHold'), isFalse,
          reason: 'a deactivated event must never be an anchor, even though '
              'the member assigned to it is genuinely double-booked');
      expect(index, isEmpty);
    });
  });

  group('eventDays', () {
    test('a single-day event is one local date', () {
      expect(
        eventDays(_event(id: 'a', start: DateTime(2026, 10, 27, 18))),
        DayRange(DateTime(2026, 10, 27), DateTime(2026, 10, 27)),
      );
    });

    test('a multi-day event runs from its first to its last date', () {
      expect(
        eventDays(_event(
          id: 'a',
          start: DateTime(2026, 12, 1, 20),
          end: DateTime(2026, 12, 2, 3),
        )),
        DayRange(DateTime(2026, 12, 1), DateTime(2026, 12, 2)),
      );
    });
  });

  group('dayRangesOverlap', () {
    DayRange range(DateTime first, [DateTime? last]) =>
        DayRange(first, last ?? first);

    test('is inclusive: a shared edge day overlaps', () {
      expect(
        dayRangesOverlap(
          range(DateTime(2026, 7, 5), DateTime(2026, 7, 7)),
          range(DateTime(2026, 7, 7)),
        ),
        isTrue,
      );
    });

    test('back-to-back ranges do not overlap', () {
      expect(
        dayRangesOverlap(
          range(DateTime(2026, 7, 5), DateTime(2026, 7, 6)),
          range(DateTime(2026, 7, 7)),
        ),
        isFalse,
      );
    });

    test('a range inside another overlaps, both ways', () {
      final outer = range(DateTime(2026, 7, 1), DateTime(2026, 7, 31));
      final inner = range(DateTime(2026, 7, 12));
      expect(dayRangesOverlap(outer, inner), isTrue);
      expect(dayRangesOverlap(inner, outer), isTrue);
    });

    test('adjacent days around the October DST change do not overlap', () {
      // Israel's clocks go back on 2026-10-25. Adding 24 hours to a local
      // midnight would drift; `!isAfter` on date-only values has no such
      // hazard.
      expect(
        dayRangesOverlap(
          range(DateTime(2026, 10, 24)),
          range(DateTime(2026, 10, 25)),
        ),
        isFalse,
      );
      expect(
        dayRangesOverlap(
          range(DateTime(2026, 10, 24), DateTime(2026, 10, 25)),
          range(DateTime(2026, 10, 25)),
        ),
        isTrue,
      );
    });
  });

  group('assignmentDays', () {
    final event = _event(
      id: 'a',
      start: DateTime(2026, 10, 27),
      end: DateTime(2026, 10, 28),
    );

    test("without hours it is the event's days", () {
      expect(
        assignmentDays(
            _assignment(id: 'a1', eventId: 'a', memberId: 'm1'), event),
        eventDays(event),
      );
    });

    test('hours ending exactly at midnight stay on the first day', () {
      final assignment = _assignment(
        id: 'a1',
        eventId: 'a',
        memberId: 'm1',
        customStartAt: '2026-10-27T18:00',
        customEndAt: '2026-10-28T00:00',
      );
      expect(
        assignmentDays(assignment, event),
        DayRange(DateTime(2026, 10, 27), DateTime(2026, 10, 27)),
      );
    });

    test('hours ending a minute past midnight reach the next day', () {
      final assignment = _assignment(
        id: 'a1',
        eventId: 'a',
        memberId: 'm1',
        customStartAt: '2026-10-27T18:00',
        customEndAt: '2026-10-28T00:01',
      );
      expect(
        assignmentDays(assignment, event),
        DayRange(DateTime(2026, 10, 27), DateTime(2026, 10, 28)),
      );
    });

    test('hours across the DST change run from the start day to the end day',
        () {
      final assignment = _assignment(
        id: 'a1',
        eventId: 'a',
        memberId: 'm1',
        customStartAt: '2026-10-24T22:00',
        customEndAt: '2026-10-26T02:00',
      );
      expect(
        assignmentDays(assignment, event),
        DayRange(DateTime(2026, 10, 24), DateTime(2026, 10, 26)),
      );
    });

    test("hours may lie outside the event's own days", () {
      final assignment = _assignment(
        id: 'a1',
        eventId: 'a',
        memberId: 'm1',
        customStartAt: '2026-10-26T22:00',
        customEndAt: '2026-10-27T06:00',
      );
      expect(
        assignmentDays(assignment, event),
        DayRange(DateTime(2026, 10, 26), DateTime(2026, 10, 27)),
      );
    });

    test("hours that cannot be read fall back to the event's days", () {
      final assignment = _assignment(
        id: 'a1',
        eventId: 'a',
        memberId: 'm1',
        customStartAt: 'soon',
        customEndAt: '2026-10-28T00:00',
      );
      expect(assignmentDays(assignment, event), eventDays(event));
    });
  });

  group('same-day detection with custom hours', () {
    final first = _event(
        id: 'A', start: DateTime(2026, 12, 1), end: DateTime(2026, 12, 2));
    final second = _event(id: 'B', start: DateTime(2026, 12, 2));

    test('hours on day 1 only: neither event names the other', () {
      final assignments = [
        _assignment(
          id: 'a1',
          eventId: 'A',
          memberId: 'm1',
          customStartAt: '2026-12-01T10:00',
          customEndAt: '2026-12-01T20:00',
        ),
        _assignment(id: 'a2', eventId: 'B', memberId: 'm1'),
      ];

      expect(
        sameDayOtherEventsByMember(
          event: first,
          allEvents: [first, second],
          allAssignments: assignments,
        ),
        isEmpty,
      );
      expect(
        sameDayOtherEventsByMember(
          event: second,
          allEvents: [first, second],
          allAssignments: assignments,
        ),
        isEmpty,
      );
      expect(
        buildSameDayOtherEventsIndex(
          events: [first, second],
          assignments: assignments,
        ),
        isEmpty,
      );
    });

    test('without the hours, both name each other', () {
      final assignments = [
        _assignment(id: 'a1', eventId: 'A', memberId: 'm1'),
        _assignment(id: 'a2', eventId: 'B', memberId: 'm1'),
      ];

      final fromFirst = sameDayOtherEventsByMember(
        event: first,
        allEvents: [first, second],
        allAssignments: assignments,
      );
      final fromSecond = sameDayOtherEventsByMember(
        event: second,
        allEvents: [first, second],
        allAssignments: assignments,
      );

      expect(fromFirst['m1']!.map((e) => e.id), ['B']);
      expect(fromSecond['m1']!.map((e) => e.id), ['A']);
    });

    test("hours that reach into the other event's day name it, both ways", () {
      final assignments = [
        _assignment(
          id: 'a1',
          eventId: 'A',
          memberId: 'm1',
          customStartAt: '2026-12-01T20:00',
          customEndAt: '2026-12-02T02:00',
        ),
        _assignment(id: 'a2', eventId: 'B', memberId: 'm1'),
      ];

      final index = buildSameDayOtherEventsIndex(
        events: [first, second],
        assignments: assignments,
      );

      expect(index['A']!['m1']!.map((e) => e.id), ['B']);
      expect(index['B']!['m1']!.map((e) => e.id), ['A']);
    });

    test("the other event's own hours decide its days", () {
      Map<String, List<Event>> namedFromA(String start, String end) =>
          sameDayOtherEventsByMember(
            event: first,
            allEvents: [first, second],
            allAssignments: [
              _assignment(id: 'a1', eventId: 'A', memberId: 'm1'),
              _assignment(
                id: 'a2',
                eventId: 'B',
                memberId: 'm1',
                customStartAt: start,
                customEndAt: end,
              ),
            ],
          );

      // A holds the member on 1-2 December. B's own dates are the 2nd, but
      // its hours say the 3rd: no shared day.
      expect(namedFromA('2026-12-03T08:00', '2026-12-03T12:00'), isEmpty);
      // B's hours start on the 1st: a shared day.
      expect(
        namedFromA('2026-12-01T22:00', '2026-12-02T04:00')['m1']!
            .map((e) => e.id),
        ['B'],
      );
    });

    test("hours outside the event's own days still find another event", () {
      // Arriving the evening before the event: the member is booked on the
      // 30th, which the event's own dates do not cover.
      final earlier = _event(id: 'earlier', start: DateTime(2026, 11, 30));
      final assignments = [
        _assignment(
          id: 'a1',
          eventId: 'A',
          memberId: 'm1',
          customStartAt: '2026-11-30T21:00',
          customEndAt: '2026-12-01T05:00',
        ),
        _assignment(id: 'a2', eventId: 'earlier', memberId: 'm1'),
      ];

      expect(
        sameDayOtherEventsByMember(
          event: first,
          allEvents: [first, earlier],
          allAssignments: assignments,
        )['m1']!
            .map((e) => e.id),
        ['earlier'],
      );
    });

    test('a member with two roles in the event is judged by the union of '
        'their days', () {
      final assignments = [
        _assignment(
          id: 'a1',
          eventId: 'A',
          memberId: 'm1',
          customStartAt: '2026-12-01T10:00',
          customEndAt: '2026-12-01T20:00',
        ),
        _assignment(
          id: 'a1b',
          eventId: 'A',
          memberId: 'm1',
          roleType: 'driver',
          customStartAt: '2026-12-02T10:00',
          customEndAt: '2026-12-02T20:00',
        ),
        _assignment(id: 'a2', eventId: 'B', memberId: 'm1'),
      ];

      expect(
        sameDayOtherEventsByMember(
          event: first,
          allEvents: [first, second],
          allAssignments: assignments,
        )['m1']!
            .map((e) => e.id),
        ['B'],
      );
    });
  });

  group('assignmentOverlapsEventDays', () {
    final multiDay = _event(
      id: 'multi',
      start: DateTime(2026, 10, 27),
      end: DateTime(2026, 10, 28),
    );
    final day2 = _event(id: 'day2', start: DateTime(2026, 10, 28));
    final day1 = _event(id: 'day1', start: DateTime(2026, 10, 27));

    test('without hours the assignment holds every day of its event', () {
      final a = _assignment(id: 'a1', eventId: 'multi', memberId: 'm1');

      expect(assignmentOverlapsEventDays(a, multiDay, day1), isTrue);
      expect(assignmentOverlapsEventDays(a, multiDay, day2), isTrue);
    });

    test('hours on day 1 only do not overlap an event on day 2', () {
      final a = _assignment(
        id: 'a1',
        eventId: 'multi',
        memberId: 'm1',
        customStartAt: '2026-10-27T10:00',
        customEndAt: '2026-10-27T16:00',
      );

      expect(assignmentOverlapsEventDays(a, multiDay, day1), isTrue);
      expect(assignmentOverlapsEventDays(a, multiDay, day2), isFalse);
    });

    test('the event being filled is judged by all of its days', () {
      final a = _assignment(
        id: 'a1',
        eventId: 'multi',
        memberId: 'm1',
        customStartAt: '2026-10-27T10:00',
        customEndAt: '2026-10-27T16:00',
      );
      final spansBoth = _event(
        id: 'both',
        start: DateTime(2026, 10, 27),
        end: DateTime(2026, 10, 28),
      );

      expect(assignmentOverlapsEventDays(a, multiDay, spansBoth), isTrue);
    });

    test('hours that reach outside the event reach the neighbouring event', () {
      // Arriving the evening before: the booking's days start on 26/10.
      final a = _assignment(
        id: 'a1',
        eventId: 'multi',
        memberId: 'm1',
        customStartAt: '2026-10-26T20:00',
        customEndAt: '2026-10-27T12:00',
      );
      final before = _event(id: 'before', start: DateTime(2026, 10, 26));

      expect(assignmentOverlapsEventDays(a, multiDay, before), isTrue);
    });
  });
}

Event _event({
  required String id,
  required DateTime start,
  DateTime? end,
  String name = 'אירוע',
  bool isDeactivated = false,
}) {
  final now = DateTime(2026, 7, 1);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: end ?? start,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
    isDeactivated: isDeactivated,
  );
}

Assignment _assignment({
  required String id,
  required String eventId,
  required String memberId,
  String roleType = 'medic',
  int slotIndex = 0,
  String? customStartAt,
  String? customEndAt,
}) {
  final now = DateTime(2026, 7, 1);
  return Assignment(
    id: id,
    eventId: eventId,
    teamMemberId: memberId,
    roleType: roleType,
    slotIndex: slotIndex,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
    customStartAt: customStartAt,
    customEndAt: customEndAt,
  );
}
