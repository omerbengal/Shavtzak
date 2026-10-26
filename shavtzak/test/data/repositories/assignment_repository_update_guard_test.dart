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

void main() {
  final eventDay = DateTime(2026, 11, 3);

  // An event with no times at all, so any approved constraint on its day blocks.
  Event event() => Event(
        id: 'e1',
        name: 'אירוע',
        startDate: eventDay,
        endDate: eventDay,
        startTime: '',
        endTime: '',
        assemblyTime: '',
        requiresArmed: false,
        roleRequirements: const {'medic': 1},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  // A permanent member with an approved whole-day unavailability on the
  // event's date: the availability check refuses them for the event.
  TeamMember member(String id, {bool canMedic = true}) => TeamMember(
        id: id,
        name: 'חבר $id',
        isActive: true,
        isPermanent: true,
        constraints: [
          DateConstraint(
            id: 'c-$id',
            startDate: eventDay,
            status: ConstraintStatus.approved,
            constraintType: ConstraintType.unavailability,
          ),
        ],
        roleCapabilities: {'medic': canMedic},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        uniqueKey: 'k-$id',
      );

  Assignment assignment({required String memberId}) => Assignment(
        id: 'a1',
        eventId: 'e1',
        teamMemberId: memberId,
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: 'הערה חדשה',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  late MockDatabaseInterface db;
  late AssignmentRepository repo;

  setUp(() {
    db = MockDatabaseInterface();
    repo = AssignmentRepository(db);
    when(db.getEventById('e1')).thenAnswer((_) async => event());
    when(db.getAssignmentsByEvent('e1')).thenAnswer((_) async => []);
    when(db.updateAssignment(any,
            bypassAvailability: anyNamed('bypassAvailability')))
        .thenAnswer((_) async {});
  });

  test('updateAssignment keeps an unchanged member/event even when unavailable',
      () async {
    when(db.getAssignmentById('a1'))
        .thenAnswer((_) async => assignment(memberId: 'm1'));
    when(db.getTeamMemberById('m1')).thenAnswer((_) async => member('m1'));

    // Only the notes changed: member and event are the stored ones, so the
    // (now stricter) availability rule must not re-refuse the row.
    await repo.updateAssignment(assignment(memberId: 'm1'));

    verify(db.updateAssignment(any,
            bypassAvailability: anyNamed('bypassAvailability')))
        .called(1);
  });

  test('updateAssignment refuses a replaced member who is unavailable',
      () async {
    when(db.getAssignmentById('a1'))
        .thenAnswer((_) async => assignment(memberId: 'm0'));
    when(db.getTeamMemberById('m1')).thenAnswer((_) async => member('m1'));

    await expectLater(
      repo.updateAssignment(assignment(memberId: 'm1')),
      throwsA(isA<AssignmentConflictException>()),
    );

    verifyNever(db.updateAssignment(any,
        bypassAvailability: anyNamed('bypassAvailability')));
  });

  test('updateAssignment still checks availability when the stored row is gone',
      () async {
    when(db.getAssignmentById('a1')).thenAnswer((_) async => null);
    when(db.getTeamMemberById('m1')).thenAnswer((_) async => member('m1'));

    await expectLater(
      repo.updateAssignment(assignment(memberId: 'm1')),
      throwsA(isA<AssignmentConflictException>()),
    );
  });

  test('updateAssignment on an unchanged member/event still checks qualification',
      () async {
    when(db.getAssignmentById('a1'))
        .thenAnswer((_) async => assignment(memberId: 'm1'));
    when(db.getTeamMemberById('m1'))
        .thenAnswer((_) async => member('m1', canMedic: false));

    // Only the availability message is skipped, not the qualification one.
    await expectLater(
      repo.updateAssignment(assignment(memberId: 'm1')),
      throwsA(isA<AssignmentConflictException>().having(
        (e) => e.conflicts.join(' | '),
        'conflicts',
        contains('לא מוסמך/ת'),
      )),
    );
  });
}
