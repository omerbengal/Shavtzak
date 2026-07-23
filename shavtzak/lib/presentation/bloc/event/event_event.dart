import 'package:equatable/equatable.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/participant_group.dart';
import '../../../core/utils/crud_action_result.dart';

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
  final CrudActionCompleter? completion;

  const CreateEvent(this.event, {this.completion});

  @override
  List<Object?> get props => [event];
}

/// Update event
class UpdateEvent extends EventEvent {
  final Event event;

  /// The pre-edit event as the modal already holds it. Passed to the
  /// repository so the save doesn't await a one-shot getEventById() that can
  /// park for tens of seconds on a flaky connection. Null for callers that
  /// don't have it (the repository then falls back to a fetch).
  final Event? originalEvent;
  final CrudActionCompleter? completion;

  const UpdateEvent(this.event, {this.originalEvent, this.completion});

  @override
  List<Object?> get props => [event];
}

/// Delete event
class DeleteEvent extends EventEvent {
  final String id;
  final CrudActionCompleter? completion;

  const DeleteEvent(this.id, {this.completion});

  @override
  List<Object?> get props => [id];
}

/// Refresh events
class RefreshEvents extends EventEvent {
  const RefreshEvents();
}

/// Deactivate event — hides it from /admin/assignments, /user/assignments, summary;
/// deletes Google Calendar events; assignments stay preserved in Firestore.
class DeactivateEventRequested extends EventEvent {
  final String eventId;
  final CrudActionCompleter? completion;

  const DeactivateEventRequested(this.eventId, {this.completion});

  @override
  List<Object?> get props => [eventId];
}

/// Reactivate event — restores visibility everywhere and recreates Google Calendar
/// events using preserved assignments.
class ReactivateEventRequested extends EventEvent {
  final String eventId;
  final CrudActionCompleter? completion;

  const ReactivateEventRequested(this.eventId, {this.completion});

  @override
  List<Object?> get props => [eventId];
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
  final String newTeamEndTime;
  final String newAssemblyTime;
  final String newActualShowStartTime;
  final List<ParticipantGroup> newParticipantGroups;
  final bool newRequiresArmed;
  final Map<String, int> newRoleRequirements;
  final bool duplicateAssignments;
  final String? categoryId;
  final bool newRelevantForExtendedTeam;

  const DuplicateEvent({
    required this.eventId,
    required this.newName,
    required this.newLocation,
    required this.newComments,
    required this.newStartDate,
    required this.newEndDate,
    required this.newStartTime,
    required this.newEndTime,
    this.newTeamEndTime = '',
    required this.newAssemblyTime,
    this.newActualShowStartTime = '',
    this.newParticipantGroups = const [],
    required this.newRequiresArmed,
    required this.newRoleRequirements,
    this.duplicateAssignments = false,
    this.categoryId,
    this.newRelevantForExtendedTeam = false,
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
        newTeamEndTime,
        newAssemblyTime,
        newActualShowStartTime,
        newParticipantGroups,
        newRequiresArmed,
        newRoleRequirements,
        duplicateAssignments,
        categoryId,
        newRelevantForExtendedTeam,
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
