import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_selection_repository.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/services/user_cache_service.dart';
import 'user_selection_event.dart';
import 'user_selection_state.dart';
import 'dart:async';
import '../calendar_sync/calendar_sync_bloc.dart';
import '../calendar_sync/calendar_sync_event.dart';

/// BLoC for managing user selection and authentication
class UserSelectionBloc extends Bloc<UserSelectionEvent, UserSelectionState> {
  final UserSelectionRepository _userSelectionRepository;
  final TeamRepository _teamRepository;
  final CalendarSyncBloc? _calendarSyncBloc;
  StreamSubscription? _teamStreamSubscription;

  UserSelectionBloc(
    this._userSelectionRepository,
    this._teamRepository,
    this._calendarSyncBloc, [
    TeamMember? preAuthenticatedUser,
  ]) : super(preAuthenticatedUser != null
      ? UserAuthenticated(preAuthenticatedUser)
      : const UserSelectionInitial()) {

    on<CheckCachedUser>(_onCheckCachedUser);
    on<SelectUser>(_onSelectUser);
    on<SearchTeamMembers>(_onSearchTeamMembers);
    on<LoadAllTeamMembers>(_onLoadAllTeamMembers);
    on<SignOut>(_onSignOut);
    on<RefreshUserData>(_onRefreshUserData);
    on<UpdatePhoneNumber>(_onUpdatePhoneNumber);
    on<UpdateBirthday>(_onUpdateBirthday);
    on<UpdateVehicleInfo>(_onUpdateVehicleInfo);
    on<UpdateEmail>(_onUpdateEmail);

    // Listen to team member changes and refresh current user if needed
    _teamStreamSubscription = _teamRepository.watchTeamMembers().listen((teamMembers) {
      final currentState = state;
      if (currentState is UserAuthenticated) {
        // Find if current user was updated
        final updatedUser = teamMembers.firstWhere(
          (member) => member.uniqueKey == currentState.user.uniqueKey,
          orElse: () => currentState.user,
        );

        // Check if any user data changed
        if (updatedUser != currentState.user) {
          emit(UserAuthenticated(updatedUser));
        }
      }
    });
  }

  @override
  Future<void> close() {
    _teamStreamSubscription?.cancel();
    return super.close();
  }

  /// Check if user is already cached and authenticate them
  Future<void> _onCheckCachedUser(
    CheckCachedUser event,
    Emitter<UserSelectionState> emit,
  ) async {
    emit(const UserSelectionLoading());

    try {
      final cachedUser = await _userSelectionRepository.getCachedUser();

      if (cachedUser == null) {
        emit(const UserSelectionRequired());
        return;
      }

      // Validate cached user exists and is valid
      final isValid = await _userSelectionRepository.validateUserSelection(cachedUser.uniqueKey);

      if (isValid) {
        emit(UserAuthenticated(cachedUser));
      } else {
        // Cached user is invalid, clear cache and show selection
        await _userSelectionRepository.clearUserSelection();
        emit(const UserSelectionRequired());
      }
    } catch (e) {
      emit(UserSelectionError('שגיאה בבדיקת משתמש מקומי: $e'));
    }
  }

  /// Select a user by unique key
  Future<void> _onSelectUser(
    SelectUser event,
    Emitter<UserSelectionState> emit,
  ) async {
    emit(const UserSelectionLoading());

    try {
      final user = await _userSelectionRepository.selectUser(event.uniqueKey);

      // selectUser already caches user and throws exceptions for invalid users
      emit(UserAuthenticated(user));
    } catch (e) {
      emit(UserSelectionValidationError('שגיאה בבחירת משתמש: $e'));
    }
  }

  /// Search team members for user selection
  Future<void> _onSearchTeamMembers(
    SearchTeamMembers event,
    Emitter<UserSelectionState> emit,
  ) async {
    try {
      final teamMembers = await _userSelectionRepository.searchTeamMembers(event.query);
      emit(TeamMembersLoaded(teamMembers, searchQuery: event.query));
    } catch (e) {
      emit(UserSelectionError('שגיאה בחיפוש חברי צוות: $e'));
    }
  }

  /// Load all team members for selection
  Future<void> _onLoadAllTeamMembers(
    LoadAllTeamMembers event,
    Emitter<UserSelectionState> emit,
  ) async {
    emit(const UserSelectionLoading());

    try {
      final teamMembers = await _userSelectionRepository.getAllTeamMembers();
      emit(TeamMembersLoaded(teamMembers));
    } catch (e) {
      emit(UserSelectionError('שגיאה בטעינת חברי צוות: $e'));
    }
  }

  /// Sign out current user
  Future<void> _onSignOut(
    SignOut event,
    Emitter<UserSelectionState> emit,
  ) async {
    try {
      await _userSelectionRepository.clearUserSelection();
      UserCacheService().clearPasscodeDialogFlag();
      emit(const UserSignedOut());
    } catch (e) {
      emit(UserSelectionError('שגיאה בהתנתקות: $e'));
    }
  }

  /// Refresh current user data
  Future<void> _onRefreshUserData(
    RefreshUserData event,
    Emitter<UserSelectionState> emit,
  ) async {
    final currentState = state;

    if (currentState is UserAuthenticated) {
      try {
        final isValid = await _userSelectionRepository.validateUserSelection(
          currentState.user.uniqueKey,
        );

        if (isValid) {
          // User is still valid, get updated data
          final allMembers = await _userSelectionRepository.getAllTeamMembers();
          final refreshedUser = allMembers
              .where((member) => member.uniqueKey == currentState.user.uniqueKey)
              .firstOrNull;

          if (refreshedUser != null) {
            emit(UserAuthenticated(refreshedUser));
          } else {
            // User not found in current members list, clear cache and require reselection
            await _userSelectionRepository.clearUserSelection();
            emit(const UserSelectionRequired());
          }
        } else {
          // User no longer exists, sign out
          await _userSelectionRepository.clearUserSelection();
          emit(const UserSelectionRequired());
        }
      } catch (e) {
        emit(UserSelectionError('שגיאה ברענון נתוני משתמש: $e'));
      }
    }
  }

  /// Update user's phone number
  Future<void> _onUpdatePhoneNumber(
    UpdatePhoneNumber event,
    Emitter<UserSelectionState> emit,
  ) async {
    final currentState = state;

    if (currentState is UserAuthenticated) {
      try {
        await _userSelectionRepository.updateTeamMemberPhoneNumber(
          currentState.user.uniqueKey,
          event.phoneNumber,
        );

        // Refresh user data to get the updated phone number
        add(const RefreshUserData());
      } catch (e) {
        emit(UserSelectionError('שגיאה בעדכון מספר טלפון: $e'));
      }
    }
  }

  /// Update user's birthday
  Future<void> _onUpdateBirthday(
    UpdateBirthday event,
    Emitter<UserSelectionState> emit,
  ) async {
    final currentState = state;

    if (currentState is UserAuthenticated) {
      try {
        await _userSelectionRepository.updateTeamMemberBirthday(
          currentState.user.uniqueKey,
          event.birthday,
        );

        // Refresh user data to get the updated birthday
        add(const RefreshUserData());
      } catch (e) {
        emit(UserSelectionError('שגיאה בעדכון תאריך לידה: $e'));
      }
    }
  }

  /// Update user's vehicle information
  Future<void> _onUpdateVehicleInfo(
    UpdateVehicleInfo event,
    Emitter<UserSelectionState> emit,
  ) async {
    final currentState = state;

    if (currentState is UserAuthenticated) {
      try {
        await _userSelectionRepository.updateTeamMemberVehicleInfo(
          currentState.user.uniqueKey,
          event.vehicleInfo,
        );

        // Refresh user data to get the updated vehicle info
        add(const RefreshUserData());
      } catch (e) {
        emit(UserSelectionError('שגיאה בעדכון פרטי רכב: $e'));
      }
    }
  }

  /// Update user's email address
  Future<void> _onUpdateEmail(
    UpdateEmail event,
    Emitter<UserSelectionState> emit,
  ) async {
    final currentState = state;

    if (currentState is UserAuthenticated) {
      try {
        final oldEmail = currentState.user.email ?? '';

        await _userSelectionRepository.updateTeamMemberEmail(
          currentState.user.uniqueKey,
          event.email,
        );

        // Refresh user data to get updated email
        add(const RefreshUserData());

        // Dispatch OnTeamMemberEmailChanged to CalendarSyncBloc
        // This will trigger calendar invite updates for future events
        if (oldEmail != null && oldEmail.isNotEmpty && event.email != null && event.email!.isNotEmpty) {
          _calendarSyncBloc?.add(OnTeamMemberEmailChanged(
            teamMemberId: currentState.user.id,
            oldEmail: oldEmail,
            newEmail: event.email!,
          ));
        }
      } catch (e) {
        emit(UserSelectionError('שגיאה בעדכון כתובת אימייל: $e'));
      }
    }
  }
}
