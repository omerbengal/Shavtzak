import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/event_constraint_collisions.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

void main() {
  final event = _event(start: DateTime(2026, 11, 5));

  group('findEventConstraintCollisions', () {
    test('includes approved, pending and rejected constraints, sorted', () {
      final result = findEventConstraintCollisions(
        event: event,
        members: [
          _member('בני', [
            _constraint('rejected', DateTime(2026, 11, 5),
                ConstraintStatus.rejected),
          ]),
          _member('אבי', [
            _constraint('pending', DateTime(2026, 11, 5),
                ConstraintStatus.pending),
          ]),
          _member('גדי', [
            _constraint('approved', DateTime(2026, 11, 5),
                ConstraintStatus.approved),
          ]),
        ],
      );

      expect(result.map((c) => c.constraint.id),
          ['approved', 'pending', 'rejected']);
    });

    test('skips other days and non-overlapping hours', () {
      final result = findEventConstraintCollisions(
        event: event,
        members: [
          _member('אבי', [
            _constraint('other-day', DateTime(2026, 11, 6),
                ConstraintStatus.approved),
            _constraint('morning', DateTime(2026, 11, 5),
                ConstraintStatus.approved,
                startTime: '08:00', endTime: '12:00'),
            _constraint('evening', DateTime(2026, 11, 5),
                ConstraintStatus.approved,
                startTime: '19:00', endTime: '23:00'),
          ]),
        ],
      );

      expect(result.map((c) => c.constraint.id), ['evening']);
    });

    test('the event starts at its assembly time, not its start time', () {
      // Assembly 17:00, start 18:00: a constraint until 17:30 collides.
      final result = findEventConstraintCollisions(
        event: event,
        members: [
          _member('אבי', [
            _constraint('until-1730', DateTime(2026, 11, 5),
                ConstraintStatus.approved,
                startTime: '12:00', endTime: '17:30'),
          ]),
        ],
      );

      expect(result.map((c) => c.constraint.id), ['until-1730']);
    });

    test('counts a recurring constraint on a matching day', () {
      final weekly = DateConstraint(
        id: 'weekly',
        startDate: DateTime(2026, 10, 1),
        status: ConstraintStatus.approved,
        constraintType: ConstraintType.unavailability,
        repeatType: RepeatType.weekly,
        repeatDay: DateTime(2026, 11, 5).weekday,
        repeatEndDate: DateTime(2026, 12, 31),
      );

      final result = findEventConstraintCollisions(
        event: event,
        members: [
          _member('אבי', [weekly])
        ],
      );

      expect(result.map((c) => c.constraint.id), ['weekly']);
    });

    test('ignores non-permanent, inactive and archived members', () {
      final c =
          _constraint('c', DateTime(2026, 11, 5), ConstraintStatus.approved);
      final result = findEventConstraintCollisions(
        event: event,
        members: [
          _member('זמני', [c], isPermanent: false),
          _member('לא פעיל', [c], isActive: false),
          _member('בארכיון', [c], isArchived: true),
        ],
      );

      expect(result, isEmpty);
    });
  });

  group('members assigned with custom hours', () {
    // A two-day event with no times: its stretch is the two whole days.
    final day1 = DateTime(2026, 11, 5);
    final day2 = DateTime(2026, 11, 6);
    final twoDays = _twoDayEvent(day1, day2);
    final day2Constraint =
        _constraint('day2', day2, ConstraintStatus.approved);

    List<String> ids(List<EventConstraintCollision> result) =>
        result.map((c) => c.constraint.id).toList();

    test(
        'a member assigned with day-1 hours is not listed for a day-2 '
        'constraint', () {
      final result = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [day2Constraint])
        ],
        assignments: [
          _assignment('a1', 'אבי',
              eventId: twoDays.id,
              start: '2026-11-05T09:00',
              end: '2026-11-05T17:00'),
        ],
      );

      expect(result, isEmpty);
    });

    test('an unassigned member is listed for the same constraint', () {
      final result = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [day2Constraint])
        ],
        assignments: [
          _assignment('a1', 'מישהו אחר',
              eventId: twoDays.id,
              start: '2026-11-05T09:00',
              end: '2026-11-05T17:00'),
        ],
      );

      expect(ids(result), ['day2']);
    });

    test('with no assignments given, every member is judged by the event', () {
      final result = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [day2Constraint])
        ],
      );

      expect(ids(result), ['day2']);
    });

    test('an assigned member without hours is judged by the event', () {
      final result = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [day2Constraint])
        ],
        assignments: [_assignment('a1', 'אבי', eventId: twoDays.id)],
      );

      expect(ids(result), ['day2']);
    });

    test('unreadable hours are judged by the event', () {
      final result = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [day2Constraint])
        ],
        assignments: [
          _assignment('a1', 'אבי',
              eventId: twoDays.id, start: 'bad', end: '2026-11-05T17:00'),
        ],
      );

      expect(ids(result), ['day2']);
    });

    test(
        'hours ending when the constraint starts do not collide, hours '
        'overlapping it by a minute do', () {
      final evening = _constraint('evening', day1, ConstraintStatus.pending,
          startTime: '18:00', endTime: '22:00');

      final before = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [evening])
        ],
        assignments: [
          _assignment('a1', 'אבי',
              eventId: twoDays.id,
              start: '2026-11-05T09:00',
              end: '2026-11-05T18:00'),
        ],
      );
      final during = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [evening])
        ],
        assignments: [
          _assignment('a1', 'אבי',
              eventId: twoDays.id,
              start: '2026-11-05T09:00',
              end: '2026-11-05T18:01'),
        ],
      );

      expect(before, isEmpty);
      expect(ids(during), ['evening']);
    });

    test('a pending or rejected constraint inside the hours is still listed',
        () {
      final result = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [
            _constraint('pending', day2, ConstraintStatus.pending),
            _constraint('rejected', day2, ConstraintStatus.rejected),
          ])
        ],
        assignments: [
          _assignment('a1', 'אבי',
              eventId: twoDays.id,
              start: '2026-11-06T09:00',
              end: '2026-11-06T12:00'),
        ],
      );

      expect(ids(result), ['pending', 'rejected']);
    });

    test('a recurring constraint is judged against the hours too', () {
      final weeklyOnDay2 = DateConstraint(
        id: 'weekly',
        startDate: DateTime(2026, 10, 1),
        status: ConstraintStatus.approved,
        constraintType: ConstraintType.unavailability,
        repeatType: RepeatType.weekly,
        repeatDay: day2.weekday,
        repeatEndDate: DateTime(2026, 12, 31),
      );

      final day1Hours = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [weeklyOnDay2])
        ],
        assignments: [
          _assignment('a1', 'אבי',
              eventId: twoDays.id,
              start: '2026-11-05T09:00',
              end: '2026-11-05T17:00'),
        ],
      );
      final day2Hours = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [weeklyOnDay2])
        ],
        assignments: [
          _assignment('a1', 'אבי',
              eventId: twoDays.id,
              start: '2026-11-06T09:00',
              end: '2026-11-06T17:00'),
        ],
      );

      expect(day1Hours, isEmpty);
      expect(ids(day2Hours), ['weekly']);
    });

    test('an assignment in another event does not narrow this event', () {
      final result = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('אבי', [day2Constraint])
        ],
        assignments: [
          _assignment('a1', 'אבי',
              eventId: 'other-event',
              start: '2026-11-05T09:00',
              end: '2026-11-05T17:00'),
        ],
      );

      expect(ids(result), ['day2']);
    });

    group('a member in several roles of the event', () {
      test('is listed when the constraint hits any one of their windows', () {
        final result = findEventConstraintCollisions(
          event: twoDays,
          members: [
            _member('אבי', [day2Constraint])
          ],
          assignments: [
            _assignment('a1', 'אבי',
                eventId: twoDays.id,
                start: '2026-11-05T09:00',
                end: '2026-11-05T17:00'),
            _assignment('a2', 'אבי',
                eventId: twoDays.id,
                slotIndex: 1,
                start: '2026-11-06T09:00',
                end: '2026-11-06T17:00'),
          ],
        );

        expect(ids(result), ['day2']);
      });

      test('is not listed when the constraint misses every window', () {
        final result = findEventConstraintCollisions(
          event: twoDays,
          members: [
            _member('אבי', [day2Constraint])
          ],
          assignments: [
            _assignment('a1', 'אבי',
                eventId: twoDays.id,
                start: '2026-11-05T09:00',
                end: '2026-11-05T12:00'),
            _assignment('a2', 'אבי',
                eventId: twoDays.id,
                slotIndex: 1,
                start: '2026-11-05T14:00',
                end: '2026-11-05T17:00'),
          ],
        );

        expect(result, isEmpty);
      });

      test('is listed when one of the roles has no hours (the whole event)',
          () {
        final result = findEventConstraintCollisions(
          event: twoDays,
          members: [
            _member('אבי', [day2Constraint])
          ],
          assignments: [
            _assignment('a1', 'אבי',
                eventId: twoDays.id,
                start: '2026-11-05T09:00',
                end: '2026-11-05T17:00'),
            _assignment('a2', 'אבי', eventId: twoDays.id, slotIndex: 1),
          ],
        );

        expect(ids(result), ['day2']);
      });
    });

    test('the order stays approved, pending, rejected, then by name', () {
      final result = findEventConstraintCollisions(
        event: twoDays,
        members: [
          _member('בני', [
            _constraint('rejected', day1, ConstraintStatus.rejected),
          ]),
          _member('אבי', [
            _constraint('pending', day1, ConstraintStatus.pending),
          ]),
          _member('גדי', [
            _constraint('approved', day1, ConstraintStatus.approved),
          ]),
        ],
        assignments: [
          _assignment('a1', 'בני',
              eventId: twoDays.id,
              start: '2026-11-05T09:00',
              end: '2026-11-05T12:00'),
        ],
      );

      expect(ids(result), ['approved', 'pending', 'rejected']);
    });
  });
}

Assignment _assignment(
  String id,
  String memberId, {
  String eventId = 'e1',
  int slotIndex = 0,
  String? start,
  String? end,
}) {
  final now = DateTime(2026, 7, 1);
  return Assignment(
    id: id,
    eventId: eventId,
    teamMemberId: memberId,
    roleType: 'medic',
    slotIndex: slotIndex,
    status: AssignmentStatus.confirmed,
    notes: '',
    customStartAt: start,
    customEndAt: end,
    createdAt: now,
    updatedAt: now,
  );
}

Event _twoDayEvent(DateTime first, DateTime last) {
  final now = DateTime(2026, 7, 1);
  return Event(
    id: 'e-two-days',
    name: 'אירוע דו יומי',
    startDate: first,
    endDate: last,
    startTime: '',
    endTime: '',
    assemblyTime: '',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}

DateConstraint _constraint(
  String id,
  DateTime date,
  ConstraintStatus status, {
  String? startTime,
  String? endTime,
}) {
  return DateConstraint(
    id: id,
    startDate: date,
    endDate: date,
    status: status,
    constraintType: ConstraintType.unavailability,
    startTime: startTime,
    endTime: endTime,
  );
}

TeamMember _member(
  String name,
  List<DateConstraint> constraints, {
  bool isPermanent = true,
  bool isActive = true,
  bool isArchived = false,
}) {
  final now = DateTime(2026, 7, 1);
  return TeamMember(
    id: name,
    name: name,
    isActive: isActive,
    isPermanent: isPermanent,
    isArchived: isArchived,
    constraints: constraints,
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: name,
  );
}

Event _event({required DateTime start}) {
  final now = DateTime(2026, 7, 1);
  return Event(
    id: 'e1',
    name: 'אירוע',
    startDate: start,
    endDate: start,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}
