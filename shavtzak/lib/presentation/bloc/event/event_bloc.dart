import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/assignment.dart';
import 'event_event.dart';
import 'event_state.dart';

/// BLoC for managing events
class EventBloc extends Bloc<EventEvent, EventState> {
  final EventRepository _repository;
  final AssignmentRepository _assignmentRepository;

  EventBloc(this._repository, this._assignmentRepository) : super(const EventInitial()) {
    // Register event handlers
    on<LoadEvents>(_onLoadEvents);
    on<LoadUpcomingEvents>(_onLoadUpcomingEvents);
    on<SearchEvents>(_onSearchEvents);
    on<LoadEventById>(_onLoadEventById);
    on<CreateEvent>(_onCreateEvent);
    on<UpdateEvent>(_onUpdateEvent);
    on<DeleteEvent>(_onDeleteEvent);
    on<RefreshEvents>(_onRefreshEvents);
  }

  /// Load all events with real-time updates (including assignment counts)
  Future<void> _onLoadEvents(
    LoadEvents event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());

    try {
      // Use emit.forEach to subscribe to combined stream of events + assignments
      await emit.forEach<_EventsWithAssignments>(
        _combineEventsAndAssignments(),
        onData: (data) {
          if (data.events.isEmpty) {
            return const EventsEmpty('אין אירועים במערכת');
          } else {
            return EventsLoaded.withCounts(
              data.events,
              assignmentCounts: data.assignmentCounts,
            );
          }
        },
        onError: (error, stackTrace) {
          return EventError('שגיאה בטעינת אירועים: $error');
        },
      );
    } catch (e) {
      emit(EventError('שגיאה בטעינת אירועים: $e'));
    }
  }

  /// Combines events and assignments streams into a single stream
  /// that emits whenever either source changes
  Stream<_EventsWithAssignments> _combineEventsAndAssignments() async* {
    // Listen to both streams
    final eventsStream = _repository.watchEvents();
    final assignmentsStream = _assignmentRepository.watchAssignments();

    // Cache latest values
    List<Event>? latestEvents;
    List<Assignment>? latestAssignments;

    // Create stream controller for combined output
    final controller = StreamController<_EventsWithAssignments>();

    // Helper to emit combined data when both are available
    void emitCombined() {
      if (latestEvents != null && latestAssignments != null) {
        // Calculate assignment counts per event
        final counts = <String, int>{};
        for (final assignment in latestAssignments!) {
          counts[assignment.eventId] = (counts[assignment.eventId] ?? 0) + 1;
        }

        controller.add(_EventsWithAssignments(
          events: latestEvents!,
          assignmentCounts: counts,
        ));
      }
    }

    // Listen to events stream
    final eventsSubscription = eventsStream.listen(
      (events) {
        latestEvents = events;
        emitCombined();
      },
      onError: controller.addError,
    );

    // Listen to assignments stream
    final assignmentsSubscription = assignmentsStream.listen(
      (assignments) {
        latestAssignments = assignments;
        emitCombined();
      },
      onError: controller.addError,
    );

    // Forward combined stream
    yield* controller.stream;

    // Cleanup when stream is cancelled
    await controller.done;
    await eventsSubscription.cancel();
    await assignmentsSubscription.cancel();
  }

  /// Load upcoming events only (future events with real-time updates)
  Future<void> _onLoadUpcomingEvents(
    LoadUpcomingEvents event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());

    try {
      final now = DateTime.now();
      // Start of today (midnight)
      final today = DateTime(now.year, now.month, now.day);

      // Use emit.forEach to subscribe to combined stream of events + assignments
      await emit.forEach<_EventsWithAssignments>(
        _combineEventsAndAssignments(),
        onData: (data) {
          // Filter for future events (end date >= today)
          final futureEvents = data.events.where((event) {
            return event.endDate.isAfter(today) ||
                   (event.endDate.year == today.year &&
                    event.endDate.month == today.month &&
                    event.endDate.day == today.day);
          }).toList();

          if (futureEvents.isEmpty) {
            // Check if database is truly empty or just filtered empty
            final isFiltered = data.events.isNotEmpty;
            return EventsEmpty('אין אירועים עתידיים', isFiltered: isFiltered);
          } else {
            return EventsLoaded.withCounts(
              futureEvents,
              assignmentCounts: data.assignmentCounts,
            );
          }
        },
        onError: (error, stackTrace) {
          return EventError('שגיאה בטעינת אירועים: $error');
        },
      );
    } catch (e) {
      emit(EventError('שגיאה בטעינת אירועים: $e'));
    }
  }

  /// Search events
  Future<void> _onSearchEvents(
    SearchEvents event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());

    try {
      final events = await _repository.searchEvents(event.query);

      if (events.isEmpty) {
        emit(const EventsEmpty('לא נמצאו אירועים'));
      } else {
        emit(EventsLoaded.withCounts(events, searchQuery: event.query));
      }
    } catch (e) {
      emit(EventError('שגיאה בחיפוש: $e'));
    }
  }

  /// Load event by ID
  Future<void> _onLoadEventById(
    LoadEventById event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());

    try {
      final eventDetail = await _repository.getEventById(event.id);

      if (eventDetail == null) {
        emit(const EventError('אירוע לא נמצא'));
      } else {
        emit(EventDetailLoaded(eventDetail));
      }
    } catch (e) {
      emit(EventError('שגיאה בטעינת פרטי האירוע: $e'));
    }
  }

  /// Create new event
  Future<void> _onCreateEvent(
    CreateEvent event,
    Emitter<EventState> emit,
  ) async {
    try {
      // Don't emit EventOperating to avoid UI rebuild
      await _repository.createEvent(event.event);
      // Emit success to show snackbar, UI will keep showing last state
      emit(const EventOperationSuccess('האירוע נוסף בהצלחה'));

      // Don't restart listener here - the modal will handle it with the correct filter
    } catch (e) {
      emit(EventError('שגיאה בהוספת אירוע: $e'));
    }
  }

  /// Update event
  Future<void> _onUpdateEvent(
    UpdateEvent event,
    Emitter<EventState> emit,
  ) async {
    try {
      // Don't emit EventOperating to avoid UI rebuild
      await _repository.updateEvent(event.event);
      // Emit success to show snackbar, UI will keep showing last state
      emit(const EventOperationSuccess('פרטי האירוע עודכנו בהצלחה'));

      // Don't restart listener here - the modal will handle it with the correct filter
    } catch (e) {
      emit(EventError('שגיאה בעדכון פרטי האירוע: $e'));
    }
  }

  /// Delete event
  Future<void> _onDeleteEvent(
    DeleteEvent event,
    Emitter<EventState> emit,
  ) async {
    try {
      // Don't emit EventOperating to avoid UI rebuild
      await _repository.deleteEvent(event.id);
      // Emit success to show snackbar, UI will keep showing last state
      emit(const EventOperationSuccess('האירוע נמחק בהצלחה'));

      // Don't restart listener here - the modal will handle it with the correct filter
    } catch (e) {
      emit(EventError('שגיאה במחיקת האירוע: $e'));
    }
  }

  /// Refresh events
  Future<void> _onRefreshEvents(
    RefreshEvents event,
    Emitter<EventState> emit,
  ) async {
    // Simply reload
    add(const LoadEvents());
  }

  @override
  Future<void> close() {
    return super.close();
  }
}

/// Internal helper class to combine events with their assignment counts
class _EventsWithAssignments {
  final List<Event> events;
  final Map<String, int> assignmentCounts;

  _EventsWithAssignments({
    required this.events,
    required this.assignmentCounts,
  });
}
