// UpdateEvent carries the hours the admin chose for members with custom hours
// when an event's dates or times changed; the bloc hands them to the
// repository next to the event so they are saved in the same call.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/domain/entities/custom_hours_resolution.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/event/event_event.dart';
import 'package:shavtzak/presentation/bloc/event/event_state.dart';

// The generated mocks of the subscription test already hold MockEventRepository
// and MockAssignmentRepository; reuse them rather than generating a second copy.
import '../event_bloc_subscription_test.mocks.dart';

void main() {
  late MockEventRepository eventRepository;
  late MockAssignmentRepository assignmentRepository;

  final now = DateTime(2026, 10, 1);
  final original = _event('e1', DateTime(2026, 10, 27), now);
  final moved = original.copyWith(
    startDate: DateTime(2026, 10, 29),
    endDate: DateTime(2026, 10, 29),
  );

  const resolutions = [
    CustomHoursResolution(
      assignmentId: 'a1',
      customStartAt: '2026-10-29T14:00',
      customEndAt: '2026-10-29T23:00',
    ),
    CustomHoursResolution(
      assignmentId: 'a2',
      customStartAt: null,
      customEndAt: null,
    ),
  ];

  setUp(() {
    eventRepository = MockEventRepository();
    assignmentRepository = MockAssignmentRepository();
  });

  test('UpdateEvent with resolutions passes them to the repository', () async {
    when(eventRepository.updateEvent(
      any,
      knownOriginal: anyNamed('knownOriginal'),
      customHoursResolutions: anyNamed('customHoursResolutions'),
    )).thenAnswer((_) async => moved);
    final bloc = EventBloc(eventRepository, assignmentRepository);
    addTearDown(bloc.close);

    final completion = Completer<CrudActionResult>();
    bloc.add(UpdateEvent(
      moved,
      originalEvent: original,
      customHoursResolutions: resolutions,
      completion: completion,
    ));
    final result = await completion.future;

    expect(result.isSuccess, isTrue);
    verify(eventRepository.updateEvent(
      moved,
      knownOriginal: original,
      customHoursResolutions: resolutions,
    )).called(1);
  });

  test('UpdateEvent without resolutions passes an empty list', () async {
    when(eventRepository.updateEvent(
      any,
      knownOriginal: anyNamed('knownOriginal'),
      customHoursResolutions: anyNamed('customHoursResolutions'),
    )).thenAnswer((_) async => moved);
    final bloc = EventBloc(eventRepository, assignmentRepository);
    addTearDown(bloc.close);

    final completion = Completer<CrudActionResult>();
    bloc.add(
        UpdateEvent(moved, originalEvent: original, completion: completion));
    await completion.future;

    verify(eventRepository.updateEvent(
      moved,
      knownOriginal: original,
      customHoursResolutions: const <CustomHoursResolution>[],
    )).called(1);
  });

  test('two UpdateEvents differing only in their resolutions are not equal',
      () {
    expect(
      UpdateEvent(moved, customHoursResolutions: resolutions),
      isNot(UpdateEvent(moved)),
    );
    expect(
      UpdateEvent(moved, customHoursResolutions: resolutions),
      UpdateEvent(moved, customHoursResolutions: List.of(resolutions)),
    );
  });

  group('when the backend refuses', () {
    // The backend's 409 reaches the client wrapped twice (the database layer
    // wraps the mutation failure, then the update). The admin must read the
    // Hebrew sentence, not the English plumbing around it.
    const uncovered =
        'לחלק מהצוות נוספו שעות מותאמות בינתיים — יש לפתוח את האירוע מחדש';

    test('the Hebrew reason reaches the state and the completer', () async {
      when(eventRepository.updateEvent(
        any,
        knownOriginal: anyNamed('knownOriginal'),
        customHoursResolutions: anyNamed('customHoursResolutions'),
      )).thenThrow(DatabaseException(
        'Failed to update event: DatabaseException: Failed backend mutation '
        'event.update: $uncovered',
      ));
      final bloc = EventBloc(eventRepository, assignmentRepository);
      addTearDown(bloc.close);

      final errors = <EventError>[];
      final subscription = bloc.stream.listen((state) {
        if (state is EventError) errors.add(state);
      });
      addTearDown(subscription.cancel);

      final completion = Completer<CrudActionResult>();
      bloc.add(UpdateEvent(moved,
          originalEvent: original,
          customHoursResolutions: resolutions,
          completion: completion));
      final result = await completion.future;
      await Future<void>.delayed(Duration.zero);

      expect(result.isFailure, isTrue);
      expect(result.message, uncovered);
      expect(errors.single.message, uncovered);
    });

    test('an English-only failure keeps its context prefix', () async {
      when(eventRepository.updateEvent(
        any,
        knownOriginal: anyNamed('knownOriginal'),
        customHoursResolutions: anyNamed('customHoursResolutions'),
      )).thenThrow(DatabaseException('Failed to update event: boom'));
      final bloc = EventBloc(eventRepository, assignmentRepository);
      addTearDown(bloc.close);

      final completion = Completer<CrudActionResult>();
      bloc.add(
          UpdateEvent(moved, originalEvent: original, completion: completion));
      final result = await completion.future;

      expect(result.isFailure, isTrue);
      expect(result.message, startsWith('שגיאה בעדכון פרטי האירוע: '));
      expect(result.message, contains('boom'));
    });
  });
}

Event _event(String id, DateTime day, DateTime now) {
  return Event(
    id: id,
    name: 'כנס חורף',
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
