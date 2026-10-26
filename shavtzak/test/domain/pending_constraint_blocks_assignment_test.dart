import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

/// A permanent member's pending unavailability blocks assignment exactly like
/// an approved one; only a rejected request stops blocking.
void main() {
  final day = DateTime(2026, 11, 3);
  final event = _event(day);

  for (final (status, blocks) in [
    (ConstraintStatus.approved, true),
    (ConstraintStatus.pending, true),
    (ConstraintStatus.rejected, false),
  ]) {
    group('${status.name} unavailability', () {
      final member = _member([_unavailability(day, status)]);

      test('blocksAssignments is $blocks', () {
        expect(member.constraints.single.blocksAssignments, blocks);
      });

      test('isAvailableForEventWithTime is ${!blocks}', () {
        expect(member.isAvailableForEventWithTime(event), !blocks);
      });

      test('isAvailableOn / isAvailableForDateRange (event duplication) is '
          '${!blocks}', () {
        expect(member.isAvailableOn(day), !blocks);
        expect(member.isAvailableForDateRange(day, day), !blocks);
      });

      test('constraintsBlockingEvent ${blocks ? 'names' : 'omits'} it', () {
        expect(member.constraintsBlockingEvent(event),
            blocks ? member.constraints : isEmpty);
      });
    });
  }

  test('a pending availability never counts as a block', () {
    final constraint = DateConstraint(
      id: 'a',
      startDate: day,
      endDate: day,
      status: ConstraintStatus.pending,
      constraintType: ConstraintType.availability,
    );
    expect(constraint.blocksAssignments, isFalse);
  });

  test('a pending constraint whose hours miss the event does not block', () {
    final member = _member([
      _unavailability(day, ConstraintStatus.pending,
          startTime: '08:00', endTime: '12:00'),
    ]);
    expect(member.isAvailableForEventWithTime(event), isTrue);
    expect(member.constraintsBlockingEvent(event), isEmpty);
  });

  test('non-permanent members are never blocked by unavailability', () {
    final member = _member(
      [_unavailability(day, ConstraintStatus.pending)],
      isPermanent: false,
    );
    expect(member.constraintsBlockingEvent(event), isEmpty);
  });
}

DateConstraint _unavailability(
  DateTime day,
  ConstraintStatus status, {
  String? startTime,
  String? endTime,
}) {
  return DateConstraint(
    id: 'c-${status.name}',
    startDate: day,
    endDate: day,
    status: status,
    constraintType: ConstraintType.unavailability,
    startTime: startTime,
    endTime: endTime,
  );
}

TeamMember _member(List<DateConstraint> constraints,
    {bool isPermanent = true}) {
  final now = DateTime(2026, 10, 1);
  return TeamMember(
    id: 'm1',
    name: 'חבר',
    isActive: true,
    isPermanent: isPermanent,
    constraints: constraints,
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'k1',
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
