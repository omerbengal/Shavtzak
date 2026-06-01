// Tests for the slot-mode redundant-refetch performance fix in
// AssignmentBloc._onLoadAssignmentSlots.
//
// Bug: the team-member / event / role stream listeners each re-fetched
// assignments via getAssignmentsInTimeWindow on every emit, even though the
// windowed assignment stream (watchAssignmentsInTimeWindow) is the source of
// truth and already keeps _repository's cache current.  That produced 3-4
// redundant DB round-trips on every member/event/role change.
//
// Fix: those three listeners reuse the cached assignments via
// getCurrentAssignments() instead of re-querying.  The windowed assignment
// listener is untouched, so live assignment changes still flow.
//
// These tests mock the four repositories with mockito (avoiding the Firebase /
// DriveService.instance dependency that real repository construction needs).
// The AssignmentRepository mock is made STATEFUL for the cache:
// cacheCurrentAssignments(x) stores x; getCurrentAssignments() returns it.

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
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';

import 'assignment_bloc_slots_refetch_test.mocks.dart';

@GenerateMocks([
  AssignmentRepository,
  TeamRepository,
  EventRepository,
  RoleRepository,
])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAssignmentRepository assignmentRepo;
  late MockTeamRepository teamRepo;
  late MockEventRepository eventRepo;
  late MockRoleRepository roleRepo;

  late StreamController<List<Assignment>> assignmentStream;
  late StreamController<List<TeamMember>> teamStream;
  late StreamController<List<Event>> eventStream;
  late StreamController<List<Role>> roleStream;

  // Mutable source for getAllRoles() so the roles-cache tests can change the
  // role set between fetches (proving watchRoles refreshes the cache).
  late List<Role> currentRoles;

  final now = DateTime(2026, 1, 1);

  // ---- Builders for minimal valid entities --------------------------------

  TeamMember member(String id) => TeamMember(
        id: id,
        name: 'member-$id',
        isActive: true,
        constraints: const [],
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'key-$id',
      );

  // A future event so it survives the showPastEvents filter, with a quota of 1
  // for the 'medic' role so a single assignment makes the slot transition
  // unfilled -> filled (observable as a distinct AssignmentSlotsLoaded state).
  Event futureEvent(String id) {
    final start = DateTime(2026, 6, 1, 9, 0);
    final end = DateTime(2026, 6, 1, 17, 0);
    return Event(
      id: id,
      name: 'event-$id',
      startDate: start,
      endDate: end,
      startTime: '09:00',
      endTime: '17:00',
      assemblyTime: '08:30',
      requiresArmed: false,
      roleRequirements: const {'medic': 1},
      createdAt: now,
      updatedAt: now,
    );
  }

  Assignment assignment(String id, String eventId, String memberId) =>
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
      );

  Role medicRole({String hebrewName = 'חובש'}) => Role(
        id: 'role-medic',
        key: 'medic',
        hebrewName: hebrewName,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );

  setUp(() {
    assignmentRepo = MockAssignmentRepository();
    teamRepo = MockTeamRepository();
    eventRepo = MockEventRepository();
    roleRepo = MockRoleRepository();

    assignmentStream = StreamController<List<Assignment>>.broadcast();
    teamStream = StreamController<List<TeamMember>>.broadcast();
    eventStream = StreamController<List<Event>>.broadcast();
    roleStream = StreamController<List<Role>>.broadcast();

    // --- Stateful cache on the AssignmentRepository mock ---
    List<Assignment> cached = const [];
    when(assignmentRepo.cacheCurrentAssignments(any)).thenAnswer((inv) {
      cached = inv.positionalArguments.first as List<Assignment>;
    });
    when(assignmentRepo.getCurrentAssignments()).thenAnswer((_) => cached);

    // --- Streams ---
    when(assignmentRepo.watchAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) => assignmentStream.stream);
    when(teamRepo.watchTeamMembers()).thenAnswer((_) => teamStream.stream);
    when(eventRepo.watchEventsByDateRange(any, any))
        .thenAnswer((_) => eventStream.stream);
    when(roleRepo.watchRoles()).thenAnswer((_) => roleStream.stream);

    // --- Initial-load (one-shot) fetches ---
    when(eventRepo.getEventsByDateRange(any, any))
        .thenAnswer((_) async => [futureEvent('e1')]);
    when(teamRepo.getActiveTeamMembers())
        .thenAnswer((_) async => [member('m1')]);
    // Initial seed assignments: empty (slot unfilled).
    when(assignmentRepo.getAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) async => const <Assignment>[]);

    // Roles: getAllRoles() returns a snapshot of the mutable currentRoles list.
    currentRoles = [medicRole()];
    when(roleRepo.getAllRoles())
        .thenAnswer((_) async => List<Role>.from(currentRoles));
  });

  tearDown(() async {
    await assignmentStream.close();
    await teamStream.close();
    await eventStream.close();
    await roleStream.close();
  });

  AssignmentBloc buildBloc() => AssignmentBloc(
        assignmentRepo,
        eventRepo,
        teamRepo,
        roleRepo,
        null, // CalendarSyncBloc is optional
      );

  test(
    'no redundant getAssignmentsInTimeWindow re-fetch on member/event/role change',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());

      // Let the initial load complete (1 getAssignmentsInTimeWindow for the seed)
      // and all four listeners attach.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Push member / event / role updates. None of these change the set of
      // assignments, so none should trigger an assignment re-fetch.
      teamStream.add([member('m1'), member('m2')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      eventStream.add([futureEvent('e1'), futureEvent('e2')]);
      // The event listener used to await a 100ms delay before re-fetching; give
      // it well over that so an (unwanted) re-fetch would have happened.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      roleStream.add([medicRole()]);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // CORE ASSERTION: getAssignmentsInTimeWindow called exactly once total
      // (the initial seed). Before the fix it was called 3 extra times.
      verify(assignmentRepo.getAssignmentsInTimeWindow(
        windowStart: anyNamed('windowStart'),
        windowEnd: anyNamed('windowEnd'),
      )).called(1);

      // The member/event/role changes must still update the UI: the bloc is in
      // the slots-loaded state and reflects the updated event set (2 events).
      final state = bloc.state;
      expect(state, isA<AssignmentSlotsLoaded>());
      // e1 + e2, each with a quota of 1 medic => 2 slots.
      expect((state as AssignmentSlotsLoaded).totalSlots, 2,
          reason: 'event-stream update should be reflected in rebuilt slots');
    },
  );

  test(
    'live assignment updates from watchAssignmentsInTimeWindow still flow (real-time preserved)',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Initially the single medic slot for e1 is unfilled.
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      expect((bloc.state as AssignmentSlotsLoaded).filledSlots, 0);

      // Push a CHANGED assignment list on the windowed assignment stream.
      final updated = [assignment('a1', 'e1', 'm1')];
      assignmentStream.add(updated);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // The windowed listener cached the pushed list...
      expect(assignmentRepo.getCurrentAssignments(), equals(updated),
          reason: 'windowed listener must cache the latest assignments');

      // ...and the bloc rebuilt: the medic slot for e1 is now filled.
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      expect((bloc.state as AssignmentSlotsLoaded).filledSlots, 1,
          reason: 'live assignment change must rebuild slots with no reload');
    },
  );

  // ---------------------------------------------------------------------------
  // Roles-cache performance fix tests.
  //
  // Bug: _onRebuildAssignmentSlotsFromData called getAllRoles() on EVERY
  // rebuild. On a slots load, four stream subscriptions each fire an initial
  // emit, producing ~5 RebuildAssignmentSlotsFromData dispatches and thus ~5
  // identical getAllRoles fetches.
  //
  // Fix: cache roles (_cachedRoles); the rebuild reads the cache; getAllRoles
  // is fetched only at initial load. watchRoles() emits the SAME role set as
  // getAllRoles() (verified: both read utilities/Lists 'Roles', same mapping +
  // sort, no filtering), so the watchRoles listener caches its stream payload
  // directly (Variant A) and rebuilds. Net: ~5 fetches/load -> 1.
  // ---------------------------------------------------------------------------

  test(
    'getAllRoles is NOT re-fetched per rebuild during a slots load',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());

      // Let the initial load complete + the four listeners attach. The bloc
      // dispatches one RebuildAssignmentSlotsFromData immediately for the seed.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // In the live app each Firestore snapshot stream fires an initial emit on
      // subscribe, producing ~4 more rebuilds (~5 total). The mock broadcast
      // streams don't auto-emit on subscribe, so reproduce that here: fire one
      // initial emit per stream. Each rebuild that re-fetches roles would call
      // getAllRoles again under the old code.
      assignmentStream.add(const <Assignment>[]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      teamStream.add([member('m1')]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      eventStream.add([futureEvent('e1')]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      roleStream.add([medicRole()]);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // CORE ASSERTION: getAllRoles is called at most once across the whole
      // multi-rebuild load (the single seed of _cachedRoles). Before the fix it
      // was called once per rebuild (~5x).
      verify(roleRepo.getAllRoles()).called(1);

      // Sanity: the load produced a valid slots state (e1 has 1 medic quota).
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      expect((bloc.state as AssignmentSlotsLoaded).totalSlots, 1);
    },
  );

  test(
    'real-time role change still updates slots (cache refreshed, no reload)',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Baseline: the single medic slot carries the original Hebrew name.
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      var slots = (bloc.state as AssignmentSlotsLoaded).slots;
      expect(slots, hasLength(1));
      expect(slots.single.role.hebrewName, 'חובש',
          reason: 'baseline role name before the rename');

      // Simulate a role change in Firestore (rename). watchRoles() emits the
      // new role set; the listener must update _cachedRoles and rebuild slots
      // live (Variant A: the listener caches the stream payload directly).
      final renamed = [medicRole(hebrewName: 'פרמדיק')];
      roleStream.add(renamed);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // CRITICAL: the slots grid reflects the renamed role with no reload.
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      slots = (bloc.state as AssignmentSlotsLoaded).slots;
      expect(slots, hasLength(1));
      expect(slots.single.role.hebrewName, 'פרמדיק',
          reason: 'role rename must flow into rebuilt slots in real time');

      // Invariant: getAllRoles is still called only once total (the load seed).
      // The real-time change came through the watchRoles stream, not a re-fetch.
      verify(roleRepo.getAllRoles()).called(1);
    },
  );
}
