import 'package:equatable/equatable.dart';
import '../../../domain/entities/event.dart';

/// Base state class for EventBloc
abstract class EventState extends Equatable {
  const EventState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class EventInitial extends EventState {
  const EventInitial();
}

/// Loading state
class EventLoading extends EventState {
  const EventLoading();
}

/// Events loaded successfully
class EventsLoaded extends EventState {
  final List<Event> events;
  final String? searchQuery;
  final int totalCount;
  final int upcomingCount;
  final int pastCount;
  final int activeCount;
  final Map<String, int> assignmentCounts; // Event ID -> count of assignments

  const EventsLoaded(
    this.events, {
    this.searchQuery,
    this.assignmentCounts = const {},
  })  : totalCount = events.length,
        upcomingCount = 0,
        pastCount = 0,
        activeCount = 0;

  EventsLoaded.withCounts(
    List<Event> events, {
    this.searchQuery,
    this.assignmentCounts = const {},
  })  : events = (events..sort((a, b) => a.startDate.compareTo(b.startDate))),
        totalCount = events.length,
        upcomingCount = events.where((e) => e.isUpcoming).length,
        pastCount = events.where((e) => e.isPast).length,
        activeCount = events.where((e) => e.isActive).length;

  @override
  List<Object?> get props => [
        events,
        searchQuery,
        totalCount,
        upcomingCount,
        pastCount,
        activeCount,
        assignmentCounts,
      ];
}

/// Single event detail loaded
class EventDetailLoaded extends EventState {
  final Event event;

  const EventDetailLoaded(this.event);

  @override
  List<Object?> get props => [event];
}

/// No events found
class EventsEmpty extends EventState {
  final String message;
  final bool isFiltered; // true if empty due to filter, false if database is empty

  const EventsEmpty(this.message, {this.isFiltered = false});

  @override
  List<Object?> get props => [message, isFiltered];
}

/// Event operation in progress (create/update/delete)
class EventOperating extends EventState {
  final String operation; // 'creating', 'updating', 'deleting'

  const EventOperating(this.operation);

  @override
  List<Object?> get props => [operation];
}

/// Event operation succeeded
class EventOperationSuccess extends EventState {
  final String message;

  const EventOperationSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

/// Error state
class EventError extends EventState {
  final String message;

  const EventError(this.message);

  @override
  List<Object?> get props => [message];
}
