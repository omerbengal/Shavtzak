import 'package:equatable/equatable.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/constants/constraint_status.dart';
import '../../../core/utils/crud_action_result.dart';

/// Events for Team BLoC
abstract class TeamEvent extends Equatable {
  const TeamEvent();

  @override
  List<Object?> get props => [];
}

/// Load all team members
class LoadTeamMembers extends TeamEvent {
  const LoadTeamMembers();
}

/// Load active team members only
class LoadActiveTeamMembers extends TeamEvent {
  const LoadActiveTeamMembers();
}

/// Search team members by name
class SearchTeamMembers extends TeamEvent {
  final String query;

  const SearchTeamMembers(this.query);

  @override
  List<Object?> get props => [query];
}

/// Load a specific team member by ID
class LoadTeamMemberById extends TeamEvent {
  final String id;

  const LoadTeamMemberById(this.id);

  @override
  List<Object?> get props => [id];
}

/// Create a new team member
class CreateTeamMember extends TeamEvent {
  final TeamMember member;
  final CrudActionCompleter? completion;

  const CreateTeamMember(this.member, {this.completion});

  @override
  List<Object?> get props => [member];
}

/// Update an existing team member
class UpdateTeamMember extends TeamEvent {
  final TeamMember member;
  final CrudActionCompleter? completion;

  const UpdateTeamMember(this.member, {this.completion});

  @override
  List<Object?> get props => [member];
}

/// Delete a team member
class DeleteTeamMember extends TeamEvent {
  final String id;
  final CrudActionCompleter? completion;

  const DeleteTeamMember(this.id, {this.completion});

  @override
  List<Object?> get props => [id];
}

/// Deactivate a team member (soft delete)
class DeactivateTeamMember extends TeamEvent {
  final String id;
  final CrudActionCompleter? completion;

  const DeactivateTeamMember(this.id, {this.completion});

  @override
  List<Object?> get props => [id];
}

/// Reactivate a team member
class ReactivateTeamMember extends TeamEvent {
  final String id;
  final CrudActionCompleter? completion;

  const ReactivateTeamMember(this.id, {this.completion});

  @override
  List<Object?> get props => [id];
}

/// Refresh team members (reload from database)
class RefreshTeamMembers extends TeamEvent {
  const RefreshTeamMembers();
}

/// Update the status of a constraint for a team member
class UpdateConstraintStatus extends TeamEvent {
  final String teamMemberId;
  final int constraintIndex;
  final ConstraintStatus newStatus;

  const UpdateConstraintStatus({
    required this.teamMemberId,
    required this.constraintIndex,
    required this.newStatus,
  });

  @override
  List<Object?> get props => [teamMemberId, constraintIndex, newStatus];
}

/// Add a new constraint request for a team member (user-facing)
class AddConstraintRequest extends TeamEvent {
  final String teamMemberId;
  final DateTime startDate;
  final DateTime? endDate;
  final String? note;
  final ConstraintStatus status;
  final ConstraintType constraintType;
  final String? startTime; // Start time in "HH:mm" format (optional)
  final String? endTime; // End time in "HH:mm" format (optional)
  final bool wasAutoRejectedFromCalendar;
  final RepeatType? repeatType; // null = one-time
  final int? repeatDay; // weekly weekday (1..7) / monthly day-of-month (1..31)
  final DateTime? repeatEndDate; // end date for recurring constraints
  final CrudActionCompleter? completion;

  const AddConstraintRequest({
    required this.teamMemberId,
    required this.startDate,
    this.endDate,
    this.note,
    this.status = ConstraintStatus.pending,
    this.constraintType = ConstraintType.unavailability,
    this.startTime,
    this.endTime,
    this.wasAutoRejectedFromCalendar = false,
    this.repeatType,
    this.repeatDay,
    this.repeatEndDate,
    this.completion,
  });

  @override
  List<Object?> get props => [
        teamMemberId,
        startDate,
        endDate,
        note,
        status,
        constraintType,
        startTime,
        endTime,
        wasAutoRejectedFromCalendar,
        repeatType,
        repeatDay,
        repeatEndDate,
      ];
}

/// Remove a constraint by ID for a team member (targeted update)
class RemoveConstraintRequest extends TeamEvent {
  final String teamMemberId;
  final String constraintId;
  final CrudActionCompleter? completion;

  const RemoveConstraintRequest({
    required this.teamMemberId,
    required this.constraintId,
    this.completion,
  });

  @override
  List<Object?> get props => [teamMemberId, constraintId];
}

/// Edit an existing constraint by ID (targeted update - reads latest from DB)
class EditConstraintRequest extends TeamEvent {
  final String teamMemberId;
  final String constraintId;
  final DateTime startDate;
  final DateTime? endDate;
  final String? note;
  final ConstraintStatus status;
  final ConstraintType constraintType;
  final String? startTime;
  final String? endTime;
  final bool wasAutoRejectedFromCalendar;
  final RepeatType? repeatType;
  final int? repeatDay;
  final DateTime? repeatEndDate;
  final CrudActionCompleter? completion;

  const EditConstraintRequest({
    required this.teamMemberId,
    required this.constraintId,
    required this.startDate,
    this.endDate,
    this.note,
    required this.status,
    required this.constraintType,
    this.startTime,
    this.endTime,
    this.wasAutoRejectedFromCalendar = false,
    this.repeatType,
    this.repeatDay,
    this.repeatEndDate,
    this.completion,
  });

  @override
  List<Object?> get props => [
        teamMemberId,
        constraintId,
        startDate,
        endDate,
        note,
        status,
        constraintType,
        startTime,
        endTime,
        wasAutoRejectedFromCalendar,
        repeatType,
        repeatDay,
        repeatEndDate,
      ];
}

// === Hybrid Constraint State Management Events ===

/// Initialize constraint manager with database constraints
class InitializeConstraintManager extends TeamEvent {
  final String teamMemberId;
  final List<DateConstraint> databaseConstraints;

  const InitializeConstraintManager({
    required this.teamMemberId,
    required this.databaseConstraints,
  });

  @override
  List<Object?> get props => [teamMemberId, databaseConstraints];
}

/// Update constraint status locally (immediate UI update)
class UpdateConstraintStatusLocal extends TeamEvent {
  final String teamMemberId;
  final String constraintId;
  final ConstraintStatus newStatus;

  const UpdateConstraintStatusLocal({
    required this.teamMemberId,
    required this.constraintId,
    required this.newStatus,
  });

  @override
  List<Object?> get props => [teamMemberId, constraintId, newStatus];
}

/// Add new constraint locally (immediate UI update)
class AddConstraintLocal extends TeamEvent {
  final String teamMemberId;
  final DateTime startDate;
  final DateTime? endDate;
  final String? note;
  final ConstraintStatus status;

  const AddConstraintLocal({
    required this.teamMemberId,
    required this.startDate,
    this.endDate,
    this.note,
    this.status = ConstraintStatus.pending,
  });

  @override
  List<Object?> get props => [teamMemberId, startDate, endDate, note, status];
}

/// Remove constraint locally (immediate UI update)
class RemoveConstraintLocal extends TeamEvent {
  final String teamMemberId;
  final String constraintId;
  final bool isLocalId;

  const RemoveConstraintLocal({
    required this.teamMemberId,
    required this.constraintId,
    this.isLocalId = false,
  });

  @override
  List<Object?> get props => [teamMemberId, constraintId, isLocalId];
}

/// Sync constraint manager with database changes and detect conflicts
class SyncConstraintsWithDatabase extends TeamEvent {
  final String teamMemberId;
  final List<DateConstraint> remoteConstraints;

  const SyncConstraintsWithDatabase({
    required this.teamMemberId,
    required this.remoteConstraints,
  });

  @override
  List<Object?> get props => [teamMemberId, remoteConstraints];
}

/// Save all pending constraint changes to database
class SavePendingConstraintChanges extends TeamEvent {
  final String teamMemberId;

  const SavePendingConstraintChanges({
    required this.teamMemberId,
  });

  @override
  List<Object?> get props => [teamMemberId];
}

/// Clear local constraint state (discard changes)
class ClearLocalConstraintState extends TeamEvent {
  final String teamMemberId;

  const ClearLocalConstraintState({
    required this.teamMemberId,
  });

  @override
  List<Object?> get props => [teamMemberId];
}

/// Clear all state (used when user signs out)
class ClearTeamState extends TeamEvent {
  const ClearTeamState();
}
