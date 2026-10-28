// Staged Save and custom hours (partial attendance).
//
// The backend reads an update that carries an explicit null hours pair as
// "clear the hours", and one that carries nothing as "keep". The client always
// sends a pair, so a staged Save has to send back exactly what is stored unless
// the admin changed it. These tests lock in that every place the bloc builds an
// Assignment from a staged change carries the hours, and that hours changed
// underneath a staged edit are a conflict (type F, with notes/label/phone).
//
// Harness copied from assignment_bloc_save_test.dart (mockito repo mocks +
// StreamControllers + entity builders) and reuses the generated mocks of
// assignment_bloc_slots_refetch_test.dart.

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
import 'package:shavtzak/presentation/bloc/assignment/models/assignment_conflict.dart';
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

  // Two days in the future: day1 and day2 are consecutive calendar days.
  final base = DateTime.now().add(const Duration(days: 30));
  final day1 = DateTime(base.year, base.month, base.day);
  final day2 = DateTime(base.year, base.month, base.day + 1);

  String two(int v) => v.toString().padLeft(2, '0');

  /// A stored custom-hours moment on [day]: `yyyy-MM-ddTHH:mm`.
  String at(DateTime day, String hhmm) =>
      '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}T$hhmm';

  // isPermanent: true so the member is available by default.
  TeamMember member(String id) => TeamMember(
        id: id,
        name: 'member-$id',
        isActive: true,
        isPermanent: true,
        constraints: const [],
        roleCapabilities: const {'medic': true},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'key-$id',
      );

  Event event(
    String id, {
    required DateTime start,
    DateTime? end,
    Map<String, int>? roleRequirements,
  }) =>
      Event(
        id: id,
        name: 'event-$id',
        startDate: start,
        endDate: end ?? start,
        startTime: '09:00',
        endTime: '17:00',
        assemblyTime: '08:30',
        requiresArmed: false,
        roleRequirements: roleRequirements ?? const {'medic': 1},
        createdAt: now,
        updatedAt: now,
      );

  Assignment assignment(
    String id,
    String eventId,
    String memberId, {
    int slotIndex = 0,
    String? customStartAt,
    String? customEndAt,
    String notes = '',
  }) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: 'medic',
        slotIndex: slotIndex,
        status: AssignmentStatus.confirmed,
        notes: notes,
        customStartAt: customStartAt,
        customEndAt: customEndAt,
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
        .thenAnswer((_) async => [event('e1', start: day1)]);
    when(teamRepo.getActiveTeamMembers())
        .thenAnswer((_) async => [member('m1'), member('m2')]);
    when(assignmentRepo.getAssignmentsInTimeWindow(
      windowStart: anyNamed('windowStart'),
      windowEnd: anyNamed('windowEnd'),
    )).thenAnswer((_) async => const <Assignment>[]);
    when(roleRepo.getAllRoles()).thenAnswer((_) async => [medicRole()]);

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

  /// Opens the grid on [events] with [assignments] as the stored data.
  Future<AssignmentSlotsLoaded> load(
    AssignmentBloc bloc, {
    required List<Event> events,
    required List<Assignment> assignments,
  }) async {
    bloc.add(const LoadAssignmentSlots());
    await pumpEventQueue();
    eventStream.add(events);
    roleStream.add([medicRole()]);
    teamStream.add([member('m1'), member('m2')]);
    assignmentStream.add(assignments);
    await pumpEventQueue();
    return bloc.state as AssignmentSlotsLoaded;
  }

  AssignmentSlot medicSlot(AssignmentSlotsLoaded state, String eventId,
          [int index = 0]) =>
      state.slots.firstWhere((s) =>
          s.event.id == eventId &&
          s.role.key == 'medic' &&
          s.slotIndex == index &&
          !s.isOffQuota);

  /// Saves and returns the (creates, updates) lists the repository received.
  /// [resolutions] are the conflict dialog's choices, per slot key.
  Future<({List<Assignment> creates, List<Assignment> updates})> save(
      AssignmentBloc bloc,
      {Map<String, ConflictResolution>? resolutions}) async {
    bloc.add(SaveStagedChanges(resolutions: resolutions));
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

  Future<List<dynamic>> cachedChanges() async {
    final raw = await UserCacheService().getPendingAssignmentChanges();
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    return decoded is List
        ? decoded
        : (decoded['changes'] as List? ?? const []);
  }

  group('Save sends the hours the admin left in place', () {
    test('a notes-only edit on an assignment with hours sends them back',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1', start: day1, end: day2)],
        assignments: [
          assignment('a1', 'e1', 'm1',
              customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
        ],
      );

      bloc.add(StageNotesChange(
        slot: medicSlot(loaded, 'e1'),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();
      final saved = await save(bloc);

      final update = saved.updates.single;
      expect(update.id, 'a1');
      expect(update.customStartAt, at(day1, '10:00'));
      expect(update.customEndAt, at(day1, '16:00'));
      // What goes on the wire: an explicit pair, never a null one.
      final wire = AssignmentModel.fromEntity(update).toJson();
      expect(wire['customStartAt'], at(day1, '10:00'));
      expect(wire['customEndAt'], at(day1, '16:00'));
    });

    test('a notes-only edit on an assignment without hours sends no hours',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1', start: day1)],
        assignments: [assignment('a1', 'e1', 'm1')],
      );

      bloc.add(StageNotesChange(
        slot: medicSlot(loaded, 'e1'),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();
      final saved = await save(bloc);

      expect(saved.updates.single.customStartAt, isNull);
      expect(saved.updates.single.customEndAt, isNull);
    });

    test('a fill of an empty slot creates the assignment without hours',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1', start: day1)],
        assignments: const [],
      );

      bloc.add(StageMemberChange(
          slot: medicSlot(loaded, 'e1'), member: member('m1')));
      await pumpEventQueue();
      final saved = await save(bloc);

      expect(saved.creates.single.teamMemberId, 'm1');
      expect(saved.creates.single.customStartAt, isNull);
      expect(saved.creates.single.customEndAt, isNull);
    });

    test('a manual add creates the assignment without hours', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      await load(
        bloc,
        events: [event('e1', start: day1)],
        assignments: [
          assignment('a1', 'e1', 'm1',
              customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
        ],
      );

      bloc.add(StageManualAdd(
        event: event('e1', start: day1),
        member: member('m2'),
        roleType: 'medic',
      ));
      await pumpEventQueue();

      final staged = (await cachedChanges()).single as Map<String, dynamic>;
      expect(staged['desiredCustomStartAt'], isNull);
      expect(staged['desiredCustomEndAt'], isNull);
      expect(staged['baselineCustomStartAt'], isNull);
      expect(staged['baselineCustomEndAt'], isNull);

      final saved = await save(bloc);
      final created = saved.creates.single;
      expect(created.teamMemberId, 'm2');
      expect(created.customStartAt, isNull);
      expect(created.customEndAt, isNull);
    });

    test(
        'a plain staged replacement of the occupant clears the hours: they '
        'belong to the one who left, and Save sends an explicit null pair',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1', start: day1)],
        assignments: [
          assignment('a1', 'e1', 'm1',
              customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
        ],
      );

      bloc.add(StageMemberChange(
          slot: medicSlot(loaded, 'e1'), member: member('m2')));
      await pumpEventQueue();
      final saved = await save(bloc);

      final update = saved.updates.single;
      expect(update.teamMemberId, 'm2');
      final wire = AssignmentModel.fromEntity(update).toJson();
      expect(wire.containsKey('customStartAt'), isTrue);
      expect(wire['customStartAt'], isNull);
      expect(wire['customEndAt'], isNull);
    });
  });

  group('the unsaved edit shows the hours', () {
    test('the optimistic row of a staged notes edit keeps the stored hours',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1', start: day1, end: day2)],
        assignments: [
          assignment('a1', 'e1', 'm1',
              customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
        ],
      );

      bloc.add(StageNotesChange(
        slot: medicSlot(loaded, 'e1'),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();

      final shown = medicSlot(bloc.state as AssignmentSlotsLoaded, 'e1')
          .currentAssignment!;
      expect(shown.notes, 'הערה');
      expect(shown.customStartAt, at(day1, '10:00'));
      expect(shown.customEndAt, at(day1, '16:00'));
    });

    test('a staged row moved by a committed row removal keeps all four fields',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1', start: day1, roleRequirements: const {'medic': 3})],
        assignments: [
          assignment('a2', 'e1', 'm1',
              slotIndex: 2,
              customStartAt: at(day1, '10:00'),
              customEndAt: at(day1, '16:00')),
        ],
      );

      bloc.add(StageNotesChange(
        slot: medicSlot(loaded, 'e1', 2),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();

      // The event form removed row 0: the survivor moves from 2 to 1.
      eventStream.add(
          [event('e1', start: day1, roleRequirements: const {'medic': 2})]);
      assignmentStream.add([
        assignment('a2', 'e1', 'm1',
            slotIndex: 1,
            customStartAt: at(day1, '10:00'),
            customEndAt: at(day1, '16:00')),
      ]);
      await pumpEventQueue();
      bloc.add(const ApplyCommittedRowRemoval(
          eventId: 'e1', roleType: 'medic', deletedIndices: {0}));
      await pumpEventQueue();

      final moved = (await cachedChanges()).single as Map<String, dynamic>;
      expect(moved['slotKey'], 'e1_medic_1');
      expect(moved['desiredCustomStartAt'], at(day1, '10:00'));
      expect(moved['desiredCustomEndAt'], at(day1, '16:00'));
      expect(moved['baselineCustomStartAt'], at(day1, '10:00'));
      expect(moved['baselineCustomEndAt'], at(day1, '16:00'));
    });
  });

  group('the same-day check judges the other booking by its own days', () {
    // e1 spans day1 and day2; e2 is on day2 only; m1 is booked in e1.
    List<Event> twoEvents() => [
          event('e1', start: day1, end: day2),
          event('e2', start: day2),
        ];

    test('without hours the booking holds m1 on day 2: not offered in e2',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: twoEvents(),
        assignments: [assignment('a1', 'e1', 'm1')],
      );

      final e2 = medicSlot(loaded, 'e2');
      expect(e2.availableMembers.map((m) => m.id), isNot(contains('m1')));
      expect(e2.sameDayAssignedMembers.map((m) => m.id), contains('m1'));
    });

    test('hours on day 1 only free m1 on day 2: offered in e2', () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: twoEvents(),
        assignments: [
          assignment('a1', 'e1', 'm1',
              customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
        ],
      );

      final e2 = medicSlot(loaded, 'e2');
      expect(e2.availableMembers.map((m) => m.id), contains('m1'));
      expect(
          e2.sameDayAssignedMembers.map((m) => m.id), isNot(contains('m1')));
    });

    test('a staged notes edit on that booking keeps m1 free on day 2',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: twoEvents(),
        assignments: [
          assignment('a1', 'e1', 'm1',
              customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
        ],
      );

      bloc.add(StageNotesChange(
        slot: medicSlot(loaded, 'e1'),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();

      // The staged copy of the booking carries the hours, so the staged
      // overlay does not put m1 back on day 2.
      final e2 = medicSlot(bloc.state as AssignmentSlotsLoaded, 'e2');
      expect(e2.availableMembers.map((m) => m.id), contains('m1'));
      expect(
          e2.sameDayAssignedMembers.map((m) => m.id), isNot(contains('m1')));
    });

    test('a staged fill of m2 on day 1 hours-less books m2 for day 2 too',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: twoEvents(),
        assignments: const [],
      );

      bloc.add(StageMemberChange(
          slot: medicSlot(loaded, 'e1'), member: member('m2')));
      await pumpEventQueue();

      // A new assignment has no hours: it holds m2 for the whole event.
      final e2 = medicSlot(bloc.state as AssignmentSlotsLoaded, 'e2');
      expect(e2.sameDayAssignedMembers.map((m) => m.id), contains('m2'));
    });
  });

  group('classifyStagedConflicts: hours changed underneath a staged edit', () {
    Future<(AssignmentBloc, AssignmentSlotsLoaded)> stagedNotesOnHours() async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1', start: day1, end: day2)],
        assignments: [
          assignment('a1', 'e1', 'm1',
              customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
        ],
      );
      bloc.add(StageNotesChange(
        slot: medicSlot(loaded, 'e1'),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();
      return (bloc, bloc.state as AssignmentSlotsLoaded);
    }

    test('unchanged hours are no conflict', () async {
      final (bloc, _) = await stagedNotesOnHours();
      assignmentStream.add([
        assignment('a1', 'e1', 'm1',
            customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
      ]);
      await pumpEventQueue();

      expect(
          bloc.classifyStagedConflicts(
              (bloc.state as AssignmentSlotsLoaded).slots),
          isEmpty);
    });

    test('hours moved by someone else are a notesChanged conflict', () async {
      final (bloc, _) = await stagedNotesOnHours();
      assignmentStream.add([
        assignment('a1', 'e1', 'm1',
            customStartAt: at(day1, '11:00'), customEndAt: at(day1, '16:00')),
      ]);
      await pumpEventQueue();

      final conflicts = bloc.classifyStagedConflicts(
          (bloc.state as AssignmentSlotsLoaded).slots);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.type, AssignmentConflictType.notesChanged);
      expect(conflicts.single.slotKey, 'e1_medic_0');
      expect(conflicts.single.description, contains('השעות'));
    });

    test('hours cleared by someone else are a notesChanged conflict',
        () async {
      final (bloc, _) = await stagedNotesOnHours();
      assignmentStream.add([assignment('a1', 'e1', 'm1')]);
      await pumpEventQueue();

      final conflicts = bloc.classifyStagedConflicts(
          (bloc.state as AssignmentSlotsLoaded).slots);
      expect(conflicts.single.type, AssignmentConflictType.notesChanged);
    });

    test('hours added by someone else to an hours-less staged edit conflict',
        () async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      final loaded = await load(
        bloc,
        events: [event('e1', start: day1, end: day2)],
        assignments: [assignment('a1', 'e1', 'm1')],
      );
      bloc.add(StageNotesChange(
        slot: medicSlot(loaded, 'e1'),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();

      assignmentStream.add([
        assignment('a1', 'e1', 'm1',
            customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
      ]);
      await pumpEventQueue();

      final conflicts = bloc.classifyStagedConflicts(
          (bloc.state as AssignmentSlotsLoaded).slots);
      expect(conflicts.single.type, AssignmentConflictType.notesChanged);
    });

    test('hours and notes both moved: one conflict naming both', () async {
      final (bloc, _) = await stagedNotesOnHours();
      assignmentStream.add([
        assignment('a1', 'e1', 'm1',
            notes: 'הערה אחרת',
            customStartAt: at(day1, '11:00'),
            customEndAt: at(day1, '16:00')),
      ]);
      await pumpEventQueue();

      final conflicts = bloc.classifyStagedConflicts(
          (bloc.state as AssignmentSlotsLoaded).slots);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.type, AssignmentConflictType.notesChanged);
      expect(conflicts.single.description, contains('ההערות'));
      expect(conflicts.single.description, contains('השעות'));
    });

    test('only notes moved: the original wording is unchanged', () async {
      final (bloc, _) = await stagedNotesOnHours();
      assignmentStream.add([
        assignment('a1', 'e1', 'm1',
            notes: 'הערה אחרת',
            customStartAt: at(day1, '10:00'),
            customEndAt: at(day1, '16:00')),
      ]);
      await pumpEventQueue();

      final conflicts = bloc.classifyStagedConflicts(
          (bloc.state as AssignmentSlotsLoaded).slots);
      expect(conflicts.single.description,
          'ההערות/הלייבל של השיבוץ שונו בינתיים ב-DB.');
    });
  });

  // The conflict dialog's default for type F is "דרוס DB" (overrideDb): the
  // staged change wins. Hours the staged change never touched are not part of
  // it, so they must not revert someone else's newer hours.
  group('Save over hours someone else changed meanwhile', () {
    const slotKey = 'e1_medic_0';

    Future<AssignmentBloc> loadWithHours() async {
      final bloc = buildBloc();
      addTearDown(() async => bloc.close());
      await load(
        bloc,
        events: [event('e1', start: day1, end: day2)],
        assignments: [
          assignment('a1', 'e1', 'm1',
              customStartAt: at(day1, '10:00'), customEndAt: at(day1, '16:00')),
        ],
      );
      return bloc;
    }

    AssignmentSlot liveSlot(AssignmentBloc bloc) =>
        medicSlot(bloc.state as AssignmentSlotsLoaded, 'e1');

    test('a notes-only edit sends the hours the database holds now', () async {
      final bloc = await loadWithHours();
      bloc.add(StageNotesChange(
        slot: liveSlot(bloc),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();

      // Another admin moves m1's hours after the edit was staged.
      assignmentStream.add([
        assignment('a1', 'e1', 'm1',
            customStartAt: at(day1, '11:00'), customEndAt: at(day1, '18:00')),
      ]);
      await pumpEventQueue();
      expect(
          bloc
              .classifyStagedConflicts(
                  (bloc.state as AssignmentSlotsLoaded).slots)
              .single
              .type,
          AssignmentConflictType.notesChanged);

      final saved = await save(bloc,
          resolutions: {slotKey: ConflictResolution.overrideDb});

      final update = saved.updates.single;
      expect(update.id, 'a1');
      expect(update.notes, 'הערה');
      expect(update.customStartAt, at(day1, '11:00'));
      expect(update.customEndAt, at(day1, '18:00'));
    });

    test('a notes-only edit keeps hours someone else cleared cleared',
        () async {
      final bloc = await loadWithHours();
      bloc.add(StageNotesChange(
        slot: liveSlot(bloc),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();

      assignmentStream.add([assignment('a1', 'e1', 'm1')]);
      await pumpEventQueue();

      final saved = await save(bloc,
          resolutions: {slotKey: ConflictResolution.overrideDb});

      final wire = AssignmentModel.fromEntity(saved.updates.single).toJson();
      expect(wire.containsKey('customStartAt'), isTrue);
      expect(wire['customStartAt'], isNull);
      expect(wire['customEndAt'], isNull);
    });

    test('an hours edit still sends the hours the admin chose', () async {
      final bloc = await loadWithHours();
      bloc.add(StageNotesChange(
        slot: liveSlot(bloc),
        notes: '',
        customStartAt: at(day1, '12:00'),
        customEndAt: at(day1, '20:00'),
      ));
      await pumpEventQueue();

      assignmentStream.add([
        assignment('a1', 'e1', 'm1',
            customStartAt: at(day1, '11:00'), customEndAt: at(day1, '18:00')),
      ]);
      await pumpEventQueue();

      final saved = await save(bloc,
          resolutions: {slotKey: ConflictResolution.overrideDb});

      final update = saved.updates.single;
      expect(update.customStartAt, at(day1, '12:00'));
      expect(update.customEndAt, at(day1, '20:00'));
    });

    test(
        'a notes-only edit over a slot someone else gave to another member '
        'never hands that member\'s hours to the staged one', () async {
      final bloc = await loadWithHours();
      bloc.add(StageNotesChange(
        slot: liveSlot(bloc),
        notes: 'הערה',
        semanticLabelId: null,
        alternativePhoneNumber: null,
      ));
      await pumpEventQueue();

      // Another admin replaced m1 by m2, with m2's own hours.
      assignmentStream.add([
        assignment('a1', 'e1', 'm2',
            customStartAt: at(day1, '13:00'), customEndAt: at(day1, '15:00')),
      ]);
      await pumpEventQueue();

      final saved = await save(bloc,
          resolutions: {slotKey: ConflictResolution.overrideDb});

      final update = saved.updates.single;
      expect(update.teamMemberId, 'm1');
      expect(update.customStartAt, at(day1, '10:00'));
      expect(update.customEndAt, at(day1, '16:00'));
    });
  });
}
