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
        're-key onto the surviving gap (staleKey \'medic#1\'), never written '
        'immediately', () async {
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
      expect(after.stagedSlotKeys, contains('e1_medic_0'));
      expect(bloc.stagedCount, 1);
      expect(bloc.hasStagedChanges, isTrue);

      // The staged re-key renders immediately via the Task-3 overlay: the
      // surviving gap (index 0) shows the drifted note, remembering the
      // STALE source key it moved from (so Save can self-heal the DB key).
      final medicSlot = after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
      expect(medicSlot.gapAnnotation!.annotation,
          const SlotAnnotation(note: 'x', labelId: 'L'));
      expect(medicSlot.gapAnnotation!.sourceKey, 'medic#1');
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

    test(
        'the "already staged" skip does not clobber an edit the admin made on '
        'top of the auto-staged cleanup, across a later UNRELATED stream '
        're-emission carrying the IDENTICAL underlying drift', () async {
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

      // The auto-cleanup already staged the re-key onto medic#0.
      var after = bloc.state as AssignmentSlotsLoaded;
      expect(after.stagedSlotKeys, contains('e1_medic_0'));
      var medicSlot = after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);

      // The admin edits that SAME slot's note by hand, on top of the
      // auto-staged entry.
      bloc.add(StageSlotAnnotation(
          slot: medicSlot, note: 'admin-edit', labelId: null));
      await pumpEventQueue();
      // Still ONE entry at that key — the admin's edit replaced the
      // auto-computed one in place, it didn't add a second.
      expect(bloc.stagedCount, 1);

      // A completely UNRELATED stream (team members) re-emits, driving a full
      // rebuild — including _stageSlotAnnotationCleanup — with the exact SAME
      // drift as before (nothing about the annotation or quota changed). The
      // `_stagedSlotAnnotations.containsKey(slotKey)` skip (see
      // _stageSlotAnnotationCleanup) must leave the admin's edit alone rather
      // than clobbering it back to the auto-computed re-key.
      teamStream.add([member('m1')]);
      await pumpEventQueue();

      after = bloc.state as AssignmentSlotsLoaded;
      expect(bloc.stagedCount, 1);
      medicSlot = after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
      expect(medicSlot.gapAnnotation!.annotation.note, 'admin-edit');
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));
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
        'Issue 1 fix: an event-form-style quota reduction (RebaselineQuotasForEvent) '
        'STAGES the orphan cleanup immediately, without waiting for the event '
        'stream to re-deliver the reduced quota', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      // Quota 2: slot 0 filled by 'm1', a note stored on slot 1 (in-range,
      // empty) — a valid, non-drifted annotation at load time.
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

      // No drift yet at quota 2: nothing staged, no write.
      expect(bloc.stagedCount, 0);
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));

      // The admin reduces the quota 2 -> 1 via the event-form modal (exactly
      // what AssignmentListScreen/EventListScreen dispatch from
      // EventFormModal.onEventSaved). Slot 1 (holding the note) no longer
      // exists and slot 0 is filled, so the note becomes a TRUE ORPHAN — with
      // NO further eventStream emission, simulating the async event-stream
      // update not having landed yet.
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 1}));
      await pumpEventQueue();

      // Staged immediately by _onRebaselineQuotasForEvent itself, not waiting
      // for a fresh eventStream emission.
      final after = bloc.state as AssignmentSlotsLoaded;
      expect(after.stagedSlotKeys, contains('e1_medic_1'));
      expect(bloc.stagedCount, 1);
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));
      // The rebuild this handler triggers also reflects the reduced quota
      // immediately (no eventStream round-trip needed): only ONE medic slot
      // renders now.
      expect(
          after.slots.where((s) => s.role.key == 'medic'), hasLength(1));

      // Confirm it converges correctly at Save: the orphan is deleted.
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#1', null,
              staleKey: null))
          .called(1);
      expect(bloc.stagedCount, 0);
    });
  });
}
