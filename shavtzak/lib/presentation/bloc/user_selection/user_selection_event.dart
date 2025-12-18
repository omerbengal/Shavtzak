import 'package:equatable/equatable.dart';

/// Events for User Selection BLoC
abstract class UserSelectionEvent extends Equatable {
  const UserSelectionEvent();

  @override
  List<Object?> get props => [];
}

/// Check if user is already cached and authenticate
class CheckCachedUser extends UserSelectionEvent {
  const CheckCachedUser();
}

/// Select a user by unique key
class SelectUser extends UserSelectionEvent {
  final String uniqueKey;

  const SelectUser(this.uniqueKey);

  @override
  List<Object?> get props => [uniqueKey];
}

/// Search team members for user selection
class SearchTeamMembers extends UserSelectionEvent {
  final String query;

  const SearchTeamMembers(this.query);

  @override
  List<Object?> get props => [query];
}

/// Load all team members for selection
class LoadAllTeamMembers extends UserSelectionEvent {
  const LoadAllTeamMembers();
}

/// Sign out current user
class SignOut extends UserSelectionEvent {
  const SignOut();
}

/// Refresh user data
class RefreshUserData extends UserSelectionEvent {
  const RefreshUserData();
}

/// Update user's phone number
class UpdatePhoneNumber extends UserSelectionEvent {
  final String? phoneNumber;

  const UpdatePhoneNumber(this.phoneNumber);

  @override
  List<Object?> get props => [phoneNumber];
}