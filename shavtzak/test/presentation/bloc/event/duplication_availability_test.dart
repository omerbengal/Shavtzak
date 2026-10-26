import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/event/duplication_availability.dart';
import 'package:shavtzak/presentation/bloc/event/event_state.dart';

/// What the duplication dialog flags, whether the admin may keep it, and why.
/// Rules, in order: member gone, inactive or archived, role lost, pool
/// member, then the event rule against the proposed (new) event.
void main() {
  final day = DateTime(2026, 11, 3);
  final proposed = _event(day, startTime: '19:00', endTime: '22:00');

  group('rules that the backend refuses even with the bypass', () {
    test('a member whose document is gone is flagged and cannot be kept', () {
      final result = duplicationAvailability(
        assignment: _assignment(null),
        proposedEvent: proposed,
      );

      expect(result.flagged, isTrue);
      expect(result.canKeep, isFalse);
      expect(result.reasons, ['חבר/ת הצוות לא נמצא/ה']);
    });

    test('an inactive member is flagged and cannot be kept', () {
      final result = duplicationAvailability(
        assignment: _assignment(_member(isActive: false)),
        proposedEvent: proposed,
      );

      expect(result.flagged, isTrue);
      expect(result.canKeep, isFalse);
      expect(result.reasons, ['לא פעיל/ה']);
    });

    test('an archived member is flagged and cannot be kept', () {
      final result = duplicationAvailability(
        assignment: _assignment(_member(isArchived: true)),
        proposedEvent: proposed,
      );

      expect(result.flagged, isTrue);
      expect(result.canKeep, isFalse);
      expect(result.reasons, ['לא פעיל/ה']);
    });

    test('a member who lost the role is flagged and cannot be kept', () {
      final result = duplicationAvailability(
        assignment: _assignment(_member(roleCapabilities: const {})),
        proposedEvent: proposed,
      );

      expect(result.flagged, isTrue);
      expect(result.canKeep, isFalse);
      expect(result.reasons, ['לא מוסמך/ת לתפקיד']);
    });

    test('the member-gone reason comes before every other', () {
      // No member at all: nothing else can even be asked.
      final result = duplicationAvailability(
        assignment: _assignment(null, roleType: 'unknown-role'),
        proposedEvent: proposed,
      );
      expect(result.reasons, ['חבר/ת הצוות לא נמצא/ה']);
    });

    test('inactive comes before a lost role', () {
      final result = duplicationAvailability(
        assignment: _assignment(
            _member(isActive: false, roleCapabilities: const {})),
        proposedEvent: proposed,
      );
      expect(result.reasons, ['לא פעיל/ה']);
    });

    test('a pool member who is inactive is still flagged and locked', () {
      final result = duplicationAvailability(
        assignment: _assignment(
            _member(isActive: false, allowMultipleAssignments: true)),
        proposedEvent: proposed,
      );
      expect(result.flagged, isTrue);
      expect(result.canKeep, isFalse);
    });
  });

  group('allowMultipleAssignments', () {
    test('a pool member is never flagged for availability', () {
      final member = _member(
        allowMultipleAssignments: true,
        constraints: [_unavailability(day, ConstraintStatus.approved)],
      );

      final result = duplicationAvailability(
        assignment: _assignment(member),
        proposedEvent: proposed,
      );

      expect(result.flagged, isFalse);
      expect(result.canKeep, isTrue);
      expect(result.reasons, isEmpty);
    });
  });

  group('permanent members, judged by the event stretch', () {
    test('an approved constraint flags, keepable, with its label', () {
      final member = _member(
        constraints: [_unavailability(day, ConstraintStatus.approved)],
      );

      final result = duplicationAvailability(
        assignment: _assignment(member),
        proposedEvent: proposed,
      );

      expect(result.flagged, isTrue);
      expect(result.canKeep, isTrue);
      expect(result.reasons, ['אילוץ מאושר: 3.11 (כל היום)']);
    });

    test('a pending constraint flags, keepable, saying it is pending', () {
      final member = _member(
        constraints: [_unavailability(day, ConstraintStatus.pending)],
      );

      final result = duplicationAvailability(
        assignment: _assignment(member),
        proposedEvent: proposed,
      );

      expect(result.flagged, isTrue);
      expect(result.canKeep, isTrue);
      expect(result.reasons, ['אילוץ ממתין לאישור: 3.11 (כל היום)']);
    });

    test('every blocking constraint gets its own reason line', () {
      final member = _member(constraints: [
        _unavailability(day, ConstraintStatus.approved, id: 'a'),
        _unavailability(day, ConstraintStatus.pending,
            id: 'b', startTime: '18:00', endTime: '20:00'),
      ]);

      final result = duplicationAvailability(
        assignment: _assignment(member),
        proposedEvent: proposed,
      );

      expect(result.reasons, [
        'אילוץ מאושר: 3.11 (כל היום)',
        'אילוץ ממתין לאישור: 3.11 18:00–20:00',
      ]);
    });

    test('a rejected constraint does not flag', () {
      final member = _member(
        constraints: [_unavailability(day, ConstraintStatus.rejected)],
      );

      final result = duplicationAvailability(
        assignment: _assignment(member),
        proposedEvent: proposed,
      );

      expect(result.flagged, isFalse);
      expect(result.reasons, isEmpty);
    });

    test('a constraint on another day does not flag', () {
      final member = _member(constraints: [
        _unavailability(DateTime(2026, 11, 4), ConstraintStatus.approved),
      ]);

      final result = duplicationAvailability(
        assignment: _assignment(member),
        proposedEvent: proposed,
      );

      expect(result.flagged, isFalse);
    });

    test('a timed morning constraint does not flag an evening duplicate (E7)',
        () {
      final member = _member(constraints: [
        _unavailability(day, ConstraintStatus.approved,
            startTime: '08:00', endTime: '10:00'),
      ]);

      final result = duplicationAvailability(
        assignment: _assignment(member),
        proposedEvent: proposed,
      );

      expect(result.flagged, isFalse);
      expect(result.canKeep, isTrue);
      expect(result.reasons, isEmpty);
    });

    test('a constraint overlapping the evening does flag, with its hours', () {
      final member = _member(constraints: [
        _unavailability(day, ConstraintStatus.approved,
            startTime: '20:00', endTime: '23:00'),
      ]);

      final result = duplicationAvailability(
        assignment: _assignment(member),
        proposedEvent: proposed,
      );

      expect(result.flagged, isTrue);
      expect(result.canKeep, isTrue);
      expect(result.reasons, ['אילוץ מאושר: 3.11 20:00–23:00']);
    });
  });

  group('non-permanent members', () {
    test('a non-permanent member is flagged, keepable, for a new event', () {
      final result = duplicationAvailability(
        assignment: _assignment(_member(isPermanent: false)),
        proposedEvent: proposed,
      );

      expect(result.flagged, isTrue);
      expect(result.canKeep, isTrue);
      expect(result.reasons, ['לא ציין/ה זמינות לאירוע']);
    });

    test('a non-permanent member who listed the proposed event is not flagged',
        () {
      final result = duplicationAvailability(
        assignment: _assignment(
            _member(isPermanent: false, availableEventIds: [proposed.id])),
        proposedEvent: proposed,
      );

      expect(result.flagged, isFalse);
    });
  });

  group('a free permanent member', () {
    test('is not flagged', () {
      final result = duplicationAvailability(
        assignment: _assignment(_member()),
        proposedEvent: proposed,
      );

      expect(result.flagged, isFalse);
      expect(result.canKeep, isTrue);
      expect(result.reasons, isEmpty);
    });
  });

  group('AssignmentDuplicationInfo', () {
    test('canKeep defaults to true and takes part in equality', () {
      final assignment = _assignment(_member());
      final keepable = AssignmentDuplicationInfo(
        assignment: assignment,
        hasAvailabilityConflict: true,
        availabilityReason: 'x',
        isInOverQuotaRole: false,
      );
      final locked = AssignmentDuplicationInfo(
        assignment: assignment,
        hasAvailabilityConflict: true,
        availabilityReason: 'x',
        isInOverQuotaRole: false,
        canKeep: false,
      );

      expect(keepable.canKeep, isTrue);
      expect(locked.canKeep, isFalse);
      expect(keepable, isNot(equals(locked)));
    });
  });
}

Assignment _assignment(TeamMember? member, {String roleType = 'medic'}) {
  final now = DateTime(2026, 10, 1);
  return Assignment(
    id: 'a1',
    eventId: 'original',
    teamMemberId: 'm1',
    roleType: roleType,
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
    teamMember: member,
  );
}

TeamMember _member({
  bool isActive = true,
  bool isArchived = false,
  bool isPermanent = true,
  bool allowMultipleAssignments = false,
  Map<String, bool> roleCapabilities = const {'medic': true},
  List<DateConstraint> constraints = const [],
  List<String> availableEventIds = const [],
}) {
  final now = DateTime(2026, 10, 1);
  return TeamMember(
    id: 'm1',
    name: 'חבר',
    isActive: isActive,
    isArchived: isArchived,
    isPermanent: isPermanent,
    allowMultipleAssignments: allowMultipleAssignments,
    constraints: constraints,
    roleCapabilities: roleCapabilities,
    availableEventIds: availableEventIds,
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'k1',
  );
}

DateConstraint _unavailability(
  DateTime day,
  ConstraintStatus status, {
  String id = 'c1',
  String? startTime,
  String? endTime,
}) {
  return DateConstraint(
    id: id,
    startDate: day,
    endDate: day,
    status: status,
    constraintType: ConstraintType.unavailability,
    startTime: startTime,
    endTime: endTime,
  );
}

Event _event(DateTime day, {required String startTime, required String endTime}) {
  final now = DateTime(2026, 10, 1);
  return Event(
    id: 'proposed',
    name: 'אירוע חדש',
    startDate: day,
    endDate: day,
    startTime: startTime,
    endTime: endTime,
    assemblyTime: startTime,
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}
