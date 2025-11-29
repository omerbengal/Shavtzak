import 'package:equatable/equatable.dart';
import '../../../domain/entities/event.dart';

/// Base event class for EventBloc
abstract class EventEvent extends Equatable {
  const EventEvent();

  @override
  List<Object?> get props => [];
}

/// Load all events with real-time updates
class LoadEvents extends EventEvent {
  const LoadEvents();
}

/// Load upcoming events only
class LoadUpcomingEvents extends EventEvent {
  const LoadUpcomingEvents();
}

/// Search events by name or location
class SearchEvents extends EventEvent {
  final String query;

  const SearchEvents(this.query);

  @override
  List<Object?> get props => [query];
}

/// Load event by ID
class LoadEventById extends EventEvent {
  final String id;

  const LoadEventById(this.id);

  @override
  List<Object?> get props => [id];
}

/// Create new event
class CreateEvent extends EventEvent {
  final Event event;

  const CreateEvent(this.event);

  @override
  List<Object?> get props => [event];
}

/// Update event
class UpdateEvent extends EventEvent {
  final Event event;

  const UpdateEvent(this.event);

  @override
  List<Object?> get props => [event];
}

/// Delete event
class DeleteEvent extends EventEvent {
  final String id;

  const DeleteEvent(this.id);

  @override
  List<Object?> get props => [id];
}

/// Refresh events
class RefreshEvents extends EventEvent {
  const RefreshEvents();
}
