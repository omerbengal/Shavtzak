import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
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
}

Assignment _assignment(String id, TeamMember? member, DateTime now) {
  return Assignment(
    id: id,
    eventId: 'original',
    teamMemberId: member?.id ?? 'deleted-member',
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
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
}) {
  return TeamMember(
    id: id,
    name: 'חבר $id',
    isActive: isActive,
    isPermanent: true,
    constraints: constraints,
    roleCapabilities: roleCapabilities,
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
