// Tests for the user-assignments redundant-refetch performance fix in
// AssignmentBloc._onLoadUserAssignments / _onRebuildUserAssignments.
//
// Bug (confirmed by a live /user/assignments debug log): every
// RebuildUserAssignments handler ran getAssignmentsByPerson, and on load THREE
// rebuilds fired (the explicit initial add + the watchAssignmentsByPerson
// initial emit + the watchEvents initial emit) => 3x getAssignmentsByPerson
// (~200ms each) + 2 equatable-equal no-emits.
//
// STEP 0 findings (firestore_database.dart):
//   (P) watchAssignmentsByPerson POPULATES relations via
//       _populateAssignmentRelations, identically to getAssignmentsByPerson, so
//       its payload carries a populated `event` => safe substitute.  TRUE.
//   (R) watchAssignmentsByPerson watches ONLY the assignments collection
//       (.where('teamMemberId', ...).snapshots()), so it does NOT re-emit when
//       an EVENT doc changes (e.g. deactivation).  R is FALSE.
//   => Variant B.
//
// Fix (Variant B):
//   * watchAssignmentsByPerson listener passes its populated payload straight
//     into RebuildUserAssignments(assignments: ...) — the rebuild uses it
//     directly, NO re-fetch on the assignment-change path.
//   * watchEvents listener still triggers a NULL-payload rebuild => re-fetch,
//     re-populating fresh events so a deactivated event drops from the list.
//   * The explicit initial add() was removed — both snapshot streams emit on
//     subscribe, covering the load with a single (watchEvents) fetch.
//
// These tests mock the repositories with mockito (avoiding the Firebase
// dependency real repository construction needs). getAssignmentsByPerson is
// made STATEFUL: its return value is a mutable list so the deactivation test
// can change what a re-fetch returns; a counter tracks how many times it runs.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/data/repositories/role_repository.dart';
import 'package:shavtzak/data/repositories/team_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';

import 'assignment_bloc_user_assignments_test.mocks.dart';

@GenerateMocks([
  AssignmentRepository,
  TeamRepository,
  EventRepository,
  RoleRepository,
])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const memberId = 'm1';

  late MockAssignmentRepository assignmentRepo;
  late MockTeamRepository teamRepo;
  late MockEventRepository eventRepo;
  late MockRoleRepository roleRepo;

  late StreamController<List<Assignment>> personAssignmentStream;
  late StreamController<List<Event>> eventStream;

  // What getAssignmentsByPerson returns on its next call, plus a call counter.
  late List<Assignment> personRefetchResult;
  late int getByPersonCalls;

  final now = DateTime(2026, 1, 1);

  // ---- Builders for minimal valid entities --------------------------------

  Event eventFor(String id, {bool isDeactivated = false}) => Event(
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
        isDeactivated: isDeactivated,
      );

  // A populated assignment (carries its event) — exactly what both
  // watchAssignmentsByPerson and getAssignmentsByPerson hand back.
  Assignment populatedAssignment(
    String id,
    String eventId, {
    bool eventDeactivated = false,
  }) =>
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
        event: eventFor(eventId, isDeactivated: eventDeactivated),
      );

  setUp(() {
    assignmentRepo = MockAssignmentRepository();
    teamRepo = MockTeamRepository();
    eventRepo = MockEventRepository();
    roleRepo = MockRoleRepository();

    personAssignmentStream = StreamController<List<Assignment>>.broadcast();
    eventStream = StreamController<List<Event>>.broadcast();

    // Streams used by the user-assignments path.
    when(assignmentRepo.watchAssignmentsByPerson(any))
        .thenAnswer((_) => personAssignmentStream.stream);
    when(eventRepo.watchEvents()).thenAnswer((_) => eventStream.stream);

    // Stateful one-shot fetch used by the watchEvents (re-fetch) path.
    personRefetchResult = [populatedAssignment('a1', 'e1')];
    getByPersonCalls = 0;
    when(assignmentRepo.getAssignmentsByPerson(any)).thenAnswer((_) async {
      getByPersonCalls++;
      return List<Assignment>.from(personRefetchResult);
    });
  });

  tearDown(() async {
    await personAssignmentStream.close();
    await eventStream.close();
  });

  AssignmentBloc buildBloc() => AssignmentBloc(
        assignmentRepo,
        eventRepo,
        teamRepo,
        roleRepo,
        null, // CalendarSyncBloc is optional
      );

  // Mirror the live Firestore behaviour: snapshot streams emit on subscribe.
  // The mock broadcast streams don't auto-emit, so fire one initial emit per
  // stream (assignment stream first, with its populated payload, then events).
  Future<void> fireInitialStreamEmits() async {
    personAssignmentStream.add([populatedAssignment('a1', 'e1')]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    eventStream.add([eventFor('e1')]);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  // ---------------------------------------------------------------------------
  // Test 1 — reduced re-fetch on load (the fix).
  // ---------------------------------------------------------------------------
  test(
    'load triggers at most ONE getAssignmentsByPerson; an assignment-stream '
    'emission does NOT trigger a re-fetch',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadUserAssignments(memberId));
      // Let the subscriptions attach.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Initial stream emits (assignment payload + events) settle the load.
      await fireInitialStreamEmits();

      // CORE ASSERTION (the fix): on load only the watchEvents path re-fetches.
      // The assignment-stream initial emit carried a populated payload and was
      // used directly. OLD code => 3 getAssignmentsByPerson; NEW => 1.
      expect(getByPersonCalls, 1,
          reason:
              'old path ran 3 getAssignmentsByPerson on load; the fix uses the '
              'populated stream payload directly and re-fetches only via '
              'watchEvents');

      // Now push a NEW assignment-stream emission (a later assignment change).
      // This must NOT trigger an extra getAssignmentsByPerson.
      final callsBefore = getByPersonCalls;
      personAssignmentStream.add([
        populatedAssignment('a1', 'e1'),
        populatedAssignment('a2', 'e1'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(getByPersonCalls, callsBefore,
          reason:
              'an assignment-stream emission must use its payload directly, not '
              're-fetch');

      // And the state reflects the streamed change (2 assignments).
      expect(bloc.state, isA<AssignmentsLoaded>());
      expect((bloc.state as AssignmentsLoaded).assignments, hasLength(2));
    },
  );

  // ---------------------------------------------------------------------------
  // Test 2 — real-time assignment change (CRITICAL: no reload).
  // ---------------------------------------------------------------------------
  test(
    'live assignment change on watchAssignmentsByPerson is reflected with no '
    'reload',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadUserAssignments(memberId));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await fireInitialStreamEmits();

      expect(bloc.state, isA<AssignmentsLoaded>());
      expect((bloc.state as AssignmentsLoaded).assignments, hasLength(1));

      // Push a CHANGED assignments list straight on the person stream.
      personAssignmentStream.add([
        populatedAssignment('a1', 'e1'),
        populatedAssignment('a2', 'e1'),
        populatedAssignment('a3', 'e1'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(bloc.state, isA<AssignmentsLoaded>());
      final ids = (bloc.state as AssignmentsLoaded)
          .assignments
          .map((a) => a.id)
          .toList();
      expect(ids, containsAll(<String>['a1', 'a2', 'a3']),
          reason: 'streamed assignment change must flow into state, no reload');
    },
  );

  // ---------------------------------------------------------------------------
  // Test 3 — event deactivation still hides the assignment (CRITICAL).
  //
  // The user is assigned to e1. The event becomes deactivated: the assignment
  // stream does NOT re-emit (it watches only the assignments collection), but
  // watchEvents fires. That forces a re-fetch (null payload) whose populated
  // events are now deactivated => the assignment is filtered out.
  // ---------------------------------------------------------------------------
  test(
    'deactivating an event the user is assigned to removes the assignment in '
    'real time',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadUserAssignments(memberId));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await fireInitialStreamEmits();

      // Baseline: the user sees their single assignment.
      expect(bloc.state, isA<AssignmentsLoaded>());
      expect((bloc.state as AssignmentsLoaded).assignments, hasLength(1));

      // Admin deactivates e1. The NEXT re-fetch returns the assignment with a
      // now-deactivated populated event (this is what the real repository's
      // fresh population would yield once the event doc flips).
      personRefetchResult = [
        populatedAssignment('a1', 'e1', eventDeactivated: true),
      ];

      // watchEvents emits the changed event set. The assignment stream does NOT
      // re-emit on an event change (R=false), so the watchEvents path is what
      // drives the re-fetch + re-population.
      eventStream.add([eventFor('e1', isDeactivated: true)]);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // CRITICAL CORRECTNESS: the deactivated event's assignment is filtered
      // out — the list is now empty.
      expect(bloc.state, isA<AssignmentsEmpty>(),
          reason:
              'a deactivated event must drop the assignment from the user list '
              'in real time (preserved via the watchEvents re-fetch)');
    },
  );

  // ---------------------------------------------------------------------------
  // Test 4 — subscription cleanup (no leak).
  //
  // _cancelUserAssignmentsSubscriptions cancels BOTH the assignment and the
  // event subscriptions. After closing the bloc, neither stream should retain
  // an active listener.
  // ---------------------------------------------------------------------------
  test(
    'both user-assignments subscriptions are cancelled on close (no leak)',
    () async {
      final bloc = buildBloc();

      bloc.add(const LoadUserAssignments(memberId));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await fireInitialStreamEmits();

      // Both broadcast streams now have a listener.
      expect(personAssignmentStream.hasListener, isTrue);
      expect(eventStream.hasListener, isTrue);

      await bloc.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // close() -> _cancelUserAssignmentsSubscriptions cancels BOTH.
      expect(personAssignmentStream.hasListener, isFalse,
          reason: 'watchAssignmentsByPerson subscription must be cancelled');
      expect(eventStream.hasListener, isFalse,
          reason: 'watchEvents subscription must also be cancelled (no leak)');
    },
  );
}
