// Tests for AssignmentBloc.classifyStagedConflicts: comparing each staged
// change's baseline (the DB state captured when the slot was first touched)
// against the CURRENT DB state to classify A-F staged-vs-DB conflicts.
//
// Harness copied from assignment_bloc_staging_test.dart (mockito repo mocks
// + StreamControllers + entity builders); reuses that sibling's generated
// mocks (`assignment_bloc_slots_refetch_test.mocks.dart`) instead of its own
// @GenerateMocks, since it mocks the exact same four repository types.

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
import 'package:shavtzak/presentation/bloc/assignment/models/assignment_conflict.dart';

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

  // ---- Builders for minimal valid entities (mirrors the sibling file) -----

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
  }) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: roleType,
        slotIndex: slotIndex,
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
    when(assignmentRepo.getAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) async => const <Assignment>[]);
    when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

    // Used by the RebuildAssignmentSlots (filter/rehydrate) path.
    when(eventRepo.getAllEvents()).thenAnswer((_) async => [futureEvent('e1')]);
    when(assignmentRepo.getAllAssignments())
        .thenAnswer((_) async => const <Assignment>[]);
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

  test('classifies a concurrently-filled slot as slotTaken', () async {
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

    // Stage m1 into the empty medic slot (baseline: empty).
    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();

    // DB now shows m9 in that same slot (someone else got there first).
    assignmentStream.add([assignment('a9', 'e1', 'm9', slotIndex: 0)]);
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    final conflicts = bloc.classifyStagedConflicts(after.slots);
    expect(conflicts, hasLength(1));
    expect(conflicts.single.type, AssignmentConflictType.slotTaken);
    expect(conflicts.single.slotKey, 'e1_medic_0');
  });

  test('classifies a staged clear colliding with a new DB occupant as clearCollision',
      () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    // DB starts with m1 already in medic-0.
    assignmentStream.add([assignment('a1', 'e1', 'm1', slotIndex: 0)]);
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final filledMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(filledMedicSlot.currentAssignment!.teamMemberId, 'm1');

    // Stage a clear of the slot (baseline: m1).
    bloc.add(StageMemberChange(slot: filledMedicSlot, member: null));
    await pumpEventQueue();

    // DB now shows m9 in that slot (someone else reassigned it in the meantime).
    assignmentStream.add([assignment('a9', 'e1', 'm9', slotIndex: 0)]);
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    final conflicts = bloc.classifyStagedConflicts(after.slots);
    expect(conflicts, hasLength(1));
    expect(conflicts.single.type, AssignmentConflictType.clearCollision);
    expect(conflicts.single.slotKey, 'e1_medic_0');
  });

  test('classifies a staged fill whose slot no longer exists as slotVanished',
      () async {
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

    // Stage m1 into the empty medic slot.
    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();

    // DB now shows the event's medic quota reduced to 0 - the slot itself no
    // longer exists in the grid.
    eventStream.add([futureEvent('e1', roleRequirements: const {'medic': 0})]);
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    expect(
      after.slots
          .where((s) => s.role.key == 'medic' && s.slotIndex == 0)
          .isEmpty,
      isTrue,
    );

    final conflicts = bloc.classifyStagedConflicts(after.slots);
    expect(conflicts, hasLength(1));
    expect(conflicts.single.type, AssignmentConflictType.slotVanished);
    expect(conflicts.single.slotKey, 'e1_medic_0');
    expect(conflicts.single.discardOnly, isFalse);
  });

  test('returns no conflicts when the DB has not diverged from the baseline',
      () async {
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

    // Stage m1 into the empty medic slot.
    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();

    // DB re-emits the same (still empty) snapshot - no divergence.
    assignmentStream.add(const <Assignment>[]);
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    final conflicts = bloc.classifyStagedConflicts(after.slots);
    expect(conflicts, isEmpty);
  });
}
