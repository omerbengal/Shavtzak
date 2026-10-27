// A member blocked by a constraint who is ALSO assigned to another event on
// the same day must carry that event's name on the slot, so the
// "בעלי מגבלות / לא זמינים" list can show both reasons, same-day first
// (spec: "If a member has more than one reason, all reasons are shown").
//
// Both slot-build paths are checked: the live-stream rebuild (Path B,
// _onRebuildAssignmentSlotsFromData) and the stage/filter rebuild (Path A,
// _buildSlotsFromAssignments via RebuildAssignmentSlots).
//
// The partitioning itself must not move: a blocked member stays out of
// availableMembers AND out of sameDayAssignedMembers (the constrained list
// finds them through its own availability check). Only the names map,
// AssignmentSlot.sameDayEventInfo, gains them.
//
// Harness copied from assignment_bloc_staged_samedy_availability_test.dart.

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
  final sharedDay = DateTime.now().add(const Duration(days: 30));
  final otherDay = sharedDay.add(const Duration(days: 3));

  DateConstraint wholeDay(String id, DateTime day, ConstraintStatus status) =>
      DateConstraint(
        id: id,
        startDate: DateTime(day.year, day.month, day.day),
        status: status,
        constraintType: ConstraintType.unavailability,
      );

  TeamMember member(String id, {List<DateConstraint> constraints = const []}) =>
      TeamMember(
        id: id,
        name: 'member-$id',
        isActive: true,
        isPermanent: true,
        constraints: constraints,
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'key-$id',
      );

  Event eventOnDay(String id, DateTime day, {int medics = 1}) => Event(
        id: id,
        name: 'event-$id',
        startDate: DateTime(day.year, day.month, day.day, 9, 0),
        endDate: DateTime(day.year, day.month, day.day, 17, 0),
        startTime: '09:00',
        endTime: '17:00',
        assemblyTime: '08:30',
        requiresArmed: false,
        roleRequirements: {'medic': medics},
        createdAt: now,
        updatedAt: now,
      );

  Assignment assignment(String id, String eventId, String memberId,
          {int slotIndex = 0}) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: 'medic',
        slotIndex: slotIndex,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: now,
        updatedAt: now,
      );

  Role medicRole() => Role(
        id: 'role-medic',
        key: 'medic',
        hebrewName: 'חובש',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );

  // X: the event being staffed (one empty medic slot).
  // Y: same day; A (free), T (approved constraint) and P (pending constraint)
  //    are all assigned to it.
  // Z: another day; C (approved constraint on sharedDay) is assigned to it,
  //    so C is blocked on X but has no same-day booking.
  final members = [
    member('A'),
    member('T',
        constraints: [wholeDay('cT', sharedDay, ConstraintStatus.approved)]),
    member('P',
        constraints: [wholeDay('cP', sharedDay, ConstraintStatus.pending)]),
    member('C',
        constraints: [wholeDay('cC', sharedDay, ConstraintStatus.approved)]),
  ];
  final events = [
    eventOnDay('x1', sharedDay),
    eventOnDay('y1', sharedDay, medics: 3),
    eventOnDay('z1', otherDay),
  ];
  final assignments = [
    assignment('aA', 'y1', 'A', slotIndex: 0),
    assignment('aT', 'y1', 'T', slotIndex: 1),
    assignment('aP', 'y1', 'P', slotIndex: 2),
    assignment('aC', 'z1', 'C'),
  ];

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
        null,
        userCacheService: UserCacheService(),
      );

  Future<void> load(AssignmentBloc bloc) async {
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add(events);
    roleStream.add([medicRole()]);
    teamStream.add(members);
    assignmentStream.add(assignments);
    await pumpEventQueue();
  }

  AssignmentSlot xSlot(AssignmentBloc bloc) =>
      (bloc.state as AssignmentSlotsLoaded).slots.firstWhere(
            (s) =>
                s.event.id == 'x1' && s.role.key == 'medic' && s.slotIndex == 0,
          );

  void expectReasons(AssignmentSlot slot, String path) {
    // Names: every same-day booking, whether or not the member is blocked.
    expect(slot.sameDayEventInfo['T'], ['event-y1'],
        reason: '$path: approved-blocked T is booked on Y the same day');
    expect(slot.sameDayEventInfo['P'], ['event-y1'],
        reason: '$path: pending-blocked P is booked on Y the same day');
    expect(slot.sameDayEventInfo['A'], ['event-y1'],
        reason: '$path: free A is booked on Y the same day (unchanged)');
    expect(slot.sameDayEventInfo.containsKey('C'), isFalse,
        reason: '$path: C is booked on another day only');

    // Partitioning untouched: blocked members are neither offered nor
    // listed as same-day candidates; the free one is the same-day candidate.
    expect(
        slot.availableMembers.map((m) => m.id),
        isNot(
            anyOf(contains('T'), contains('P'), contains('C'), contains('A'))),
        reason: path);
    expect(slot.sameDayAssignedMembers.map((m) => m.id), ['A'], reason: path);
  }

  test(
      'live-stream rebuild (Path B): a constraint-blocked member booked '
      'elsewhere the same day carries the same-day event names', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await load(bloc);

    expectReasons(xSlot(bloc), 'Path B');
  });

  test(
      'stage/filter rebuild (Path A): a constraint-blocked member booked '
      'elsewhere the same day carries the same-day event names', () async {
    final bloc = buildBloc();
    addTearDown(() async => bloc.close());
    await load(bloc);

    bloc.add(const RebuildAssignmentSlots());
    await pumpEventQueue();

    expectReasons(xSlot(bloc), 'Path A');
  });
}
