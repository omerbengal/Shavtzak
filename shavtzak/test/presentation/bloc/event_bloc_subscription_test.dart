import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/event/event_event.dart';
import 'package:shavtzak/presentation/bloc/event/event_state.dart';

import 'event_bloc_subscription_test.mocks.dart';

@GenerateMocks([EventRepository, AssignmentRepository])
void main() {
  late MockEventRepository mockEventRepository;
  late MockAssignmentRepository mockAssignmentRepository;
  late StreamController<List<Event>> eventsController;
  late StreamController<List<Assignment>> assignmentsController;

  final now = DateTime(2024, 1, 1);
  // A far-future date so "upcoming" filtering keeps the event regardless of
  // when the test runs.
  final futureStart = DateTime(2999, 1, 1);
  final futureEnd = DateTime(2999, 1, 2);

  /// Build a minimal valid Event for tests.
  Event event({
    required String id,
    required String name,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return Event(
      id: id,
      name: name,
      startDate: startDate ?? futureStart,
      endDate: endDate ?? futureEnd,
      startTime: '10:00',
      endTime: '12:00',
      assemblyTime: '09:00',
      requiresArmed: false,
      roleRequirements: const {},
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Build a minimal valid Assignment for tests.
  Assignment assignment({
    required String id,
    required String eventId,
  }) {
    return Assignment(
      id: id,
      eventId: eventId,
      teamMemberId: 'member-$id',
      roleType: 'medic',
      slotIndex: 0,
      status: AssignmentStatus.confirmed,
      notes: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() {
    mockEventRepository = MockEventRepository();
    mockAssignmentRepository = MockAssignmentRepository();
    // Broadcast so the bloc subscription does not consume the single-listener
    // budget and tests can also read frames if needed.
    eventsController = StreamController<List<Event>>.broadcast();
    assignmentsController = StreamController<List<Assignment>>.broadcast();
    when(mockEventRepository.watchEvents())
        .thenAnswer((_) => eventsController.stream);
    when(mockAssignmentRepository.watchAssignments())
        .thenAnswer((_) => assignmentsController.stream);
  });

  tearDown(() async {
    await eventsController.close();
    await assignmentsController.close();
  });

  EventBloc buildBloc() => EventBloc(
        mockEventRepository,
        mockAssignmentRepository,
        calendarSyncBloc: null,
      );

  test(
      'subscribes to watchEvents AND watchAssignments exactly once for repeated LoadEvents',
      () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    bloc.add(const LoadEvents());
    // Allow the first Load to process and establish the subscriptions.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    bloc.add(const LoadEvents());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The core fix: exactly ONE subscription each, never torn down/re-created
    // on a repeat Load. (Old code → 2 each.)
    verify(mockEventRepository.watchEvents()).called(1);
    verify(mockAssignmentRepository.watchAssignments()).called(1);
  });

  test(
      'real-time EVENTS change propagates WITHOUT a reload through the single subscription',
      () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    final emitted = <EventState>[];
    final sub = bloc.stream.listen(emitted.add);
    addTearDown(sub.cancel);

    final eventA = event(id: 'a', name: 'Alpha');

    bloc.add(const LoadEvents());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Both streams must emit before _emitCombinedIfReady emits.
    eventsController.add([eventA]);
    assignmentsController.add(<Assignment>[]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final loadedStates = emitted.whereType<EventsLoaded>().toList();
    expect(loadedStates, isNotEmpty);
    expect(loadedStates.last.events.single.name, 'Alpha');

    // A live change in Firestore arrives on the SAME events subscription, with
    // NO further Load dispatch.
    final changed = eventA.copyWith(name: 'changed');
    eventsController.add([changed]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final loadedAfter = emitted.whereType<EventsLoaded>().toList();
    // A NEW EventsLoaded must be emitted reflecting the change.
    expect(loadedAfter.last.events.single.name, 'changed',
        reason:
            'Live Firestore events change must flow to the UI through the single subscription with no reload');
    // Still only one subscription each.
    verify(mockEventRepository.watchEvents()).called(1);
    verify(mockAssignmentRepository.watchAssignments()).called(1);
  });

  test(
      'real-time ASSIGNMENTS change propagates WITHOUT a reload (second stream still drives live updates)',
      () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    final emitted = <EventState>[];
    final sub = bloc.stream.listen(emitted.add);
    addTearDown(sub.cancel);

    final eventA = event(id: 'a', name: 'Alpha');

    bloc.add(const LoadEvents());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Initial emissions on both streams: event with zero assignments.
    eventsController.add([eventA]);
    assignmentsController.add(<Assignment>[]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final initialLoaded = emitted.whereType<EventsLoaded>().toList();
    expect(initialLoaded, isNotEmpty);
    expect(initialLoaded.last.assignmentCounts['a'] ?? 0, 0,
        reason: 'No assignments yet for event a');

    // A live assignments change arrives on the SAME assignments subscription,
    // with NO further Load dispatch.
    assignmentsController.add([assignment(id: '1', eventId: 'a')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final loadedAfter = emitted.whereType<EventsLoaded>().toList();
    expect(loadedAfter.last.assignmentCounts['a'], 1,
        reason:
            'Live Firestore assignments change must update the combined state through the single subscription with no reload');
    // Still only one subscription each.
    verify(mockEventRepository.watchEvents()).called(1);
    verify(mockAssignmentRepository.watchAssignments()).called(1);
  });

  test(
      'filter switch (all -> upcoming) is served from cache without a second subscription',
      () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    final emitted = <EventState>[];
    final sub = bloc.stream.listen(emitted.add);
    addTearDown(sub.cancel);

    final upcomingEvent = event(id: 'up', name: 'Future');
    final pastEvent = event(
      id: 'past',
      name: 'Past',
      startDate: DateTime(2000, 1, 1),
      endDate: DateTime(2000, 1, 2),
    );

    // Load ALL events.
    bloc.add(const LoadEvents());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    eventsController.add([upcomingEvent, pastEvent]);
    assignmentsController.add(<Assignment>[]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final allLoaded = emitted.whereType<EventsLoaded>().toList();
    expect(allLoaded.last.events.length, 2,
        reason: 'LoadEvents should surface both past and upcoming events');

    // Switch filter to UPCOMING only — must be served from cache.
    bloc.add(const LoadUpcomingEvents());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final upcomingLoaded = emitted.whereType<EventsLoaded>().toList();
    expect(upcomingLoaded.last.events.length, 1);
    expect(upcomingLoaded.last.events.single.name, 'Future');

    // No second subscription was created for the filter switch.
    verify(mockEventRepository.watchEvents()).called(1);
    verify(mockAssignmentRepository.watchAssignments()).called(1);
  });

  test('a stream error re-subscribes fresh instead of dying (recovery)',
      () async {
    final bloc = EventBloc(
      mockEventRepository,
      mockAssignmentRepository,
      calendarSyncBloc: null,
      resubscribeBackoff: const Duration(milliseconds: 10),
      watchdogTimeout: const Duration(seconds: 30), // long: isolate error path
    );
    addTearDown(bloc.close);

    bloc.add(const LoadEvents());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    verify(mockEventRepository.watchEvents()).called(1);
    verify(mockAssignmentRepository.watchAssignments()).called(1);

    // The events stream errors — previously this settled on empty with a dead
    // listener; now it must re-subscribe both streams fresh.
    eventsController.addError(Exception('transient'));
    await Future<void>.delayed(const Duration(milliseconds: 40)); // > backoff

    verify(mockEventRepository.watchEvents()).called(1); // the re-subscribe
    verify(mockAssignmentRepository.watchAssignments()).called(1);
  });

  test('the watchdog re-subscribes when no authoritative data arrives in time',
      () async {
    final bloc = EventBloc(
      mockEventRepository,
      mockAssignmentRepository,
      calendarSyncBloc: null,
      watchdogTimeout: const Duration(milliseconds: 30),
      resubscribeBackoff: const Duration(milliseconds: 10),
    );
    addTearDown(bloc.close);

    bloc.add(const LoadEvents());
    // Never emit on either stream — simulates a cold cache-empty snapshot
    // (skipped by the repository) whose first server snapshot is parked.
    await Future<void>.delayed(const Duration(milliseconds: 90));

    // Watchdog fired → at least one fresh re-subscribe.
    verify(mockEventRepository.watchEvents()).called(greaterThanOrEqualTo(2));
  });

  test('the watchdog does not re-subscribe once authoritative data arrives',
      () async {
    final bloc = EventBloc(
      mockEventRepository,
      mockAssignmentRepository,
      calendarSyncBloc: null,
      watchdogTimeout: const Duration(milliseconds: 30),
      resubscribeBackoff: const Duration(milliseconds: 10),
    );
    addTearDown(bloc.close);

    bloc.add(const LoadEvents());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    // Authoritative data arrives before the watchdog would fire.
    eventsController.add([event(id: 'a', name: 'Alpha')]);
    assignmentsController.add(<Assignment>[]);
    await Future<void>.delayed(const Duration(milliseconds: 60)); // > timeout

    // Still exactly one subscription each — watchdog disarmed on the emit.
    verify(mockEventRepository.watchEvents()).called(1);
    verify(mockAssignmentRepository.watchAssignments()).called(1);
  });

  test('a fresh Load after the recovery budget is exhausted re-subscribes',
      () async {
    final bloc = EventBloc(
      mockEventRepository,
      mockAssignmentRepository,
      calendarSyncBloc: null,
      watchdogTimeout: const Duration(milliseconds: 20),
      resubscribeBackoff: const Duration(milliseconds: 10),
      maxResubscribes: 2,
    );
    addTearDown(bloc.close);

    bloc.add(const LoadEvents());
    // Never emit → the watchdog exhausts the (2) re-subscribe budget, then the
    // bloc gives up (would otherwise be stuck until a full page reload).
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Reset recorded subscriptions so the next assertion is unambiguous.
    clearInteractions(mockEventRepository);
    clearInteractions(mockAssignmentRepository);

    // A fresh Load is a user-driven retry → it must re-subscribe fresh.
    bloc.add(const LoadEvents());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    verify(mockEventRepository.watchEvents()).called(1);
    verify(mockAssignmentRepository.watchAssignments()).called(1);
  });
}
