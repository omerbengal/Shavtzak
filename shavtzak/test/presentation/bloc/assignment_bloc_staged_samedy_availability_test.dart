// Regression test for a staged-Save bug: the assignment dropdown's
// cross-event same-day availability ignored staged (unsaved) changes.
//
// Repro: event X (empty medic slot) and event Y are on the SAME day. Member T
// is assigned to Y. In X's medic dropdown, T is correctly hidden (booked
// same-day). If the admin STAGE-CLEARS T from Y (unsaved), T should reappear
// in X's dropdown — before the fix, it didn't, because the same-day exclusion
// in AssignmentBloc._buildSlotsFromAssignments was computed from the raw DB
// `assignments` list, never from _stagedChanges.
//
// Fix: AssignmentBloc._stagedEffectiveAssignments(dbAssignments) applies the
// in-memory staged changes (clear removes, fill/swap replaces) to the DB
// assignment list, and the same-day loop in _buildSlotsFromAssignments now
// iterates that staged-effective list instead of the raw DB list. Everything
// else in that method (currentAssignment, assignedMemberIds, the optimistic
// merge) is untouched.
//
// Harness copied from assignment_bloc_staging_test.dart (mockito repo mocks +
// StreamControllers + entity builders, itself copied from
// assignment_bloc_slots_refetch_test.dart), extended with a same-day two-event
// builder (`eventOnDay`) since the sibling harnesses only ever load one event.
//
// Why StageMemberChange reaches the code under test: _onStageMemberChange
// stages the edit then dispatches RebuildAssignmentSlots, whose handler
// (_onRebuildAssignmentSlots) calls _buildSlotsFromAssignments with
// `_repository.getAllAssignments()` (a ONE-SHOT fetch, not the live stream) —
// so `assignmentRepo.getAllAssignments()` is stubbed with the DB assignment
// (T -> Y) that stays fixed for the whole test, exactly mirroring an unsaved
// stage sitting on top of an unchanged database.

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
  // Computed once (not per-event) so X and Y land on the same calendar day by
  // construction — no reliance on two DateTime.now() calls landing on the
  // same day.
  final sharedDay = DateTime.now().add(const Duration(days: 30));

  // ---- Builders for minimal valid entities (mirrors the sibling harness) --

  // isPermanent: true so the member is available by default (see
  // TeamMember.isAvailableForEventWithTime) — non-permanent members are
  // UNAVAILABLE by default and would need explicit availableEventIds, which
  // would defeat the point of this test (T must be a genuine same-day
  // availability candidate, per the bug repro).
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

  // Same as the sibling harness's `futureEvent`, but takes an explicit `day`
  // so two events can be pinned onto the SAME calendar day deterministically.
  Event eventOnDay(String id, DateTime day,
      {Map<String, int>? roleRequirements}) {
    final start = DateTime(day.year, day.month, day.day, 9, 0);
    final end = DateTime(day.year, day.month, day.day, 17, 0);
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
    when(eventRepo.getEventsByDateRange(any, any)).thenAnswer(
        (_) async => [eventOnDay('x1', sharedDay), eventOnDay('y1', sharedDay)]);
    when(teamRepo.getActiveTeamMembers())
        .thenAnswer((_) async => [member('T')]);
    when(assignmentRepo.getAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) async => const <Assignment>[]);
    when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

    // Used by the RebuildAssignmentSlots (stage/filter/rehydrate) path — this
    // is the ONE-SHOT read _buildSlotsFromAssignments uses, i.e. the DB truth
    // that staged changes are laid on top of.
    when(eventRepo.getAllEvents()).thenAnswer(
        (_) async => [eventOnDay('x1', sharedDay), eventOnDay('y1', sharedDay)]);
    when(assignmentRepo.getAllAssignments())
        .thenAnswer((_) async => [assignment('aY', 'y1', 'T')]);
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

  /// Loads the bloc with X (empty medic slot) and Y (T assigned to medic slot
  /// 0), both sharing [sharedDay], and pushes matching data through every
  /// live stream so the first-paint gate opens.
  Future<void> loadTwoSameDayEvents(AssignmentBloc bloc) async {
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([eventOnDay('x1', sharedDay), eventOnDay('y1', sharedDay)]);
    roleStream.add([medicRole()]);
    teamStream.add([member('T')]);
    assignmentStream.add([assignment('aY', 'y1', 'T')]);
    await pumpEventQueue();
  }

  AssignmentSlot medicSlotOf(AssignmentSlotsLoaded state, String eventId) =>
      state.slots.firstWhere(
        (s) => s.event.id == eventId && s.role.key == 'medic' && s.slotIndex == 0,
      );

  test(
      'base case: a member booked on a same-day event is excluded from '
      "another event's dropdown (guards the pre-staging behavior)", () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadTwoSameDayEvents(bloc);

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final xSlot = medicSlotOf(loaded, 'x1');
    final ySlot = medicSlotOf(loaded, 'y1');

    // Y really has T assigned.
    expect(ySlot.isFilled, isTrue);
    expect(ySlot.currentAssignment!.teamMemberId, 'T');

    // X must NOT offer T (same-day booked on Y) and must list T as a
    // same-day-booked candidate instead.
    expect(xSlot.availableMembers.map((m) => m.id), isNot(contains('T')));
    expect(xSlot.sameDayAssignedMembers.map((m) => m.id), contains('T'));
  });

  test(
      'stage-clearing T from Y reinstates T as available in X immediately '
      '(unsaved)', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadTwoSameDayEvents(bloc);

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final xSlotBefore = medicSlotOf(loaded, 'x1');
    final ySlotBefore = medicSlotOf(loaded, 'y1');

    // Precondition (same as the base-case test): T starts excluded from X.
    expect(xSlotBefore.availableMembers.map((m) => m.id), isNot(contains('T')));
    expect(
        xSlotBefore.sameDayAssignedMembers.map((m) => m.id), contains('T'));

    // Stage-clear T from Y. This is unsaved — the DB mock (getAllAssignments)
    // keeps returning T -> Y for the rest of the test, exactly like a real
    // unsaved edit sitting on top of an unchanged database.
    bloc.add(StageMemberChange(slot: ySlotBefore, member: null));
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    final xSlotAfter = medicSlotOf(after, 'x1');
    final ySlotAfter = medicSlotOf(after, 'y1');

    // Y shows the staged clear (unsaved, but reflected optimistically).
    expect(ySlotAfter.isFilled, isFalse);
    expect(after.stagedSlotKeys, contains('y1_medic_0'));

    // THE FIX: X's dropdown must now offer T again, and T must no longer be
    // reported as same-day-booked, because the staged clear is reflected in
    // the cross-event same-day computation.
    expect(xSlotAfter.availableMembers.map((m) => m.id), contains('T'));
    expect(
        xSlotAfter.sameDayAssignedMembers.map((m) => m.id), isNot(contains('T')));
  });

  test(
      'a live Firestore stream emit while T is stage-cleared from Y keeps T '
      'available in X (the STREAM rebuild path is also staged-aware)', () async {
    // Guards the SECOND same-day loop — the one inside
    // _onRebuildAssignmentSlotsFromData (the live-stream rebuild path), distinct
    // from _buildSlotsFromAssignments (the stage/filter path exercised above).
    // Because Firestore emits fire constantly, a staged clear that only the
    // stage path respected would be re-hidden the instant any stream tick
    // arrived. Before the fix this test fails (T re-excluded from X after the
    // emit); after it, the staged clear survives the rebuild.
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadTwoSameDayEvents(bloc);

    final ySlotBefore =
        medicSlotOf(bloc.state as AssignmentSlotsLoaded, 'y1');

    // Stage-clear T from Y (goes through the stage path first).
    bloc.add(StageMemberChange(slot: ySlotBefore, member: null));
    await pumpEventQueue();
    expect(
        medicSlotOf(bloc.state as AssignmentSlotsLoaded, 'x1')
            .availableMembers
            .map((m) => m.id),
        contains('T'),
        reason: 'stage path should already free T in X');

    // Now a live Firestore emit lands — T is STILL on Y in the DB (the stage is
    // unsaved). This drives _onRebuildAssignmentSlotsFromData, whose OWN
    // same-day loop must also read the staged-effective assignments.
    assignmentStream.add([assignment('aY', 'y1', 'T')]);
    await pumpEventQueue();

    final afterStream = bloc.state as AssignmentSlotsLoaded;
    final xSlotAfter = medicSlotOf(afterStream, 'x1');

    // The staged clear must survive the stream rebuild...
    expect(afterStream.stagedSlotKeys, contains('y1_medic_0'));
    // ...and X must still offer T (this is what the second fix guarantees).
    expect(xSlotAfter.availableMembers.map((m) => m.id), contains('T'));
    expect(xSlotAfter.sameDayAssignedMembers.map((m) => m.id),
        isNot(contains('T')));
  });
}
