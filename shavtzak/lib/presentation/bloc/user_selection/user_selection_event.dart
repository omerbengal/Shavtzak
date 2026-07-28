import 'package:equatable/equatable.dart';
import '../../../domain/entities/vehicle_info.dart';
import '../../../core/utils/crud_action_result.dart';

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
  final String passcode;

  const SelectUser(this.uniqueKey, this.passcode);

  @override
  List<Object?> get props => [uniqueKey, passcode];
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

/// The underlying Firebase credential disappeared without the user asking to
/// sign out — a rejected token, or a backend 401 that survived a token refresh.
///
/// Without this the app keeps rendering as if authenticated while every live
/// Firestore listener is dead, so screens silently freeze on their last
/// snapshot and any stream that errors stays broken until a full page reload.
class SessionLost extends UserSelectionEvent {
  const SessionLost();
}

/// Refresh user data
class RefreshUserData extends UserSelectionEvent {
  const RefreshUserData();
}

/// Update user's phone number
class UpdatePhoneNumber extends UserSelectionEvent {
  final String? phoneNumber;
  final CrudActionCompleter? completion;

  const UpdatePhoneNumber(this.phoneNumber, {this.completion});

  @override
  List<Object?> get props => [phoneNumber];
}

/// Update user's birthday
class UpdateBirthday extends UserSelectionEvent {
  final DateTime? birthday;
  final CrudActionCompleter? completion;

  const UpdateBirthday(this.birthday, {this.completion});

  @override
  List<Object?> get props => [birthday];
}

/// Update user's vehicle information
class UpdateVehicleInfo extends UserSelectionEvent {
  final VehicleInfo? vehicleInfo;
  final CrudActionCompleter? completion;

  const UpdateVehicleInfo(this.vehicleInfo, {this.completion});

  @override
  List<Object?> get props => [vehicleInfo];
}

/// Update user's email address
class UpdateEmail extends UserSelectionEvent {
  final String? email;
  final CrudActionCompleter? completion;

  const UpdateEmail(this.email, {this.completion});

  @override
  List<Object?> get props => [email];
}
