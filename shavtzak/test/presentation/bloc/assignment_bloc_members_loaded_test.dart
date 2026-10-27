// `AssignmentSlotsLoaded.membersLoaded` — the explicit "the team-members
// stream has delivered" signal the assignments screen waits on before it
// paints the grid.
//
// Background: the screen used to INFER "members not loaded yet" from "no slot
// has an available member". That is also true when members HAVE loaded and
// every one of them is unavailable for every slot (a permanent member with a
// blocking constraint on the only event's date, a non-permanent member with no
// availability). No later state differs (Equatable), so the builder never
// re-ran and the spinner stayed up forever. The bloc now says it outright.
//
// Harness: same mocked repositories + broadcast StreamControllers as
// assignment_bloc_slots_refetch_test.dart / the slot-build characterization
// test. The bloc is built INSIDE each test body, never in setUp.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';
import 'package:shavtzak/core/utils/filter_persistence.dart';
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

  final stamp = DateTime(2026, 1, 1); // entity metadata only

  // The event day: comfortably inside the -90d/+180d window and in the future,
  // so the showPastEvents=false filter keeps it.
  final eventDay = DateTime.now().add(const Duration(days: 10));

  Event eventOnDay(String id, DateTime day) => Event(
        id: id,
        name: 'event-$id',
        startDate: DateTime(day.year, day.month, day.day, 9, 0),
        endDate: DateTime(day.year, day.month, day.day, 17, 0),
        startTime: '09:00',
        endTime: '17:00',
        assemblyTime: '08:30',
        requiresArmed: false,
        roleRequirements: const {'medic': 1},
        createdAt: stamp,
        updatedAt: stamp,
      );

  // A permanent member is available by default; [blockedOn] adds an APPROVED
  // whole-day unavailability on that date, which makes them unavailable for an
  // event on that day.
  TeamMember member(String id, {DateTime? blockedOn}) => TeamMember(
        id: id,
        name: 'member-$id',
        isActive: true,
        isPermanent: true,
        constraints: [
          if (blockedOn != null)
            DateConstraint(
              id: 'c-$id',
              startDate: blockedOn,
              endDate: blockedOn,
              status: ConstraintStatus.approved,
              constraintType: ConstraintType.unavailability,
            ),
        ],
        roleCapabilities: const {'medic': true},
        createdAt: stamp,
        updatedAt: stamp,
        uniqueKey: 'key-$id',
      );

  Role medicRole() => Role(
        id: 'role-medic',
        key: 'medic',
        hebrewName: 'חובש',
        sortOrder: 0,
        createdAt: stamp,
        updatedAt: stamp,
      );

  Assignment assignment(String id, String eventId, String memberId) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: stamp,
        updatedAt: stamp,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilterPersistence.showPastEvents = false;

    assignmentRepo = MockAssignmentRepository();
    teamRepo = MockTeamRepository();
    eventRepo = MockEventRepository();
    roleRepo = MockRoleRepository();

    assignmentStream = StreamController<List<Assignment>>.broadcast();
    teamStream = StreamController<List<TeamMember>>.broadcast();
    eventStream = StreamController<List<Event>>.broadcast();
    roleStream = StreamController<List<Role>>.broadcast();

    List<Assignment> cached = const [];
    when(assignmentRepo.cacheCurrentAssignments(any)).thenAnswer((inv) {
      cached = inv.positionalArguments.first as List<Assignment>;
    });
    when(assignmentRepo.getCurrentAssignments()).thenAnswer((_) => cached);

    when(assignmentRepo.watchAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) => assignmentStream.stream);
    when(teamRepo.watchTeamMembers()).thenAnswer((_) => teamStream.stream);
    when(eventRepo.watchEventsByDateRange(any, any))
        .thenAnswer((_) => eventStream.stream);
    when(roleRepo.watchRoles()).thenAnswer((_) => roleStream.stream);
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

  /// Every `AssignmentSlotsLoaded` the bloc emits from now on.
  List<AssignmentSlotsLoaded> recordSlotStates(AssignmentBloc bloc) {
    final seen = <AssignmentSlotsLoaded>[];
    final sub = bloc.stream.listen((s) {
      if (s is AssignmentSlotsLoaded) seen.add(s);
    });
    addTearDown(sub.cancel);
    return seen;
  }

  group('AssignmentSlotsLoaded.membersLoaded', () {
    test(
        'members who are ALL unavailable for the only event: the emitted state '
        'says membersLoaded and every slot has no available member', () async {
      final blocked = member('M1', blockedOn: eventDay);
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final seen = recordSlotStates(bloc);

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventOnDay('e1', eventDay)]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const []);
      teamStream.add([blocked]);
      await pumpEventQueue();

      final loaded = bloc.state as AssignmentSlotsLoaded;
      expect(loaded.slots, isNotEmpty,
          reason: 'the event has a medic quota, so it has a slot');
      expect(loaded.slots.every((s) => s.availableMembers.isEmpty), isTrue,
          reason: 'the only member is blocked by an approved constraint');
      expect(loaded.membersLoaded, isTrue,
          reason: 'the members stream HAS delivered — an empty availability '
              'list must not be mistaken for "still loading"');
      expect(seen.last.membersLoaded, isTrue);
    });

    test(
        'control: the same fixture with an unblocked member has availability '
        '(so the all-empty case above is really the constraint, not a '
        'fixture mistake)', () async {
      final free = member('M1');
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventOnDay('e1', eventDay)]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const []);
      teamStream.add([free]);
      await pumpEventQueue();

      final loaded = bloc.state as AssignmentSlotsLoaded;
      expect(loaded.slots.single.availableMembers.map((m) => m.id), ['M1']);
      expect(loaded.membersLoaded, isTrue);
    });

    test(
        'before the members stream emits, every emitted slots state says '
        'membersLoaded == false; the first state after it says true', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final seen = recordSlotStates(bloc);

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      // Roles, events and assignments arrive — the first-paint gate opens —
      // but the team-members stream stays silent.
      eventStream.add([eventOnDay('e1', eventDay)]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const []);
      await pumpEventQueue();

      expect(seen, isNotEmpty,
          reason: 'with roles+events+assignments in, the grid is emitted');
      expect(seen.every((s) => !s.membersLoaded), isTrue,
          reason: 'no members yet, so the screen must keep waiting');

      // A rebuild from another path (stage/filter) does not flip it either.
      bloc.add(const RebuildAssignmentSlots());
      await pumpEventQueue();
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isFalse);

      teamStream.add([member('M1', blockedOn: eventDay)]);
      await pumpEventQueue();
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isTrue);
    });

    test(
        'members arriving with an EMPTY list still count as loaded (a team '
        'with nobody in it is not "still loading")', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventOnDay('e1', eventDay)]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const []);
      teamStream.add(const []);
      await pumpEventQueue();

      final loaded = bloc.state as AssignmentSlotsLoaded;
      expect(loaded.slots, isNotEmpty);
      expect(loaded.membersLoaded, isTrue);
    });

    test('once loaded it stays loaded across rebuilds and filter changes',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventOnDay('e1', eventDay)]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const []);
      teamStream.add([member('M1', blockedOn: eventDay)]);
      await pumpEventQueue();
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isTrue);

      // Path A (stage/filter/rehydrate rebuild).
      bloc.add(const RebuildAssignmentSlots());
      await pumpEventQueue();
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isTrue);

      // Path B again through a stream tick, and a filter change.
      eventStream.add([eventOnDay('e1', eventDay)]);
      await pumpEventQueue();
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isTrue);

      bloc.add(ApplyEventFilter({'e1'}));
      await pumpEventQueue();
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isTrue);
    });

    test(
        'a fresh LoadAssignmentSlots (e.g. toggling past events) re-arms the '
        'signal: false again until the members stream re-delivers', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventOnDay('e1', eventDay)]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const []);
      teamStream.add([member('M1', blockedOn: eventDay)]);
      await pumpEventQueue();
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isTrue);

      final seen = recordSlotStates(bloc);
      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventOnDay('e1', eventDay)]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const []);
      await pumpEventQueue();
      expect(seen, isNotEmpty);
      expect(seen.every((s) => !s.membersLoaded), isTrue,
          reason: 'the member cache was cleared at reload; the screen must '
              'not treat the new, member-less grid as loaded');

      teamStream.add([member('M1', blockedOn: eventDay)]);
      await pumpEventQueue();
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isTrue);
    });

    test(
        'optimistic create/update/delete emits carry the current value '
        'through instead of resetting it to the default', () async {
      // Hold each write open so the optimistic (pre-write) state is the one
      // we look at, then let it finish to see the post-write emit as well.
      final createGate = Completer<void>();
      when(assignmentRepo.createAssignment(any))
          .thenAnswer((_) => createGate.future);

      final bloc = buildBloc();
      addTearDown(() async => bloc.close());

      bloc.add(const LoadAssignmentSlots());
      await pumpEventQueue();
      eventStream.add([eventOnDay('e1', eventDay)]);
      roleStream.add([medicRole()]);
      assignmentStream.add(const []);
      await pumpEventQueue();
      // Members NOT delivered: the loaded state says false, and an optimistic
      // write on top of it must not flip it to the constructor default (true).
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isFalse);

      final seen = recordSlotStates(bloc);
      bloc.add(OptimisticCreateAssignment(assignment('a1', 'e1', 'M1')));
      await pumpEventQueue();
      expect(seen, isNotEmpty);
      expect(seen.every((s) => !s.membersLoaded), isTrue,
          reason: 'optimistic emit while the write is in flight');

      createGate.complete();
      await pumpEventQueue();
      expect(seen.every((s) => !s.membersLoaded), isTrue,
          reason: 'post-write emit and the rebuild that follows it');

      // And the other direction: once members arrive, the same path carries
      // true.
      teamStream.add([member('M1', blockedOn: eventDay)]);
      await pumpEventQueue();
      expect((bloc.state as AssignmentSlotsLoaded).membersLoaded, isTrue);

      final updateGate = Completer<void>();
      when(assignmentRepo.getAssignmentById(any)).thenAnswer((_) async => null);
      when(assignmentRepo.updateAssignment(any))
          .thenAnswer((_) => updateGate.future);
      final seenAfterMembers = recordSlotStates(bloc);
      bloc.add(OptimisticUpdateAssignment(assignment('a1', 'e1', 'M1')));
      await pumpEventQueue();
      updateGate.complete();
      await pumpEventQueue();
      expect(seenAfterMembers, isNotEmpty);
      expect(seenAfterMembers.every((s) => s.membersLoaded), isTrue);
    });
  });

  group('AssignmentSlotsLoaded value semantics', () {
    test('membersLoaded defaults to true, so existing constructions keep their '
        'meaning', () {
      expect(AssignmentSlotsLoaded(const []).membersLoaded, isTrue);
    });

    test('membersLoaded takes part in equality (repo rule: every field in '
        'props)', () {
      expect(
        AssignmentSlotsLoaded(const [], membersLoaded: false),
        isNot(equals(AssignmentSlotsLoaded(const [], membersLoaded: true))),
      );
    });

    test('copyWith keeps the value unless told otherwise', () {
      final waiting = AssignmentSlotsLoaded(const [], membersLoaded: false);
      expect(waiting.copyWith(isLoadingMorePast: true).membersLoaded, isFalse);
      expect(waiting.copyWith(membersLoaded: true).membersLoaded, isTrue);
      final loaded = AssignmentSlotsLoaded(const []);
      expect(loaded.copyWith(hasMorePast: true).membersLoaded, isTrue);
    });
  });
}
