import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/assignment.dart';
import '../../../core/constants/role_types.dart';
import 'event_event.dart';
import 'event_state.dart';

/// BLoC for managing events
class EventBloc extends Bloc<EventEvent, EventState> {
  final EventRepository _repository;
  final AssignmentRepository _assignmentRepository;

  // Stream subscriptions for manual control to prevent memory leaks
  StreamSubscription<List<Event>>? _eventsSubscription;
  StreamSubscription<List<Assignment>>? _assignmentsSubscription;

  // Cache latest values for combining streams
  List<Event> _latestEvents = [];
  List<Assignment> _latestAssignments = [];
  bool _eventsLoaded = false;
  bool _assignmentsLoaded = false;
  bool _upcomingOnly = false;

  EventBloc(this._repository, this._assignmentRepository) : super(const EventInitial()) {
    // Register event handlers
    on<LoadEvents>(_onLoadEvents);
    on<LoadUpcomingEvents>(_onLoadUpcomingEvents);
    on<SearchEvents>(_onSearchEvents);
    on<LoadEventById>(_onLoadEventById);
    on<CreateEvent>(_onCreateEvent);
    on<UpdateEvent>(_onUpdateEvent);
    on<DeleteEvent>(_onDeleteEvent);
    on<DuplicateEvent>(_onDuplicateEvent);
    on<RefreshEvents>(_onRefreshEvents);
    on<_EventsDataUpdated>(_onEventsDataUpdated);
  }

  /// Load all events with real-time updates (including assignment counts)
  Future<void> _onLoadEvents(
    LoadEvents event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());
    _upcomingOnly = false;

    try {
      // Start combined stream subscriptions
      await _startCombinedStreams();
    } catch (e) {
      emit(EventError('שגיאה בטעינת אירועים: $e'));
    }
  }

  /// Start combined stream subscriptions for events and assignments
  Future<void> _startCombinedStreams() async {
    // Cancel previous subscriptions before starting new ones to prevent memory leaks
    await _eventsSubscription?.cancel();
    await _assignmentsSubscription?.cancel();

    // Reset state
    _eventsLoaded = false;
    _assignmentsLoaded = false;
    _latestEvents = [];
    _latestAssignments = [];

    // Subscribe to events stream
    _eventsSubscription = _repository.watchEvents().listen(
      (events) {
        _latestEvents = events;
        _eventsLoaded = true;
        _emitCombinedIfReady();
      },
      onError: (error) {
        _latestEvents = [];
        _eventsLoaded = true;
        _emitCombinedIfReady();
      },
    );

    // Subscribe to assignments stream
    _assignmentsSubscription = _assignmentRepository.watchAssignments().listen(
      (assignments) {
        _latestAssignments = assignments;
        _assignmentsLoaded = true;
        _emitCombinedIfReady();
      },
      onError: (error) {
        _latestAssignments = [];
        _assignmentsLoaded = true;
        _emitCombinedIfReady();
      },
    );
  }

  /// Emit combined data when both streams have loaded
  void _emitCombinedIfReady() {
    if (!_eventsLoaded || !_assignmentsLoaded) return;

    // Calculate assignment counts per event
    final counts = <String, int>{};
    for (final assignment in _latestAssignments) {
      counts[assignment.eventId] = (counts[assignment.eventId] ?? 0) + 1;
    }

    add(_EventsDataUpdated(
      events: _latestEvents,
      assignmentCounts: counts,
      upcomingOnly: _upcomingOnly,
    ));
  }

  /// Handle combined events and assignments data update
  Future<void> _onEventsDataUpdated(
    _EventsDataUpdated event,
    Emitter<EventState> emit,
  ) async {
    var events = event.events;

    if (event.upcomingOnly) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Filter for future events
      final futureEvents = events.where((e) {
        return e.endDate.isAfter(today) ||
               (e.endDate.year == today.year &&
                e.endDate.month == today.month &&
                e.endDate.day == today.day);
      }).toList();

      if (futureEvents.isEmpty) {
        final isFiltered = events.isNotEmpty;
        emit(EventsEmpty('אין אירועים עתידיים', isFiltered: isFiltered));
      } else {
        emit(EventsLoaded.withCounts(
          futureEvents,
          assignmentCounts: event.assignmentCounts,
        ));
      }
    } else {
      if (events.isEmpty) {
        emit(const EventsEmpty('אין אירועים במערכת'));
      } else {
        emit(EventsLoaded.withCounts(
          events,
          assignmentCounts: event.assignmentCounts,
        ));
      }
    }
  }

  /// Load upcoming events only (future events with real-time updates)
  Future<void> _onLoadUpcomingEvents(
    LoadUpcomingEvents event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());
    _upcomingOnly = true;

    try {
      // Start combined stream subscriptions
      await _startCombinedStreams();
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
      // Delete the event
      await _repository.deleteEvent(event.id);

      // Immediately reload events to get updated state
      // This ensures the UI reflects the deletion immediately
      add(const LoadEvents());

      // Emit success to show snackbar
      emit(const EventOperationSuccess('האירוע נמחק בהצלחה'));
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

  /// Duplicate event with new date/time
  Future<void> _onDuplicateEvent(
    DuplicateEvent event,
    Emitter<EventState> emit,
  ) async {
    try {
      
      // Get the original event
      final originalEvent = await _repository.getEventById(event.eventId);
      if (originalEvent == null) {
        emit(const EventError('האירוע לא נמצא'));
        return;
      }

      // Get all assignments for the original event
      final assignments = await _assignmentRepository.getAssignmentsByEvent(event.eventId);

      // Create the duplicated event with all new values
      final duplicatedEvent = Event(
        id: const Uuid().v4(), // Generate unique ID for the duplicated event
        name: event.newName,
        location: event.newLocation,
        comments: event.newComments,
        startDate: event.newStartDate,
        endDate: event.newEndDate,
        startTime: event.newStartTime,
        endTime: event.newEndTime,
        assemblyTime: event.newAssemblyTime,
        requiresArmed: event.newRequiresArmed,
        roleRequirements: Map.from(event.newRoleRequirements),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Check for assignment conflicts with new dates
      final conflicts = <AssignmentConflict>[];

      for (final assignment in assignments) {
        if (assignment.teamMember != null) {
          final conflictReasons = <String>[];

          // Check availability conflict with new dates
          if (!assignment.teamMember!.isAvailableForDateRange(event.newStartDate, event.newEndDate)) {
            conflictReasons.add('חבר הצוות לא זמין בתאריכים החדשים');
          }

          // Add to conflicts list if any conflicts found
          if (conflictReasons.isNotEmpty) {
            conflicts.add(AssignmentConflict(
              assignmentId: assignment.id,
              teamMemberName: assignment.teamMember!.name,
              roleName: assignment.roleType.hebrewName,
              conflictReasons: conflictReasons,
            ));
          }
        }
      }

      // Use repository method to duplicate event and assignments
      await _repository.duplicateEvent(
        originalEvent,
        duplicatedEvent,
        assignments,
      );

      // If there are conflicts, emit special state
      if (conflicts.isNotEmpty) {
        emit(EventDuplicatedWithConflicts(
          duplicatedEvent: duplicatedEvent,
          assignmentConflicts: conflicts,
        ));
      } else {
        // Otherwise emit success
        emit(const EventOperationSuccess('האירוע שוכפל בהצלחה עם כל השיבוצים'));
      }

      // Reload events to show the new one
      add(const LoadEvents());
    } catch (e) {
      emit(EventError('שגיאה בשכפול האירוע: $e'));
    }
  }

  @override
  Future<void> close() async {
    // Cancel stream subscriptions to prevent memory leaks
    await _eventsSubscription?.cancel();
    await _assignmentsSubscription?.cancel();
    return super.close();
  }
}

/// Internal event: Received events and assignments update from streams
/// This is used to properly manage stream subscriptions and prevent memory leaks
class _EventsDataUpdated extends EventEvent {
  final List<Event> events;
  final Map<String, int> assignmentCounts;
  final bool upcomingOnly;

  const _EventsDataUpdated({
    required this.events,
    required this.assignmentCounts,
    this.upcomingOnly = false,
  });

  @override
  List<Object?> get props => [events, assignmentCounts, upcomingOnly];
}
