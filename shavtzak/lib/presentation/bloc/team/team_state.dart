import 'package:equatable/equatable.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/state/constraint_manager.dart';

/// States for Team BLoC
abstract class TeamState extends Equatable {
  const TeamState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class TeamInitial extends TeamState {
  const TeamInitial();
}

/// Loading team members
class TeamLoading extends TeamState {
  const TeamLoading();
}

/// Team members loaded successfully
class TeamLoaded extends TeamState {
  final List<TeamMember> members;
  final String? searchQuery;

  const TeamLoaded(this.members, {this.searchQuery});

  @override
  List<Object?> get props => [members, searchQuery];

  /// Get filtered members based on search
  List<TeamMember> get filteredMembers {
    if (searchQuery == null || searchQuery!.isEmpty) {
      return members;
    }
    final query = searchQuery!.toLowerCase();
    return members
        .where((m) => m.name.toLowerCase().contains(query))
        .toList();
  }

  /// Get statistics
  int get totalCount => members.length;
  int get activeCount => members.where((m) => m.isActive).length;
  int get inactiveCount => members.where((m) => !m.isActive).length;
}

/// Single team member loaded
class TeamMemberDetailLoaded extends TeamState {
  final TeamMember member;

  const TeamMemberDetailLoaded(this.member);

  @override
  List<Object?> get props => [member];
}

/// Team member operation in progress
class TeamMemberOperating extends TeamState {
  final String operation; // 'creating', 'updating', 'deleting'

  const TeamMemberOperating(this.operation);

  @override
  List<Object?> get props => [operation];
}

/// Team member operation succeeded
class TeamMemberOperationSuccess extends TeamState {
  final String message;

  const TeamMemberOperationSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

/// Error occurred
class TeamError extends TeamState {
  final String message;

  const TeamError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Empty state (no team members)
class TeamEmpty extends TeamState {
  final String message;
  final bool isFiltered; // true if empty due to filter, false if database is empty

  const TeamEmpty(this.message, {this.isFiltered = false});

  @override
  List<Object?> get props => [message, isFiltered];
}

// === Hybrid Constraint State Management States ===

/// Constraint manager initialized and ready
class ConstraintManagerInitialized extends TeamState {
  final String teamMemberId;
  final LocalConstraintManager constraintManager;

  const ConstraintManagerInitialized({
    required this.teamMemberId,
    required this.constraintManager,
  });

  @override
  List<Object?> get props => [teamMemberId, constraintManager];
}

/// Constraint conflicts detected during sync
class ConstraintConflictsDetected extends TeamState {
  final String teamMemberId;
  final List<ConstraintConflict> conflicts;

  const ConstraintConflictsDetected({
    required this.teamMemberId,
    required this.conflicts,
  });

  @override
  List<Object?> get props => [teamMemberId, conflicts];
}

/// Constraint operations completed successfully
class ConstraintOperationSuccess extends TeamState {
  final String message;
  final String? teamMemberId;

  const ConstraintOperationSuccess(this.message, {this.teamMemberId});

  @override
  List<Object?> get props => [message, teamMemberId];
}
