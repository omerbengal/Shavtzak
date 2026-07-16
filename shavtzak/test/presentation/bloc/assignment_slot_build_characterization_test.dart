// CHARACTERIZATION tests for AssignmentBloc's two duplicated slot-build
// paths, written BEFORE the unification refactor (see the plan doc). They
// pin TODAY's behavior — bugs included — so Task 2's unification shows up as
// an intentional, reviewed diff instead of a silent behavior change.
//
// Plan: docs/superpowers/plans/2026-07-16-assignments-slot-build-unification.md
// Brief: .superpowers/sdd/task-1-brief.md
//
// The two paths (both in lib/presentation/bloc/assignment/assignment_bloc.dart):
//   Path A = _buildSlotsFromAssignments (~2107), reached via RebuildAssignmentSlots
//            (_onRebuildAssignmentSlots, ~2341). Uses UNBOUNDED one-shot fetches:
//            getAllAssignments() / getAllEvents() / getActiveTeamMembers().
//   Path B = the inline build inside _onRebuildAssignmentSlotsFromData
//            (~2385-2643), reached by pushing data through the live Firestore
//            streams. Uses the WINDOWED stream payload (+ _extraPastAssignments),
//            re-stamps relations, has a first-paint gate, and filters .slots by
//            selectedEventIds.
//
// Every test below is named "PRE-REFACTOR SNAPSHOT" and states which
// divergence (numbered per the plan's divergence table) it pins. Task 2 is
// expected to INTENTIONALLY flip the divergence-pin tests once the paths are
// unified; the baseline (A==B) test must never break.
//
// Harness copied from assignment_bloc_staged_samedy_availability_test.dart
// (mockito repo mocks + StreamControllers + SharedPreferences.setMockInitialValues
// + pumpEventQueue + the eventOnDay/member/assignment/medicRole builders +
// buildBloc() with userCacheService), extended with:
//   - optional isActive/allowMultipleAssignments params on member() (test #4),
//   - eventSpanning() for a multi-day event (test #5),
//   - default-success saveAssignmentsBatch stub (test #2, mirroring
//     assignment_bloc_save_test.dart's setUp).
// Both the windowed streams (Path B) AND the one-shot fetches
// getAllAssignments()/getAllEvents()/getActiveTeamMembers()/getAllRoles()
// (Path A) are stubbed per-test (not in a single shared setUp default) so
// each test can make them return DIFFERENT data and expose a divergence.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/core/utils/filter_persistence.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot.dart';

import 'assignment_bloc_slots_refetch_test.mocks.dart';

/// Deterministic (eventId, roleType, slotIndex, currentAssignment?.
/// teamMemberId) fingerprint for one slot.
String _tuple(AssignmentSlot s) =>
    '${s.event.id}|${s.role.key}|${s.slotIndex}|${s.currentAssignment?.teamMemberId ?? '-'}';

/// Grid fingerprint as a Set of per-slot tuples — order-independent, so two
/// grids built via different code paths (and possibly different internal
/// iteration order) can be compared for content equality.
Set<String> _gridFingerprint(List<AssignmentSlot> slots) =>
    slots.map(_tuple).toSet();

/// slotKey ("${eventId}_${roleType}_${slotIndex}") -> availableMembers id set,
/// for every slot in [slots].
Map<String, Set<String>> _availableIdsByKey(List<AssignmentSlot> slots) => {
      for (final s in slots)
        '${s.event.id}_${s.role.key}_${s.slotIndex}':
            s.availableMembers.map((m) => m.id).toSet(),
    };

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

  final now = DateTime(2026, 1, 1); // fixed timestamp for entity metadata only

  // ---- Builders for minimal valid entities (mirrors the sibling harness) --

  // isPermanent: true by default so a member is available-by-default (see
  // TeamMember.isAvailableForEventWithTime) without needing constraints —
  // matches assignment_bloc_staged_samedy_availability_test.dart's rationale.
  // isActive/allowMultipleAssignments are exposed for test #4 (inactive +
  // allowMultipleAssignments member).
  TeamMember member(
    String id, {
    bool isActive = true,
    bool isPermanent = true,
    bool allowMultipleAssignments = false,
  }) =>
      TeamMember(
        id: id,
        name: 'member-$id',
        isActive: isActive,
        isPermanent: isPermanent,
        constraints: const [],
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'key-$id',
        allowMultipleAssignments: allowMultipleAssignments,
      );

  // Single-day event (start 09:00 / end 17:00 on [day]) with a 1-slot medic
  // quota by default.
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

  // Multi-day event spanning [startDay]..[endDay] (09:00 first day / 17:00
  // last day). Needed only by test #5: an event whose date RANGE starts on a
  // past day (shared with a same-day past event) but ends in the future, so
  // it survives the showPastEvents filter while still sharing a calendar day
  // with a filtered-out past event.
  Event eventSpanning(String id, DateTime startDay, DateTime endDay,
      {Map<String, int>? roleRequirements}) {
    final start = DateTime(startDay.year, startDay.month, startDay.day, 9, 0);
    final end = DateTime(endDay.year, endDay.month, endDay.day, 17, 0);
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
    // Explicit default (defensive against a leaked mutation from another test
    // in this file — none currently set it true, but tests 2/3/5 rely on the
    // showPastEvents=false behavior specifically).
    FilterPersistence.showPastEvents = false;

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

    // --- Streams (Path B) ---
    when(assignmentRepo.watchAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) => assignmentStream.stream);
    when(teamRepo.watchTeamMembers()).thenAnswer((_) => teamStream.stream);
    when(eventRepo.watchEventsByDateRange(any, any))
        .thenAnswer((_) => eventStream.stream);
    when(roleRepo.watchRoles()).thenAnswer((_) => roleStream.stream);

    // Default: the batch write succeeds (only test #2 inspects its args;
    // every other test that might incidentally reach Save needs a stub so
    // throwOnMissingStub doesn't fire).
    when(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).thenAnswer((_) async {});

    // NOTE: getAllAssignments()/getAllEvents()/getActiveTeamMembers()/
    // getAllRoles() (Path A's one-shot fetches) are deliberately NOT stubbed
    // here with a shared default — each test stubs them with the exact data
    // it needs (sometimes matching the stream payload, sometimes deliberately
    // diverging from it) before dispatching LoadAssignmentSlots.
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

  group('AssignmentBloc slot-build characterization (Path A vs Path B) — '
      'PRE-REFACTOR SNAPSHOTS', () {
    test(
        'PRE-REFACTOR SNAPSHOT (baseline, A==B — must never break): '
        'in-window data, all-active members, no filter — RebuildAssignmentSlots '
        '(A) and RebuildAssignmentSlotsFromData (B) produce grids with the SAME '
        'set of (eventId, roleType, slotIndex, currentAssignment.teamMemberId) '
        'tuples and the same availableMembers id-set per slot', () async {
      final dayP = DateTime.now().add(const Duration(days: 10));
      final dayQ = DateTime.now().add(const Duration(days: 40));
      final eventP = eventOnDay('p1', dayP);
      final eventQ = eventOnDay('q1', dayQ);
      final t1 = member('T1');
      final t2 = member('T2');
      final assignments = [assignment('aP', 'p1', 'T1')];

      when(eventRepo.getAllEvents()).thenAnswer((_) async => [eventP, eventQ]);
      when(assignmentRepo.getAllAssignments())
          .thenAnswer((_) async => assignments);
      when(teamRepo.getActiveTeamMembers()).thenAnswer((_) async => [t1, t2]);
      when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventP, eventQ]);
      roleStream.add([medicRole()]);
      teamStream.add([t1, t2]);
      assignmentStream.add(assignments);
      await pumpEventQueue();

      // Path B: grid from the live-stream rebuild.
      final gridB = (bloc.state as AssignmentSlotsLoaded).slots;

      // Path A: grid from the stage/filter/rehydrate rebuild, backed by the
      // SAME underlying data via the one-shot fetches stubbed above.
      bloc.add(const RebuildAssignmentSlots());
      await pumpEventQueue();
      final gridA = (bloc.state as AssignmentSlotsLoaded).slots;

      expect(gridA.length, gridB.length);
      expect(_gridFingerprint(gridA), equals(_gridFingerprint(gridB)));
      expect(_availableIdsByKey(gridA), equals(_availableIdsByKey(gridB)));
    });

    test(
        'PRE-REFACTOR SNAPSHOT (#1/#2 window scope + #3 root-cause chain — '
        'THE BUG): an out-of-window (>180d) event/assignment is surfaced by '
        'Path A but not Path B; staging a clear on it and Saving yields a '
        'silent 0-write "success" AND drops the staged entry', () async {
      // Outside the +180-day-forward window that Path B's live stream covers.
      final farDay = DateTime.now().add(const Duration(days: 400));
      final farEvent = eventOnDay('far1', farDay);
      final m1 = member('M1');
      final farAssignment = assignment('aFar', 'far1', 'M1');

      // Path A (unbounded one-shot fetches) DOES include the far-future
      // event + assignment.
      when(eventRepo.getAllEvents()).thenAnswer((_) async => [farEvent]);
      when(assignmentRepo.getAllAssignments())
          .thenAnswer((_) async => [farAssignment]);
      when(teamRepo.getActiveTeamMembers()).thenAnswer((_) async => [m1]);
      when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      // Path B (windowed streams) EXCLUDES the far-future event + assignment
      // entirely — nothing in the -90d/+180d window mentions it.
      eventStream.add(const []);
      roleStream.add([medicRole()]);
      teamStream.add([m1]);
      assignmentStream.add(const []);
      await pumpEventQueue();

      // (b) A stream rebuild (Path B) does NOT contain the far-future slot.
      final afterStream = bloc.state as AssignmentSlotsLoaded;
      expect(
        afterStream.slots.where((s) => s.event.id == 'far1'),
        isEmpty,
        reason: 'Path B is windowed to ~180 days forward; the far-future '
            'event must not appear',
      );

      // (a) RebuildAssignmentSlots (Path A) DOES surface it, via the
      // unbounded getAllAssignments()/getAllEvents() fetches.
      bloc.add(const RebuildAssignmentSlots());
      await pumpEventQueue();
      final afterA = bloc.state as AssignmentSlotsLoaded;
      final farSlot = afterA.slots.firstWhere((s) =>
          s.event.id == 'far1' && s.role.key == 'medic' && s.slotIndex == 0);
      expect(farSlot.currentAssignment?.teamMemberId, 'M1');

      // Stage a clear on the far-future slot. This is only reachable through
      // Path A's grid (Path B never shows it), exactly like an admin editing
      // via the assignments screen, which is fed by Path A's rebuilds while
      // staging is active.
      bloc.add(StageMemberChange(slot: farSlot, member: null));
      await pumpEventQueue();
      expect(bloc.hasStagedChanges, isTrue);

      final completer = Completer<CrudActionResult>();
      bloc.add(SaveStagedChanges(completion: completer));
      await pumpEventQueue();

      final captured = verify(assignmentRepo.saveAssignmentsBatch(
        creates: captureAnyNamed('creates'),
        updates: captureAnyNamed('updates'),
        deletes: captureAnyNamed('deletes'),
      )).captured;
      final creates = captured[0] as List<Assignment>;
      final updates = captured[1] as List<Assignment>;
      final deletes = captured[2] as List<String>;

      // (c) THE BUG, part 1: the batch write is a true no-op. dbByKey at Save
      // time is built from the WINDOWED _repository.getCurrentAssignments()
      // (+ _extraPastAssignments) — the far-future assignment was never
      // cached there (Path A's rebuild never calls cacheCurrentAssignments),
      // so the staged clear is classified 'clear-noop': nothing to delete.
      expect(creates, isEmpty);
      expect(updates, isEmpty);
      expect(deletes, isEmpty);

      // THE BUG, part 2: Save still reports this as an unqualified SUCCESS
      // with "0 changes" — indistinguishable from "Save was clicked with
      // nothing staged".
      final result = await completer.future;
      expect(result.isSuccess, isTrue);
      expect(result.message, 'נשמרו 0 שינויים');

      // THE BUG, part 3 (the user-visible symptom — "נשמרו 0 → member
      // reappears"): despite writing NOTHING, the staged entry is
      // unconditionally dropped from _stagedChanges (appliedKeys always
      // includes a 'clear-noop' key, and every appliedKeys entry is removed
      // from staging). The dirty marker disappears and the next rebuild
      // reflects the untouched DB row — M1's assignment "reappears" as if
      // the admin's clear had never happened.
      expect(bloc.hasStagedChanges, isFalse);
    });

    test(
        'PRE-REFACTOR SNAPSHOT (#11 selectedEventIds): '
        'RebuildAssignmentSlotsFromData (Path B) filters .slots down to the '
        'selected event(s); RebuildAssignmentSlots (Path A) does not — A only '
        'records the filter in selectedEventIds and leaves .slots unfiltered',
        () async {
      final dayP = DateTime.now().add(const Duration(days: 12));
      final dayQ = DateTime.now().add(const Duration(days: 22));
      final eventP = eventOnDay('p1', dayP);
      final eventQ = eventOnDay('q1', dayQ);
      final t1 = member('T1');

      when(eventRepo.getAllEvents()).thenAnswer((_) async => [eventP, eventQ]);
      when(assignmentRepo.getAllAssignments()).thenAnswer((_) async => const []);
      when(teamRepo.getActiveTeamMembers()).thenAnswer((_) async => [t1]);
      when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventP, eventQ]);
      roleStream.add([medicRole()]);
      teamStream.add([t1]);
      assignmentStream.add(const []);
      await pumpEventQueue();

      // ApplyEventFilter always rebuilds via Path A (RebuildAssignmentSlots).
      bloc.add(const ApplyEventFilter({'p1'}));
      await pumpEventQueue();

      final afterFilterA = bloc.state as AssignmentSlotsLoaded;
      expect(afterFilterA.selectedEventIds, {'p1'});
      // THE DIVERGENCE: Path A recorded the filter in selectedEventIds but did
      // NOT narrow .slots — both events are still present in the grid.
      expect(
          afterFilterA.slots.map((s) => s.event.id).toSet(), {'p1', 'q1'});

      // Retrigger a STREAM rebuild (Path B) while the filter is active
      // (_currentEventFilter was already set to {'p1'} by ApplyEventFilter).
      assignmentStream.add(const []);
      await pumpEventQueue();

      final afterStreamB = bloc.state as AssignmentSlotsLoaded;
      expect(afterStreamB.selectedEventIds, {'p1'});
      // Path B DOES narrow .slots down to the filtered event only.
      expect(afterStreamB.slots.map((s) => s.event.id).toSet(), {'p1'});
    });

    test(
        'PRE-REFACTOR SNAPSHOT (#3 inactive allowMultipleAssignments member): '
        'an inactive member with allowMultipleAssignments=true leaks into '
        "Path B's availableMembers via the unfiltered team stream, but Path "
        "A's getActiveTeamMembers() correctly excludes them at the source",
        () async {
      final day = DateTime.now().add(const Duration(days: 15));
      final ev = eventOnDay('r1', day);
      // Inactive: TeamMember.isAvailableForEventWithTime would normally
      // return false for them (isActive gate) — but allowMultipleAssignments
      // SKIPS that availability check entirely in both slot-build loops
      // (`if (!member.allowMultipleAssignments && !isAvailable) continue;`),
      // so whether this member is even CONSIDERED comes down purely to which
      // member source each path reads from.
      final ghost =
          member('ghost', isActive: false, allowMultipleAssignments: true);

      when(eventRepo.getAllEvents()).thenAnswer((_) async => [ev]);
      when(assignmentRepo.getAllAssignments()).thenAnswer((_) async => const []);
      // Path A: the one-shot fetch is DB-filtered to active members only —
      // ghost is correctly excluded at the source.
      when(teamRepo.getActiveTeamMembers()).thenAnswer((_) async => const []);
      when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([ev]);
      roleStream.add([medicRole()]);
      // Path B: watchTeamMembers() is UNFILTERED (every member regardless of
      // isActive) — ghost lands in _windowMembersMap.
      teamStream.add([ghost]);
      assignmentStream.add(const []);
      await pumpEventQueue();

      final medicSlotB = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) =>
              s.event.id == 'r1' && s.role.key == 'medic' && s.slotIndex == 0);
      expect(
        medicSlotB.availableMembers.map((m) => m.id),
        contains('ghost'),
        reason: 'Path B (stream rebuild): ghost leaks in via the unfiltered '
            'team stream',
      );

      bloc.add(const RebuildAssignmentSlots());
      await pumpEventQueue();

      final medicSlotA = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) =>
              s.event.id == 'r1' && s.role.key == 'medic' && s.slotIndex == 0);
      expect(
        medicSlotA.availableMembers.map((m) => m.id),
        isNot(contains('ghost')),
        reason: 'Path A (stage/filter rebuild): getActiveTeamMembers() '
            'excludes ghost at the source',
      );
    });

    test(
        'PRE-REFACTOR SNAPSHOT (#5 showPastEvents boundary-day past event): '
        "Path B's same-day lookup is independent of the showPastEvents "
        "toggle and correctly excludes a same-day-booked member; Path A's "
        'same-day lookup reads its OWN already-filtered event list, silently '
        'fails to resolve the filtered-out otherEvent, and does not exclude '
        'the member', () async {
      final pastDay = DateTime.now().subtract(const Duration(days: 5));
      // X: multi-day event starting on the SAME calendar day as past event Y
      // but ending 10 days from now — survives the showPastEvents filter
      // (its OWN endDate is in the future) while still sharing pastDay
      // with Y.
      final eventX =
          eventSpanning('x1', pastDay, pastDay.add(const Duration(days: 10)));
      // Y: single-day event on pastDay only. Its endDate is in the past, so
      // it is filtered out of both paths' OWN visible-event list under
      // showPastEvents=false — yet it is still loaded into the underlying
      // window data (well within the -90 day back window) both paths draw
      // from.
      final eventY = eventOnDay('y1', pastDay);
      final m1 = member('M1');
      // M1 booked on Y, which shares a calendar day with X.
      final assignmentOnY = assignment('aY', 'y1', 'M1');

      when(eventRepo.getAllEvents()).thenAnswer((_) async => [eventX, eventY]);
      when(assignmentRepo.getAllAssignments())
          .thenAnswer((_) async => [assignmentOnY]);
      when(teamRepo.getActiveTeamMembers()).thenAnswer((_) async => [m1]);
      when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventX, eventY]); // raw window: both loaded
      roleStream.add([medicRole()]);
      teamStream.add([m1]);
      assignmentStream.add([assignmentOnY]);
      await pumpEventQueue();

      // Path B (stream rebuild): correctly excludes M1 from X's
      // availableMembers — its same-day loop reads `mergedEvents` (the
      // unfiltered window map), so it finds Y (and thus the conflict)
      // regardless of showPastEvents.
      final xSlotB = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) =>
              s.event.id == 'x1' && s.role.key == 'medic' && s.slotIndex == 0);
      expect(
        xSlotB.availableMembers.map((m) => m.id),
        isNot(contains('M1')),
        reason: 'Path B same-day lookup is independent of showPastEvents',
      );
      expect(xSlotB.sameDayAssignedMembers.map((m) => m.id), contains('M1'));

      bloc.add(const RebuildAssignmentSlots());
      await pumpEventQueue();

      // Path A (stage/filter rebuild): its same-day loop looks up
      // `otherEvent` in the ALREADY showPastEvents-filtered `events` list
      // (Y was removed from it), can't find Y there, falls back to `event`
      // itself (the `orElse: () => event` fallback), and then skips the
      // candidate entirely via `if (otherEvent.id == event.id) continue;` —
      // so the conflict is silently missed and M1 stays "available".
      final xSlotA = (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
          (s) =>
              s.event.id == 'x1' && s.role.key == 'medic' && s.slotIndex == 0);
      expect(
        xSlotA.availableMembers.map((m) => m.id),
        contains('M1'),
        reason: 'Path A incorrectly offers M1 because Y was filtered out of '
            "its own same-day lookup's event list",
      );
    });
  });
}
