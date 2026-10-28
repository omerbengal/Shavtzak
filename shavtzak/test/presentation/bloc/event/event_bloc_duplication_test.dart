import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/event/duplication_availability.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/event/event_event.dart';
import 'package:shavtzak/presentation/bloc/event/event_state.dart';

// The generated mocks of the subscription test already hold MockEventRepository
// and MockAssignmentRepository; reuse them rather than generating a second copy.
import '../event_bloc_subscription_test.mocks.dart';

/// The duplication flow flags members with the same rule as assigning, tells
/// the dialog which ones it must lock, and never sends a locked member to the
/// backend.
void main() {
  late MockEventRepository eventRepository;
  late MockAssignmentRepository assignmentRepository;
  late StreamController<List<Event>> eventsController;
  late StreamController<List<Assignment>> assignmentsController;
  late EventBloc bloc;

  final now = DateTime(2026, 10, 1);
  final originalDay = DateTime(2026, 11, 3);
  final newDay = DateTime(2026, 11, 10);
  final original = _event('original', originalDay, now);

  DuplicateEvent duplicateRequest() => DuplicateEvent(
        eventId: original.id,
        newName: 'אירוע חדש',
        newLocation: '',
        newComments: '',
        newStartDate: newDay,
        newEndDate: newDay,
        newStartTime: '19:00',
        newEndTime: '22:00',
        newAssemblyTime: '18:30',
        newRequiresArmed: false,
        newRoleRequirements: const {'medic': 3},
        duplicateAssignments: true,
      );

  setUp(() {
    eventRepository = MockEventRepository();
    assignmentRepository = MockAssignmentRepository();
    eventsController = StreamController<List<Event>>.broadcast();
    assignmentsController = StreamController<List<Assignment>>.broadcast();
    when(eventRepository.watchEvents())
        .thenAnswer((_) => eventsController.stream);
    when(assignmentRepository.watchAssignments())
        .thenAnswer((_) => assignmentsController.stream);
    when(eventRepository.getEventById(original.id))
        .thenAnswer((_) async => original);
    when(eventRepository.duplicateEvent(any, any, any))
        .thenAnswer((_) async {});
    bloc = EventBloc(eventRepository, assignmentRepository);
  });

  tearDown(() async {
    await bloc.close();
    await eventsController.close();
    await assignmentsController.close();
  });

  /// The next state of a given type after [bloc.add(request)].
  Future<T> nextState<T extends EventState>(EventEvent request) async {
    final future = bloc.stream.firstWhere((state) => state is T);
    bloc.add(request);
    return (await future) as T;
  }

  group('DuplicateEvent', () {
    test('a member whose document is gone is listed, locked, marked for '
        'removal', () async {
      final gone = _assignment('a-gone', null, now);
      final fine = _assignment('a-fine', _member('m-fine', now), now);
      when(assignmentRepository.getAssignmentsByEvent(original.id))
          .thenAnswer((_) async => [gone, fine]);

      final state = await nextState<DuplicationRequiresConflictResolution>(
          duplicateRequest());

      final goneInfo = state.assignmentInfos
          .singleWhere((info) => info.assignment.id == 'a-gone');
      expect(goneInfo.hasAvailabilityConflict, isTrue);
      expect(goneInfo.canKeep, isFalse);
      expect(goneInfo.availabilityReason, 'חבר/ת הצוות לא נמצא/ה');
      expect(state.suggestedExclusions, {'a-gone'});

      final fineInfo = state.assignmentInfos
          .singleWhere((info) => info.assignment.id == 'a-fine');
      expect(fineInfo.hasAvailabilityConflict, isFalse);
      expect(fineInfo.canKeep, isTrue);
      expect(fineInfo.availabilityReason, isNull);

      // Nothing is created until the admin confirms.
      verifyNever(eventRepository.duplicateEvent(any, any, any));
    });

    test('a pending constraint is listed with its label, keepable', () async {
      final member = _member('m-pending', now,
          constraints: [_unavailability(newDay, ConstraintStatus.pending)]);
      when(assignmentRepository.getAssignmentsByEvent(original.id))
          .thenAnswer((_) async => [_assignment('a1', member, now)]);

      final state = await nextState<DuplicationRequiresConflictResolution>(
          duplicateRequest());

      final info = state.assignmentInfos.single;
      expect(info.hasAvailabilityConflict, isTrue);
      expect(info.canKeep, isTrue);
      expect(info.availabilityReason, 'אילוץ ממתין לאישור: 10.11 (כל היום)');
      expect(state.suggestedExclusions, {'a1'});
    });

    test('several blocking constraints give a multi-line reason', () async {
      final member = _member('m-two', now, constraints: [
        _unavailability(newDay, ConstraintStatus.approved, id: 'c1'),
        _unavailability(newDay, ConstraintStatus.pending,
            id: 'c2', startTime: '19:00', endTime: '21:00'),
      ]);
      when(assignmentRepository.getAssignmentsByEvent(original.id))
          .thenAnswer((_) async => [_assignment('a1', member, now)]);

      final state = await nextState<DuplicationRequiresConflictResolution>(
          duplicateRequest());

      expect(
        state.assignmentInfos.single.availabilityReason,
        'אילוץ מאושר: 10.11 (כל היום)\n'
        'אילוץ ממתין לאישור: 10.11 19:00–21:00',
      );
    });

    test('a morning constraint does not hold back an evening duplicate (E7)',
        () async {
      final member = _member('m-morning', now, constraints: [
        _unavailability(newDay, ConstraintStatus.approved,
            startTime: '08:00', endTime: '10:00'),
      ]);
      when(assignmentRepository.getAssignmentsByEvent(original.id))
          .thenAnswer((_) async => [_assignment('a1', member, now)]);

      final state =
          await nextState<EventOperationSuccess>(duplicateRequest());

      expect(state.message, contains('עם כל השיבוצים'));
      final copied = verify(eventRepository.duplicateEvent(
        any,
        any,
        captureAny,
      )).captured.single as List<Assignment>;
      expect(copied.map((a) => a.id), ['a1']);
    });
  });

  group('ConfirmDuplicationWithExclusions', () {
    DuplicationRequiresConflictResolution? resolution;

    Future<void> openResolution(List<Assignment> assignments) async {
      when(assignmentRepository.getAssignmentsByEvent(original.id))
          .thenAnswer((_) async => assignments);
      resolution = await nextState<DuplicationRequiresConflictResolution>(
          duplicateRequest());
    }

    ConfirmDuplicationWithExclusions confirm(Set<String> excluded,
        List<Assignment> assignments) {
      return ConfirmDuplicationWithExclusions(
        originalEvent: original,
        proposedEvent: resolution!.proposedEvent,
        assignmentIdsToExclude: excluded,
        originalAssignmentIds: assignments.map((a) => a.id).toList(),
      );
    }

    test('a flagged member the admin keeps is copied', () async {
      final kept = _assignment(
          'a-kept',
          _member('m-kept', now, constraints: [
            _unavailability(newDay, ConstraintStatus.pending),
          ]),
          now);
      final dropped = _assignment(
          'a-dropped',
          _member('m-dropped', now, constraints: [
            _unavailability(newDay, ConstraintStatus.approved),
          ]),
          now);
      final assignments = [kept, dropped];
      await openResolution(assignments);

      await nextState<EventOperationSuccess>(
          confirm({'a-dropped'}, assignments));

      final copied = verify(eventRepository.duplicateEvent(
        any,
        any,
        captureAny,
      )).captured.single as List<Assignment>;
      expect(copied.map((a) => a.id), ['a-kept']);
    });

    test('a member who cannot be kept is dropped even when not excluded',
        () async {
      final gone = _assignment('a-gone', null, now);
      final inactive =
          _assignment('a-inactive', _member('m-off', now, isActive: false), now);
      final noRole = _assignment(
          'a-norole', _member('m-norole', now, roleCapabilities: const {}), now);
      final fine = _assignment('a-fine', _member('m-fine', now), now);
      final assignments = [gone, inactive, noRole, fine];
      await openResolution(assignments);

      // A stale or hand-made confirmation that excludes nobody.
      final state =
          await nextState<EventOperationSuccess>(confirm({}, assignments));

      final copied = verify(eventRepository.duplicateEvent(
        any,
        any,
        captureAny,
      )).captured.single as List<Assignment>;
      expect(copied.map((a) => a.id), ['a-fine']);
      expect(state.message, contains('(3 הוסרו)'));
    });
  });

  // Custom hours: the source is on 1.12 and the copy on 8.12, a shift of seven
  // days. The copy's own stretch is 8.12 18:30-22:00.
  group('custom hours', () {
    final source = _event('hours-source', DateTime(2026, 12, 1), now);
    final copyDay = DateTime(2026, 12, 8);
    const sourceStart = '2026-12-01T14:00';
    const sourceEnd = '2026-12-01T20:00';
    const movedStart = '2026-12-08T14:00';
    const movedEnd = '2026-12-08T20:00';

    setUp(() {
      when(eventRepository.getEventById(source.id))
          .thenAnswer((_) async => source);
      when(eventRepository.duplicateEvent(
        any,
        any,
        any,
        hoursByAssignmentId: anyNamed('hoursByAssignmentId'),
      )).thenAnswer((_) async {});
    });

    DuplicateEvent request({bool customHours = true}) => DuplicateEvent(
          eventId: source.id,
          newName: 'אירוע חדש',
          newLocation: '',
          newComments: '',
          newStartDate: copyDay,
          newEndDate: copyDay,
          newStartTime: '19:00',
          newEndTime: '22:00',
          newAssemblyTime: '18:30',
          newRequiresArmed: false,
          newRoleRequirements: const {'medic': 3},
          duplicateAssignments: true,
          duplicateCustomHours: customHours,
        );

    void givenAssignments(List<Assignment> assignments) {
      when(assignmentRepository.getAssignmentsByEvent(source.id))
          .thenAnswer((_) async => assignments);
    }

    /// The hours handed to the repository by the one duplicateEvent call.
    Map<String, ({String? start, String? end})> copiedHours() {
      return verify(eventRepository.duplicateEvent(
        any,
        any,
        any,
        hoursByAssignmentId: captureAnyNamed('hoursByAssignmentId'),
      )).captured.single as Map<String, ({String? start, String? end})>;
    }

    ConfirmDuplicationWithExclusions confirm(
      DuplicationRequiresConflictResolution state, {
      Set<String> excluded = const {},
      Set<String> hoursDropped = const {},
      bool customHours = true,
    }) {
      return ConfirmDuplicationWithExclusions(
        originalEvent: source,
        proposedEvent: state.proposedEvent,
        assignmentIdsToExclude: excluded,
        originalAssignmentIds:
            state.assignmentInfos.map((info) => info.assignment.id).toList(),
        duplicateCustomHours: customHours,
        customHoursDropped: hoursDropped,
      );
    }

    group('DuplicateEvent', () {
      test('hours to confirm open the dialog even with no conflict, showing '
          'the hours moved by the shift', () async {
        givenAssignments([
          _assignment('a1', _member('m1', now), now,
              start: sourceStart, end: sourceEnd),
          _assignment('a2', _member('m2', now), now),
        ]);

        final state =
            await nextState<DuplicationRequiresConflictResolution>(request());

        final withHours =
            state.assignmentInfos.singleWhere((i) => i.assignment.id == 'a1');
        expect(withHours.movedCustomStartAt, movedStart);
        expect(withHours.movedCustomEndAt, movedEnd);
        expect(withHours.hasAvailabilityConflict, isFalse);
        expect(withHours.availabilityWithEventHours,
            DuplicationAvailability.clear);
        final without =
            state.assignmentInfos.singleWhere((i) => i.assignment.id == 'a2');
        expect(without.movedCustomStartAt, isNull);
        expect(without.movedCustomEndAt, isNull);
        expect(without.availabilityWithEventHours, isNull);
        expect(state.copiesCustomHours, isTrue);
        verifyNever(eventRepository.duplicateEvent(
          any,
          any,
          any,
          hoursByAssignmentId: anyNamed('hoursByAssignmentId'),
        ));
      });

      test('with the sub-switch off nothing opens and the copies carry no '
          'hours', () async {
        givenAssignments([
          _assignment('a1', _member('m1', now), now,
              start: sourceStart, end: sourceEnd),
        ]);

        final state = await nextState<EventOperationSuccess>(
            request(customHours: false));

        expect(state.message, contains('עם כל השיבוצים'));
        expect(copiedHours(), isEmpty);
      });

      test('a source with no hours behaves as it did before, switch on or '
          'off', () async {
        givenAssignments([_assignment('a1', _member('m1', now), now)]);

        final state = await nextState<EventOperationSuccess>(request());

        expect(state.message, contains('עם כל השיבוצים'));
        expect(copiedHours(), isEmpty);
      });

      test('hours that cannot be read are no reason to open the dialog',
          () async {
        givenAssignments([
          _assignment('a1', _member('m1', now), now,
              start: 'soon', end: sourceEnd),
        ]);

        await nextState<EventOperationSuccess>(request());

        expect(copiedHours(), isEmpty);
      });

      test('the dialog still opens for a conflict alone, and then lists no '
          'hours', () async {
        givenAssignments([
          _assignment(
              'a1',
              _member('m1', now, constraints: [
                _unavailability(copyDay, ConstraintStatus.approved),
              ]),
              now),
        ]);

        final state =
            await nextState<DuplicationRequiresConflictResolution>(request());

        expect(state.copiesCustomHours, isFalse);
        expect(state.suggestedExclusions, {'a1'});
      });

      test('availability is judged with the moved hours, and again with the '
          "event's own", () async {
        // 9-12 moves to 8.12 09:00-12:00, where the member is busy 08:00-10:00;
        // the copy's own stretch (18:30-22:00) is free of it.
        final busyInTheMorning = _member('m-morning', now, constraints: [
          _unavailability(copyDay, ConstraintStatus.approved,
              startTime: '08:00', endTime: '10:00'),
        ]);
        // 14-20 moves to 8.12 14:00-20:00, free of a 21:00-22:00 constraint
        // that does block the copy's own stretch.
        final busyInTheEvening = _member('m-evening', now, constraints: [
          _unavailability(copyDay, ConstraintStatus.pending,
              id: 'c2', startTime: '21:00', endTime: '22:00'),
        ]);
        givenAssignments([
          _assignment('a-morning', busyInTheMorning, now,
              start: '2026-12-01T09:00', end: '2026-12-01T12:00'),
          _assignment('a-evening', busyInTheEvening, now,
              start: sourceStart, end: sourceEnd),
        ]);

        final state =
            await nextState<DuplicationRequiresConflictResolution>(request());

        final morning = state.assignmentInfos
            .singleWhere((i) => i.assignment.id == 'a-morning');
        expect(morning.hasAvailabilityConflict, isTrue);
        expect(morning.availabilityReason, 'אילוץ מאושר: 8.12 08:00–10:00');
        expect(
            morning.availabilityWithEventHours, DuplicationAvailability.clear);

        final evening = state.assignmentInfos
            .singleWhere((i) => i.assignment.id == 'a-evening');
        expect(evening.hasAvailabilityConflict, isFalse);
        expect(evening.availabilityReason, isNull);
        expect(evening.availabilityWithEventHours!.flagged, isTrue);
        expect(evening.availabilityWithEventHours!.canKeep, isTrue);
        expect(evening.availabilityWithEventHours!.reasons,
            ['אילוץ ממתין לאישור: 8.12 21:00–22:00']);
        expect(state.suggestedExclusions, {'a-morning'});
      });

      test('every copy of one member shows the same hours, also the one whose '
          'row had none', () async {
        final member = _member('m1', now);
        givenAssignments([
          _assignment('a1', member, now),
          _assignment('a2', member, now, start: sourceStart, end: sourceEnd),
        ]);

        final state =
            await nextState<DuplicationRequiresConflictResolution>(request());

        expect(state.assignmentInfos.map((i) => i.movedCustomStartAt),
            [movedStart, movedStart]);
        expect(state.assignmentInfos.map((i) => i.movedCustomEndAt),
            [movedEnd, movedEnd]);
      });

      test('a member flagged allowMultipleAssignments keeps the hours of each '
          'row', () async {
        final pool = _member('pool', now, allowMultipleAssignments: true);
        givenAssignments([
          _assignment('a1', pool, now, start: sourceStart, end: sourceEnd),
          _assignment('a2', pool, now,
              start: '2026-12-01T09:00', end: '2026-12-01T12:00'),
          _assignment('a3', pool, now),
        ]);

        final state =
            await nextState<DuplicationRequiresConflictResolution>(request());

        expect(state.assignmentInfos.map((i) => i.movedCustomStartAt),
            [movedStart, '2026-12-08T09:00', null]);
        expect(state.assignmentInfos.map((i) => i.movedCustomEndAt),
            [movedEnd, '2026-12-08T12:00', null]);
      });

      test('moving to an earlier date moves the hours back', () async {
        givenAssignments([
          _assignment('a1', _member('m1', now), now,
              start: sourceStart, end: sourceEnd),
        ]);

        final state =
            await nextState<DuplicationRequiresConflictResolution>(
                DuplicateEvent(
          eventId: source.id,
          newName: 'אירוע חדש',
          newLocation: '',
          newComments: '',
          newStartDate: DateTime(2026, 11, 24),
          newEndDate: DateTime(2026, 11, 24),
          newStartTime: '19:00',
          newEndTime: '22:00',
          newAssemblyTime: '18:30',
          newRequiresArmed: false,
          newRoleRequirements: const {'medic': 3},
          duplicateAssignments: true,
          duplicateCustomHours: true,
        ));

        expect(state.assignmentInfos.single.movedCustomStartAt,
            '2026-11-24T14:00');
        expect(
            state.assignmentInfos.single.movedCustomEndAt, '2026-11-24T20:00');
      });
    });

    group('ConfirmDuplicationWithExclusions', () {
      late DuplicationRequiresConflictResolution state;

      Future<void> open(List<Assignment> assignments) async {
        givenAssignments(assignments);
        state =
            await nextState<DuplicationRequiresConflictResolution>(request());
      }

      test('with nothing dropped the copies carry the moved hours', () async {
        final assignments = [
          _assignment('a1', _member('m1', now), now,
              start: sourceStart, end: sourceEnd),
          _assignment('a2', _member('m2', now), now),
        ];
        await open(assignments);

        await nextState<EventOperationSuccess>(confirm(state));

        expect(copiedHours(), {
          'a1': (start: movedStart, end: movedEnd),
        });
      });

      test('a dropped id leaves its copy with no hours', () async {
        final assignments = [
          _assignment('a1', _member('m1', now), now,
              start: sourceStart, end: sourceEnd),
          _assignment('a2', _member('m2', now), now,
              start: '2026-12-01T09:00', end: '2026-12-01T12:00'),
        ];
        await open(assignments);

        await nextState<EventOperationSuccess>(
            confirm(state, hoursDropped: {'a1'}));

        final call = verify(eventRepository.duplicateEvent(
          any,
          any,
          captureAny,
          hoursByAssignmentId: captureAnyNamed('hoursByAssignmentId'),
        )).captured;
        // Dropping the hours does not drop the member.
        expect((call[0] as List<Assignment>).map((a) => a.id), ['a1', 'a2']);
        expect(call[1], {
          'a2': (start: '2026-12-08T09:00', end: '2026-12-08T12:00'),
        });
      });

      test('one dropped id of a member with two copies drops the hours of '
          'both', () async {
        final member = _member('m1', now);
        final assignments = [
          _assignment('a1', member, now, start: sourceStart, end: sourceEnd),
          _assignment('a2', member, now, start: sourceStart, end: sourceEnd),
        ];
        await open(assignments);

        await nextState<EventOperationSuccess>(
            confirm(state, hoursDropped: {'a2'}));

        expect(copiedHours(), isEmpty);
      });

      test('a removed assignment takes its hours with it', () async {
        final assignments = [
          _assignment('a1', _member('m1', now), now,
              start: sourceStart, end: sourceEnd),
          _assignment('a2', _member('m2', now), now,
              start: sourceStart, end: sourceEnd),
        ];
        await open(assignments);

        await nextState<EventOperationSuccess>(
            confirm(state, excluded: {'a1'}));

        expect(copiedHours().keys, ['a2']);
      });

      test('a request that did not ask for hours copies none, whatever the '
          'source holds', () async {
        final assignments = [
          _assignment(
              'a1',
              _member('m1', now, constraints: [
                _unavailability(copyDay, ConstraintStatus.pending),
              ]),
              now,
              start: sourceStart,
              end: sourceEnd),
        ];
        await open(assignments);

        await nextState<EventOperationSuccess>(
            confirm(state, customHours: false));

        expect(copiedHours(), isEmpty);
      });

      test('a member who cannot be kept is dropped, with their hours',
          () async {
        final assignments = [
          _assignment('a-off', _member('m-off', now, isActive: false), now,
              start: sourceStart, end: sourceEnd),
          _assignment('a-fine', _member('m-fine', now), now,
              start: sourceStart, end: sourceEnd),
        ];
        await open(assignments);

        await nextState<EventOperationSuccess>(confirm(state));

        expect(copiedHours().keys, ['a-fine']);
      });

      test('a member flagged allowMultipleAssignments loses only the dropped '
          "copy's hours", () async {
        final pool = _member('pool', now, allowMultipleAssignments: true);
        final assignments = [
          _assignment('a1', pool, now, start: sourceStart, end: sourceEnd),
          _assignment('a2', pool, now,
              start: '2026-12-01T09:00', end: '2026-12-01T12:00'),
        ];
        await open(assignments);

        await nextState<EventOperationSuccess>(
            confirm(state, hoursDropped: {'a1'}));

        expect(copiedHours(), {
          'a2': (start: '2026-12-08T09:00', end: '2026-12-08T12:00'),
        });
      });
    });
  });
}

Assignment _assignment(
  String id,
  TeamMember? member,
  DateTime now, {
  String? start,
  String? end,
}) {
  return Assignment(
    id: id,
    eventId: 'original',
    teamMemberId: member?.id ?? 'deleted-member',
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    customStartAt: start,
    customEndAt: end,
    createdAt: now,
    updatedAt: now,
    teamMember: member,
  );
}

TeamMember _member(
  String id,
  DateTime now, {
  bool isActive = true,
  Map<String, bool> roleCapabilities = const {'medic': true},
  List<DateConstraint> constraints = const [],
  bool allowMultipleAssignments = false,
}) {
  return TeamMember(
    id: id,
    name: 'חבר $id',
    isActive: isActive,
    isPermanent: true,
    constraints: constraints,
    roleCapabilities: roleCapabilities,
    allowMultipleAssignments: allowMultipleAssignments,
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'key-$id',
  );
}

DateConstraint _unavailability(
  DateTime day,
  ConstraintStatus status, {
  String id = 'c1',
  String? startTime,
  String? endTime,
}) {
  return DateConstraint(
    id: id,
    startDate: day,
    endDate: day,
    status: status,
    constraintType: ConstraintType.unavailability,
    startTime: startTime,
    endTime: endTime,
  );
}

Event _event(String id, DateTime day, DateTime now) {
  return Event(
    id: id,
    name: 'אירוע',
    startDate: day,
    endDate: day,
    startTime: '19:00',
    endTime: '22:00',
    assemblyTime: '18:30',
    requiresArmed: false,
    roleRequirements: const {'medic': 3},
    createdAt: now,
    updatedAt: now,
  );
}
