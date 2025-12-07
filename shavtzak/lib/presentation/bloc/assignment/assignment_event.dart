import 'package:equatable/equatable.dart';
import '../../../core/constants/role_types.dart';
import '../../../domain/entities/assignment.dart';

/// Base event class for AssignmentBloc
abstract class AssignmentEvent extends Equatable {
  const AssignmentEvent();

  @override
  List<Object?> get props => [];
}

/// Load all assignments
class LoadAssignments extends AssignmentEvent {
  const LoadAssignments();
}

/// Load assignments for a specific event
class LoadAssignmentsByEvent extends AssignmentEvent {
  final String eventId;

  const LoadAssignmentsByEvent(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

/// Load assignments for a specific team member
class LoadAssignmentsByPerson extends AssignmentEvent {
  final String teamMemberId;

  const LoadAssignmentsByPerson(this.teamMemberId);

  @override
  List<Object?> get props => [teamMemberId];
}

/// Load assignments by date range
class LoadAssignmentsByDateRange extends AssignmentEvent {
  final DateTime start;
  final DateTime end;

  const LoadAssignmentsByDateRange(this.start, this.end);

  @override
  List<Object?> get props => [start, end];
}

/// Load assignment by ID
class LoadAssignmentById extends AssignmentEvent {
  final String id;

  const LoadAssignmentById(this.id);

  @override
  List<Object?> get props => [id];
}

/// Create new assignment
class CreateAssignment extends AssignmentEvent {
  final Assignment assignment;

  const CreateAssignment(this.assignment);

  @override
  List<Object?> get props => [assignment];
}

/// Create new assignment bypassing conflict checks (for manual assignments)
class CreateAssignmentWithBypass extends AssignmentEvent {
  final Assignment assignment;

  const CreateAssignmentWithBypass(this.assignment);

  @override
  List<Object?> get props => [assignment];
}

/// Update assignment
class UpdateAssignment extends AssignmentEvent {
  final Assignment assignment;

  const UpdateAssignment(this.assignment);

  @override
  List<Object?> get props => [assignment];
}

/// Delete assignment
class DeleteAssignment extends AssignmentEvent {
  final String id;

  const DeleteAssignment(this.id);

  @override
  List<Object?> get props => [id];
}

/// Update assignment status
class UpdateAssignmentStatus extends AssignmentEvent {
  final String id;
  final AssignmentStatus status;

  const UpdateAssignmentStatus(this.id, this.status);

  @override
  List<Object?> get props => [id, status];
}

/// Confirm assignment
class ConfirmAssignment extends AssignmentEvent {
  final String id;

  const ConfirmAssignment(this.id);

  @override
  List<Object?> get props => [id];
}

/// Decline assignment
class DeclineAssignment extends AssignmentEvent {
  final String id;

  const DeclineAssignment(this.id);

  @override
  List<Object?> get props => [id];
}

/// Load assignments with conflicts
class LoadAssignmentsWithConflicts extends AssignmentEvent {
  const LoadAssignmentsWithConflicts();
}

/// Load assignment statistics for an event
class LoadEventAssignmentStats extends AssignmentEvent {
  final String eventId;

  const LoadEventAssignmentStats(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

/// Refresh assignments
class RefreshAssignments extends AssignmentEvent {
  const RefreshAssignments();
}

/// Load all assignment slots (role requirements) for grid view
class LoadAssignmentSlots extends AssignmentEvent {
  const LoadAssignmentSlots();
}

/// Apply event filter to assignment slots
class ApplyEventFilter extends AssignmentEvent {
  final Set<String> eventIds;

  const ApplyEventFilter(this.eventIds);

  @override
  List<Object?> get props => [eventIds];
}

/// Clear event filter
class ClearEventFilter extends AssignmentEvent {
  const ClearEventFilter();
}

/// Internal event to rebuild slots (triggered by real-time streams)
/// Note: Should only be used internally by AssignmentBloc
class RebuildAssignmentSlots extends AssignmentEvent {
  final Set<String>? preservedFilter;

  const RebuildAssignmentSlots({this.preservedFilter});

  @override
  List<Object?> get props => [preservedFilter];
}

/// Load assignments for a specific user with real-time updates for both assignments AND events
/// This ensures that when event details change or events are deleted, the UI updates automatically
class LoadUserAssignments extends AssignmentEvent {
  final String teamMemberId;

  const LoadUserAssignments(this.teamMemberId);

  @override
  List<Object?> get props => [teamMemberId];
}

/// Internal event to rebuild user assignments (triggered by real-time streams)
class RebuildUserAssignments extends AssignmentEvent {
  final String teamMemberId;

  const RebuildUserAssignments(this.teamMemberId);

  @override
  List<Object?> get props => [teamMemberId];
}

