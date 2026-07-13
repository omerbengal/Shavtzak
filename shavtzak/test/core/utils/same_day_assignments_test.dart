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
  );
}
