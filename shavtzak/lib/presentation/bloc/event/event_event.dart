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

/// Duplicate an event with new date/time and other fields
class DuplicateEvent extends EventEvent {
  final String eventId;
  final String newName;
  final String newLocation;
  final String newComments;
  final DateTime newStartDate;
  final DateTime newEndDate;
  final String newStartTime;
  final String newEndTime;
  final String newAssemblyTime;
  final String newActualShowStartTime;
  final bool newRequiresArmed;
  final Map<String, int> newRoleRequirements;
  final bool duplicateAssignments;

  const DuplicateEvent({
    required this.eventId,
    required this.newName,
    required this.newLocation,
    required this.newComments,
    required this.newStartDate,
    required this.newEndDate,
    required this.newStartTime,
    required this.newEndTime,
    required this.newAssemblyTime,
    this.newActualShowStartTime = '',
    required this.newRequiresArmed,
    required this.newRoleRequirements,
    this.duplicateAssignments = false,
  });

  @override
  List<Object?> get props => [
        eventId,
        newName,
        newLocation,
        newComments,
        newStartDate,
        newEndDate,
        newStartTime,
        newEndTime,
        newAssemblyTime,
        newActualShowStartTime,
        newRequiresArmed,
        newRoleRequirements,
        duplicateAssignments,
      ];
}

/// Confirm duplication after user resolves conflicts
/// This event is dispatched AFTER the user selects which assignments to exclude
class ConfirmDuplicationWithExclusions extends EventEvent {
  final Event originalEvent;
  final Event proposedEvent;
  final Set<String> assignmentIdsToExclude;
  final List<String> originalAssignmentIds; // All original assignment IDs

  const ConfirmDuplicationWithExclusions({
    required this.originalEvent,
    required this.proposedEvent,
    required this.assignmentIdsToExclude,
    required this.originalAssignmentIds,
  });

  @override
  List<Object?> get props => [
        originalEvent,
        proposedEvent,
        assignmentIdsToExclude,
        originalAssignmentIds,
      ];
}
