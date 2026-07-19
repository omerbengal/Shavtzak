// Tests for AssignmentBloc's staged quota-changing actions (Task 6):
// StageSlotDeletion marks a slot for deletion (lowering the derived quota by
// 1 only when the slot is IN-quota), and StageManualAdd appends a staged
// fill beyond the live quota (raising the derived quota by 1). Both seed
// `_baselineQuota` from the event's live `roleRequirements` on first touch,
// so `derivedQuota` = baseline + adds − in-quota deletions reflects the
// admin's INTENDED quota independent of the (not-yet-written) DB value.
//
// Deliberately NOT asserted here (Task 7 territory — rendering the derived
// quota on the grid): `state.stagedDeletionSlotKeys` (a state field Task 7
// adds) and the medic slot COUNT growing from 2 to 3 rows. This file only
// covers the bloc-level contract Task 6 is responsible for: derivedQuota,
// hasStagedChanges, and stagedSlotKeys (which already exists and is simply
// `_stagedChanges.keys`).
//
// Harness copied from assignment_bloc_staging_test.dart (mockito repo mocks
// + StreamControllers + entity builders); reuses that sibling's generated
// mocks (assignment_bloc_slots_refetch_test.mocks.dart) since it mocks the
// exact same four repository types.

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

  // Future event (survives showPastEvents) with a 2-slot medic quota by
  // default, matching the two seeded DB assignments (m1@0, m2@1) used below.
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
      roleRequirements: roleRequirements ?? const {'medic': 2},
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
        .thenAnswer((_) async => [member('m1'), member('m2')]);
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

  /// Loads [bloc] with event e1 (medic quota 2, per [futureEvent]'s default)
  /// and [dbAssignments], returning the resulting AssignmentSlotsLoaded state
  /// so callers can pull real AssignmentSlot fixtures out of it (rather than
  /// hand-building ones that could drift from what the bloc actually emits).
  Future<AssignmentSlotsLoaded> loadWithAssignments(
    AssignmentBloc bloc,
    List<Assignment> dbAssignments,
  ) async {
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    assignmentStream.add(dbAssignments);
    await pumpEventQueue();
    return bloc.state as AssignmentSlotsLoaded;
  }

  test('StageSlotDeletion lowers the derived quota by 1 and marks the slot',
      () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    final loaded = await loadWithAssignments(bloc, [
      assignment('a1', 'e1', 'm1', slotIndex: 0),
      assignment('a2', 'e1', 'm2', slotIndex: 1),
    ]);

    final slot1 = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 1);
    expect(slot1.isOffQuota, isFalse); // in-quota (baseline quota is 2)

    bloc.add(StageSlotDeletion(slot1));
    await pumpEventQueue();

    expect(bloc.derivedQuota('e1', 'medic'), 1); // 2 baseline − 1 deletion
    expect(bloc.hasStagedChanges, isTrue);
    final state = bloc.state as AssignmentSlotsLoaded;
    expect(state.stagedSlotKeys, contains('e1_medic_1'));
  });

  test(
      'StageManualAdd raises the derived quota by 1 and stages a fill at '
      'the appended slot', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadWithAssignments(bloc, [
      assignment('a1', 'e1', 'm1', slotIndex: 0),
      assignment('a2', 'e1', 'm2', slotIndex: 1),
    ]);

    bloc.add(StageManualAdd(
      event: futureEvent('e1'),
      member: member('m9'),
      roleType: 'medic',
    ));
    await pumpEventQueue();

    expect(bloc.derivedQuota('e1', 'medic'), 3); // 2 baseline + 1 add
    expect(bloc.hasStagedChanges, isTrue);
    final state = bloc.state as AssignmentSlotsLoaded;
    expect(state.stagedSlotKeys,
        contains('e1_medic_2')); // appended at slotIndex = liveQuota (2)
  });

  test('deleting an off-quota row does NOT change the quota', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    final loaded = await loadWithAssignments(bloc, [
      assignment('a1', 'e1', 'm1', slotIndex: 0),
      assignment('a2', 'e1', 'm2', slotIndex: 1),
      // Off-quota: quota is 2 (indices 0-1 are in-quota), so index 5 renders
      // as an off-quota row instead of landing in a normal quota slot.
      assignment('a3', 'e1', 'm3', slotIndex: 5),
    ]);

    final offQuotaSlot = loaded.slots.firstWhere(
        (s) => s.role.key == 'medic' && s.isOffQuota && s.slotIndex == 5);

    bloc.add(StageSlotDeletion(offQuotaSlot));
    await pumpEventQueue();

    expect(bloc.derivedQuota('e1', 'medic'), 2); // unchanged (5 >= baseline 2)
  });
}
