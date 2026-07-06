// Regression test for a production bug seen on /user/assignments:
//
// The admin (viewing their OWN /user/assignments) briefly saw EVERY event with
// ALL its role badges green, then it corrected itself. The live debug log
// showed the AssignmentsLoaded state flip from (filterType:'person', 9
// assignments) to (filterType:'all', 259 assignments) right after a
// `watchAssignments` (full collection) emit — propsChanged included filterType
// [1] and filterId [2].
//
// ROOT CAUSE: the older list-mode handlers (_onLoadAssignments /
// _onLoadAssignmentsByEvent / _onLoadAssignmentsByPerson) subscribe to their
// stream via `emit.forEach`, whose future never completes for an infinite
// Firestore stream — so the subscription lives for the bloc's whole lifetime.
// The newer _onLoadUserAssignments (and slots) handlers cancel only their OWN
// manual subscriptions; they never stop a lingering list-mode forEach. On the
// app-scoped AssignmentBloc, a full-list `watchAssignments` subscription left
// over from a prior LoadAssignments therefore keeps emitting and overwrites the
// per-user state with the entire assignments collection.
//
// These tests reuse the generated mocks from
// assignment_bloc_user_assignments_test.mocks.dart.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';

import 'assignment_bloc_user_assignments_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const memberId = 'm1';

  late MockAssignmentRepository assignmentRepo;
  late MockTeamRepository teamRepo;
  late MockEventRepository eventRepo;
  late MockRoleRepository roleRepo;

  late StreamController<List<Assignment>> personAssignmentStream;
  late StreamController<List<Event>> eventStream;
  late StreamController<List<Assignment>> fullAssignmentStream;

  final now = DateTime(2026, 1, 1);

  Event eventFor(String id) => Event(
        id: id,
        name: 'event-$id',
        startDate: DateTime(2026, 6, 1, 9, 0),
        endDate: DateTime(2026, 6, 1, 17, 0),
        startTime: '09:00',
        endTime: '17:00',
        assemblyTime: '08:30',
        requiresArmed: false,
        roleRequirements: const {'medic': 1},
        createdAt: now,
        updatedAt: now,
      );

  Assignment assignmentFor(String id, String eventId, String memberId) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: now,
        updatedAt: now,
        event: eventFor(eventId),
      );

  setUp(() {
    assignmentRepo = MockAssignmentRepository();
    teamRepo = MockTeamRepository();
    eventRepo = MockEventRepository();
    roleRepo = MockRoleRepository();

    personAssignmentStream = StreamController<List<Assignment>>.broadcast();
    eventStream = StreamController<List<Event>>.broadcast();
    fullAssignmentStream = StreamController<List<Assignment>>.broadcast();

    when(assignmentRepo.watchAssignmentsByPerson(any))
        .thenAnswer((_) => personAssignmentStream.stream);
    when(eventRepo.watchEvents()).thenAnswer((_) => eventStream.stream);
    when(assignmentRepo.watchAssignments())
        .thenAnswer((_) => fullAssignmentStream.stream);

    when(assignmentRepo.getAssignmentsByPerson(any)).thenAnswer(
      (_) async => [assignmentFor('a1', 'e1', memberId)],
    );
  });

  tearDown(() async {
    await personAssignmentStream.close();
    await eventStream.close();
    await fullAssignmentStream.close();
  });

  AssignmentBloc buildBloc() => AssignmentBloc(
        assignmentRepo,
        eventRepo,
        teamRepo,
        roleRepo,
        null,
      );

  // ---------------------------------------------------------------------------
  // The regression: a leaked full-list subscription must NOT clobber the
  // per-user view after switching into user-assignments mode.
  // ---------------------------------------------------------------------------
  test(
    'a full-list watchAssignments emit does NOT overwrite the user-assignments '
    'state after switching to user mode',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      // 1) Enter full-list mode (as happens on the admin list, or via the
      //    create/update/delete reload fallback add(LoadAssignments())).
      bloc.add(const LoadAssignments());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      fullAssignmentStream.add([assignmentFor('x1', 'e1', memberId)]);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // 2) Now switch to the user's personal assignments view.
      bloc.add(const LoadUserAssignments(memberId));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      personAssignmentStream.add([assignmentFor('a1', 'e1', memberId)]);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Sanity: the user view is showing the single, person-filtered assignment.
      expect(bloc.state, isA<AssignmentsLoaded>());
      expect((bloc.state as AssignmentsLoaded).filterType, 'person');
      expect((bloc.state as AssignmentsLoaded).assignments, hasLength(1));

      // 3) The full-collection stream emits again (the admin assigns other
      //    members => the global assignments collection changes). With the bug,
      //    the leaked LoadAssignments forEach clobbers the user view with the
      //    entire collection (filterType 'all').
      fullAssignmentStream.add([
        assignmentFor('x1', 'e1', memberId),
        assignmentFor('x2', 'e2', 'someone-else'),
        assignmentFor('x3', 'e3', 'another-person'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // CORE ASSERTION: the state must remain the person-filtered view.
      expect(bloc.state, isA<AssignmentsLoaded>());
      final state = bloc.state as AssignmentsLoaded;
      expect(state.filterType, 'person',
          reason:
              'the leaked full-list forEach must be cancelled when entering '
              'user mode; it must not overwrite the per-user state with '
              "filterType 'all'");
      expect(state.filterId, memberId);
      expect(state.assignments, hasLength(1),
          reason: 'user must keep seeing only their own assignment');
    },
  );

  // ---------------------------------------------------------------------------
  // The full-list subscription must actually be released (no lingering read
  // traffic) once we leave list mode for user mode.
  // ---------------------------------------------------------------------------
  test(
    'switching from list mode to user mode releases the full-list subscription',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignments());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      fullAssignmentStream.add([assignmentFor('x1', 'e1', memberId)]);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(fullAssignmentStream.hasListener, isTrue);

      bloc.add(const LoadUserAssignments(memberId));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fullAssignmentStream.hasListener, isFalse,
          reason:
              'the full-list subscription must be cancelled when switching to '
              'user-assignments mode (no leak, no cross-contamination)');
    },
  );
}
