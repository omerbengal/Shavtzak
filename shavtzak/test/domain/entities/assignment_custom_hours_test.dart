// An assignment's own hours (custom hours): the two stored strings, the window
// they make, and how that window changes the availability check.
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

void main() {
  group('customWindow and hasCustomHours', () {
    test('no hours: no window', () {
      final assignment = _assignment();
      expect(assignment.customWindow, isNull);
      expect(assignment.hasCustomHours, isFalse);
    });

    test('readable hours make the window', () {
      final assignment = _assignment(
        customStartAt: '2026-10-27T14:00',
        customEndAt: '2026-10-27T23:00',
      );
      expect(
        assignment.customWindow,
        WallInterval(DateTime.utc(2026, 10, 27, 14), DateTime.utc(2026, 10, 27, 23)),
      );
      expect(assignment.hasCustomHours, isTrue);
    });

    test('hours that cannot be read are no hours, and never throw', () {
      expect(
        _assignment(customStartAt: '27.10 14:00', customEndAt: '2026-10-27T23:00')
            .hasCustomHours,
        isFalse,
      );
      expect(_assignment(customStartAt: '2026-10-27T14:00').hasCustomHours, isFalse);
    });

    test('an end that is not after the start is no hours', () {
      expect(
        _assignment(
          customStartAt: '2026-10-27T14:00',
          customEndAt: '2026-10-27T14:00',
        ).hasCustomHours,
        isFalse,
      );
      expect(
        _assignment(
          customStartAt: '2026-10-27T14:00',
          customEndAt: '2026-10-27T09:00',
        ).hasCustomHours,
        isFalse,
      );
    });
  });

  group('windowIn', () {
    final event = _event(DateTime(2026, 10, 27));

    test('without hours it is the event stretch', () {
      expect(_assignment().windowIn(event), eventStretch(event));
    });

    test('with hours it is those hours', () {
      final assignment = _assignment(
        customStartAt: '2026-10-27T19:00',
        customEndAt: '2026-10-27T21:00',
      );
      expect(
        assignment.windowIn(event),
        WallInterval(DateTime.utc(2026, 10, 27, 19), DateTime.utc(2026, 10, 27, 21)),
      );
    });

    test('unreadable hours fall back to the stretch', () {
      final assignment = _assignment(
        customStartAt: 'nope',
        customEndAt: '2026-10-27T21:00',
      );
      expect(assignment.windowIn(event), eventStretch(event));
    });
  });

  group('hasAvailabilityConflict judges the assignment window', () {
    final event = _event(DateTime(2026, 10, 27)); // 17:00 – 22:00
    // Unavailable 27.10 from 08:00 to 12:00: before the event begins.
    final morning = _unavailability(
      DateTime(2026, 10, 27),
      status: ConstraintStatus.approved,
      startTime: '08:00',
      endTime: '12:00',
    );

    test('no hours: the morning constraint misses the event', () {
      final assignment = _assignment(event: event, teamMember: _member([morning]));
      expect(assignment.hasAvailabilityConflict(), isFalse);
    });

    test('hours that reach into the constraint conflict', () {
      final assignment = _assignment(
        event: event,
        teamMember: _member([morning]),
        customStartAt: '2026-10-27T10:00',
        customEndAt: '2026-10-27T20:00',
      );
      expect(assignment.hasAvailabilityConflict(), isTrue);
      expect(assignment.hasConflicts, isTrue);
    });

    test('hours that stop before a whole-day constraint do not conflict', () {
      final nextDay = _unavailability(
        DateTime(2026, 10, 28),
        status: ConstraintStatus.pending,
      );
      final clear = _assignment(
        event: event,
        teamMember: _member([nextDay]),
        customStartAt: '2026-10-27T18:00',
        customEndAt: '2026-10-28T00:00',
      );
      expect(clear.hasAvailabilityConflict(), isFalse);

      final reaching = _assignment(
        event: event,
        teamMember: _member([nextDay]),
        customStartAt: '2026-10-27T18:00',
        customEndAt: '2026-10-28T02:00',
      );
      expect(reaching.hasAvailabilityConflict(), isTrue);
    });
  });

  group('copyWith', () {
    final base = _assignment(
      customStartAt: '2026-10-27T14:00',
      customEndAt: '2026-10-27T23:00',
    );

    test('leaving the hours out keeps them', () {
      final copy = base.copyWith(notes: 'x');
      expect(copy.customStartAt, '2026-10-27T14:00');
      expect(copy.customEndAt, '2026-10-27T23:00');
    });

    test('a sentinel sets the hours', () {
      final copy = base.copyWith(
        customStartAt: () => '2026-10-27T15:00',
        customEndAt: () => '2026-10-27T22:00',
      );
      expect(copy.customStartAt, '2026-10-27T15:00');
      expect(copy.customEndAt, '2026-10-27T22:00');
    });

    test('a sentinel returning null clears the field', () {
      final copy = base.copyWith(
        customStartAt: () => null,
        customEndAt: () => null,
      );
      expect(copy.customStartAt, isNull);
      expect(copy.customEndAt, isNull);
      expect(copy.hasCustomHours, isFalse);
    });

    test('clearing one field leaves the other', () {
      final copy = base.copyWith(customStartAt: () => null);
      expect(copy.customStartAt, isNull);
      expect(copy.customEndAt, '2026-10-27T23:00');
    });
  });

  group('props', () {
    test('differ when only customEndAt differs', () {
      final a = _assignment(
        customStartAt: '2026-10-27T14:00',
        customEndAt: '2026-10-27T23:00',
      );
      final b = a.copyWith(customEndAt: () => '2026-10-27T22:00');
      expect(a, isNot(equals(b)));
    });

    test('differ when only customStartAt differs', () {
      final a = _assignment(
        customStartAt: '2026-10-27T14:00',
        customEndAt: '2026-10-27T23:00',
      );
      final b = a.copyWith(customStartAt: () => '2026-10-27T15:00');
      expect(a, isNot(equals(b)));
    });

    test('same hours are equal', () {
      expect(
        _assignment(customStartAt: '2026-10-27T14:00', customEndAt: '2026-10-27T23:00'),
        _assignment(customStartAt: '2026-10-27T14:00', customEndAt: '2026-10-27T23:00'),
      );
    });
  });

  group('withRelations', () {
    test('keeps both hours fields', () {
      final base = _assignment(
        customStartAt: '2026-10-27T14:00',
        customEndAt: '2026-10-27T23:00',
      );
      final related = base.withRelations(
        event: _event(DateTime(2026, 10, 27)),
        teamMember: _member(const []),
      );
      expect(related.customStartAt, '2026-10-27T14:00');
      expect(related.customEndAt, '2026-10-27T23:00');
      expect(related.event, isNotNull);
    });
  });
}

Assignment _assignment({
  String? customStartAt,
  String? customEndAt,
  Event? event,
  TeamMember? teamMember,
}) {
  final now = DateTime(2026, 10, 1);
  return Assignment(
    id: 'a1',
    eventId: 'e1',
    teamMemberId: 'm1',
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
    customStartAt: customStartAt,
    customEndAt: customEndAt,
    event: event,
    teamMember: teamMember,
  );
}

Event _event(DateTime day) {
  final now = DateTime(2026, 10, 1);
  return Event(
    id: 'e1',
    name: 'אירוע',
    startDate: day,
    endDate: day,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}

DateConstraint _unavailability(
  DateTime day, {
  required ConstraintStatus status,
  String? startTime,
  String? endTime,
}) {
  return DateConstraint(
    id: 'c-${day.day}',
    startDate: day,
    endDate: day,
    status: status,
    constraintType: ConstraintType.unavailability,
    startTime: startTime,
    endTime: endTime,
  );
}

TeamMember _member(List<DateConstraint> constraints) {
  final now = DateTime(2026, 10, 1);
  return TeamMember(
    id: 'm1',
    name: 'חבר',
    isActive: true,
    isPermanent: true,
    constraints: constraints,
    roleCapabilities: const {'medic': true},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'k1',
  );
}
