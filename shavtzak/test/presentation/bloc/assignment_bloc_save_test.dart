// Tests for AssignmentBloc's SaveStagedChanges handler: converging each
// staged change to its desired state against the RAW DB and calling
// AssignmentRepository.saveAssignmentsBatch atomically, clearing staging +
// cache ONLY on success.
//
// Two corrections are locked in here (see task-8 brief + corrections, same
// bug class Task 7's classifyStagedConflicts hit):
//  1. The DB-occupant lookup MUST come from `_repository.getCurrentAssignments()`
//     (the raw, pre-merge cache) — NOT from `state.slots`/`currentSlots`, whose
//     `currentAssignment` is already the merged/staged (optimistic) value. Using
//     the merged value would mis-route a staged FILL to `updates` (updating a
//     nonexistent doc) and would LOSE a staged CLEAR (merged slot looks empty).
//  2. An UPDATE must preserve the existing DB doc's `createdAt` (the backend
//     `batch.update` rewrites the full doc) — NOT reset it to `DateTime.now()`.
//
// Harness copied from assignment_bloc_staging_test.dart / assignment_conflict_test.dart
// (mockito repo mocks + StreamControllers + entity builders); reuses that
// sibling's generated mocks (`assignment_bloc_slots_refetch_test.mocks.dart`)
// instead of its own @GenerateMocks, since it mocks the exact same four
// repository types.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';

import 'assignment_bloc_slots_refetch_test.mocks.dart';

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

  // ---- Builders for minimal valid entities (mirrors the sibling files) ----

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

  // Future event (survives showPastEvents) with a 1-slot medic quota by
  // default, so an empty medic slot exists to stage into.
  Event futureEvent(String id, {Map<String, int>? roleRequirements}) {
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
      roleRequirements: roleRequirements ?? const {'medic': 1},
      createdAt: now,
      updatedAt: now,
    );
  }

  Assignment assignment(
    String id,
    String eventId,
    String memberId, {
    String roleType = 'medic',
    int slotIndex = 0,
    DateTime? createdAt,
  }) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: roleType,
        slotIndex: slotIndex,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: createdAt ?? now,
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
    SharedPreferences.setMockInitialValues({});

    assignmentRepo = MockAssignmentRepository();
    teamRepo = MockTeamRepository();
    eventRepo = MockEventRepository();
    roleRepo = MockRoleRepository();

    assignmentStream = StreamController<List<Assignment>>.broadcast();
    teamStream = StreamController<List<TeamMember>>.broadcast();
    eventStream = StreamController<List<Event>>.broadcast();
    roleStream = StreamController<List<Role>>.broadcast();

    // --- Stateful cache on the AssignmentRepository mock ---
    // This is the RAW-DB snapshot the real repository keeps (populated from
    // the assignments stream at RebuildAssignmentSlotsFromData time), and is
    // what classifyStagedConflicts / SaveStagedChanges must converge against.
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
        .thenAnswer((_) async => [member('m1'), member('m2')]);
    when(assignmentRepo.getAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) async => const <Assignment>[]);
    when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

    // Used by the RebuildAssignmentSlots (filter/rehydrate/save-rebuild) path.
    when(eventRepo.getAllEvents()).thenAnswer((_) async => [futureEvent('e1')]);
    when(assignmentRepo.getAllAssignments())
        .thenAnswer((_) async => const <Assignment>[]);

    // Default: the batch write succeeds. Overridden per-test for the failure case.
    when(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).thenAnswer((_) async {});
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
        userCacheService: UserCacheService(),
      );

  test(
      'save of a staged fill against an empty DB slot batches it as a create, '
      'not an update, and clears staging on success', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    assignmentStream.add(const <Assignment>[]); // DB starts empty
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);

    // Stage m1 into the empty medic slot (baseline: empty).
    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();

    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();

    final captured = verify(assignmentRepo.saveAssignmentsBatch(
      creates: captureAnyNamed('creates'),
      updates: captureAnyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).captured;
    final creates = captured[0] as List<Assignment>;
    final updates = captured[1] as List<Assignment>;

    // The DB never had a doc for this slot, so this MUST be a create. Routing
    // it to `updates` (the bug: sourcing the DB occupant from the merged/
    // optimistic `state.slots` instead of the raw `getCurrentAssignments()`)
    // would try to update a document id that was never written -> batch fails.
    expect(creates, hasLength(1));
    expect(creates.single.teamMemberId, 'm1');
    expect(updates, isEmpty);
    expect(bloc.hasStagedChanges, isFalse); // cleared on success
  });

  test(
      'save of a staged swap against an occupied DB slot batches it as an '
      'update and preserves the original DB doc createdAt', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    final originalCreatedAt = DateTime(2020, 5, 5); // far from `now`/save-time
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    final a1 = assignment('a1', 'e1', 'm1', createdAt: originalCreatedAt);
    assignmentStream.add([a1]); // DB starts with m1 in medic-0
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final filledMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(filledMedicSlot.currentAssignment!.teamMemberId, 'm1');

    // Stage a swap m1 -> m2 (baseline: m1/a1).
    bloc.add(StageMemberChange(slot: filledMedicSlot, member: member('m2')));
    await pumpEventQueue();

    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();

    final captured = verify(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: captureAnyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).captured;
    final updates = captured.single as List<Assignment>;

    expect(updates, hasLength(1));
    expect(updates.single.id, a1.id); // converges the EXISTING doc, in place
    expect(updates.single.teamMemberId, 'm2');
    // Proves createdAt was preserved from the DB doc, NOT reset to save-time.
    expect(updates.single.createdAt, originalCreatedAt);
    expect(bloc.hasStagedChanges, isFalse);
  });

  test('a failed batch write keeps the staged change and cache intact for retry',
      () async {
    when(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).thenThrow(Exception('boom'));

    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    assignmentStream.add(const <Assignment>[]);
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isTrue);

    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();

    // Retry-safe: the staged change (in-memory AND cached) must survive a
    // failed write so the admin can retry without losing the edit.
    expect(bloc.hasStagedChanges, isTrue);
    final cached = await UserCacheService().getPendingAssignmentChanges();
    expect(cached, hasLength(1));
    expect(cached.single['desiredMemberId'], 'm1');
  });
}
