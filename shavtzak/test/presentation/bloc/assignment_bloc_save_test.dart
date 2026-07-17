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
import 'package:shavtzak/core/utils/crud_action_result.dart';
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

    // POST-WINDOWING (assignments-slot-build-unification, task 2a): the
    // RebuildAssignmentSlots (stage/filter/rehydrate/save-rebuild) path no
    // longer does a one-shot getAllEvents()/getAllAssignments() read — it now
    // shares _windowEventsMap/getCurrentAssignments() with the live-stream
    // path (seeded via each test's own event/assignment-stream emissions).
    // No stubs needed here any more.

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

  test(
      'a second SaveStagedChanges dispatched while one is already in flight '
      'is rejected by the re-entrancy guard (no double write)', () async {
    // Backs the batch write with a Completer so the test controls exactly
    // when it resolves, keeping the first save "in flight" on demand.
    final batchCompleter = Completer<void>();
    when(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).thenAnswer((_) => batchCompleter.future);

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

    // Stage m1 into the empty medic slot.
    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isTrue);

    // First save: reaches the awaited batch write and pends there
    // (batchCompleter is not yet resolved).
    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();

    // Second save dispatched WHILE the first is still in flight. flutter_bloc's
    // default event transformer runs same-type events concurrently, so
    // without the _saveInFlight guard this would call saveAssignmentsBatch a
    // second time — a double write.
    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();

    // Let the one legitimate write complete.
    batchCompleter.complete();
    await pumpEventQueue();

    verify(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).called(1);
    expect(bloc.hasStagedChanges, isFalse); // cleared by the one save that ran
  });

  // --- FIX A: discard-during-save race --------------------------------------
  //
  // The leave-guard's tab-switch Save runs without the screen's blocking
  // overlay, so the grid stays interactive during an in-flight save. A
  // discard dispatched in that window must not clear _stagedChanges: the
  // save already captured its own creates/updates/deletes snapshot before
  // the discard runs, so it writes anyway and the discard would otherwise be
  // silently overridden.

  test(
      'DiscardAllStagedChanges dispatched while a save is in flight does not '
      'clear staged changes', () async {
    final batchCompleter = Completer<void>();
    when(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).thenAnswer((_) => batchCompleter.future);

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

    // Save reaches the awaited batch write and pends there.
    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();

    // A discard dispatched WHILE the save is in flight must be rejected by
    // the _saveInFlight guard.
    bloc.add(const DiscardAllStagedChanges());
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isTrue);
    final cachedMidSave = await UserCacheService().getPendingAssignmentChanges();
    expect(cachedMidSave, hasLength(1)); // NOT wiped by the rejected discard

    // Let the save resolve — its own success path clears the applied change.
    batchCompleter.complete();
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isFalse);
  });

  test(
      'DiscardStagedSlot dispatched while a save is in flight does not clear '
      'the staged change', () async {
    final batchCompleter = Completer<void>();
    when(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).thenAnswer((_) => batchCompleter.future);

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

    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();

    bloc.add(const DiscardStagedSlot('e1_medic_0'));
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isTrue);

    batchCompleter.complete();
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isFalse);
  });

  test(
      'a new edit staged during an in-flight save survives the success-path '
      'cache write instead of being wiped by a blanket clear', () async {
    final batchCompleter = Completer<void>();
    when(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).thenAnswer((_) => batchCompleter.future);

    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    // Two future events so there are two independent empty slots to stage —
    // POST-WINDOWING, Path A (RebuildAssignmentSlots, driven by staging/save
    // below) reads events from _windowEventsMap, so both must be seeded via
    // the event stream (the getAllEvents() override this test used to need
    // is gone: Path A no longer calls it at all).
    eventStream.add([futureEvent('e1'), futureEvent('e2')]);
    roleStream.add([medicRole()]);
    assignmentStream.add(const <Assignment>[]); // both slots start empty
    // e1 and e2 land on the SAME calendar day (futureEvent has no explicit
    // day param), so staging both makes them same-day cross-event candidates
    // for each other. That same-day loop needs a resolvable member map —
    // POST-WINDOWING it reads _windowMembersMap (populated only via this
    // stream), not the old getActiveTeamMembers() fetch — so, unlike before
    // this task, this test must seed it explicitly or the rebuild after the
    // second StageMemberChange below throws (empty-list .first fallback).
    teamStream.add([member('m1'), member('m2')]);
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final slotE1 = loaded.slots.firstWhere(
        (s) => s.event.id == 'e1' && s.role.key == 'medic' && s.slotIndex == 0);
    final slotE2 = loaded.slots.firstWhere(
        (s) => s.event.id == 'e2' && s.role.key == 'medic' && s.slotIndex == 0);

    // Stage a fill on e1 and start the save (pends on the Completer).
    bloc.add(StageMemberChange(slot: slotE1, member: member('m1')));
    await pumpEventQueue();
    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();

    // While that save is in flight, stage a NEW edit on a different slot
    // (e2). The screen has no blocking overlay during this leave-guard Save,
    // so the grid stays interactive and this is a legitimate user action —
    // it lands in _stagedChanges AFTER appliedKeys was captured by the save.
    bloc.add(StageMemberChange(slot: slotE2, member: member('m2')));
    await pumpEventQueue();
    expect(bloc.stagedCount, 2); // e1 (mid-save) and e2 (new) both staged

    // Let the one in-flight save resolve successfully.
    batchCompleter.complete();
    await pumpEventQueue();

    // e1's staged change was applied by the save and removed; e2's survives
    // (it was staged after appliedKeys was captured, so it's not part of
    // this save's applied set).
    expect(bloc.hasStagedChanges, isTrue);
    expect(bloc.stagedCount, 1);
    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, contains('e2_medic_0'));
    expect(after.stagedSlotKeys, isNot(contains('e1_medic_0')));

    // The cache must reflect the survivor, NOT be blanket-cleared (the bug:
    // clearPendingAssignmentChanges() here would wipe e2's entry too, losing
    // it from crash-recovery even though it correctly stayed in memory).
    final cached = await UserCacheService().getPendingAssignmentChanges();
    expect(cached, hasLength(1));
    expect(cached.single['slotKey'], 'e2_medic_0');
    expect(cached.single['desiredMemberId'], 'm2');
  });

  // --- Task 3: fail-loud Save for a baseline-anchored change whose DB row --
  // --- is gone at save time -------------------------------------------------
  //
  // Windowing (assignments-slot-build-unification, task 2a) already closed
  // the main way a staged change could outlive its DB row (an out-of-window
  // assignment reachable via stage but invisible to Save's windowed
  // dbByKey). This covers the residual edge case: the DB row genuinely
  // existed when the slot was staged (baselineMemberId != null, seeded from
  // the slot's real DB occupant at first touch — see _seedStaged) but is
  // gone by the time Save runs, e.g. a co-admin deleted it concurrently.
  // Before this fix, _onSaveStagedChanges treated ANY staged-clear-with-no-
  // db-row as a "clear-noop": zero writes queued, the staged entry silently
  // dropped, and the batch reported a bare 'נשמרו 0 שינויים' — indistinguishable
  // from the LEGITIMATE no-op (clearing a slot that was already empty in the
  // DB, baselineMemberId == null). The member would then reappear via the
  // next live-stream tick with no indication the clear was ever lost.

  test(
      'a staged clear anchored to a real DB member (baselineMemberId != '
      'null) whose DB row is gone at save time is reported as a skip, not '
      'a silent 0-change success', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    final a1 = assignment('a1', 'e1', 'm1');
    assignmentStream.add([a1]); // DB starts with m1 in medic-0
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final filledMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(filledMedicSlot.currentAssignment!.teamMemberId, 'm1');

    // Stage a clear on the filled slot. _seedStaged captures baselineMemberId
    // from the slot's CURRENT db occupant (m1) — this staged change is
    // baseline-anchored, unlike a clear staged on a slot that started empty.
    bloc.add(StageMemberChange(slot: filledMedicSlot, member: null));
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isTrue);

    // Simulate a concurrent delete: a1's DB row is gone by the time Save
    // runs. This re-emits cacheCurrentAssignments([]) on the repository
    // mock, so getCurrentAssignments() — the raw dbByKey source
    // _onSaveStagedChanges reads — reports nothing for this slot, exactly
    // as if another admin deleted a1 out from under this staged edit.
    assignmentStream.add(const <Assignment>[]);
    await pumpEventQueue();

    final completer = Completer<CrudActionResult>();
    bloc.add(SaveStagedChanges(completion: completer));
    await pumpEventQueue();

    // Nothing to write for this slot: the expected DB row is gone, so there
    // is nothing to delete (and, per the rule, nothing should be silently
    // fabricated as a create either).
    final captured = verify(assignmentRepo.saveAssignmentsBatch(
      creates: captureAnyNamed('creates'),
      updates: captureAnyNamed('updates'),
      deletes: captureAnyNamed('deletes'),
    )).captured;
    expect(captured[0] as List<Assignment>, isEmpty); // creates
    expect(captured[1] as List<Assignment>, isEmpty); // updates
    expect(captured[2] as List<String>, isEmpty); // deletes

    // The completion message MUST surface the skip. A bare 'נשמרו 0 שינויים'
    // here IS the silent-loss bug this test guards against — this assertion
    // fails against the pre-fix behavior (which reported exactly that
    // string unconditionally whenever a staged clear hit a missing DB row,
    // with no way to tell a real loss from a legitimate no-op).
    final result = await completer.future;
    expect(result.isSuccess, isTrue);
    expect(result.message, isNot('נשמרו 0 שינויים'));
    expect(result.message, contains('דולגו'));
    expect(result.message, contains('1'));

    // The now-meaningless staged entry (its anchor DB row is gone) is
    // cleaned up rather than left dirty forever.
    expect(bloc.hasStagedChanges, isFalse);
  });

  test(
      'a normal clear whose DB row IS present still deletes it and reports '
      'a plain success with no skip wording', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    final a1 = assignment('a1', 'e1', 'm1');
    assignmentStream.add([a1]); // DB starts with m1 in medic-0
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final filledMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);

    // Stage a clear (baseline: m1/a1) — the DB row stays intact this time.
    bloc.add(StageMemberChange(slot: filledMedicSlot, member: null));
    await pumpEventQueue();

    final completer = Completer<CrudActionResult>();
    bloc.add(SaveStagedChanges(completion: completer));
    await pumpEventQueue();

    final captured = verify(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: captureAnyNamed('deletes'),
    )).captured;
    final deletes = captured.single as List<String>;
    expect(deletes, [a1.id]); // the existing DB doc is actually deleted

    final result = await completer.future;
    expect(result.isSuccess, isTrue);
    expect(result.message, 'נשמרו 1 שינויים'); // unchanged, no skip suffix
    expect(bloc.hasStagedChanges, isFalse);
  });

  // --- Counterpart to the fail-loud skip: an EXPLICIT override of a baseline-
  // --- anchored change whose DB row is gone must RE-CREATE, not skip ---------
  //
  // The skip-not-found branch above is for the UNRESOLVED lossy case. When the
  // admin is shown the Save-time conflict dialog and explicitly chooses override
  // ("my change wins" — דרוס DB / צור מחוץ למכסה), that is a deliberate
  // instruction to bring the row back. Before this fix the skip-not-found branch
  // fired FIRST and intercepted the override, so the row the admin asked to
  // restore was silently dropped ('1 דולגו · השיבוץ כבר לא קיים') instead of
  // re-created.

  test(
      'an explicit overrideDb resolution of a baseline-anchored change whose '
      'DB row is gone RE-creates the row (a create) instead of skipping it',
      () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    final a1 = assignment('a1', 'e1', 'm1');
    assignmentStream.add([a1]); // DB starts with m1 in medic-0
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final filledMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);

    // Stage a NOTES edit on the filled slot (baseline: m1/a1, desired member
    // unchanged = m1). _seedStaged anchors baselineMemberId to m1 and
    // desiredAssignmentId to a1's id.
    bloc.add(StageNotesChange(slot: filledMedicSlot, notes: 'note-edited'));
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isTrue);

    // Concurrent delete: a1's DB row is gone by Save time (getCurrentAssignments
    // no longer reports it) — exactly the case that produces a Save-time
    // targetRemoved conflict.
    assignmentStream.add(const <Assignment>[]);
    await pumpEventQueue();

    // The admin resolved that conflict as override in the dialog.
    final completer = Completer<CrudActionResult>();
    bloc.add(SaveStagedChanges(
      resolutions: const {'e1_medic_0': ConflictResolution.overrideDb},
      completion: completer,
    ));
    await pumpEventQueue();

    // Override => RE-create the deleted row (a create keyed to a1's original
    // id, carrying m1 + the edited notes), NOT a skip-not-found.
    final captured = verify(assignmentRepo.saveAssignmentsBatch(
      creates: captureAnyNamed('creates'),
      updates: captureAnyNamed('updates'),
      deletes: captureAnyNamed('deletes'),
    )).captured;
    final creates = captured[0] as List<Assignment>;
    expect(creates, hasLength(1));
    expect(creates.single.id, a1.id); // re-created with the ORIGINAL id
    expect(creates.single.teamMemberId, 'm1');
    expect(creates.single.notes, 'note-edited');
    expect(captured[1] as List<Assignment>, isEmpty); // no updates
    expect(captured[2] as List<String>, isEmpty); // no deletes

    // A plain success — NOT the '... דולגו' skip wording.
    final result = await completer.future;
    expect(result.isSuccess, isTrue);
    expect(result.message, isNot(contains('דולגו')));
    expect(bloc.hasStagedChanges, isFalse);
  });
}
