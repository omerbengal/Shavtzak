import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/utils/event_constraint_collisions.dart';
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
