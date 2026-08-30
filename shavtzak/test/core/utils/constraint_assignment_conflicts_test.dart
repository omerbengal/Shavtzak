import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/constraint_assignment_conflicts.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

/// "Today" for every test in this file. Events before it are in the past.
final _now = DateTime(2026, 8, 30);

void main() {
  group('findNewlyConflictingAssignments', () {
    test('reports an assignment blocked by a newly approved constraint', () {
      final event = _event(id: 'e1', start: DateTime(2026, 9, 29));
      final pending = _constraint(
        id: 'c1',
        date: DateTime(2026, 9, 29),
        status: ConstraintStatus.pending,
      );

      final result = findNewlyConflictingAssignments(
        originalConstraints: [pending],
        updatedConstraints: [
          pending.copyWith(status: ConstraintStatus.approved),
        ],
        assignments: [_assignment(id: 'a1', event: event)],
        now: _now,
      );

      expect(result.map((a) => a.id), ['a1']);
    });

    test(
        'ignores conflicts caused by untouched constraints — the reported bug: '
        'approving a 29/09 constraint surfaced assignments blocked by two other '
        'constraints the admin never touched (and cannot even see)', () {
      final june = _constraint(
        id: 'june',
        date: DateTime(2026, 6, 11),
        status: ConstraintStatus.approved,
        startTime: '18:30',
        endTime: '22:30',
      );
      final august = _constraint(
        id: 'august',
        date: DateTime(2026, 8, 5),
        status: ConstraintStatus.approved,
      );
      final september = _constraint(
        id: 'september',
        date: DateTime(2026, 9, 29),
        status: ConstraintStatus.pending,
        startTime: '16:00',
        endTime: '23:59',
      );

      final result = findNewlyConflictingAssignments(
        originalConstraints: [june, august, september],
        updatedConstraints: [
          june,
          august,
          september.copyWith(status: ConstraintStatus.approved),
        ],
        assignments: [
          // Both of these are blocked by june/august, which were NOT edited.
          _assignment(
            id: 'megadim',
            event: _event(
              id: 'e-megadim',
              start: DateTime(2026, 6, 11),
              end: DateTime(2026, 6, 13),
            ),
          ),
          _assignment(
            id: 'zoo',
            event: _event(id: 'e-zoo', start: DateTime(2026, 8, 5)),
          ),
        ],
        now: _now,
      );

      expect(result, isEmpty);
    });

    test('ignores an assignment for an event that already ended', () {
      final constraint = _constraint(
        id: 'c1',
        date: DateTime(2026, 8, 5),
        status: ConstraintStatus.approved,
      );

      final result = findNewlyConflictingAssignments(
        originalConstraints: const [],
        updatedConstraints: [constraint],
        assignments: [
          _assignment(
            id: 'a1',
            event: _event(id: 'e1', start: DateTime(2026, 8, 5)),
          ),
        ],
        now: _now,
      );

      expect(result, isEmpty);
    });

    test('still reports a multi-day event that is only partly in the past', () {
      final constraint = _constraint(
        id: 'c1',
        date: DateTime(2026, 8, 29),
        endDate: DateTime(2026, 9, 2),
        status: ConstraintStatus.approved,
      );

      final result = findNewlyConflictingAssignments(
        originalConstraints: const [],
        updatedConstraints: [constraint],
        assignments: [
          _assignment(
            id: 'a1',
            event: _event(
              id: 'e1',
              start: DateTime(2026, 8, 29),
              end: DateTime(2026, 8, 31),
            ),
          ),
        ],
        now: _now,
      );

      expect(result.map((a) => a.id), ['a1']);
    });

    test('ignores an event whose hours fall outside the constraint window', () {
      final constraint = _constraint(
        id: 'c1',
        date: DateTime(2026, 9, 29),
        status: ConstraintStatus.approved,
        startTime: '16:00',
        endTime: '23:59',
      );

      final result = findNewlyConflictingAssignments(
        originalConstraints: const [],
        updatedConstraints: [constraint],
        assignments: [
          _assignment(
            id: 'a1',
            event: _event(
              id: 'e1',
              start: DateTime(2026, 9, 29),
              startTime: '09:00',
              endTime: '13:00',
            ),
          ),
        ],
        now: _now,
      );

      expect(result, isEmpty);
    });

    test('reports an event whose hours overlap the constraint window', () {
      final constraint = _constraint(
        id: 'c1',
        date: DateTime(2026, 9, 29),
        status: ConstraintStatus.approved,
        startTime: '16:00',
        endTime: '23:59',
      );

      final result = findNewlyConflictingAssignments(
        originalConstraints: const [],
        updatedConstraints: [constraint],
        assignments: [
          _assignment(
            id: 'a1',
            event: _event(
              id: 'e1',
              start: DateTime(2026, 9, 29),
              startTime: '18:00',
              endTime: '22:00',
            ),
          ),
        ],
        now: _now,
      );

      expect(result.map((a) => a.id), ['a1']);
    });

    test('ignores a rejected constraint', () {
      final result = findNewlyConflictingAssignments(
        originalConstraints: const [],
        updatedConstraints: [
          _constraint(
            id: 'c1',
            date: DateTime(2026, 9, 29),
            status: ConstraintStatus.rejected,
          ),
        ],
        assignments: [
          _assignment(
            id: 'a1',
            event: _event(id: 'e1', start: DateTime(2026, 9, 29)),
          ),
        ],
        now: _now,
      );

      expect(result, isEmpty);
    });

    test('ignores a pending constraint — pending does not block assignment yet',
        () {
      final result = findNewlyConflictingAssignments(
        originalConstraints: const [],
        updatedConstraints: [
          _constraint(
            id: 'c1',
            date: DateTime(2026, 9, 29),
            status: ConstraintStatus.pending,
          ),
        ],
        assignments: [
          _assignment(
            id: 'a1',
            event: _event(id: 'e1', start: DateTime(2026, 9, 29)),
          ),
        ],
        now: _now,
      );

      expect(result, isEmpty);
    });

    test('ignores an availability constraint — it grants time, never blocks it',
        () {
      final result = findNewlyConflictingAssignments(
        originalConstraints: const [],
        updatedConstraints: [
          _constraint(
            id: 'c1',
            date: DateTime(2026, 9, 29),
            status: ConstraintStatus.approved,
            constraintType: ConstraintType.availability,
          ),
        ],
        assignments: [
          _assignment(
            id: 'a1',
            event: _event(id: 'e1', start: DateTime(2026, 9, 29)),
          ),
        ],
        now: _now,
      );

      expect(result, isEmpty);
    });

    test('ignores a removed constraint — deleting one can only free time up',
        () {
      final constraint = _constraint(
        id: 'c1',
        date: DateTime(2026, 9, 29),
        status: ConstraintStatus.approved,
      );

      final result = findNewlyConflictingAssignments(
        originalConstraints: [constraint],
        updatedConstraints: const [],
        assignments: [
          _assignment(
            id: 'a1',
            event: _event(id: 'e1', start: DateTime(2026, 9, 29)),
          ),
        ],
        now: _now,
      );

      expect(result, isEmpty);
    });

    test('skips assignments whose event relation was not populated', () {
      final result = findNewlyConflictingAssignments(
        originalConstraints: const [],
        updatedConstraints: [
          _constraint(
            id: 'c1',
            date: DateTime(2026, 9, 29),
            status: ConstraintStatus.approved,
          ),
        ],
        assignments: [_assignment(id: 'a1', event: null)],
        now: _now,
      );

      expect(result, isEmpty);
    });

    test('reports each assignment once even when two edited constraints hit it',
        () {
      final result = findNewlyConflictingAssignments(
        originalConstraints: const [],
        updatedConstraints: [
          _constraint(
            id: 'c1',
            date: DateTime(2026, 9, 29),
            status: ConstraintStatus.approved,
          ),
          _constraint(
            id: 'c2',
            date: DateTime(2026, 9, 29),
            status: ConstraintStatus.approved,
          ),
        ],
        assignments: [
          _assignment(
            id: 'a1',
            event: _event(id: 'e1', start: DateTime(2026, 9, 29)),
          ),
        ],
        now: _now,
      );

      expect(result.map((a) => a.id), ['a1']);
    });
  });
}

DateConstraint _constraint({
  required String id,
  required DateTime date,
  required ConstraintStatus status,
  DateTime? endDate,
  String? startTime,
  String? endTime,
  ConstraintType constraintType = ConstraintType.unavailability,
}) {
  return DateConstraint(
    id: id,
    startDate: date,
    endDate: endDate ?? date,
    status: status,
    constraintType: constraintType,
    startTime: startTime,
    endTime: endTime,
  );
}

Event _event({
  required String id,
  required DateTime start,
  DateTime? end,
  String startTime = '18:00',
  String endTime = '22:00',
  String name = 'אירוע',
}) {
  final now = DateTime(2026, 7, 1);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: end ?? start,
    startTime: startTime,
    endTime: endTime,
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}

Assignment _assignment({
  required String id,
  required Event? event,
  String memberId = 'm1',
  String roleType = 'medic',
}) {
  final now = DateTime(2026, 7, 1);
  return Assignment(
    id: id,
    eventId: event?.id ?? 'missing',
    teamMemberId: memberId,
    roleType: roleType,
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
    event: event,
  );
}
