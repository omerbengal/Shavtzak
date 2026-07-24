// Tests for AssignmentBloc's staged-Save core: staging a member/notes edit
// keeps it OFF the database (persisted only to UserCacheService) until an
// explicit Save, and shows up immediately on the grid via the same
// _mergeSlotsWithOptimisticUpdates machinery the (dormant) Optimistic*
// events use — see _stagedAsPendingOperations / _syncPendingOperationsWithStaged
// in AssignmentBloc.
//
// Harness copied from assignment_bloc_slots_refetch_test.dart (mockito repo
// mocks + StreamControllers + entity builders); this file reuses that
// sibling's generated mocks (`assignment_bloc_slots_refetch_test.mocks.dart`)
// instead of its own @GenerateMocks, since it mocks the exact same four
// repository types.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';
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

    // Task SG6: the quota-driven slotAnnotations cleanup (see
    // _stageSlotAnnotationCleanup in AssignmentBloc) STAGES its fix into
    // _stagedSlotAnnotations instead of calling this immediately — it is only
    // ever written via SaveStagedChanges. Stubbed globally anyway so a test
    // that DOES dispatch SaveStagedChanges (the Issue-1 regression test below)
    // doesn't hit a MissingStubError.
    when(eventRepo.updateSlotAnnotation(any, any, any,
        staleKey: anyNamed('staleKey'))).thenAnswer((_) async {});

    // Needed by the Issue-1 regression test, which dispatches SaveStagedChanges
    // on an annotation-only staged set — _onSaveStagedChanges unconditionally
    // calls the assignment-batch write on every Save (see
    // assignment_bloc_staged_annotations_test.dart's identical stub).
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

  /// Task 12: the cache now stores a JSON OBJECT
  /// (`{'changes': [...], 'baselineQuota': {...}}`), not a bare list — decode
  /// down to just the changes list for tests that only care about that shape.
  Future<List<dynamic>> cachedChanges() async {
    final raw = await UserCacheService().getPendingAssignmentChanges();
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    return decoded is List
        ? decoded
        : (decoded['changes'] as List? ?? const []);
  }

  test('staging a member fill marks the slot filled and dirty', () async {
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
    expect(emptyMedicSlot.isFilled, isFalse);

    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    final medicSlot = after.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(medicSlot.isFilled, isTrue);
    expect(medicSlot.currentAssignment!.teamMemberId, 'm1');
    expect(after.stagedSlotKeys, contains('e1_medic_0'));
    expect(bloc.hasStagedChanges, isTrue);
    expect((bloc.state as AssignmentSlotsLoaded).pendingOperations['e1_medic_0']!.type, PendingOperationType.createAssignment);

    // Mirrored to cache (crash recovery) — awaited, not fire-and-forget.
    final cached = await cachedChanges();
    expect(cached, hasLength(1));
    expect(cached.single['slotKey'], 'e1_medic_0');
    expect(cached.single['desiredMemberId'], 'm1');
  });

  test('discarding the staged slot reverts to the DB (empty) and clears dirty',
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
    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isTrue);

    bloc.add(const DiscardStagedSlot('e1_medic_0'));
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, isEmpty);
    expect(bloc.hasStagedChanges, isFalse);
    expect(
      after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0)
          .isFilled,
      isFalse,
    );

    // Cache mirrors the reverted (now-empty) staging map.
    final cached = await cachedChanges();
    expect(cached, isEmpty);
  });

  test(
      'staging a notes-only edit on an already-filled slot keeps the occupant '
      'and marks it dirty', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    assignmentStream.add([assignment('a1', 'e1', 'm1')]);
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final filledMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(filledMedicSlot.isFilled, isTrue);

    bloc.add(StageNotesChange(
      slot: filledMedicSlot,
      notes: 'הערה חשובה',
      semanticLabelId: null,
      alternativePhoneNumber: null,
    ));
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    final medicSlot = after.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(after.stagedSlotKeys, contains('e1_medic_0'));
    expect(bloc.hasStagedChanges, isTrue);
    expect((bloc.state as AssignmentSlotsLoaded).pendingOperations['e1_medic_0']!.type, PendingOperationType.updateAssignment);
    // The occupant is unchanged — only notes were staged.
    expect(medicSlot.currentAssignment!.teamMemberId, 'm1');
    expect(medicSlot.currentAssignment!.notes, 'הערה חשובה');
  });

  test('DiscardAllStagedChanges clears every staged slot and the cache',
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
    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isTrue);
    expect(await cachedChanges(), isNot(isEmpty));

    bloc.add(const DiscardAllStagedChanges());
    await pumpEventQueue();

    expect(bloc.hasStagedChanges, isFalse);
    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, isEmpty);
    expect(await cachedChanges(), isEmpty);
  });

  test(
      'RehydrateStagedChanges tolerates the LEGACY bare-list cache format '
      '(pre-Task-12, no baselineQuota ever persisted): restores the staged '
      'change, renders it on the grid, and leaves the baseline empty',
      () async {
    // Pre-seed the cache as if a previous app session (running OLD code,
    // before Task 12's wrapper-object format) staged this change and never
    // saved (crash recovery scenario) — a bare JSON list, written directly
    // via the JSON shape StagedAssignmentChange.toJson/fromJson round-trip,
    // matching Task 1/2's contract. _onRehydrateStagedChanges must decode
    // this exactly as before (no baseline to restore) rather than choke on
    // the missing wrapper object.
    await UserCacheService().savePendingAssignmentChanges(jsonEncode([
      {
        'slotKey': 'e1_medic_0',
        'eventId': 'e1',
        'roleType': 'medic',
        'slotIndex': 0,
        'desiredMemberId': 'm1',
        'desiredNotes': '',
        'desiredSemanticLabelId': null,
        'desiredAltPhone': null,
        'baselineAssignmentId': null,
        'baselineMemberId': null,
        'baselineNotes': '',
        'baselineSemanticLabelId': null,
        'baselineAltPhone': null,
        'desiredAssignmentId': 'staged-a1',
        'stagedAtMillis': 1000,
      }
    ]));

    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([futureEvent('e1')]);
    roleStream.add([medicRole()]);
    assignmentStream.add(const <Assignment>[]);
    await pumpEventQueue();

    // Before rehydration: nothing staged yet, slot is DB-empty.
    expect(bloc.hasStagedChanges, isFalse);

    bloc.add(const RehydrateStagedChanges());
    await pumpEventQueue();

    expect(bloc.hasStagedChanges, isTrue);
    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, contains('e1_medic_0'));
    final medicSlot = after.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(medicSlot.isFilled, isTrue);
    // Empty baseline: this staged change never touched quota (it's an
    // ordinary fill, baselineMemberId == null meaning the slot merely
    // started empty — not a StageManualAdd/StageSlotDeletion), and a legacy
    // cache never persisted a baseline to begin with. derivedQuota falls
    // back to the raw live quota (1, this file's default) — the tell that
    // no stray baseline got seeded from the legacy rehydrate.
    expect(bloc.derivedQuota('e1', 'medic'), 1);
    expect(medicSlot.currentAssignment!.teamMemberId, 'm1');
  });

  // Task 7: an empty quota slot carries the event's reconciled gap
  // annotation (AssignmentSlot.gapAnnotation), and staging a fresh fill onto
  // that gap carries the note + label over onto the new (staged, optimistic)
  // assignment — see _upsertStagedMember's carry-over seed.
  test(
      'staging a member fill onto an annotated empty gap carries the note '
      '+ label onto the optimistic assignment', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([
      futureEvent('e1').copyWith(slotAnnotations: {
        'medic#0': const SlotAnnotation(note: 'C', labelId: 'L2'),
      }),
    ]);
    roleStream.add([medicRole()]);
    assignmentStream.add(const <Assignment>[]);
    await pumpEventQueue();

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(emptyMedicSlot.currentAssignment, isNull);
    // The empty slot itself now carries the reconciled gap annotation.
    expect(emptyMedicSlot.gapAnnotation, isNotNull);
    expect(emptyMedicSlot.gapAnnotation!.annotation.note, 'C');
    expect(emptyMedicSlot.gapAnnotation!.annotation.labelId, 'L2');

    bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    final medicSlot = after.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(medicSlot.currentAssignment, isNotNull);
    expect(medicSlot.currentAssignment!.teamMemberId, 'm1');
    // Carry-over: the staged fill's optimistic assignment inherits the
    // gap's note + label instead of starting blank.
    expect(medicSlot.currentAssignment!.notes, 'C');
    expect(medicSlot.currentAssignment!.semanticLabelId, 'L2');
    // gapAnnotation's own "null when filled" invariant: now that the slot is
    // optimistically filled, it must no longer carry the gap annotation.
    expect(medicSlot.gapAnnotation, isNull);
  });

  // Task SG6: quota-driven slotAnnotations cleanup STAGES the fix instead of
  // writing immediately. _onRebuildAssignmentSlotsFromData (the live-stream
  // rebuild handler, fired when fresh DB data arrives) computes each role's
  // normalization writes via the pure computeSlotAnnotationNormalization
  // helper and STAGES them into _stagedSlotAnnotations (_stageSlotAnnotationCleanup),
  // so a quota change self-heals the stored keys via the SAME staged-Save path
  // as a manual StageSlotAnnotation edit — never an immediate DB write. The fix
  // shows up right away via the existing Task-3 overlay and is only persisted
  // by SaveStagedChanges.
  group('staged slotAnnotations cleanup on quota change', () {
    test(
        'a note stored on a since-shrunk-out-of-range slot is STAGED as a '
        'DELETE (never drifted onto the surviving gap, never written '
        'immediately)', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([
        futureEvent('e1').copyWith(slotAnnotations: {
          'medic#1': const SlotAnnotation(note: 'x', labelId: 'L'),
        }),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]); // no assignments at all
      await pumpEventQueue();

      // Staged, not written: no DB call from ANY of the several rebuild
      // passes this stream-settling batch drives (each of the three streams'
      // first emit dispatches its own RebuildAssignmentSlotsFromData once the
      // first-paint gate is open).
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));

      final after = bloc.state as AssignmentSlotsLoaded;
      // The orphan-delete is keyed to the note's OWN (gone) slot 1 — NOT
      // drifted onto the free medic#0.
      expect(after.stagedSlotKeys, contains('e1_medic_1'));
      expect(after.stagedSlotKeys, isNot(contains('e1_medic_0')));
      expect(bloc.stagedCount, 1);
      expect(bloc.hasStagedChanges, isTrue);

      // The surviving in-quota gap (slot 0) stays a PLAIN empty slot — the note
      // did not move onto it.
      final medicSlot0 = after.slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 0 && !s.isOffQuota);
      expect(medicSlot0.gapAnnotation, isNull);

      // The orphaned note surfaces as a pending-removal off-quota row (SG7) so
      // the admin can see/Save/Discard it rather than it vanishing silently.
      final orphan = after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.isOffQuota);
      expect(orphan.slotIndex, 1);
      expect(orphan.gapAnnotation!.annotation,
          const SlotAnnotation(note: 'x', labelId: 'L'));

      // Save deletes it from the DB.
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#1', null,
              staleKey: null))
          .called(1);
      expect(bloc.stagedCount, 0);
    });

    test(
        'a note already on its correct (in-range, empty) gap is left '
        'untouched — nothing staged, no write dispatched', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([
        futureEvent('e1').copyWith(slotAnnotations: {
          'medic#0': const SlotAnnotation(note: 'x'),
        }),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]); // no assignments at all
      await pumpEventQueue();

      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));
      final after = bloc.state as AssignmentSlotsLoaded;
      expect(after.stagedSlotKeys, isEmpty);
      expect(bloc.stagedCount, 0);
      expect(bloc.hasStagedChanges, isFalse);
    });

    // ---- Issue 1 regression: the quota-reduction TRIGGER fix -------------
    //
    // Before this fix, an event-form quota reduction dispatched
    // RebaselineQuotasForEvent, whose handler only ever fired
    // RebuildAssignmentSlots (the OTHER rebuild handler) — which never called
    // the cleanup at all. The cleanup only ran once the Firestore event stream
    // happened to re-emit the reduced quota later, so an orphaned note could
    // sit un-cleaned-up right after a quota reduction. This test drives the
    // exact same event (RebaselineQuotasForEvent) WITHOUT any further
    // eventStream emission, proving the cleanup now fires deterministically
    // from that handler itself.
    test(
        'Issue 1 fix: an event-form quota reduction (RebaselineQuotasForEvent) '
        'COMMITS the orphan cleanup immediately (writes it, nothing staged), '
        'without waiting for the event stream to re-deliver the reduced quota',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      // Quota 2: slot 0 filled by 'm1', a note stored on slot 1 (in-range,
      // empty) — a valid annotation at load time.
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 2}).copyWith(
          slotAnnotations: {
            'medic#1': const SlotAnnotation(note: 'y', labelId: 'L2'),
          },
        ),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add([assignment('a1', 'e1', 'm1', slotIndex: 0)]);
      await pumpEventQueue();

      // At quota 2 the note is valid: nothing staged, no write.
      expect(bloc.stagedCount, 0);
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));

      // Reduce 2 -> 1 via the event-form modal (committed by event.update).
      // Slot 1 (holding the note) no longer exists and slot 0 is filled, so the
      // note is a TRUE ORPHAN. NO further eventStream emission — proving
      // _onRebaselineQuotasForEvent itself commits the cleanup.
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 1}));
      await pumpEventQueue();

      // WRITTEN immediately, NOTHING staged (so a later Discard can't strand
      // the orphan). This is the fix: the committed quota drop and its forced
      // orphan cleanup are both committed, not split into committed-quota +
      // discardable-cleanup.
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#1', null,
              staleKey: null))
          .called(1);
      expect(bloc.stagedCount, 0);
      expect(bloc.hasStagedChanges, isFalse);

      // The reduced quota is reflected immediately: exactly ONE in-quota medic
      // slot (index 0), and NO pending-removal off-quota row (the orphan was
      // committed, not staged for review).
      final after = bloc.state as AssignmentSlotsLoaded;
      final medicSlots =
          after.slots.where((s) => s.role.key == 'medic').toList();
      expect(medicSlots, hasLength(1));
      expect(medicSlots.single.slotIndex, 0);
      expect(medicSlots.single.isOffQuota, isFalse);
    });

    // ---- Quota reduced ALL THE WAY TO 0 -----------------------------------
    test(
        'a role reduced ALL THE WAY TO 0 (not just lowered) commits its orphan '
        'delete immediately', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      // Quota 1, a note already on its own (in-range, empty) gap.
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 1}).copyWith(
          slotAnnotations: {
            'medic#0': const SlotAnnotation(note: 'z'),
          },
        ),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]); // slot 0 stays empty
      await pumpEventQueue();

      expect(bloc.stagedCount, 0);

      // Remove the role from the event entirely (quota 1 -> 0) via the event
      // form. Every slot is gone, so the note is orphaned — committed (deleted)
      // immediately, nothing staged.
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 0}));
      await pumpEventQueue();

      verify(eventRepo.updateSlotAnnotation('e1', 'medic#0', null,
              staleKey: null))
          .called(1);
      expect(bloc.stagedCount, 0);
      expect(bloc.hasStagedChanges, isFalse);
      // Quota 0 → no medic rows at all (the orphan was committed, not surfaced
      // as a pending-removal row).
      final after = bloc.state as AssignmentSlotsLoaded;
      expect(after.slots.where((s) => s.role.key == 'medic'), isEmpty);
    });
  });
}
