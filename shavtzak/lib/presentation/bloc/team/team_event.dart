import 'package:equatable/equatable.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/constants/constraint_status.dart';

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

  const CreateTeamMember(this.member);

  @override
  List<Object?> get props => [member];
}

/// Update an existing team member
class UpdateTeamMember extends TeamEvent {
  final TeamMember member;

  const UpdateTeamMember(this.member);

  @override
  List<Object?> get props => [member];
}

/// Delete a team member
class DeleteTeamMember extends TeamEvent {
  final String id;

  const DeleteTeamMember(this.id);

  @override
  List<Object?> get props => [id];
}

/// Deactivate a team member (soft delete)
class DeactivateTeamMember extends TeamEvent {
  final String id;

  const DeactivateTeamMember(this.id);

  @override
  List<Object?> get props => [id];
}

/// Reactivate a team member
class ReactivateTeamMember extends TeamEvent {
  final String id;

  const ReactivateTeamMember(this.id);

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

  const AddConstraintRequest({
    required this.teamMemberId,
    required this.startDate,
    this.endDate,
    this.note,
  });

  @override
  List<Object?> get props => [teamMemberId, startDate, endDate, note];
}

/// Remove a pending constraint request for a team member (user-facing)
class RemoveConstraintRequest extends TeamEvent {
  final String teamMemberId;
  final int constraintIndex;

  const RemoveConstraintRequest({
    required this.teamMemberId,
    required this.constraintIndex,
  });

  @override
  List<Object?> get props => [teamMemberId, constraintIndex];
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
