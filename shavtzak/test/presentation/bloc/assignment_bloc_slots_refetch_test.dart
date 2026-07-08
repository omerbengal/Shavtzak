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
  //
  // The date is computed RELATIVE TO DateTime.now() (30 days out) rather than
  // hard-coded, so the event is always genuinely in the future regardless of
  // the wall-clock date the suite runs on. A fixed calendar date silently
  // "expires" once the real date passes it, which would make the showPastEvents
  // filter drop the event and collapse every slot count to 0.
  Event futureEvent(String id) {
    final base = DateTime.now().add(const Duration(days: 30));
    final start = DateTime(base.year, base.month, base.day, 9, 0);
    final end = DateTime(base.year, base.month, base.day, 17, 0);
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

      // Let the initial load run and all four listeners attach. pumpEventQueue
      // drains microtasks+timers until idle, so the async pipeline settles
      // deterministically.
      await pumpEventQueue();

      // First paint is stream-driven: emit the initial (empty) assignment set on
      // the windowed stream so the bloc leaves AssignmentLoading. In the live app
      // this comes from `.snapshots()` firing on subscribe; the mock broadcast
      // stream doesn't auto-emit, so we reproduce it here.
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

      // Push member / event / role updates. None of these change the set of
      // assignments, so none should trigger an assignment re-fetch.
      teamStream.add([member('m1'), member('m2')]);
      await pumpEventQueue();
      eventStream.add([futureEvent('e1'), futureEvent('e2')]);
      // The event listener used to await a 100ms delay before re-fetching; pump
      // until idle so an (unwanted) re-fetch would have happened by now.
      await pumpEventQueue();
      roleStream.add([medicRole()]);
      await pumpEventQueue();

      // CORE ASSERTION: getAssignmentsInTimeWindow is never called. First paint
      // and all live updates are now driven by the watchAssignmentsInTimeWindow
      // stream, so the windowed one-shot fetch must never run — not at load, and
      // not on the member/event/role changes (which previously each re-fetched).
      verifyNever(assignmentRepo.getAssignmentsInTimeWindow(
        windowStart: anyNamed('windowStart'),
        windowEnd: anyNamed('windowEnd'),
      ));

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
      await pumpEventQueue();

      // First paint is now gated until the events, roles, AND assignments
      // streams have each delivered once (the one-shot seed getEventsByDateRange
      // / getActiveTeamMembers / getAllRoles was removed to kill a ~30s cold
      // `.get()` park). In the live app these three are the `.snapshots()`
      // initial emits; the mock broadcast streams don't auto-emit, so fire them.
      eventStream.add([futureEvent('e1')]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

      // Initially the single medic slot for e1 is unfilled.
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      expect((bloc.state as AssignmentSlotsLoaded).filledSlots, 0);

      // Push a CHANGED assignment list on the windowed assignment stream.
      final updated = [assignment('a1', 'e1', 'm1')];
      assignmentStream.add(updated);
      await pumpEventQueue();

      // The windowed listener cached the pushed list...
      expect(assignmentRepo.getCurrentAssignments(), equals(updated),
          reason: 'windowed listener must cache the latest assignments');

      // ...and the bloc rebuilt: the medic slot for e1 is now filled.
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      expect((bloc.state as AssignmentSlotsLoaded).filledSlots, 1,
          reason: 'live assignment change must rebuild slots with no reload');
    },
  );

  test(
    'first paint is held until events, roles, and assignments have each '
    'streamed once (flicker-free gate)',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();

      // Nothing has streamed yet → spinner holds.
      expect(bloc.state, isA<AssignmentLoading>());

      // Assignments alone are not enough — events and roles are still missing.
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();
      expect(bloc.state, isA<AssignmentLoading>(),
          reason: 'assignments alone must not open the gate');

      // + events, still missing roles.
      eventStream.add([futureEvent('e1')]);
      await pumpEventQueue();
      expect(bloc.state, isA<AssignmentLoading>(),
          reason: 'events without roles must not open the gate');

      // Members are intentionally NOT part of the gate: emitting them must not
      // open it while roles are still missing (assignments carry populated
      // teamMember relations, so the map isn't needed for a correct first paint).
      teamStream.add([member('m1')]);
      await pumpEventQueue();
      expect(bloc.state, isA<AssignmentLoading>(),
          reason: 'members are excluded from the gate');

      // + roles → all three gated streams have now emitted → first paint lands,
      // fully populated (no empty/partial intermediate frame was ever emitted).
      roleStream.add([medicRole()]);
      await pumpEventQueue();
      expect(bloc.state, isA<AssignmentSlotsLoaded>(),
          reason: 'gate opens only after events, roles, assignments each emit');
      expect((bloc.state as AssignmentSlotsLoaded).totalSlots, 1);
    },
  );

  // ---------------------------------------------------------------------------
  // Roles-cache tests.
  //
  // History: _onRebuildAssignmentSlotsFromData once called getAllRoles() on
  // EVERY rebuild (~5 identical fetches per load). That was first cut to a
  // single load-time seed by caching into _cachedRoles.
  //
  // Now (stream-first load): the one-shot getAllRoles() seed was removed
  // entirely, along with getEventsByDateRange / getActiveTeamMembers, because
  // the first cold `.get()` parked ~30s on the WebChannel handshake. _cachedRoles
  // is seeded by the watchRoles() stream's first emit instead — watchRoles()
  // emits the SAME role set getAllRoles() returns (both read utilities/Lists
  // 'Roles', same mapping + sort, no filtering). Net: getAllRoles fetches per
  // load -> 0. The rebuild reads the cache; the filter path falls back to a
  // one-shot getAllRoles() only if the cache is somehow still empty.
  // ---------------------------------------------------------------------------

  test(
    'getAllRoles is NOT re-fetched per rebuild during a slots load',
    () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());

      // Let the initial load complete + the four listeners attach. The bloc
      // dispatches one RebuildAssignmentSlotsFromData immediately for the seed.
      await pumpEventQueue();

      // In the live app each Firestore snapshot stream fires an initial emit on
      // subscribe, producing ~4 more rebuilds (~5 total). The mock broadcast
      // streams don't auto-emit on subscribe, so reproduce that here: fire one
      // initial emit per stream. Each rebuild that re-fetches roles would call
      // getAllRoles again under the old code.
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();
      teamStream.add([member('m1')]);
      await pumpEventQueue();
      eventStream.add([futureEvent('e1')]);
      await pumpEventQueue();
      roleStream.add([medicRole()]);
      await pumpEventQueue();

      // CORE ASSERTION: getAllRoles is NEVER called on the slots-load path.
      // _cachedRoles is now seeded by the watchRoles stream's first emit (not a
      // one-shot fetch), so no getAllRoles round-trip happens at load or on any
      // of the member/event/role rebuilds. (Was ~5x pre-cache, then 1x as the
      // load seed; now 0.)
      verifyNever(roleRepo.getAllRoles());

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
      await pumpEventQueue();

      // Open the first-paint gate (events + roles + assignments each once). The
      // roles emit doubles as the seed of _cachedRoles with the ORIGINAL name.
      eventStream.add([futureEvent('e1')]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

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
      await pumpEventQueue();

      // CRITICAL: the slots grid reflects the renamed role with no reload.
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      slots = (bloc.state as AssignmentSlotsLoaded).slots;
      expect(slots, hasLength(1));
      expect(slots.single.role.hebrewName, 'פרמדיק',
          reason: 'role rename must flow into rebuilt slots in real time');

      // Invariant: getAllRoles is never called — roles are seeded and refreshed
      // entirely through the watchRoles stream, never a one-shot fetch.
      verifyNever(roleRepo.getAllRoles());
    },
  );

  // ---------------------------------------------------------------------------
  // Filter-change slot-build roles-cache fix tests.
  //
  // Bug: _buildSlotsFromAssignments (the filter-change path,
  // RebuildAssignmentSlots -> _onRebuildAssignmentSlots) re-fetched roles via
  // getAllRoles() on every filter change, even though _cachedRoles is already
  // seeded at load and kept fresh by the watchRoles() listener.
  //
  // Fix: reuse _cachedRoles in _buildSlotsFromAssignments (roles are global /
  // window-independent and getAllRoles() returns the same set already cached),
  // falling back to a one-shot getAllRoles() only if the cache is empty. The
  // full-dataset getAllEvents()/getActiveTeamMembers()/getAllAssignments()
  // fetches on this path are intentionally left untouched.
  // ---------------------------------------------------------------------------

  test(
    'filter change (RebuildAssignmentSlots) does NOT re-fetch roles',
    () async {
      // The filter path uses the FULL datasets (getAllEvents/getAllAssignments),
      // distinct from the windowed hot-path mocks; stub them here.
      when(eventRepo.getAllEvents())
          .thenAnswer((_) async => [futureEvent('e1')]);
      when(assignmentRepo.getAllAssignments())
          .thenAnswer((_) async => const <Assignment>[]);

      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();

      // Seed _cachedRoles via the watchRoles stream (the new seed source, in
      // place of the removed one-shot getAllRoles() at load).
      roleStream.add([medicRole()]);
      await pumpEventQueue();

      // Dispatch a filter change. This drives _onRebuildAssignmentSlots ->
      // _buildSlotsFromAssignments.
      bloc.add(const RebuildAssignmentSlots(preservedFilter: {'e1'}));
      await pumpEventQueue();

      // CORE ASSERTION: getAllRoles is never called — the load no longer seeds
      // via a one-shot fetch, and the filter rebuild reuses the stream-seeded
      // _cachedRoles instead of re-fetching.
      verifyNever(roleRepo.getAllRoles());

      // The filter path still uses the full event/assignment datasets (expected,
      // unchanged) and produced a valid slots state.
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      expect((bloc.state as AssignmentSlotsLoaded).totalSlots, 1);
    },
  );

  test(
    'real-time role change flows into the filter-change build path',
    () async {
      when(eventRepo.getAllEvents())
          .thenAnswer((_) async => [futureEvent('e1')]);
      when(assignmentRepo.getAllAssignments())
          .thenAnswer((_) async => const <Assignment>[]);

      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();

      // A role rename arrives via watchRoles(), updating _cachedRoles.
      final renamed = [medicRole(hebrewName: 'פרמדיק')];
      roleStream.add(renamed);
      await pumpEventQueue();

      // A subsequent filter change rebuilds via _buildSlotsFromAssignments.
      bloc.add(const RebuildAssignmentSlots(preservedFilter: {'e1'}));
      await pumpEventQueue();

      // The rebuilt slot reflects the updated (cached) role name...
      expect(bloc.state, isA<AssignmentSlotsLoaded>());
      final slots = (bloc.state as AssignmentSlotsLoaded).slots;
      expect(slots, hasLength(1));
      expect(slots.single.role.hebrewName, 'פרמדיק',
          reason: 'filter rebuild must use the live-updated cached roles');

      // ...and it did so WITHOUT any getAllRoles fetch: the cache was seeded and
      // updated purely through watchRoles, and the filter rebuild reused it.
      verifyNever(roleRepo.getAllRoles());
    },
  );
}
