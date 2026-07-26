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
        'a note ALREADY out of range at load is surfaced as a plain '
        'out-of-quota row — never drifted onto the surviving gap, never '
        'written, and not auto-staged for removal', () async {
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

      // Nothing written, and nothing STAGED either: the note was already
      // orphaned when the screen loaded, so no quota drop is attributable to
      // this admin (see _lastKnownQuota) and the app does not propose a removal
      // they didn't ask for.
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));

      final after = bloc.state as AssignmentSlotsLoaded;
      expect(after.stagedSlotKeys, isEmpty);
      expect(bloc.stagedCount, 0);
      expect(bloc.hasStagedChanges, isFalse);

      // The surviving in-quota gap (slot 0) stays a PLAIN empty slot — the note
      // did not move onto it.
      final medicSlot0 = after.slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 0 && !s.isOffQuota);
      expect(medicSlot0.gapAnnotation, isNull);

      // It still SURFACES as an out-of-quota note row (built from the DB, not
      // from staging) so the admin can see it and swipe it away — it never
      // silently vanishes and never silently deletes.
      final orphan = after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.isOffQuota);
      expect(orphan.slotIndex, 1);
      expect(orphan.gapAnnotation!.annotation,
          const SlotAnnotation(note: 'x', labelId: 'L'));

      // Swiping that row is what stages its removal (an empty note = a
      // user-owned delete); only then does Save write it.
      bloc.add(StageSlotAnnotation(slot: orphan, note: '', labelId: null));
      await pumpEventQueue();
      expect(bloc.stagedCount, 1);

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
    // sit un-flagged right after a quota reduction. This test drives the exact
    // same event (RebaselineQuotasForEvent) WITHOUT any further eventStream
    // emission, proving the cleanup now fires deterministically from that
    // handler itself.
    test(
        'Issue 1 fix: an event-form quota reduction (RebaselineQuotasForEvent) '
        'proposes the orphan removal immediately, without waiting for the '
        'event stream to re-deliver the reduced quota', () async {
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
      // _onRebaselineQuotasForEvent itself runs the cleanup.
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 1}));
      await pumpEventQueue();

      // PROPOSED, not written: the admin gets a pending-removal row to Save or
      // Discard. The quota drop is committed; the note's fate is theirs.
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));
      expect(bloc.stagedCount, 1);
      final after = bloc.state as AssignmentSlotsLoaded;
      expect(after.stagedSlotKeys, contains('e1_medic_1'));
      // One in-quota row (slot 0) plus the pending-removal note row (slot 1).
      final medicSlots =
          after.slots.where((s) => s.role.key == 'medic').toList();
      expect(medicSlots, hasLength(2));
      expect(medicSlots.firstWhere((s) => s.isOffQuota).slotIndex, 1);
    });

    // ---- Quota reduced ALL THE WAY TO 0 -----------------------------------
    test(
        'a role reduced ALL THE WAY TO 0 (not just lowered) still gets its '
        'pending-removal row', () async {
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

      // Remove the role from the event entirely (quota 1 -> 0). Every slot is
      // gone, so the note is orphaned — it must STILL render (the zero-quota
      // gate must not swallow it) as a pending-removal row.
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 0}));
      await pumpEventQueue();

      expect(bloc.stagedCount, 1);
      final after = bloc.state as AssignmentSlotsLoaded;
      final orphan =
          after.slots.firstWhere((s) => s.role.key == 'medic' && s.isOffQuota);
      expect(orphan.slotIndex, 0);
      expect(orphan.gapAnnotation!.annotation.note, 'z');

      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#0', null,
              staleKey: null))
          .called(1);
      expect(bloc.stagedCount, 0);
    });

    // ---- The REAL production ordering -------------------------------------
    //
    // Firestore's listener fires OPTIMISTICALLY on the local write, so the
    // reduced quota reaches the stream BEFORE updateEvent's await resolves and
    // before RebaselineQuotasForEvent is dispatched. Both paths therefore
    // observe the same drop; the proposal must be staged exactly ONCE.
    test(
        'the stream re-emitting the reduced quota FIRST (Firestore optimistic '
        'emit) proposes the removal exactly once', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      // Quota 2, both slots empty, a note on the LAST row (medic#1).
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 2}).copyWith(
          slotAnnotations: {'medic#1': const SlotAnnotation(note: 'A')},
        ),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();
      expect(bloc.stagedCount, 0);

      // 1) Firestore's optimistic emit lands the reduced quota first.
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 1}).copyWith(
          slotAnnotations: {'medic#1': const SlotAnnotation(note: 'A')},
        ),
      ]);
      await pumpEventQueue();
      expect(bloc.stagedCount, 1);

      // 2) updateEvent resolves and the modal dispatches the rebaseline. The
      //    drop is already accounted for, so this must not double-propose.
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 1}));
      await pumpEventQueue();
      expect(bloc.stagedCount, 1);
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));

      // 3) Discard All keeps the note AND its row — and no later stream emit
      //    re-proposes the removal.
      bloc.add(const DiscardAllStagedChanges());
      await pumpEventQueue();
      expect(bloc.hasStagedChanges, isFalse);
      expect(await cachedChanges(), isEmpty);
      var kept = (bloc.state as AssignmentSlotsLoaded)
          .slots
          .firstWhere((s) => s.role.key == 'medic' && s.isOffQuota);
      expect(kept.slotIndex, 1);
      expect(kept.gapAnnotation!.annotation.note, 'A');

      teamStream.add([member('m1')]);
      await pumpEventQueue();
      expect(bloc.stagedCount, 0);
      kept = (bloc.state as AssignmentSlotsLoaded)
          .slots
          .firstWhere((s) => s.role.key == 'medic' && s.isOffQuota);
      expect(kept.gapAnnotation!.annotation.note, 'A');
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));
    });

    // ---- A STAGED note whose row is removed out from under it -----------
    //
    // Type a note on the last row, then reduce the quota so that row is gone.
    // The row used to VANISH while the edit stayed staged (a dirty screen with
    // nothing to show for it) and Save then wrote the note at the dead index —
    // manufacturing the very orphan the out-of-quota row exists to surface.
    // The note must keep its row (struck through, since it is on its way out)
    // and Save must never write it back onto a slot that no longer exists.
    test(
        'a note staged on a row a LATER quota reduction removes keeps its row '
        '(pending removal) and is not written on Save', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      // Quota 3, all empty, NO stored notes — the note about to be staged has
      // nothing behind it in the DB.
      eventStream
          .add([futureEvent('e1', roleRequirements: const {'medic': 3})]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

      final row2 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 2 && !s.isOffQuota);
      bloc.add(StageSlotAnnotation(slot: row2, note: 'typed', labelId: null));
      await pumpEventQueue();
      expect(bloc.stagedCount, 1);

      // Reduce 3 -> 2 from the event form: row #3 (index 2) is gone.
      eventStream
          .add([futureEvent('e1', roleRequirements: const {'medic': 2})]);
      await pumpEventQueue();
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 2}));
      await pumpEventQueue();

      // The row is STILL THERE, out of quota, showing the staged text — and
      // staged, so the screen stripes it as a pending removal.
      final after = bloc.state as AssignmentSlotsLoaded;
      final orphan = after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.isOffQuota);
      expect(orphan.slotIndex, 2);
      expect(orphan.gapAnnotation!.annotation.note, 'typed');
      expect(after.stagedSlotKeys, contains('e1_medic_2'));

      // Save writes NOTHING for it: the note died with its row, and there was
      // no stored note to clear.
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();
      verifyNever(eventRepo.updateSlotAnnotation(any, any, any,
          staleKey: anyNamed('staleKey')));
      expect(bloc.stagedCount, 0);
    });

    test(
        'the same, over an EXISTING stored note: Save CLEARS it rather than '
        'rewriting the staged text at the dead index', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      final withNote = futureEvent('e1', roleRequirements: const {'medic': 3})
          .copyWith(
              slotAnnotations: {'medic#2': const SlotAnnotation(note: 'old')});
      eventStream.add([withNote]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

      final row2 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 2 && !s.isOffQuota);
      bloc.add(StageSlotAnnotation(slot: row2, note: 'edited', labelId: null));
      await pumpEventQueue();

      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 2}).copyWith(
            slotAnnotations: {'medic#2': const SlotAnnotation(note: 'old')}),
      ]);
      await pumpEventQueue();
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 2}));
      await pumpEventQueue();

      final orphan = (bloc.state as AssignmentSlotsLoaded)
          .slots
          .firstWhere((s) => s.role.key == 'medic' && s.isOffQuota);
      expect(orphan.gapAnnotation!.annotation.note, 'edited');

      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();
      // The stored note is CLEARED — never replaced by the staged text on a
      // slot that no longer exists.
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#2', null,
              staleKey: null))
          .called(1);
      verifyNever(eventRepo.updateSlotAnnotation(
          'e1', 'medic#2', const SlotAnnotation(note: 'edited'),
          staleKey: anyNamed('staleKey')));
    });

    test(
        'swiping a plain out-of-quota note row stages its removal, and Save '
        'writes it', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      // A note already orphaned at load (quota 1, note on slot 1).
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 1}).copyWith(
          slotAnnotations: {'medic#1': const SlotAnnotation(note: 'leftover')},
        ),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();
      expect(bloc.stagedCount, 0);

      final orphan = (bloc.state as AssignmentSlotsLoaded)
          .slots
          .firstWhere((s) => s.role.key == 'medic' && s.isOffQuota);
      // What the row's swipe dispatches: an empty note = a user-owned delete.
      bloc.add(StageSlotAnnotation(slot: orphan, note: '', labelId: null));
      await pumpEventQueue();
      expect(bloc.stagedCount, 1);
      expect((bloc.state as AssignmentSlotsLoaded).stagedSlotKeys,
          contains('e1_medic_1'));

      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#1', null,
              staleKey: null))
          .called(1);
      expect(bloc.stagedCount, 0);
    });
  });

  // ---- Swipe-delete a row repacks the notes to follow their rows ----------
  //
  // The reported bug: two empty rows [row0="123", row1="456"]; swipe-delete
  // row 0 and "123" survived while "456" got deleted — because the quota drop
  // deletes the HIGHEST-index note regardless of WHICH row you removed, and
  // never shifts. Fixed by computeNoteReindexAfterDeletion, wired into
  // _onSaveStagedChanges next to the existing assignment reindex.
  group('swipe-delete repacks notes (keeps the RIGHT note, not the highest)',
      () {
    test(
        'swipe-delete row 0 of [row0="123", row1="456"] keeps "456" on the '
        'remaining row (drops "123", shifts "456" up to medic#0)', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 2}).copyWith(
          slotAnnotations: {
            'medic#0': const SlotAnnotation(note: '123'),
            'medic#1': const SlotAnnotation(note: '456'),
          },
        ),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

      final row0 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 0 && !s.isOffQuota);
      bloc.add(StageSlotDeletion(row0));
      await pumpEventQueue();
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();

      // "456" shifts up to medic#0; the old top note (medic#1) is cleared.
      verify(eventRepo.updateSlotAnnotation(
              'e1', 'medic#0', const SlotAnnotation(note: '456'),
              staleKey: null))
          .called(1);
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#1', null,
              staleKey: null))
          .called(1);
    });

    test(
        'swipe-delete row 1 (the "456" row) keeps "123" at row 0 untouched',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 2}).copyWith(
          slotAnnotations: {
            'medic#0': const SlotAnnotation(note: '123'),
            'medic#1': const SlotAnnotation(note: '456'),
          },
        ),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

      final row1 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 1 && !s.isOffQuota);
      bloc.add(StageSlotDeletion(row1));
      await pumpEventQueue();
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();

      // Deleting the LAST row: only medic#1 ("456") is cleared; "123" stays.
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#1', null,
              staleKey: null))
          .called(1);
      verifyNever(eventRepo.updateSlotAnnotation('e1', 'medic#0', any,
          staleKey: anyNamed('staleKey')));
    });

    test(
        'swipe-delete the MIDDLE row of [A, B, C] shifts C up: result is [A, C]',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 3}).copyWith(
          slotAnnotations: {
            'medic#0': const SlotAnnotation(note: 'A'),
            'medic#1': const SlotAnnotation(note: 'B'),
            'medic#2': const SlotAnnotation(note: 'C'),
          },
        ),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

      final row1 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 1 && !s.isOffQuota);
      bloc.add(StageSlotDeletion(row1)); // delete "B"
      await pumpEventQueue();
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();

      // "C" (row 2) shifts up into row 1; the freed top slot medic#2 is cleared;
      // "A" (row 0) is untouched.
      verify(eventRepo.updateSlotAnnotation(
              'e1', 'medic#1', const SlotAnnotation(note: 'C'),
              staleKey: null))
          .called(1);
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#2', null,
              staleKey: null))
          .called(1);
      verifyNever(eventRepo.updateSlotAnnotation('e1', 'medic#0', any,
          staleKey: anyNamed('staleKey')));
    });

    test(
        'MIXED: swipe-delete the FILLED first row of [member@0, empty+"X"@1] '
        'shifts "X" up to slot 0 (notes shift in lockstep with assignments)',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 2}).copyWith(
          slotAnnotations: {'medic#1': const SlotAnnotation(note: 'X')},
        ),
      ]);
      roleStream.add([medicRole()]);
      // slot 0 filled by m1, slot 1 empty carrying note "X".
      assignmentStream.add([assignment('a1', 'e1', 'm1', slotIndex: 0)]);
      await pumpEventQueue();

      final filledRow0 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 0 && !s.isOffQuota);
      expect(filledRow0.isFilled, isTrue);
      bloc.add(StageSlotDeletion(filledRow0)); // delete the assigned row
      await pumpEventQueue();
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();

      // Row 0 (the assignment) is deleted → everything below shifts up one, so
      // the empty "X" row moves to slot 0; medic#1 cleared. "X" is NOT stranded
      // on the (now gone) filled slot.
      verify(eventRepo.updateSlotAnnotation(
              'e1', 'medic#0', const SlotAnnotation(note: 'X'),
              staleKey: null))
          .called(1);
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#1', null,
              staleKey: null))
          .called(1);
    });

    // The reported bug: a note STAGED in the same batch as the row-deletion was
    // written at its PRE-shift index while the repack — computed from the DB
    // map alone — never saw it. [#0="1", #1="2", stage #2="3", delete row 1]
    // saved as [#0="1", gap, #2="3"] instead of [#0="1", #1="3"]. The repack
    // must reindex the layout the ADMIN SEES (DB overlaid with staging), and it
    // owns those slots on Save so the staged edit is not ALSO written unshifted.
    test(
        'a note staged in the SAME batch as the deletion shifts with its row '
        '(stage "3" on row 2, delete row 1 → "3" lands on row 1)', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 3}).copyWith(
          slotAnnotations: {
            'medic#0': const SlotAnnotation(note: '1'),
            'medic#1': const SlotAnnotation(note: '2'),
          },
        ),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

      final row2 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 2 && !s.isOffQuota);
      bloc.add(StageSlotAnnotation(slot: row2, note: '3', labelId: null));
      await pumpEventQueue();

      final row1 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 1 && !s.isOffQuota);
      bloc.add(StageSlotDeletion(row1)); // delete the "2" row
      await pumpEventQueue();
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();

      // Final layout is ["1", "3"]: "2" dies with its row and the staged "3"
      // follows its row up from slot 2 to slot 1.
      verify(eventRepo.updateSlotAnnotation(
              'e1', 'medic#1', const SlotAnnotation(note: '3'),
              staleKey: null))
          .called(1);
      // The staged edit must NOT also land at its pre-shift index.
      verifyNever(eventRepo.updateSlotAnnotation(
          'e1', 'medic#2', const SlotAnnotation(note: '3'),
          staleKey: anyNamed('staleKey')));
      verifyNever(eventRepo.updateSlotAnnotation('e1', 'medic#0', any,
          staleKey: anyNamed('staleKey')));
    });

    test(
        'a note staged on the row being DELETED dies with it, and the note '
        'below still shifts up', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 3}).copyWith(
          slotAnnotations: {
            'medic#1': const SlotAnnotation(note: 'B'),
            'medic#2': const SlotAnnotation(note: 'C'),
          },
        ),
      ]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const <Assignment>[]);
      await pumpEventQueue();

      final row0 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 0 && !s.isOffQuota);
      bloc.add(StageSlotAnnotation(slot: row0, note: 'A', labelId: null));
      await pumpEventQueue();

      final freshRow0 = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) => s.role.key == 'medic' && s.slotIndex == 0 && !s.isOffQuota);
      bloc.add(StageSlotDeletion(freshRow0)); // delete the row "A" sits on
      await pumpEventQueue();
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();

      // [A(staged), B, C] minus row 0 → [B, C]. "A" is never written.
      verify(eventRepo.updateSlotAnnotation(
              'e1', 'medic#0', const SlotAnnotation(note: 'B'),
              staleKey: null))
          .called(1);
      verify(eventRepo.updateSlotAnnotation(
              'e1', 'medic#1', const SlotAnnotation(note: 'C'),
              staleKey: null))
          .called(1);
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#2', null,
              staleKey: null))
          .called(1);
      verifyNever(eventRepo.updateSlotAnnotation(
          'e1', any, const SlotAnnotation(note: 'A'),
          staleKey: anyNamed('staleKey')));
    });
  });
}
