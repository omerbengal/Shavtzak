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

  Role medicRole() => Role(
        id: 'role-medic',
        key: 'medic',
        hebrewName: 'חובש',
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

    // Roles fetched inside RebuildAssignmentSlotsFromData.
    when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);
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
}
