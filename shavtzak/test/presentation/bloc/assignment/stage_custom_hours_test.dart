// Staging a member's custom hours from the notes dialog.
//
// The backend refuses a Save that would leave a member (not in the
// multiple-assignments pool) with different hours in the roles they hold in one
// event, so the bloc stages the hours on every slot the same member holds in
// that event: all of them change in the ONE staged Save. These tests pin
// siblings (by effective occupant), the exempt member, the revert, and what
// goes on the wire.
//
// Harness copied from assignment_bloc_staged_hours_test.dart (mockito repo
// mocks + StreamControllers + entity builders); blocs are built inside each
// test, never in setUp.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';
import 'package:shavtzak/data/models/assignment_model.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot.dart';

import '../assignment_bloc_slots_refetch_test.mocks.dart';

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

  // Two consecutive future days.
  final base = DateTime.now().add(const Duration(days: 30));
  final day1 = DateTime(base.year, base.month, base.day);
  final day2 = DateTime(base.year, base.month, base.day + 1);

  String two(int v) => v.toString().padLeft(2, '0');

  /// A custom-hours moment on [day]: `yyyy-MM-ddTHH:mm`.
  String at(DateTime day, String hhmm) =>
      '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}T$hhmm';

  TeamMember member(String id, {bool allowMultiple = false}) => TeamMember(
        id: id,
        name: 'member-$id',
        isActive: true,
        isPermanent: true,
        constraints: const [],
        roleCapabilities: const {'medic': true, 'paramedic': true},
        allowMultipleAssignments: allowMultiple,
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'key-$id',
      );

  Event event(String id, {Map<String, int>? roles}) => Event(
        id: id,
        name: 'event-$id',
        startDate: day1,
        endDate: day2,
        startTime: '09:00',
        endTime: '17:00',
        assemblyTime: '08:30',
        requiresArmed: false,
        roleRequirements: roles ?? const {'medic': 1, 'paramedic': 1},
        createdAt: now,
        updatedAt: now,
      );

  Assignment assignment(
    String id,
    String eventId,
    String memberId,
    String roleType, {
    int slotIndex = 0,
    String notes = '',
    String? customStartAt,
    String? customEndAt,
  }) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: roleType,
        slotIndex: slotIndex,
        status: AssignmentStatus.confirmed,
        notes: notes,
        customStartAt: customStartAt,
        customEndAt: customEndAt,
        createdAt: now,
        updatedAt: now,
      );

  Role role(String key, int order) => Role(
        id: 'role-$key',
        key: key,
        hebrewName: key,
        sortOrder: order,
        createdAt: now,
        updatedAt: now,
      );

  final roles = [role('medic', 0), role('paramedic', 1)];
  final members = [
    member('m1'),
    member('m2'),
    member('pool', allowMultiple: true),
  ];

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

    when(eventRepo.getEventsByDateRange(any, any))
        .thenAnswer((_) async => [event('e1')]);
    when(teamRepo.getActiveTeamMembers()).thenAnswer((_) async => members);
    when(assignmentRepo.getAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) async => const <Assignment>[]);
    when(roleRepo.getAllRoles()).thenAnswer((_) async => roles);

    when(assignmentRepo.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
      eventQuotaBumps: anyNamed('eventQuotaBumps'),
      eventQuotaSets: anyNamed('eventQuotaSets'),
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
        null,
        userCacheService: UserCacheService(),
      );

  Future<AssignmentSlotsLoaded> load(
    AssignmentBloc bloc, {
    required List<Event> events,
    required List<Assignment> assignments,
  }) async {
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add(events);
    roleStream.add(roles);
    teamStream.add(members);
    assignmentStream.add(assignments);
    await pumpEventQueue();
    return bloc.state as AssignmentSlotsLoaded;
  }

  AssignmentSlot slotOf(
    AssignmentSlotsLoaded state,
    String eventId,
    String roleKey, [
    int index = 0,
  ]) =>
      state.slots.firstWhere((s) =>
          s.event.id == eventId &&
          s.role.key == roleKey &&
          s.slotIndex == index &&
          !s.isOffQuota);

  AssignmentSlotsLoaded current(AssignmentBloc bloc) =>
      bloc.state as AssignmentSlotsLoaded;

  Future<Map<String, Map<String, dynamic>>> cachedBySlot() async {
    final raw = await UserCacheService().getPendingAssignmentChanges();
    if (raw == null) return const {};
    final decoded = jsonDecode(raw);
    final list = decoded is List
        ? decoded
        : (decoded['changes'] as List? ?? const []);
    return {
      for (final c in list)
        (c as Map<String, dynamic>)['slotKey'] as String: c,
    };
  }

  Future<({List<Assignment> creates, List<Assignment> updates})> save(
      AssignmentBloc bloc) async {
    bloc.add(const SaveStagedChanges());
    await pumpEventQueue();
    final captured = verify(assignmentRepo.saveAssignmentsBatch(
      creates: captureAnyNamed('creates'),
      updates: captureAnyNamed('updates'),
      deletes: anyNamed('deletes'),
      eventQuotaBumps: anyNamed('eventQuotaBumps'),
      eventQuotaSets: anyNamed('eventQuotaSets'),
    )).captured;
    return (
      creates: captured[0] as List<Assignment>,
      updates: captured[1] as List<Assignment>,
    );
  }

  /// m1 holds the medic and paramedic roles of e1, with distinct notes.
  List<Assignment> twoRolesOfM1({String? start, String? end}) => [
        assignment('a1', 'e1', 'm1', 'medic',
            notes: 'חובש', customStartAt: start, customEndAt: end),
        assignment('a2', 'e1', 'm1', 'paramedic',
            notes: 'פראמדיק', customStartAt: start, customEndAt: end),
      ];

  group('the hours of a member holding several roles', () {
    test('staged on the edited slot and on every other slot of that member',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(),
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'medic'),
        notes: 'חובש (נערך)',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day1, '16:00'),
      ));
      await pumpEventQueue();

      final staged = await cachedBySlot();
      expect(staged.keys, unorderedEquals(['e1_medic_0', 'e1_paramedic_0']));
      expect(staged['e1_medic_0']!['desiredCustomStartAt'], at(day1, '10:00'));
      expect(staged['e1_medic_0']!['desiredCustomEndAt'], at(day1, '16:00'));
      expect(staged['e1_paramedic_0']!['desiredCustomStartAt'],
          at(day1, '10:00'));
      expect(
          staged['e1_paramedic_0']!['desiredCustomEndAt'], at(day1, '16:00'));
      // The sibling keeps everything else as it was stored.
      expect(staged['e1_medic_0']!['desiredNotes'], 'חובש (נערך)');
      expect(staged['e1_paramedic_0']!['desiredNotes'], 'פראמדיק');
      expect(staged['e1_paramedic_0']!['desiredMemberId'], 'm1');
      expect(current(bloc).stagedSlotKeys,
          {'e1_medic_0', 'e1_paramedic_0'});
    });

    test('a sibling that is already staged keeps its own edit', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(),
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'paramedic'),
        notes: 'כבר שונה',
        semanticLabelId: 'label-1',
        alternativePhoneNumber: '050-1234567',
      ));
      await pumpEventQueue();
      bloc.add(StageNotesChange(
        slot: slotOf(current(bloc), 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day1, '16:00'),
        setsCustomHours: true,
      ));
      await pumpEventQueue();

      final sibling = (await cachedBySlot())['e1_paramedic_0']!;
      expect(sibling['desiredNotes'], 'כבר שונה');
      expect(sibling['desiredSemanticLabelId'], 'label-1');
      expect(sibling['desiredAltPhone'], '050-1234567');
      expect(sibling['desiredCustomStartAt'], at(day1, '10:00'));
      expect(sibling['desiredCustomEndAt'], at(day1, '16:00'));
    });

    test('a slot just filled with the same member counts as a sibling',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: [assignment('a1', 'e1', 'm1', 'medic')],
      );

      bloc.add(StageMemberChange(
          slot: slotOf(loaded, 'e1', 'paramedic'), member: members[0]));
      await pumpEventQueue();
      bloc.add(StageNotesChange(
        slot: slotOf(current(bloc), 'e1', 'medic'),
        notes: '',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day1, '16:00'),
      ));
      await pumpEventQueue();

      final staged = await cachedBySlot();
      expect(staged['e1_paramedic_0']!['desiredMemberId'], 'm1');
      expect(staged['e1_paramedic_0']!['desiredCustomStartAt'],
          at(day1, '10:00'));
      expect(
          staged['e1_paramedic_0']!['desiredCustomEndAt'], at(day1, '16:00'));
    });

    test('a slot the admin staged to someone else is not a sibling', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(),
      );

      bloc.add(StageMemberChange(
          slot: slotOf(loaded, 'e1', 'paramedic'), member: members[1]));
      await pumpEventQueue();
      bloc.add(StageNotesChange(
        slot: slotOf(current(bloc), 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day1, '16:00'),
      ));
      await pumpEventQueue();

      final staged = await cachedBySlot();
      expect(staged['e1_paramedic_0']!['desiredMemberId'], 'm2');
      // The seeded (interim) hours of the replaced slot are untouched.
      expect(staged['e1_paramedic_0']!['desiredCustomStartAt'], isNull);
      expect(staged['e1_paramedic_0']!['desiredCustomEndAt'], isNull);
    });

    test('a slot staged for deletion is not a sibling', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(),
      );

      bloc.add(StageSlotDeletion(slotOf(loaded, 'e1', 'paramedic')));
      await pumpEventQueue();
      bloc.add(StageNotesChange(
        slot: slotOf(current(bloc), 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day1, '16:00'),
      ));
      await pumpEventQueue();

      final staged = await cachedBySlot();
      expect(staged['e1_paramedic_0']!['markedForDeletion'], isTrue);
      expect(staged['e1_paramedic_0']!['desiredCustomStartAt'], isNull);
    });

    test('the same member in another event is not touched', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1'), event('e2')],
        assignments: [
          assignment('a1', 'e1', 'm1', 'medic'),
          assignment('b1', 'e2', 'm1', 'medic'),
        ],
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'medic'),
        notes: '',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day1, '16:00'),
      ));
      await pumpEventQueue();

      expect((await cachedBySlot()).keys, ['e1_medic_0']);
    });

    test('an exempt member (multiple assignments) stages only the edited slot',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: [
          assignment('a1', 'e1', 'pool', 'medic'),
          assignment('a2', 'e1', 'pool', 'paramedic'),
        ],
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'medic'),
        notes: '',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day1, '16:00'),
      ));
      await pumpEventQueue();

      expect((await cachedBySlot()).keys, ['e1_medic_0']);
      expect(current(bloc).stagedSlotKeys, {'e1_medic_0'});
    });

    test('an edit that does not decide the hours stages no sibling', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(
            start: at(day1, '10:00'), end: at(day1, '16:00')),
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'medic'),
        notes: 'רק הערה',
      ));
      await pumpEventQueue();

      final staged = await cachedBySlot();
      expect(staged.keys, ['e1_medic_0']);
      // The hours the slot held are kept, not cleared.
      expect(staged['e1_medic_0']!['desiredCustomStartAt'], at(day1, '10:00'));
      expect(staged['e1_medic_0']!['desiredCustomEndAt'], at(day1, '16:00'));
    });

    test('switching the hours off clears them on every role', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(
            start: at(day1, '10:00'), end: at(day1, '16:00')),
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: null,
        customEndAt: null,
        setsCustomHours: true,
      ));
      await pumpEventQueue();

      final staged = await cachedBySlot();
      expect(staged.keys, unorderedEquals(['e1_medic_0', 'e1_paramedic_0']));
      for (final change in staged.values) {
        expect(change['desiredCustomStartAt'], isNull);
        expect(change['desiredCustomEndAt'], isNull);
        expect(change['baselineCustomStartAt'], at(day1, '10:00'));
      }
    });
  });

  group('reverting the hours', () {
    test('staging them back to the baseline un-dirties every role', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(
            start: at(day1, '10:00'), end: at(day1, '16:00')),
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: at(day1, '11:00'),
        customEndAt: at(day1, '15:00'),
      ));
      await pumpEventQueue();
      expect(current(bloc).stagedSlotKeys,
          {'e1_medic_0', 'e1_paramedic_0'});

      bloc.add(StageNotesChange(
        slot: slotOf(current(bloc), 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day1, '16:00'),
      ));
      await pumpEventQueue();

      expect(current(bloc).stagedSlotKeys, isEmpty);
      expect(bloc.hasStagedChanges, isFalse);
      expect(await cachedBySlot(), isEmpty);
    });

    test('setting hours and then switching them off leaves nothing staged',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(),
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day1, '16:00'),
      ));
      await pumpEventQueue();
      bloc.add(StageNotesChange(
        slot: slotOf(current(bloc), 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: null,
        customEndAt: null,
        setsCustomHours: true,
      ));
      await pumpEventQueue();

      expect(current(bloc).stagedSlotKeys, isEmpty);
    });
  });

  group('Save', () {
    test('sends the hours of every role in the one batch', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(),
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: at(day1, '10:00'),
        customEndAt: at(day2, '02:00'),
      ));
      await pumpEventQueue();
      final saved = await save(bloc);

      expect(saved.creates, isEmpty);
      expect(saved.updates.map((u) => u.id), unorderedEquals(['a1', 'a2']));
      for (final update in saved.updates) {
        final wire = AssignmentModel.fromEntity(update).toJson();
        expect(wire['customStartAt'], at(day1, '10:00'));
        expect(wire['customEndAt'], at(day2, '02:00'));
      }
      expect(saved.updates.firstWhere((u) => u.id == 'a2').notes, 'פראמדיק');
    });

    test('switching the hours off sends an explicit null pair', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(
            start: at(day1, '10:00'), end: at(day1, '16:00')),
      );

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'e1', 'medic'),
        notes: 'חובש',
        customStartAt: null,
        customEndAt: null,
        setsCustomHours: true,
      ));
      await pumpEventQueue();
      final saved = await save(bloc);

      expect(saved.updates, hasLength(2));
      for (final update in saved.updates) {
        final wire = AssignmentModel.fromEntity(update).toJson();
        expect(wire.containsKey('customStartAt'), isTrue);
        expect(wire['customStartAt'], isNull);
        expect(wire['customEndAt'], isNull);
      }
    });
  });

  group('otherSlotsOfSameMember (the dialog asks it for its note)', () {
    test('lists the other roles the member holds in the event', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(),
      );

      final others =
          bloc.otherSlotsOfSameMember(slotOf(loaded, 'e1', 'medic'));
      expect(others.map((s) => s.role.key), ['paramedic']);
    });

    test('is empty for a member with one slot', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: [assignment('a1', 'e1', 'm1', 'medic')],
      );

      expect(bloc.otherSlotsOfSameMember(slotOf(loaded, 'e1', 'medic')),
          isEmpty);
    });

    test('is empty for an exempt member', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: [
          assignment('a1', 'e1', 'pool', 'medic'),
          assignment('a2', 'e1', 'pool', 'paramedic'),
        ],
      );

      expect(bloc.otherSlotsOfSameMember(slotOf(loaded, 'e1', 'medic')),
          isEmpty);
    });

    test('follows the staged occupant, not the stored one', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1')],
        assignments: twoRolesOfM1(),
      );

      bloc.add(StageMemberChange(
          slot: slotOf(loaded, 'e1', 'paramedic'), member: members[1]));
      await pumpEventQueue();

      expect(
          bloc.otherSlotsOfSameMember(slotOf(current(bloc), 'e1', 'medic')),
          isEmpty);
    });
  });
}
