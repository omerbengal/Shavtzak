import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

// The mock is generated once for the sibling save-batch test; reuse it.
import 'assignment_repository_save_batch_test.mocks.dart';

/// `checkConflicts` judges the member against the assignment's own window:
/// its custom hours when it has them, the event's whole stretch otherwise.
void main() {
  final day1 = DateTime(2026, 11, 3);
  final day2 = DateTime(2026, 11, 4);

  // A two-day event with no times, so its stretch is day 1 00:00 to day 2 24:00.
  Event twoDayEvent() => Event(
        id: 'e1',
        name: 'אירוע',
        startDate: day1,
        endDate: day2,
        startTime: '',
        endTime: '',
        assemblyTime: '',
        requiresArmed: false,
        roleRequirements: const {'medic': 1},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  TeamMember member({ConstraintStatus status = ConstraintStatus.approved}) =>
      TeamMember(
        id: 'm1',
        name: 'דנה',
        isActive: true,
        isPermanent: true,
        constraints: [
          // All day on day 2.
          DateConstraint(
            id: 'c1',
            startDate: day2,
            status: status,
            constraintType: ConstraintType.unavailability,
          ),
        ],
        roleCapabilities: const {'medic': true},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        uniqueKey: 'k-m1',
      );

  Assignment assignment({String? customStartAt, String? customEndAt}) =>
      Assignment(
        id: 'a1',
        eventId: 'e1',
        teamMemberId: 'm1',
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: '',
        customStartAt: customStartAt,
        customEndAt: customEndAt,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  late MockDatabaseInterface db;
  late AssignmentRepository repo;

  void stub(TeamMember m) {
    when(db.getEventById('e1')).thenAnswer((_) async => twoDayEvent());
    when(db.getTeamMemberById('m1')).thenAnswer((_) async => m);
    when(db.getAssignmentsByEvent('e1')).thenAnswer((_) async => []);
  }

  setUp(() {
    db = MockDatabaseInterface();
    repo = AssignmentRepository(db);
  });

  test('without hours, a day-2 constraint blocks the two-day event', () async {
    stub(member());

    final conflicts = await repo.checkConflicts(assignment());

    expect(conflicts, hasLength(1));
    expect(conflicts.single, contains('יש הגבלה מאושרת'));
  });

  test('hours on day 1 only: the day-2 constraint is no availability conflict',
      () async {
    stub(member());

    final conflicts = await repo.checkConflicts(assignment(
      customStartAt: '2026-11-03T09:00',
      customEndAt: '2026-11-03T17:00',
    ));

    expect(conflicts, isEmpty);
  });

  test('hours that reach into day 2 are blocked by the day-2 constraint',
      () async {
    stub(member());

    final conflicts = await repo.checkConflicts(assignment(
      customStartAt: '2026-11-03T20:00',
      customEndAt: '2026-11-04T06:00',
    ));

    expect(conflicts, hasLength(1));
    expect(conflicts.single, contains('יש הגבלה מאושרת'));
  });

  test('a pending constraint inside the hours blocks, and says it is pending',
      () async {
    stub(member(status: ConstraintStatus.pending));

    final conflicts = await repo.checkConflicts(assignment(
      customStartAt: '2026-11-04T09:00',
      customEndAt: '2026-11-04T12:00',
    ));

    expect(conflicts, hasLength(1));
    expect(conflicts.single, contains('יש הגבלה הממתינה לאישור'));
  });

  test('unreadable hours fall back to the whole event', () async {
    stub(member());

    final conflicts = await repo.checkConflicts(assignment(
      customStartAt: 'not-a-time',
      customEndAt: '2026-11-03T17:00',
    ));

    expect(conflicts, hasLength(1));
  });

  test('skipAvailability still skips the availability message with hours',
      () async {
    stub(member());

    final conflicts = await repo.checkConflicts(
      assignment(
        customStartAt: '2026-11-04T09:00',
        customEndAt: '2026-11-04T12:00',
      ),
      skipAvailability: true,
    );

    expect(conflicts, isEmpty);
  });
}
