// The summary screen's "assign anyway" for a member from the
// "constrained / unavailable" list must really assign. The screen therefore
// sends CreateAssignmentWithBypass for those picks and waits for the bloc's
// result before it tells the admin anything.
//
// These tests pin the two bloc behaviours that fix relies on:
//  - CreateAssignmentWithBypass writes the assignment and completes with
//    success for a member a constraint (pending or approved) would block;
//  - a plain CreateAssignment for the same member is refused by the conflict
//    check and completes with failure, nothing written. That is why the screen
//    must not use it for the constrained list.
//
// The repository is mocked; "blocked by a pending constraint" is modelled the
// way the real checkConflicts reports it.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';

// The mocks are generated once for the user-assignments bloc test; reuse them.
import 'assignment_bloc_user_assignments_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const blockedByPending =
      'חבר m1 לא זמין/ה בתאריכים 03/11/2026 (יש הגבלה ממתינה)';
  final now = DateTime(2026, 1, 1);

  Assignment assignment() => Assignment(
        id: 'a1',
        eventId: 'e1',
        teamMemberId: 'm1',
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.pending,
        notes: '',
        createdAt: now,
        updatedAt: now,
      );

  late MockAssignmentRepository assignmentRepo;
  late MockTeamRepository teamRepo;
  late MockEventRepository eventRepo;
  late MockRoleRepository roleRepo;
  late StreamController<List<Assignment>> listStream;

  void stubRepository() {
    assignmentRepo = MockAssignmentRepository();
    teamRepo = MockTeamRepository();
    eventRepo = MockEventRepository();
    roleRepo = MockRoleRepository();
    listStream = StreamController<List<Assignment>>.broadcast();

    // A pending unavailability constraint blocks the member in the conflict
    // check (it counts like an approved one).
    when(assignmentRepo.checkConflicts(any, skipAvailability: false))
        .thenAnswer((_) async => [blockedByPending]);
    when(assignmentRepo.createAssignment(any)).thenAnswer((_) async {});
    when(assignmentRepo.createAssignmentWithBypass(any))
        .thenAnswer((_) async {});
    // The post-save reload of the plain path subscribes to the list; it never
    // emits here.
    when(assignmentRepo.watchAssignments()).thenAnswer((_) => listStream.stream);
  }

  AssignmentBloc buildBloc() => AssignmentBloc(
        assignmentRepo,
        eventRepo,
        teamRepo,
        roleRepo,
        null, // CalendarSyncBloc is optional
      );

  tearDown(() async {
    await listStream.close();
  });

  test(
      'CreateAssignmentWithBypass completes success for a member blocked by a '
      'pending constraint', () async {
    stubRepository();
    final bloc = buildBloc();
    addTearDown(bloc.close);

    final completion = CrudActionCompleter();
    bloc.add(CreateAssignmentWithBypass(assignment(), completion: completion));
    final result = await completion.future;
    await pumpEventQueue();

    expect(result.isSuccess, isTrue, reason: result.message);
    verify(assignmentRepo.createAssignmentWithBypass(any)).called(1);
    // The bypass path never runs the conflict check and never writes through
    // the checked path.
    verifyNever(assignmentRepo.checkConflicts(any, skipAvailability: false));
    verifyNever(assignmentRepo.createAssignment(any));
  });

  test('CreateAssignment completes failure for the same member', () async {
    stubRepository();
    final bloc = buildBloc();
    addTearDown(bloc.close);
    final states = <AssignmentState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);

    final completion = CrudActionCompleter();
    bloc.add(CreateAssignment(assignment(), completion: completion));
    final result = await completion.future;
    await pumpEventQueue();

    expect(result.isFailure, isTrue);
    expect(result.message, contains(blockedByPending));
    expect(states.whereType<AssignmentConflictWarning>(), isNotEmpty);
    verifyNever(assignmentRepo.createAssignment(any));
    verifyNever(assignmentRepo.createAssignmentWithBypass(any));
  });
}
