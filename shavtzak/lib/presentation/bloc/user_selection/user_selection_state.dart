import 'package:equatable/equatable.dart';
import '../../../domain/entities/team_member.dart';

/// States for User Selection BLoC
abstract class UserSelectionState extends Equatable {
  const UserSelectionState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class UserSelectionInitial extends UserSelectionState {
  const UserSelectionInitial();
}

/// Loading state
class UserSelectionLoading extends UserSelectionState {
  const UserSelectionLoading();
}

/// User is authenticated and loaded
class UserAuthenticated extends UserSelectionState {
  final TeamMember user;
  final bool isAdmin;

  UserAuthenticated(this.user) : isAdmin = user.isAdmin;

  @override
  List<Object?> get props => [user, isAdmin];
}

/// No cached user found, need to show selection
class UserSelectionRequired extends UserSelectionState {
  const UserSelectionRequired();
}

/// Team members loaded for selection
class TeamMembersLoaded extends UserSelectionState {
  final List<TeamMember> teamMembers;
  final String? searchQuery;

  const TeamMembersLoaded(this.teamMembers, {this.searchQuery});

  @override
  List<Object?> get props => [teamMembers, searchQuery];

  /// Get filtered members based on search
  List<TeamMember> get filteredMembers {
    if (searchQuery == null || searchQuery!.isEmpty) {
      return teamMembers;
    }
    final query = searchQuery!.toLowerCase();
    return teamMembers
        .where((m) => m.name.toLowerCase().contains(query))
        .toList();
  }
}

/// Authentication error
class UserSelectionError extends UserSelectionState {
  final String message;

  const UserSelectionError(this.message);

  @override
  List<Object?> get props => [message];
}

/// User successfully signed out
class UserSignedOut extends UserSelectionState {
  const UserSignedOut();
}

/// User selected but validation failed
class UserSelectionValidationError extends UserSelectionState {
  final String message;

  const UserSelectionValidationError(this.message);

  @override
  List<Object?> get props => [message];
}