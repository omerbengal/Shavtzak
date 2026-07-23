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

    // Task ff3: eager slotAnnotations normalization writes through this method
    // (see _normalizeSlotAnnotations in AssignmentBloc). Stubbed globally so
    // every test's rebuild can dispatch it without a MissingStubError.
    when(eventRepo.updateSlotAnnotation(any, any, any,
        staleKey: anyNamed('staleKey'))).thenAnswer((_) async {});
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
}
