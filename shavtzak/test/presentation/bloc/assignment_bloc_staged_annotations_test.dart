// Tests for AssignmentBloc's staged gap-annotation core (SG2): staging a
// note/label edit on an EMPTY slot via StageSlotAnnotation keeps it OFF the
// database (persisted only to UserCacheService, in `_stagedSlotAnnotations`)
// until an explicit Save, mirroring `_stagedChanges`/StageNotesChange — but
// never routed through the assignment-save partition (that is a later task).
//
// Harness copied from assignment_bloc_staging_test.dart (mockito repo mocks +
// StreamControllers + entity builders), which itself reuses
// assignment_bloc_slots_refetch_test.dart's generated mocks
// (`assignment_bloc_slots_refetch_test.mocks.dart`).

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
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

  Role medicRole({String hebrewName = 'חובש'}) => Role(
        id: 'role-medic',
        key: 'medic',
        hebrewName: hebrewName,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );

  // Mirrors assignment_bloc_staging_test.dart's helper — needed by the
  // quota-reduce-then-raise repro group below, which fills slot 0 so slot 1's
  // note has nowhere to drift to on a reduction (a true orphan).
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
    // _stageSlotAnnotationCleanup in AssignmentBloc) STAGES its fix instead of
    // writing through this method immediately; it's only called at Save. Still
    // stubbed globally so this file's own Save tests (Task 5) don't hit a
    // MissingStubError.
    when(eventRepo.updateSlotAnnotation(any, any, any,
        staleKey: anyNamed('staleKey'))).thenAnswer((_) async {});

    // Task 5: _onSaveStagedChanges unconditionally calls the assignment-batch
    // write on every Save — including an annotation-only one, whose
    // creates/updates/deletes/quotaBumps/quotaSets all end up empty. Stubbed
    // globally (mirrors assignment_bloc_save_test.dart's setUp) so the new
    // Save tests below don't hit a MissingStubError.
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

  /// The cache stores a JSON OBJECT (`{'changes': [...], 'baselineQuota':
  /// {...}, 'slotAnnotations': [...]}`), not a bare list — decode down to
  /// just the slotAnnotations list for tests that only care about that shape.
  Future<List<dynamic>> cachedAnnotations() async {
    final raw = await UserCacheService().getPendingAssignmentChanges();
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    return decoded is List
        ? const [] // legacy bare-list format never had annotations
        : (decoded['slotAnnotations'] as List? ?? const []);
  }

  /// Drives a bloc to a loaded grid with a single future event ('e1'), one
  /// medic slot (quota 1, empty unless [assignments] fills it), using the
  /// event's [slotAnnotations] (DB-stored gap notes) if given.
  Future<void> loadSlots(
    AssignmentBloc bloc, {
    Map<String, SlotAnnotation>? slotAnnotations,
    Map<String, int>? roleRequirements,
    List<Assignment> assignments = const [],
  }) async {
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([
      slotAnnotations == null
          ? futureEvent('e1', roleRequirements: roleRequirements)
          : futureEvent('e1', roleRequirements: roleRequirements)
              .copyWith(slotAnnotations: slotAnnotations),
    ]);
    roleStream.add([medicRole()]);
    assignmentStream.add(assignments);
    await pumpEventQueue();
  }

  test('staging a gap annotation on an empty slot marks it dirty', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc);

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(emptyMedicSlot.isFilled, isFalse);
    expect(emptyMedicSlot.gapAnnotation, isNull); // no stored annotation yet

    bloc.add(StageSlotAnnotation(
        slot: emptyMedicSlot, note: 'תזכורת', labelId: 'L1'));
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, contains('e1_medic_0'));
    expect(bloc.stagedCount, 1);
    expect(bloc.hasStagedChanges, isTrue);

    // Mirrored to cache (crash recovery) — awaited, not fire-and-forget.
    final cached = await cachedAnnotations();
    expect(cached, hasLength(1));
    expect(cached.single['eventId'], 'e1');
    expect(cached.single['roleType'], 'medic');
    expect(cached.single['slotIndex'], 0);
    expect(cached.single['desired']['note'], 'תזכורת');
    expect(cached.single['desired']['labelId'], 'L1');
    expect(cached.single['baseline'], isNull); // no DB annotation existed
  });

  test(
      're-dispatching StageSlotAnnotation reverted to the (null) baseline '
      'drops the entry and clears the cache', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc);

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);

    bloc.add(StageSlotAnnotation(slot: emptyMedicSlot, note: 'טיוטה', labelId: null));
    await pumpEventQueue();
    expect(bloc.stagedCount, 1);

    // Revert: blank note, no label — matches the (null) baseline exactly.
    bloc.add(StageSlotAnnotation(slot: emptyMedicSlot, note: '', labelId: null));
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, isEmpty);
    expect(bloc.stagedCount, 0);
    expect(bloc.hasStagedChanges, isFalse);
    expect(await cachedAnnotations(), isEmpty);
  });

  test(
      'DiscardAllStagedChanges clears staged slot annotations and the cache '
      'alongside staged member/notes changes', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc);

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);

    bloc.add(StageSlotAnnotation(slot: emptyMedicSlot, note: 'טיוטה', labelId: null));
    await pumpEventQueue();
    expect(bloc.hasStagedChanges, isTrue);
    expect(await cachedAnnotations(), isNot(isEmpty));

    bloc.add(const DiscardAllStagedChanges());
    await pumpEventQueue();

    expect(bloc.hasStagedChanges, isFalse);
    expect(bloc.stagedCount, 0);
    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, isEmpty);
    expect(await cachedAnnotations(), isEmpty);
  });

  test(
      'DiscardStagedSlot clears just that slot\'s staged annotation, leaving '
      'a different staged slot annotation untouched', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    // TWO empty medic slots (quota 2: medic#0 and medic#1). With only one
    // staged slot this test would pass identically whether the handler did
    // a targeted _stagedSlotAnnotations.remove(key) or an incorrect blanket
    // .clear() — staging one on EACH slot and discarding only one is what
    // actually proves the other survives (isolation).
    await loadSlots(bloc,
        roleRequirements: const {'medic': 2}, assignments: const []);

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final slot0 = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    final slot1 = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 1);

    bloc.add(StageSlotAnnotation(slot: slot0, note: 'note-a', labelId: null));
    await pumpEventQueue();
    bloc.add(StageSlotAnnotation(slot: slot1, note: 'note-b', labelId: null));
    await pumpEventQueue();
    expect(bloc.stagedCount, 2);

    // Discard ONLY slot0's key.
    bloc.add(const DiscardStagedSlot('e1_medic_0'));
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, isNot(contains('e1_medic_0')));
    // slot1's staged annotation SURVIVES — this is the assertion that fails
    // if _onDiscardStagedSlot ever regresses from a targeted .remove(key)
    // to a blanket .clear() (or otherwise touches unrelated slots).
    expect(after.stagedSlotKeys, contains('e1_medic_1'));
    expect(bloc.stagedCount, 1);
    expect(bloc.hasStagedChanges, isTrue);

    // The cache mirrors the same isolation: only slot1's entry remains.
    final cached = await cachedAnnotations();
    expect(cached, hasLength(1));
    expect(cached.single['slotIndex'], 1);
  });

  test(
      'a staged gap annotation survives a reload: a fresh bloc reading the '
      'same cache + RehydrateStagedChanges restores _stagedSlotAnnotations',
      () async {
    // First bloc: stage a gap annotation and let it persist to the cache.
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc);

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    bloc.add(StageSlotAnnotation(
        slot: emptyMedicSlot, note: 'לזכור', labelId: 'L1'));
    await pumpEventQueue();
    expect(bloc.stagedCount, 1);

    // Simulate a browser refresh: a FRESH bloc reading the SAME
    // SharedPreferences-backed cache, then RehydrateStagedChanges (exactly
    // what AssignmentListScreen.initState dispatches on mount).
    final reloaded = buildBloc();
    addTearDown(() async => reloaded.close());
    await loadSlots(reloaded);
    reloaded.add(const RehydrateStagedChanges());
    await pumpEventQueue();

    expect(reloaded.stagedCount, 1);
    expect(reloaded.hasStagedChanges, isTrue);
    final state = reloaded.state as AssignmentSlotsLoaded;
    expect(state.stagedSlotKeys, contains('e1_medic_0'));
  });

  test(
      'rehydrate tolerates the LEGACY bare-list cache format (pre-Task-2, no '
      'slotAnnotations ever persisted): _stagedSlotAnnotations stays empty',
      () async {
    // Pre-seed the cache as if written by OLD code that only knew about
    // _stagedChanges (Task 12's wrapper format, before this task's
    // 'slotAnnotations' key existed).
    await UserCacheService().savePendingAssignmentChanges(jsonEncode({
      'changes': <dynamic>[],
      'baselineQuota': <String, int>{},
    }));

    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc);

    bloc.add(const RehydrateStagedChanges());
    await pumpEventQueue();

    expect(bloc.stagedCount, 0);
    expect(bloc.hasStagedChanges, isFalse);
  });

  test(
      'staging a note on a gap with a stored DB annotation captures ITS note '
      'as the baseline (not null)', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc, slotAnnotations: {
      'medic#0': const SlotAnnotation(note: 'orig', labelId: 'Lorig'),
    });

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(emptyMedicSlot.gapAnnotation, isNotNull);
    expect(emptyMedicSlot.gapAnnotation!.annotation.note, 'orig');

    bloc.add(StageSlotAnnotation(slot: emptyMedicSlot, note: 'edit1', labelId: null));
    await pumpEventQueue();

    final cached = await cachedAnnotations();
    expect(cached.single['baseline']['note'], 'orig');
    expect(cached.single['baseline']['labelId'], 'Lorig');
    expect(cached.single['desired']['note'], 'edit1');
    expect(cached.single['staleKey'], isNull); // sourceKey matched own key
  });

  test(
      'a drifted stored annotation (out-of-range index) captures its ACTUAL '
      'sourceKey as staleKey, so Save can self-heal the DB key', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    // Quota is 1 (single medic gap, index 0), but the annotation is stored
    // under index 1 (out of range) — reconcileGapAnnotations drifts it onto
    // the surviving gap (index 0), remembering sourceKey 'medic#1'.
    await loadSlots(bloc, slotAnnotations: {
      'medic#1': const SlotAnnotation(note: 'drifted', labelId: 'L'),
    });

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(emptyMedicSlot.gapAnnotation!.sourceKey, 'medic#1');

    bloc.add(StageSlotAnnotation(slot: emptyMedicSlot, note: 'edit', labelId: null));
    await pumpEventQueue();

    final cached = await cachedAnnotations();
    expect(cached.single['staleKey'], 'medic#1');
    expect(cached.single['baseline']['note'], 'drifted');
  });

  // Key subtlety (see the SG2 brief): baseline/staleKey are captured ONCE, on
  // the FIRST stage of a slot, and PRESERVED on every re-edit — never re-read
  // from the slot's (Task 3-overlaid) display value. This test simulates what
  // a Task-3 overlay would hand the handler on a SECOND edit (a slot whose
  // gapAnnotation reflects the currently-staged desired note, not the true DB
  // baseline) and confirms the handler does NOT mistake that for the baseline.
  test(
      're-editing an already-staged slot preserves the ORIGINAL baseline '
      'instead of re-reading the (overlaid) display value on the second call',
      () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc, slotAnnotations: {
      'medic#0': const SlotAnnotation(note: 'orig', labelId: 'Lorig'),
    });

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);

    // First stage: edits the note away from the DB original. Baseline is
    // captured now, from the slot's TRUE (DB-reconciled) gapAnnotation.
    bloc.add(StageSlotAnnotation(slot: emptyMedicSlot, note: 'edit1', labelId: null));
    await pumpEventQueue();
    expect(bloc.stagedCount, 1);

    // Simulate the slot AS TASK 3 WOULD OVERLAY IT after that first stage:
    // gapAnnotation now reflects the STAGED desired value ('edit1'), not the
    // true DB baseline ('orig'). A naive handler that re-reads
    // slot.gapAnnotation on every call would then capture 'edit1' as the
    // (wrong) "baseline" instead of preserving the real one.
    final overlaidSlot = emptyMedicSlot.copyWith(
      gapAnnotation: () => (
        annotation: const SlotAnnotation(note: 'edit1', labelId: null),
        sourceKey: 'medic#0',
      ),
    );

    // Second edit: the admin restores the note back to the TRUE original DB
    // value. If baseline was correctly PRESERVED from the first stage
    // ('orig'/'Lorig'), this exactly matches it => isNoop => entry dropped.
    bloc.add(StageSlotAnnotation(
        slot: overlaidSlot, note: 'orig', labelId: 'Lorig'));
    await pumpEventQueue();

    expect(bloc.stagedCount, 0);
    expect(bloc.hasStagedChanges, isFalse);
    expect(await cachedAnnotations(), isEmpty);
  });

  // ---- Task 3: display overlay — a staged edit shows immediately ----------

  test(
      'staging a note on an empty slot overlays the rebuilt gapAnnotation '
      'immediately, before Save', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc);

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(emptyMedicSlot.gapAnnotation, isNull); // no stored annotation yet

    bloc.add(StageSlotAnnotation(
        slot: emptyMedicSlot, note: 'תזכורת', labelId: 'L1'));
    await pumpEventQueue();

    final after = bloc.state as AssignmentSlotsLoaded;
    final rebuiltSlot = after.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(rebuiltSlot.gapAnnotation, isNotNull);
    expect(rebuiltSlot.gapAnnotation!.annotation,
        const SlotAnnotation(note: 'תזכורת', labelId: 'L1'));
  });

  test(
      'staging a DELETE (blank note, no label) on a slot with a stored DB '
      'annotation overlays the rebuilt gapAnnotation to null immediately',
      () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc, slotAnnotations: {
      'medic#0': const SlotAnnotation(note: 'x'),
    });

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(emptyMedicSlot.gapAnnotation, isNotNull); // stored DB annotation

    // Blank note + no label => desired == null (a staged delete). This
    // differs from the non-null baseline ('x'), so it is NOT a no-op and
    // stays staged (confirmed via stagedCount below) rather than being
    // dropped immediately.
    bloc.add(
        StageSlotAnnotation(slot: emptyMedicSlot, note: '', labelId: null));
    await pumpEventQueue();
    expect(bloc.stagedCount, 1);

    final after = bloc.state as AssignmentSlotsLoaded;
    final rebuiltSlot = after.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    expect(rebuiltSlot.gapAnnotation, isNull);
  });

  // ---- Task 5: Save phase 2 — writes staged gap annotations ---------------

  test(
      'Save with ONE staged gap annotation and NO assignment changes writes '
      'it via updateSlotAnnotation and clears the staged-annotations map',
      () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await loadSlots(bloc);

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final emptyMedicSlot = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);

    bloc.add(
        StageSlotAnnotation(slot: emptyMedicSlot, note: 'x', labelId: 'L'));
    await pumpEventQueue();
    expect(bloc.stagedCount, 1); // annotation-only: no StageMemberChange etc.

    final completer = Completer<CrudActionResult>();
    bloc.add(SaveStagedChanges(completion: completer));
    await pumpEventQueue();

    verify(eventRepo.updateSlotAnnotation(
      'e1',
      'medic#0',
      const SlotAnnotation(note: 'x', labelId: 'L'),
      staleKey: null,
    )).called(1);

    expect(bloc.stagedCount, 0);
    expect(bloc.hasStagedChanges, isFalse);
    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, isEmpty);
    expect(await cachedAnnotations(), isEmpty); // re-persisted as cleared

    // The annotation write must be reflected in the completion message — NOT
    // a bare "0 changes" that reads as if nothing happened, even though the
    // annotation write just succeeded (the exact bug the comment right above
    // `written`'s computation in _onSaveStagedChanges already warns against
    // for the skip case; this is the same class of bug for annotations).
    final result = await completer.future;
    expect(result.isSuccess, isTrue);
    expect(result.message, isNot(contains('0 שינויים')));
    expect(result.message, contains('נשמרו 1'));
  });

  test(
      'MIXED Save — a staged member fill AND a staged gap annotation on '
      'different slots — writes BOTH (assignment batch + annotation write) '
      'and clears both staged maps', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    // Quota 2 on a single event: slot #0 stays empty (gets the annotation),
    // slot #1 gets the staged member fill — independent slotKeys.
    await loadSlots(bloc, roleRequirements: const {'medic': 2});

    final loaded = bloc.state as AssignmentSlotsLoaded;
    final slot0 = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
    final slot1 = loaded.slots
        .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 1);

    bloc.add(StageSlotAnnotation(slot: slot0, note: 'x', labelId: 'L'));
    await pumpEventQueue();
    bloc.add(StageMemberChange(slot: slot1, member: member('m1')));
    await pumpEventQueue();
    expect(bloc.stagedCount, 2);

    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();

    verify(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).called(1);
    verify(eventRepo.updateSlotAnnotation(
      'e1',
      'medic#0',
      const SlotAnnotation(note: 'x', labelId: 'L'),
      staleKey: null,
    )).called(1);

    expect(bloc.stagedCount, 0);
    expect(bloc.hasStagedChanges, isFalse);
    final after = bloc.state as AssignmentSlotsLoaded;
    expect(after.stagedSlotKeys, isEmpty);
    expect(await cachedAnnotations(), isEmpty);
  });

  // ---- Note-loss fix: retract stale auto-staged annotation cleanups -------
  //
  // _stageSlotAnnotationCleanup used to be add-only: it staged orphan-delete
  // / re-key entries but never retracted one it no longer needed. Repro: a
  // note on medic#1 (quota 2, slot 0 filled so slot 1 is the note's home).
  // Reduce 2->1 stages an orphan-delete for medic#1 (no free gap to drift
  // onto). Raise 1->2 BEFORE saving makes medic#1 a valid gap again — the
  // fresh cleanup computes NO delete for it, but the STALE delete used to
  // stay staged, so Save would wrongly delete the note. Fixed via the `auto`
  // provenance flag (StagedSlotAnnotation.auto) + a per-(event,role) retract
  // of stale auto entries in _stageSlotAnnotationCleanup.
  group('quota reduce-then-raise: retract stale auto-staged cleanups', () {
    test(
        'REPRO: raising the quota back up before Save retracts the stale '
        'auto-staged orphan-delete for a note that is valid again (prevents '
        'note loss)', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      // Quota 2: slot 0 filled by 'm1', a note stored on the OTHER (empty)
      // gap, slot 1 — valid, non-drifted, nothing staged at load.
      await loadSlots(bloc,
          roleRequirements: const {'medic': 2},
          slotAnnotations: {'medic#1': const SlotAnnotation(note: 'keep')},
          assignments: [assignment('a1', 'e1', 'm1', slotIndex: 0)]);
      expect(bloc.stagedCount, 0);

      // Reduce 2 -> 1 (event-form style, exactly like the SG6 Issue-1 test):
      // slot 0 (filled) is the ONLY remaining slot, so the note on slot 1 has
      // nowhere to drift to — a TRUE orphan. Staged as a delete.
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 1}));
      await pumpEventQueue();

      var after = bloc.state as AssignmentSlotsLoaded;
      expect(after.stagedSlotKeys, contains('e1_medic_1'));
      expect(bloc.stagedCount, 1);

      // Raise BACK to 2 before saving: slot 1 is a valid gap again and the
      // note is exactly where it belongs (medic#1) — the fresh cleanup
      // computes NO delete for it.
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 2}));
      await pumpEventQueue();

      after = bloc.state as AssignmentSlotsLoaded;
      // The bug: the STALE auto-staged delete from the reduce used to
      // survive even though it is no longer wanted. The fix retracts it.
      expect(after.stagedSlotKeys, isNot(contains('e1_medic_1')));
      expect(bloc.stagedCount, 0);
      expect(bloc.hasStagedChanges, isFalse);

      // Save must NOT delete the note.
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();
      verifyNever(
          eventRepo.updateSlotAnnotation('e1', 'medic#1', null, staleKey: null));
    });

    test(
        'a USER-edited annotation (auto:false) is never auto-retracted, even '
        'when a fresh cleanup pass wants nothing for that exact slot',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      await loadSlots(bloc,
          roleRequirements: const {'medic': 2},
          slotAnnotations: {'medic#1': const SlotAnnotation(note: 'keep')},
          assignments: [assignment('a1', 'e1', 'm1', slotIndex: 0)]);

      final loaded = bloc.state as AssignmentSlotsLoaded;
      final gapSlot = loaded.slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 1);
      expect(gapSlot.gapAnnotation, isNotNull);

      // The admin edits that note by hand — a user-owned (auto:false) entry
      // that OVERWRITES what would otherwise be the auto-cleanup's territory.
      bloc.add(StageSlotAnnotation(
          slot: gapSlot, note: 'user-note', labelId: null));
      await pumpEventQueue();
      expect(bloc.stagedCount, 1);
      expect((bloc.state as AssignmentSlotsLoaded).stagedSlotKeys,
          contains('e1_medic_1'));

      // Re-dispatch the SAME quota (2) — _onRebaselineQuotasForEvent always
      // re-runs the cleanup regardless of whether the quota actually moved,
      // and it computes NO ops for medic (nothing drifted): a pass that
      // "wants nothing" for this exact slot. If retraction ever keyed off
      // wantedKeys alone (ignoring `auto`), this would wrongly wipe the
      // admin's edit.
      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 2}));
      await pumpEventQueue();

      final after = bloc.state as AssignmentSlotsLoaded;
      expect(after.stagedSlotKeys, contains('e1_medic_1'));
      expect(bloc.stagedCount, 1);
      expect(bloc.hasStagedChanges, isTrue);
      final survivor = after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 1);
      expect(survivor.gapAnnotation!.annotation.note, 'user-note');
    });

    test(
        'a PERSISTENT orphan (quota reduced and never raised back) stays '
        'staged as a delete — a repeated cleanup pass over the same '
        'still-reduced quota must not wrongly retract it', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      await loadSlots(bloc,
          roleRequirements: const {'medic': 2},
          slotAnnotations: {'medic#1': const SlotAnnotation(note: 'keep')},
          assignments: [assignment('a1', 'e1', 'm1', slotIndex: 0)]);

      bloc.add(const RebaselineQuotasForEvent('e1', {'medic': 1}));
      await pumpEventQueue();

      var after = bloc.state as AssignmentSlotsLoaded;
      expect(after.stagedSlotKeys, contains('e1_medic_1'));
      expect(bloc.stagedCount, 1);

      // A completely UNRELATED stream re-emission drives another full
      // rebuild — including _stageSlotAnnotationCleanup — over the SAME
      // (still-reduced) quota: the orphan-delete is recomputed identically
      // every time, so it must NOT be retracted.
      teamStream.add([member('m1')]);
      await pumpEventQueue();

      after = bloc.state as AssignmentSlotsLoaded;
      expect(after.stagedSlotKeys, contains('e1_medic_1'));
      expect(bloc.stagedCount, 1);
      expect(bloc.hasStagedChanges, isTrue);

      // Confirm Save still applies the (still-valid) orphan delete.
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#1', null,
              staleKey: null))
          .called(1);
      expect(bloc.stagedCount, 0);
    });
  });

  // ---- Unchanged reopen+Save is a no-op (isContentNoop) -------------------
  //
  // Opening the gap dialog and pressing שמירה WITHOUT touching the note/label
  // must never mark the row dirty. Regression: for a DRIFTED note (stored key
  // != displayed gap) staleKey was non-null, so the old `isNoop` (which ANDs
  // in `staleKey == null`) returned false and staged a phantom re-key. Now the
  // user path keys off `isContentNoop` (staleKey-agnostic), so an unchanged
  // Save is a no-op regardless of drift; drift still self-heals via the quota
  // auto-cleanup / a real edit.
  group('unchanged reopen+Save is a no-op', () {
    test(
        'CANONICAL: reopening a note stored at its own key and Saving the '
        'SAME note/label does not mark the row dirty', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      await loadSlots(bloc, slotAnnotations: {
        'medic#0': const SlotAnnotation(note: '123', labelId: null),
      });

      final slot0 = (bloc.state as AssignmentSlotsLoaded)
          .slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
      expect(slot0.gapAnnotation!.sourceKey, 'medic#0'); // canonical

      // Exactly what the dialog dispatches on an untouched Save.
      bloc.add(StageSlotAnnotation(slot: slot0, note: '123', labelId: null));
      await pumpEventQueue();

      expect(bloc.stagedCount, 0);
      expect(bloc.hasStagedChanges, isFalse);
      expect((bloc.state as AssignmentSlotsLoaded).stagedSlotKeys, isEmpty);
      expect(await cachedAnnotations(), isEmpty);
    });

    test(
        'DRIFTED: reopening a note whose stored key drifted onto this gap and '
        'Saving the SAME note/label does not mark the row dirty', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      // Quota 1 (only gap index 0), but the note is stored under index 1 (out
      // of range) — reconcile drifts it onto gap 0 with sourceKey 'medic#1'.
      await loadSlots(bloc, slotAnnotations: {
        'medic#1': const SlotAnnotation(note: '123', labelId: null),
      });

      final slot0 = (bloc.state as AssignmentSlotsLoaded)
          .slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
      expect(slot0.gapAnnotation!.annotation.note, '123');
      expect(slot0.gapAnnotation!.sourceKey, 'medic#1'); // DRIFTED

      // User changes nothing and hits Save.
      bloc.add(StageSlotAnnotation(slot: slot0, note: '123', labelId: null));
      await pumpEventQueue();

      expect(bloc.stagedCount, 0,
          reason: 'no content change must not mark the row dirty');
      expect(bloc.hasStagedChanges, isFalse);
      expect((bloc.state as AssignmentSlotsLoaded).stagedSlotKeys, isEmpty);
      expect(await cachedAnnotations(), isEmpty);
    });

    test(
        'DRIFTED but an ACTUAL edit still stages + captures staleKey so Save '
        'self-heals the key (fix must not neuter real drifted edits)', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      await loadSlots(bloc, slotAnnotations: {
        'medic#1': const SlotAnnotation(note: '123', labelId: null),
      });

      final slot0 = (bloc.state as AssignmentSlotsLoaded)
          .slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
      expect(slot0.gapAnnotation!.sourceKey, 'medic#1');

      // A genuine change (note '123' -> '456') is NOT a content noop.
      bloc.add(StageSlotAnnotation(slot: slot0, note: '456', labelId: null));
      await pumpEventQueue();

      expect(bloc.stagedCount, 1);
      final cached = await cachedAnnotations();
      expect(cached.single['staleKey'], 'medic#1'); // still self-heals on Save
      expect(cached.single['desired']['note'], '456');
    });
  });

  // ---- Staged edit on a drifted note + quota bump must not duplicate -------
  //
  // A note stored at medic#1 while quota is 1 drifts onto the only gap (slot
  // 0). The admin edits it there (staged: slotIndex 0, desired '456', staleKey
  // 'medic#1'). Then raises the quota 1 -> 2: medic#1 is IN range again, so
  // reconcile puts the ORIGINAL '123' back on its canonical slot 1 — while the
  // staged '456' stays pinned to slot 0. Without Approach A the note SPLITS
  // into two rows ('456' on slot 0, a resurrected '123' on slot 1), and Save
  // would then delete the slot-1 note via the now-stale staleKey. Approach A
  // suppresses a stored note that a live staged edit already claims via its
  // staleKey, so slot 1 renders empty.
  group('staged edit on a drifted note survives a quota bump w/o duplicating',
      () {
    test(
        'raising the quota after editing a drifted note does NOT resurrect the '
        'original value on the newly-canonical slot', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      // Quota 1, note stored at medic#1 (out of range) → drifts onto gap 0.
      await loadSlots(bloc, slotAnnotations: {
        'medic#1': const SlotAnnotation(note: '123', labelId: null),
      });

      final slot0 = (bloc.state as AssignmentSlotsLoaded)
          .slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
      expect(slot0.gapAnnotation!.sourceKey, 'medic#1'); // drifted

      // Stage an EDIT (123 -> 456) on the drifted display slot.
      bloc.add(StageSlotAnnotation(slot: slot0, note: '456', labelId: null));
      await pumpEventQueue();
      expect(bloc.stagedCount, 1);

      // Quota 1 -> 2 (event edit re-emits with the new requirement; the stored
      // annotation is unchanged). medic#1 is now IN range → canonical on slot 1.
      eventStream.add([
        futureEvent('e1', roleRequirements: const {'medic': 2}).copyWith(
            slotAnnotations: {
              'medic#1': const SlotAnnotation(note: '123', labelId: null)
            }),
      ]);
      await pumpEventQueue();

      final after = bloc.state as AssignmentSlotsLoaded;
      final s0 = after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 0);
      final s1 = after.slots
          .firstWhere((s) => s.role.key == 'medic' && s.slotIndex == 1);

      // The staged edit still shows on slot 0...
      expect(s0.gapAnnotation!.annotation.note, '456');
      // ...and the original '123' must NOT reappear on slot 1 (Approach A).
      expect(s1.gapAnnotation, isNull);

      // Exactly one staged entry, on slot 0 — slot 1 is a plain empty row.
      expect(bloc.stagedCount, 1);
      expect(after.stagedSlotKeys, contains('e1_medic_0'));
      expect(after.stagedSlotKeys, isNot(contains('e1_medic_1')));

      // ...and Save stays consistent: the edit re-keys to the canonical slot 0
      // and deletes the stale medic#1 in the SAME write — no orphaned '123'.
      bloc.add(const SaveStagedChanges());
      await pumpEventQueue();
      verify(eventRepo.updateSlotAnnotation(
        'e1',
        'medic#0',
        const SlotAnnotation(note: '456', labelId: null),
        staleKey: 'medic#1',
      )).called(1);
      expect(bloc.stagedCount, 0);
    });
  });
}
