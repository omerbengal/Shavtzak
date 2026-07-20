// Regression test: a member whose assignment in an event is staged for
// deletion (swipe-delete) or staged-cleared must be freed for reassignment
// to OTHER slots in the SAME event immediately (unsaved) — not just excluded
// from OTHER events on the same day (already covered by
// assignment_bloc_staged_samedy_availability_test.dart, which is the
// cross-event case).
//
// Repro (pre-fix): event E has a medic quota of 2. Slot #0 is filled by
// member T (a DB assignment); slot #1 is empty. Staging a deletion or a
// clear on T's row (slot #0) should immediately free T to be offered again
// in slot #1's dropdown, since T will no longer be assigned to E once Save
// runs. Before the fix, T stayed excluded from slot #1 until Save.
//
// Root cause: the same-event "already assigned" set gating each slot's
// availableMembers/alreadyAssignedMembers split (`assignedMemberIds`, computed
// once per event in both _buildSlotsFromAssignments and
// _onRebuildAssignmentSlotsFromData) was computed from the RAW DB
// `assignments` list, never from the staged-effective view
// (_stagedEffectiveAssignments) already used for the cross-event same-day
// exclusion. A staged deletion (markedForDeletion) or staged clear doesn't
// remove the member from the raw DB list, so the member stayed in
// `assignedMemberIds` and was excluded from every OTHER slot's dropdown in
// the event until Save.
//
// Harness copied from assignment_bloc_quota_staging_test.dart (mockito repo
// mocks + StreamControllers + entity builders), reusing its "bump the DB
// quota via the event stream" pattern (see its "phantom row" test) to turn a
// filled quota-1 slot into a quota-2 grid with one empty slot (#1) to
// reassign the freed member into.

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
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot.dart';

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

  // ---- Builders for minimal valid entities (mirrors the sibling harnesses) -

  // isPermanent: true so the member is available by default (see
  // TeamMember.isAvailableForEventWithTime) — non-permanent members are
  // UNAVAILABLE by default and would need explicit availableEventIds, which
  // would defeat the point of this test (T must be a genuine reassignment
  // candidate for slot #1 once freed from slot #0).
  TeamMember member(String id) => TeamMember(
        id: id,
        name: 'member-$id',
        isActive: true,
        isPermanent: true,
        constraints: const [],
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'key-$id',
      );

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
    when(eventRepo.getEventsByDateRange(any, any)).thenAnswer((_) async =>
        [futureEvent('e1', roleRequirements: const {'medic': 1})]);
    when(teamRepo.getActiveTeamMembers())
        .thenAnswer((_) async => [member('T')]);
    when(assignmentRepo.getAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) async => const <Assignment>[]);
    when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

    // Used by the RebuildAssignmentSlots (filter/rehydrate) path.
    when(eventRepo.getAllEvents()).thenAnswer((_) async =>
        [futureEvent('e1', roleRequirements: const {'medic': 1})]);
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

  AssignmentSlot slotForIndex(AssignmentBloc bloc, int index) {
    final s = bloc.state as AssignmentSlotsLoaded;
    return s.slots.firstWhere((slot) =>
        slot.event.id == 'e1' &&
        slot.role.key == 'medic' &&
        slot.slotIndex == index);
  }

  /// Loads e1 with medic quota 1 and T filled at slot #0 (a DB assignment),
  /// then bumps the quota to 2 via the event stream — matching how
  /// assignment_bloc_quota_staging_test.dart's "phantom row" test simulates a
  /// live event-form quota change — opening up an empty slot #1 for T to be
  /// reassigned into once freed from slot #0.
  Future<void> loadFilledSlotThenGrowQuota(AssignmentBloc bloc) async {
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1', roleRequirements: const {'medic': 1})]);
    roleStream.add([medicRole()]);
    teamStream.add([member('T')]);
    assignmentStream.add([assignment('a1', 'e1', 'T', slotIndex: 0)]);
    await pumpEventQueue();

    // Co-admin (or the admin's own event-form edit) raises the live DB quota
    // 1 -> 2, opening an empty slot #1.
    eventStream.add([futureEvent('e1', roleRequirements: const {'medic': 2})]);
    await pumpEventQueue();
  }

  test(
      'base case: the member filling slot #0 is excluded from slot #1\'s '
      'dropdown in the same event (guards the pre-staging behavior)',
      () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadFilledSlotThenGrowQuota(bloc);

    final slot0 = slotForIndex(bloc, 0);
    final slot1 = slotForIndex(bloc, 1);

    expect(slot0.currentAssignment?.teamMemberId, 'T');
    expect(slot1.availableMembers.map((m) => m.id), isNot(contains('T')));
    expect(slot1.alreadyAssignedMembers.map((m) => m.id), contains('T'));
  });

  test(
      'staging a SLOT DELETION on T\'s row (slot #0) frees T for slot #1\'s '
      'dropdown immediately (unsaved)', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadFilledSlotThenGrowQuota(bloc);

    final slot0 = slotForIndex(bloc, 0);
    // Precondition (same as the base-case test): T starts excluded from #1.
    expect(slotForIndex(bloc, 1).availableMembers.map((m) => m.id),
        isNot(contains('T')));

    bloc.add(StageSlotDeletion(slot0));
    await pumpEventQueue();

    final state = bloc.state as AssignmentSlotsLoaded;
    // Confirms the deletion actually staged (still dirty / red-striped).
    expect(state.stagedDeletionSlotKeys, contains('e1_medic_0'));

    final slot1After = slotForIndex(bloc, 1);
    // THE FIX: T must now be offered in slot #1's dropdown, and must no
    // longer be reported as already-assigned to e1.
    expect(slot1After.availableMembers.map((m) => m.id), contains('T'));
    expect(slot1After.alreadyAssignedMembers.map((m) => m.id),
        isNot(contains('T')));
  });

  test(
      'staging a CLEAR on T\'s row (slot #0) also frees T for slot #1\'s '
      'dropdown immediately (unsaved)', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadFilledSlotThenGrowQuota(bloc);

    final slot0 = slotForIndex(bloc, 0);

    bloc.add(StageMemberChange(slot: slot0, member: null));
    await pumpEventQueue();

    final slot1After = slotForIndex(bloc, 1);
    expect(slot1After.availableMembers.map((m) => m.id), contains('T'));
    expect(slot1After.alreadyAssignedMembers.map((m) => m.id),
        isNot(contains('T')));
  });

  test(
      'a live Firestore stream emit while T is stage-deleted from slot #0 '
      'keeps T available in slot #1 (the STREAM rebuild path is also '
      'staged-aware)', () async {
    // Guards the SECOND same-event loop — the one inside
    // _onRebuildAssignmentSlotsFromData (the live-stream rebuild path),
    // distinct from _buildSlotsFromAssignments (the stage/filter path
    // exercised above). Because Firestore emits fire constantly, a staged
    // deletion that only the stage path respected would be re-hidden the
    // instant any stream tick arrived.
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadFilledSlotThenGrowQuota(bloc);

    final slot0 = slotForIndex(bloc, 0);
    bloc.add(StageSlotDeletion(slot0));
    await pumpEventQueue();
    expect(
        slotForIndex(bloc, 1).availableMembers.map((m) => m.id),
        contains('T'),
        reason: 'stage path should already free T for slot #1');

    // A live Firestore emit lands — T is STILL assigned to slot #0 in the DB
    // (the stage is unsaved). This drives _onRebuildAssignmentSlotsFromData,
    // whose OWN same-event computation must also read the staged-effective
    // assignments.
    assignmentStream.add([assignment('a1', 'e1', 'T', slotIndex: 0)]);
    await pumpEventQueue();

    final state = bloc.state as AssignmentSlotsLoaded;
    expect(state.stagedDeletionSlotKeys, contains('e1_medic_0'));
    final slot1After = slotForIndex(bloc, 1);
    expect(slot1After.availableMembers.map((m) => m.id), contains('T'));
  });

  test(
      'staging a FILL into slot #1 still counts the filled member as '
      "assigned to e1 (no same-event double-booking regression)", () async {
    // Guards the OTHER direction of the fix: making assignedMemberIds
    // staged-aware must not stop counting a staged fill/swap as "assigned" —
    // _stagedEffectiveAssignments adds the desired assignment back in for
    // any staged change that is neither a clear nor a deletion, so a member
    // staged INTO one slot must still be excluded from every OTHER slot in
    // the same event, exactly like a real DB assignment would.
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadFilledSlotThenGrowQuota(bloc);
    // Grow the quota again (2 -> 3) so there are TWO empty slots (#1, #2) to
    // stage into / observe from.
    eventStream.add([futureEvent('e1', roleRequirements: const {'medic': 3})]);
    await pumpEventQueue();
    // Make U a known active (medic-capable) member so the staged fill can
    // render/participate in availability like the quota-staging harness does
    // for its manual-add tests.
    teamStream.add([member('T'), member('U')]);
    await pumpEventQueue();

    final slot1 = slotForIndex(bloc, 1);
    bloc.add(StageMemberChange(slot: slot1, member: member('U')));
    await pumpEventQueue();

    final slot2After = slotForIndex(bloc, 2);
    // THE GUARD: U must NOT be offered again in slot #2 — U is already
    // (staged-)assigned to e1 via slot #1.
    expect(slot2After.availableMembers.map((m) => m.id), isNot(contains('U')));
    expect(slot2After.alreadyAssignedMembers.map((m) => m.id), contains('U'));
    // T (still DB-assigned to slot #0, untouched by this staging action) is
    // likewise still reported as already-assigned, unaffected by the fix.
    expect(slot2After.alreadyAssignedMembers.map((m) => m.id), contains('T'));
  });
}
