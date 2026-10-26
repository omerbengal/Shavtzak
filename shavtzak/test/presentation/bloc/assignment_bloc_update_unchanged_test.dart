// AssignmentBloc._onUpdateAssignment runs its own checkConflicts pre-check
// BEFORE it reaches AssignmentRepository.updateAssignment. That pre-check must
// follow the same rule as the repository and the backend: an update that keeps
// the stored member and event is never re-refused on availability, so a rule
// that grew stricter since the row was made cannot make an unrelated save
// (notes, label, ...) fail.
//
// The repository is mocked, so "the member is unavailable" is modelled the way
// the real checkConflicts reports it: the call WITHOUT skipAvailability returns
// an availability conflict, the call WITH skipAvailability returns none. The
// tests therefore pin which of the two the bloc asks for.

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

  const unavailable = 'חבר m1 לא זמין/ה בתאריכים 03/11/2026 (יש הגבלה מאושרת)';
  final now = DateTime(2026, 1, 1);

  Assignment assignment({required String memberId, String notes = ''}) =>
      Assignment(
        id: 'a1',
        eventId: 'e1',
        teamMemberId: memberId,
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: notes,
        createdAt: now,
        updatedAt: now,
      );

  late MockAssignmentRepository assignmentRepo;
  late MockTeamRepository teamRepo;
  late MockEventRepository eventRepo;
  late MockRoleRepository roleRepo;
  late StreamController<List<Assignment>> listStream;

  void stubRepository({required Assignment? stored}) {
    assignmentRepo = MockAssignmentRepository();
    teamRepo = MockTeamRepository();
    eventRepo = MockEventRepository();
    roleRepo = MockRoleRepository();
    listStream = StreamController<List<Assignment>>.broadcast();

    when(assignmentRepo.getAssignmentById('a1'))
        .thenAnswer((_) async => stored);
    // The member is unavailable for the event: only the check that does not
    // skip availability says so.
    when(assignmentRepo.checkConflicts(any, skipAvailability: false))
        .thenAnswer((_) async => [unavailable]);
    when(assignmentRepo.checkConflicts(any, skipAvailability: true))
        .thenAnswer((_) async => <String>[]);
    when(assignmentRepo.updateAssignment(any)).thenAnswer((_) async {});
    // The post-save reload subscribes to the list; it never emits here.
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
      'UpdateAssignment keeps an unchanged member/event even when the member '
      'is unavailable (no AssignmentConflictWarning)', () async {
    stubRepository(stored: assignment(memberId: 'm1'));
    final bloc = buildBloc();
    addTearDown(bloc.close);
    final states = <AssignmentState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);

    final completion = CrudActionCompleter();
    // Only the notes changed: same member (m1) and event (e1) as stored.
    bloc.add(UpdateAssignment(
      assignment(memberId: 'm1', notes: 'הערה חדשה'),
      completion: completion,
    ));
    final result = await completion.future;
    await pumpEventQueue();

    expect(result.isSuccess, isTrue, reason: result.message);
    verify(assignmentRepo.updateAssignment(any)).called(1);
    expect(states.whereType<AssignmentConflictWarning>(), isEmpty);
    // The pre-check must have been asked to skip availability.
    verify(assignmentRepo.checkConflicts(any, skipAvailability: true))
        .called(1);
    verifyNever(assignmentRepo.checkConflicts(any, skipAvailability: false));
  });

  test(
      'UpdateAssignment refuses a replaced member who is unavailable '
      '(AssignmentConflictWarning, nothing written)', () async {
    stubRepository(stored: assignment(memberId: 'm0'));
    final bloc = buildBloc();
    addTearDown(bloc.close);
    final states = <AssignmentState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);

    final completion = CrudActionCompleter();
    bloc.add(UpdateAssignment(
      assignment(memberId: 'm1'),
      completion: completion,
    ));
    final result = await completion.future;
    await pumpEventQueue();

    expect(result.isFailure, isTrue);
    final warnings = states.whereType<AssignmentConflictWarning>().toList();
    expect(warnings, hasLength(1));
    expect(warnings.single.conflicts, [unavailable]);
    verifyNever(assignmentRepo.updateAssignment(any));
  });

  test(
      'UpdateAssignment still checks availability when the stored row is gone',
      () async {
    stubRepository(stored: null);
    final bloc = buildBloc();
    addTearDown(bloc.close);
    final states = <AssignmentState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);

    final completion = CrudActionCompleter();
    bloc.add(UpdateAssignment(
      assignment(memberId: 'm1'),
      completion: completion,
    ));
    final result = await completion.future;
    await pumpEventQueue();

    expect(result.isFailure, isTrue);
    expect(states.whereType<AssignmentConflictWarning>(), hasLength(1));
    verifyNever(assignmentRepo.updateAssignment(any));
  });
}
