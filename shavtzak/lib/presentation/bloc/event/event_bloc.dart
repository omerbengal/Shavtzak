import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../domain/entities/event.dart';
import 'event_event.dart';
import 'event_state.dart';

/// BLoC for managing events
class EventBloc extends Bloc<EventEvent, EventState> {
  final EventRepository _repository;

  EventBloc(this._repository) : super(const EventInitial()) {
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

  /// Load all events with real-time updates
  Future<void> _onLoadEvents(
    LoadEvents event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());

    try {
      // Use emit.forEach to subscribe to real-time stream
      await emit.forEach<List<Event>>(
        _repository.watchEvents(),
        onData: (events) {
          if (events.isEmpty) {
            return const EventsEmpty('אין אירועים במערכת');
          } else {
            return EventsLoaded.withCounts(events);
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

  /// Load upcoming events only
  Future<void> _onLoadUpcomingEvents(
    LoadUpcomingEvents event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());

    try {
      final events = await _repository.getUpcomingEvents();

      if (events.isEmpty) {
        emit(const EventsEmpty('אין אירועים קרובים'));
      } else {
        emit(EventsLoaded.withCounts(events));
      }
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
    emit(const EventOperating('creating'));

    try {
      await _repository.createEvent(event.event);
      emit(const EventOperationSuccess('האירוע נוסף בהצלחה'));
      // Restart real-time listener
      add(const LoadEvents());
    } catch (e) {
      emit(EventError('שגיאה בהוספת אירוע: $e'));
    }
  }

  /// Update event
  Future<void> _onUpdateEvent(
    UpdateEvent event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventOperating('updating'));

    try {
      await _repository.updateEvent(event.event);
      emit(const EventOperationSuccess('פרטי האירוע עודכנו בהצלחה'));
      // Restart real-time listener
      add(const LoadEvents());
    } catch (e) {
      emit(EventError('שגיאה בעדכון פרטי האירוע: $e'));
    }
  }

  /// Delete event
  Future<void> _onDeleteEvent(
    DeleteEvent event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventOperating('deleting'));

    try {
      await _repository.deleteEvent(event.id);
      emit(const EventOperationSuccess('האירוע נמחק בהצלחה'));
      // Restart real-time listener
      add(const LoadEvents());
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
}
