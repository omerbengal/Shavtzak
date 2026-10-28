// Filling or replacing a slot when custom hours are involved.
//
// The admin assignments screen asks which hours the incoming member gets
// (ReplacementHoursDialog) and stages the answer with StageMemberChange. The
// backend refuses a Save that leaves a member (not in the multiple-assignments
// pool) with different hours in the roles they hold in one event, and never
// gives a staged row hours of its own accord, so every staging action must
// leave each such member with one set of hours in the event. These tests pin
// that: the chosen hours reach every role of the incoming member, a plain
// replace never inherits, a manual add takes the member's hours, and undo puts
// everything back.
//
// Harness copied from stage_custom_hours_test.dart (mockito repo mocks +
// StreamControllers + entity builders); blocs are built inside each test,
// never in setUp.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
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

  Event event(String id) => Event(
        id: id,
        name: 'event-$id',
        startDate: day1,
        endDate: day2,
        startTime: '09:00',
        endTime: '17:00',
        assemblyTime: '08:30',
        requiresArmed: false,
        roleRequirements: const {'medic': 1, 'paramedic': 1},
        createdAt: now,
        updatedAt: now,
      );

  Assignment assignment(
    String id,
    String eventId,
    String memberId,
    String roleType, {
    String notes = '',
    String? customStartAt,
    String? customEndAt,
  }) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: roleType,
        slotIndex: 0,
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
  final dana = member('dana');
  final yossi = member('yossi');
  final pool = member('pool', allowMultiple: true);
  final members = [dana, yossi, pool];

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
    required List<Assignment> assignments,
    List<String> eventIds = const ['e1'],
  }) async {
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add([for (final id in eventIds) event(id)]);
    roleStream.add(roles);
    teamStream.add(members);
    assignmentStream.add(assignments);
    await pumpEventQueue();
    return bloc.state as AssignmentSlotsLoaded;
  }

  AssignmentSlotsLoaded current(AssignmentBloc bloc) =>
      bloc.state as AssignmentSlotsLoaded;

  AssignmentSlot slotOf(AssignmentSlotsLoaded state, String roleKey,
          [int index = 0]) =>
      state.slots.firstWhere((s) =>
          s.event.id == 'e1' &&
          s.role.key == roleKey &&
          s.slotIndex == index &&
          !s.isOffQuota);

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

  // Dana's hours on the medic slot: day 1, 14:00 to 23:00.
  final danaStart = at(day1, '14:00');
  final danaEnd = at(day1, '23:00');

  /// Dana holds medic with her own hours; [paramedicHolder] holds paramedic,
  /// with [paramedicStart]/[paramedicEnd] as its hours.
  List<Assignment> danaOnMedic({
    String paramedicHolder = 'yossi',
    String? paramedicStart,
    String? paramedicEnd,
  }) =>
      [
        assignment('a1', 'e1', 'dana', 'medic',
            notes: 'של דנה', customStartAt: danaStart, customEndAt: danaEnd),
        assignment('a2', 'e1', paramedicHolder, 'paramedic',
            notes: 'פראמדיק',
            customStartAt: paramedicStart,
            customEndAt: paramedicEnd),
      ];

  /// Yossi replaces dana on medic, keeping her hours.
  Future<void> replaceDanaKeepingHerHours(
      AssignmentBloc bloc, AssignmentSlotsLoaded loaded) async {
    bloc.add(StageMemberChange(
      slot: slotOf(loaded, 'medic'),
      member: yossi,
      setsCustomHours: true,
      customStartAt: danaStart,
      customEndAt: danaEnd,
    ));
    await pumpEventQueue();
  }

  group('replacing an occupant who has hours', () {
    test('keeping her hours gives them to the incoming member', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());

      await replaceDanaKeepingHerHours(bloc, loaded);

      final medic = (await cachedBySlot())['e1_medic_0']!;
      expect(medic['desiredMemberId'], 'yossi');
      expect(medic['desiredCustomStartAt'], danaStart);
      expect(medic['desiredCustomEndAt'], danaEnd);
    });

    test('the incoming member\'s other role in the event gets the same hours',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());

      await replaceDanaKeepingHerHours(bloc, loaded);

      final staged = await cachedBySlot();
      expect(staged.keys, unorderedEquals(['e1_medic_0', 'e1_paramedic_0']));
      final paramedic = staged['e1_paramedic_0']!;
      expect(paramedic['desiredMemberId'], 'yossi');
      expect(paramedic['desiredNotes'], 'פראמדיק');
      expect(paramedic['desiredCustomStartAt'], danaStart);
      expect(paramedic['desiredCustomEndAt'], danaEnd);
      expect(current(bloc).stagedSlotKeys, {'e1_medic_0', 'e1_paramedic_0'});
    });

    test('the event\'s hours clear the incoming member\'s hours on every role',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: danaOnMedic(
          paramedicStart: at(day2, '08:00'),
          paramedicEnd: at(day2, '12:00'),
        ),
      );

      bloc.add(StageMemberChange(
        slot: slotOf(loaded, 'medic'),
        member: yossi,
        setsCustomHours: true,
      ));
      await pumpEventQueue();

      final staged = await cachedBySlot();
      expect(staged.keys, unorderedEquals(['e1_medic_0', 'e1_paramedic_0']));
      for (final change in staged.values) {
        expect(change['desiredMemberId'], 'yossi');
        expect(change['desiredCustomStartAt'], isNull);
        expect(change['desiredCustomEndAt'], isNull);
      }
    });

    test('an exempt incoming member gets the hours on the slot only',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded =
          await load(bloc, assignments: danaOnMedic(paramedicHolder: 'pool'));

      bloc.add(StageMemberChange(
        slot: slotOf(loaded, 'medic'),
        member: pool,
        setsCustomHours: true,
        customStartAt: danaStart,
        customEndAt: danaEnd,
      ));
      await pumpEventQueue();

      final staged = await cachedBySlot();
      expect(staged.keys, ['e1_medic_0']);
      expect(staged['e1_medic_0']!['desiredCustomStartAt'], danaStart);
    });

    test('a plain replace leaves the new occupant without hours', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());

      bloc.add(StageMemberChange(slot: slotOf(loaded, 'medic'), member: yossi));
      await pumpEventQueue();

      final medic = (await cachedBySlot())['e1_medic_0']!;
      expect(medic['desiredMemberId'], 'yossi');
      expect(medic['desiredCustomStartAt'], isNull);
      expect(medic['desiredCustomEndAt'], isNull);
      // The stored hours stay the baseline: Save clears them on the row.
      expect(medic['baselineCustomStartAt'], danaStart);
    });

    test('staging the same occupant again keeps their hours', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());

      bloc.add(StageMemberChange(slot: slotOf(loaded, 'medic'), member: dana));
      await pumpEventQueue();

      expect(current(bloc).stagedSlotKeys, isEmpty);
    });

    test('filling an empty slot with hours and clearing it leaves it clean',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: const []);

      bloc.add(StageMemberChange(
        slot: slotOf(loaded, 'medic'),
        member: yossi,
        setsCustomHours: true,
        customStartAt: danaStart,
        customEndAt: danaEnd,
      ));
      await pumpEventQueue();
      bloc.add(StageMemberChange(
          slot: slotOf(current(bloc), 'medic'), member: null));
      await pumpEventQueue();

      expect(current(bloc).stagedSlotKeys, isEmpty);
    });

    test('Save sends the incoming member\'s hours on every role in one batch',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());

      await replaceDanaKeepingHerHours(bloc, loaded);
      final saved = await save(bloc);

      expect(saved.creates, isEmpty);
      expect(saved.updates.map((u) => u.id), unorderedEquals(['a1', 'a2']));
      for (final update in saved.updates) {
        expect(update.teamMemberId, 'yossi');
        expect(update.customStartAt, danaStart);
        expect(update.customEndAt, danaEnd);
      }
    });
  });

  group('StageMemberChange guards its hours', () {
    test('a half pair is refused', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());

      expect(
        () => StageMemberChange(
          slot: slotOf(loaded, 'medic'),
          member: yossi,
          setsCustomHours: true,
          customStartAt: danaStart,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('hours without setsCustomHours are refused', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());

      expect(
        () => StageMemberChange(
          slot: slotOf(loaded, 'medic'),
          member: yossi,
          customStartAt: danaStart,
          customEndAt: danaEnd,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('undoing a replacement', () {
    test('undoing the replaced slot puts the incoming member\'s other role '
        'back as it was', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());
      await replaceDanaKeepingHerHours(bloc, loaded);
      expect(current(bloc).stagedSlotKeys, {'e1_medic_0', 'e1_paramedic_0'});

      bloc.add(const DiscardStagedSlot('e1_medic_0'));
      await pumpEventQueue();

      expect(current(bloc).stagedSlotKeys, isEmpty);
      expect(await cachedBySlot(), isEmpty);
    });

    test('undoing the other role puts the replaced slot on the member\'s '
        'stored hours, so Save never splits them', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());
      await replaceDanaKeepingHerHours(bloc, loaded);

      bloc.add(const DiscardStagedSlot('e1_paramedic_0'));
      await pumpEventQueue();

      // Yossi's stored paramedic row has no hours, so the replacement on
      // medic goes without them too; it stays a replacement.
      final staged = await cachedBySlot();
      expect(staged.keys, ['e1_medic_0']);
      expect(staged['e1_medic_0']!['desiredMemberId'], 'yossi');
      expect(staged['e1_medic_0']!['desiredCustomStartAt'], isNull);
      expect(staged['e1_medic_0']!['desiredCustomEndAt'], isNull);

      final saved = await save(bloc);
      expect(saved.updates.map((u) => u.id), ['a1']);
      expect(saved.updates.single.customStartAt, isNull);
    });
  });

  group('undoing a staged deletion', () {
    test('the member\'s other role takes their stored hours back, so Save '
        'never splits them', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      // Yossi is stored on medic with hours, his only role; paramedic is empty.
      final loaded = await load(
        bloc,
        assignments: [
          assignment('a1', 'e1', 'yossi', 'medic',
              customStartAt: danaStart, customEndAt: danaEnd),
        ],
      );

      // Medic is swiped away, so yossi holds nothing: putting him on
      // paramedic asks nothing and gives him no hours.
      bloc.add(StageSlotDeletion(slotOf(loaded, 'medic')));
      await pumpEventQueue();
      bloc.add(StageMemberChange(
          slot: slotOf(current(bloc), 'paramedic'), member: yossi));
      await pumpEventQueue();
      expect((await cachedBySlot())['e1_paramedic_0']!['desiredCustomStartAt'],
          isNull);

      // Undoing the deletion brings medic back with his stored hours.
      bloc.add(const DiscardStagedSlot('e1_medic_0'));
      await pumpEventQueue();

      final paramedic = (await cachedBySlot())['e1_paramedic_0']!;
      expect(paramedic['desiredMemberId'], 'yossi');
      expect(paramedic['desiredCustomStartAt'], danaStart);
      expect(paramedic['desiredCustomEndAt'], danaEnd);

      final saved = await save(bloc);
      expect(saved.updates, isEmpty);
      final created = saved.creates.single;
      expect(created.teamMemberId, 'yossi');
      expect(created.customStartAt, danaStart);
      expect(created.customEndAt, danaEnd);
    });

    test('a manual add made while it stood takes the stored hours too',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: [
          assignment('a1', 'e1', 'yossi', 'medic',
              customStartAt: danaStart, customEndAt: danaEnd),
        ],
      );
      bloc.add(StageSlotDeletion(slotOf(loaded, 'medic')));
      await pumpEventQueue();
      // With medic gone, yossi holds no hours: the added row takes none.
      bloc.add(StageManualAdd(
          event: event('e1'), member: yossi, roleType: 'paramedic'));
      await pumpEventQueue();

      bloc.add(const DiscardStagedSlot('e1_medic_0'));
      await pumpEventQueue();

      final saved = await save(bloc);
      expect(saved.updates, isEmpty);
      final created = saved.creates.single;
      expect(created.roleType, 'paramedic');
      expect(created.customStartAt, danaStart);
      expect(created.customEndAt, danaEnd);
    });
  });

  group('picking the slot\'s stored occupant back', () {
    test('when she holds no other role, her stored hours come back and the '
        'slot is clean', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: [
          assignment('a1', 'e1', 'dana', 'medic',
              notes: 'של דנה', customStartAt: danaStart, customEndAt: danaEnd),
        ],
      );

      // Yossi replaces her with the event's hours...
      bloc.add(StageMemberChange(
        slot: slotOf(loaded, 'medic'),
        member: yossi,
        setsCustomHours: true,
      ));
      await pumpEventQueue();
      expect(current(bloc).stagedSlotKeys, {'e1_medic_0'});

      // ...and she is picked again: no hours step runs (nobody has hours).
      bloc.add(StageMemberChange(
          slot: slotOf(current(bloc), 'medic'), member: dana));
      await pumpEventQueue();

      expect(current(bloc).stagedSlotKeys, isEmpty);
      expect(await cachedBySlot(), isEmpty);
    });

    test('while she holds another role, the hours are left to the hours step',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: [
          assignment('a1', 'e1', 'dana', 'medic',
              customStartAt: danaStart, customEndAt: danaEnd),
          assignment('a2', 'e1', 'dana', 'paramedic',
              customStartAt: danaStart, customEndAt: danaEnd),
        ],
      );
      bloc.add(StageMemberChange(
        slot: slotOf(loaded, 'medic'),
        member: yossi,
        setsCustomHours: true,
      ));
      await pumpEventQueue();

      // The screen would ask here (her paramedic role has hours); a plain
      // change gives no hours back.
      bloc.add(StageMemberChange(
          slot: slotOf(current(bloc), 'medic'), member: dana));
      await pumpEventQueue();

      final medic = (await cachedBySlot())['e1_medic_0']!;
      expect(medic['desiredMemberId'], 'dana');
      expect(medic['desiredCustomStartAt'], isNull);
    });
  });

  group('a manual add', () {
    test('into an event the screen\'s filter hides still takes the member\'s '
        'hours there, so Save never splits them', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final stored = [
        assignment('b2', 'e2', 'yossi', 'paramedic',
            customStartAt: danaStart, customEndAt: danaEnd),
      ];
      await load(bloc, eventIds: ['e1', 'e2'], assignments: stored);
      // The screen is filtered to e1; the next stream update builds the grid
      // with e1's slots only.
      bloc.add(const ApplyEventFilter({'e1'}));
      await pumpEventQueue();
      assignmentStream.add([...stored]);
      await pumpEventQueue();
      expect(current(bloc).slots, isNotEmpty);
      expect(current(bloc).slots.every((s) => s.event.id == 'e1'), isTrue);

      bloc.add(StageManualAdd(
          event: event('e2'), member: yossi, roleType: 'medic'));
      await pumpEventQueue();

      final saved = await save(bloc);
      final created = saved.creates.single;
      expect(created.eventId, 'e2');
      expect(created.teamMemberId, 'yossi');
      expect(created.customStartAt, danaStart);
      expect(created.customEndAt, danaEnd);
    });

    test('undone, it leaves a staged hours edit on the member\'s other role '
        'alone', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: [assignment('a2', 'e1', 'yossi', 'paramedic')],
      );
      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'paramedic'),
        notes: '',
        customStartAt: at(day2, '08:00'),
        customEndAt: at(day2, '12:00'),
      ));
      await pumpEventQueue();
      bloc.add(StageManualAdd(
          event: event('e1'), member: yossi, roleType: 'medic'));
      await pumpEventQueue();
      final addedKey = (await cachedBySlot())
          .values
          .singleWhere((c) => c['isManualAdd'] == true)['slotKey'] as String;

      bloc.add(DiscardStagedSlot(addedKey));
      await pumpEventQueue();

      final staged = await cachedBySlot();
      expect(staged.keys, ['e1_paramedic_0']);
      expect(staged['e1_paramedic_0']!['desiredCustomStartAt'],
          at(day2, '08:00'));
      expect(staged['e1_paramedic_0']!['desiredCustomEndAt'],
          at(day2, '12:00'));
    });

    test('takes the hours the member holds in the event', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      await load(
        bloc,
        assignments: [
          assignment('a2', 'e1', 'yossi', 'paramedic',
              customStartAt: danaStart, customEndAt: danaEnd),
        ],
      );

      bloc.add(StageManualAdd(
          event: event('e1'), member: yossi, roleType: 'medic'));
      await pumpEventQueue();
      final saved = await save(bloc);

      final created = saved.creates.single;
      expect(created.teamMemberId, 'yossi');
      expect(created.customStartAt, danaStart);
      expect(created.customEndAt, danaEnd);
    });

    test('takes the staged hours when they are being changed', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: [
          assignment('a2', 'e1', 'yossi', 'paramedic',
              customStartAt: danaStart, customEndAt: danaEnd),
        ],
      );
      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'paramedic'),
        notes: '',
        customStartAt: at(day2, '08:00'),
        customEndAt: at(day2, '12:00'),
      ));
      await pumpEventQueue();

      bloc.add(StageManualAdd(
          event: event('e1'), member: yossi, roleType: 'medic'));
      await pumpEventQueue();

      final added = (await cachedBySlot())
          .values
          .singleWhere((c) => c['isManualAdd'] == true);
      expect(added['desiredCustomStartAt'], at(day2, '08:00'));
      expect(added['desiredCustomEndAt'], at(day2, '12:00'));
      // A new slot has no stored hours.
      expect(added['baselineCustomStartAt'], isNull);
    });

    test('of an exempt member has no hours', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      await load(
        bloc,
        assignments: [
          assignment('a2', 'e1', 'pool', 'paramedic',
              customStartAt: danaStart, customEndAt: danaEnd),
        ],
      );

      bloc.add(
          StageManualAdd(event: event('e1'), member: pool, roleType: 'medic'));
      await pumpEventQueue();

      final added = (await cachedBySlot())
          .values
          .singleWhere((c) => c['isManualAdd'] == true);
      expect(added['desiredCustomStartAt'], isNull);
      expect(added['desiredCustomEndAt'], isNull);
    });
  });

  group('what the hours step is told', () {
    test('effectiveCustomWindow reads the stored, then the staged hours',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(bloc, assignments: danaOnMedic());

      expect(
        bloc.effectiveCustomWindow(slotOf(loaded, 'medic')),
        customHoursInterval(danaStart, danaEnd),
      );
      expect(bloc.effectiveCustomWindow(slotOf(loaded, 'paramedic')), isNull);

      bloc.add(StageNotesChange(
        slot: slotOf(loaded, 'medic'),
        notes: '',
        customStartAt: at(day2, '08:00'),
        customEndAt: at(day2, '12:00'),
      ));
      await pumpEventQueue();
      expect(
        bloc.effectiveCustomWindow(slotOf(current(bloc), 'medic')),
        customHoursInterval(at(day2, '08:00'), at(day2, '12:00')),
      );

      bloc.add(
          StageMemberChange(slot: slotOf(current(bloc), 'medic'), member: null));
      await pumpEventQueue();
      expect(
          bloc.effectiveCustomWindow(slotOf(current(bloc), 'medic')), isNull);
    });

    test('otherSlotsHeldBy and hoursHeldElsewhere describe the incoming '
        'member\'s other roles', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: danaOnMedic(
          paramedicStart: at(day2, '08:00'),
          paramedicEnd: at(day2, '12:00'),
        ),
      );
      final medic = slotOf(loaded, 'medic');

      expect(bloc.otherSlotsHeldBy(yossi, medic).map((s) => s.role.key),
          ['paramedic']);
      expect(bloc.hoursHeldElsewhere(yossi, medic),
          customHoursInterval(at(day2, '08:00'), at(day2, '12:00')));
      // Seen from her own medic slot, dana holds nothing else.
      expect(bloc.otherSlotsHeldBy(dana, medic), isEmpty);
      expect(bloc.hoursHeldElsewhere(dana, medic), isNull);
      // Seen from paramedic, she holds medic with her hours.
      expect(
          bloc
              .otherSlotsHeldBy(dana, slotOf(loaded, 'paramedic'))
              .map((s) => s.role.key),
          ['medic']);
      expect(bloc.hoursHeldElsewhere(dana, slotOf(loaded, 'paramedic')),
          customHoursInterval(danaStart, danaEnd));
    });

    test('an exempt member holds nothing elsewhere', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: danaOnMedic(
          paramedicHolder: 'pool',
          paramedicStart: at(day2, '08:00'),
          paramedicEnd: at(day2, '12:00'),
        ),
      );
      final medic = slotOf(loaded, 'medic');

      expect(bloc.otherSlotsHeldBy(pool, medic), isEmpty);
      expect(bloc.hoursHeldElsewhere(pool, medic), isNull);
    });

    test('a role the member was just staged into counts, with its staged hours',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: [
          assignment('a1', 'e1', 'dana', 'medic',
              customStartAt: danaStart, customEndAt: danaEnd),
        ],
      );

      // Yossi fills the empty paramedic slot with hours of his own.
      bloc.add(StageMemberChange(
        slot: slotOf(loaded, 'paramedic'),
        member: yossi,
        setsCustomHours: true,
        customStartAt: at(day2, '08:00'),
        customEndAt: at(day2, '12:00'),
      ));
      await pumpEventQueue();

      final medic = slotOf(current(bloc), 'medic');
      expect(bloc.otherSlotsHeldBy(yossi, medic).map((s) => s.role.key),
          ['paramedic']);
      expect(bloc.hoursHeldElsewhere(yossi, medic),
          customHoursInterval(at(day2, '08:00'), at(day2, '12:00')));
    });

    test('a role the member was staged out of does not count', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        assignments: danaOnMedic(
          paramedicStart: at(day2, '08:00'),
          paramedicEnd: at(day2, '12:00'),
        ),
      );

      bloc.add(StageMemberChange(
          slot: slotOf(loaded, 'paramedic'), member: null));
      await pumpEventQueue();

      final medic = slotOf(current(bloc), 'medic');
      expect(bloc.otherSlotsHeldBy(yossi, medic), isEmpty);
      expect(bloc.hoursHeldElsewhere(yossi, medic), isNull);
    });
  });
}
