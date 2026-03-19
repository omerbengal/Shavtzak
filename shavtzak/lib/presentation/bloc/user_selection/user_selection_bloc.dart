import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_selection_repository.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/services/user_cache_service.dart';
import '../../../core/utils/crud_action_result.dart';
import 'user_selection_event.dart';
import 'user_selection_state.dart';
import 'dart:async';
import 'dart:developer' as developer;
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
    on<_AuthenticatedUserUpdated>(_onAuthenticatedUserUpdated);

    if (preAuthenticatedUser != null) {
      unawaited(_startTeamStream());
    }
  }

  @override
  void onChange(Change<UserSelectionState> change) {
    super.onChange(change);
    developer.log(
      'state change: ${change.currentState.runtimeType} -> ${change.nextState.runtimeType}',
      name: 'UserSelectionBloc',
    );
  }

  @override
  Future<void> close() {
    _teamStreamSubscription?.cancel();
    return super.close();
  }

  Future<void> _startTeamStream() async {
    await _teamStreamSubscription?.cancel();
    _teamStreamSubscription = _teamRepository.watchTeamMembers().listen(
      (teamMembers) {
        final currentState = state;
        if (currentState is! UserAuthenticated) {
          return;
        }

        final updatedUser = teamMembers.firstWhere(
          (member) => member.uniqueKey == currentState.user.uniqueKey,
          orElse: () => currentState.user,
        );

        if (_hasAuthRelevantUserChanges(updatedUser, currentState.user)) {
          developer.log(
            'team stream detected user change for ${updatedUser.id} -> emitting UserAuthenticated',
            name: 'UserSelectionBloc',
          );
          add(_AuthenticatedUserUpdated(updatedUser));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'team stream error: $error',
          name: 'UserSelectionBloc',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  Future<void> _onAuthenticatedUserUpdated(
    _AuthenticatedUserUpdated event,
    Emitter<UserSelectionState> emit,
  ) async {
    emit(UserAuthenticated(event.user));
  }

  Future<void> _stopTeamStream() async {
    await _teamStreamSubscription?.cancel();
    _teamStreamSubscription = null;
  }

  bool _hasAuthRelevantUserChanges(TeamMember next, TeamMember current) {
    // Keep settings dialogs in sync with Firestore updates for the
    // authenticated user without requiring a full app restart.
    return next.id != current.id ||
        next.uniqueKey != current.uniqueKey ||
        next.isAdmin != current.isAdmin ||
        next.canAccessSummaryScreen != current.canAccessSummaryScreen ||
        next.canAccessShamapExport != current.canAccessShamapExport ||
        next.canAccessConstraintsExamining !=
            current.canAccessConstraintsExamining ||
        next.isPermanent != current.isPermanent ||
        next.isActive != current.isActive ||
        next.isArchived != current.isArchived ||
        next.passcodeLength != current.passcodeLength ||
        next.name != current.name ||
        next.phoneNumber != current.phoneNumber ||
        next.email != current.email ||
        next.birthday != current.birthday ||
        next.vehicleInfo != current.vehicleInfo;
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
      final isValid = await _userSelectionRepository
          .validateUserSelection(cachedUser.uniqueKey);

      if (isValid) {
        await _startTeamStream();
        emit(UserAuthenticated(cachedUser));
      } else {
        // Cached user is invalid, clear cache and show selection
        await _stopTeamStream();
        await _userSelectionRepository.clearUserSelection();
        emit(const UserSelectionRequired());
      }
    } catch (e) {
      await _stopTeamStream();
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
      final user = await _userSelectionRepository.selectUser(
        event.uniqueKey,
        event.passcode,
      );

      // selectUser already caches user and throws exceptions for invalid users
      await _startTeamStream();
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
      final teamMembers =
          await _userSelectionRepository.searchTeamMembers(event.query);
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
      await _stopTeamStream();
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
      developer.log(
        'RefreshUserData start for user=${currentState.user.id}',
        name: 'UserSelectionBloc',
      );
      try {
        final isValid = await _userSelectionRepository.validateUserSelection(
          currentState.user.uniqueKey,
        );

        if (isValid) {
          // User is still valid, get updated data
          final allMembers = await _userSelectionRepository.getAllTeamMembers();
          final refreshedUser = allMembers
              .where(
                  (member) => member.uniqueKey == currentState.user.uniqueKey)
              .firstOrNull;

          if (refreshedUser != null) {
            developer.log(
              'RefreshUserData emit UserAuthenticated user=${refreshedUser.id}',
              name: 'UserSelectionBloc',
            );
            await _startTeamStream();
            emit(UserAuthenticated(refreshedUser));
          } else {
            // User not found in current members list, clear cache and require reselection
            await _stopTeamStream();
            await _userSelectionRepository.clearUserSelection();
            emit(const UserSelectionRequired());
          }
        } else {
          // User no longer exists, sign out
          await _stopTeamStream();
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
      developer.log(
        'UpdatePhoneNumber requested for user=${currentState.user.id} value="${event.phoneNumber}"',
        name: 'UserSelectionBloc',
      );
      try {
        await _userSelectionRepository.updateTeamMemberPhoneNumber(
          currentState.user.uniqueKey,
          event.phoneNumber,
        );
        _completeActionSuccess(
          event.completion,
          event.phoneNumber == null
              ? 'מספר הטלפון נמחק בהצלחה'
              : 'מספר הטלפון עודכן בהצלחה',
        );
      } catch (e) {
        _completeActionFailure(event.completion, 'שגיאה בעדכון מספר טלפון: $e');
      }
    } else {
      _completeActionFailure(event.completion, 'אין משתמש מחובר');
    }
  }

  /// Update user's birthday
  Future<void> _onUpdateBirthday(
    UpdateBirthday event,
    Emitter<UserSelectionState> emit,
  ) async {
    final currentState = state;

    if (currentState is UserAuthenticated) {
      developer.log(
        'UpdateBirthday requested for user=${currentState.user.id} value=${event.birthday}',
        name: 'UserSelectionBloc',
      );
      try {
        await _userSelectionRepository.updateTeamMemberBirthday(
          currentState.user.uniqueKey,
          event.birthday,
        );
        _completeActionSuccess(
          event.completion,
          event.birthday == null
              ? 'תאריך הלידה נמחק בהצלחה'
              : 'תאריך הלידה עודכן בהצלחה',
        );
      } catch (e) {
        _completeActionFailure(
          event.completion,
          'שגיאה בעדכון תאריך לידה: $e',
        );
      }
    } else {
      _completeActionFailure(event.completion, 'אין משתמש מחובר');
    }
  }

  /// Update user's vehicle information
  Future<void> _onUpdateVehicleInfo(
    UpdateVehicleInfo event,
    Emitter<UserSelectionState> emit,
  ) async {
    final currentState = state;

    if (currentState is UserAuthenticated) {
      developer.log(
        'UpdateVehicleInfo requested for user=${currentState.user.id}',
        name: 'UserSelectionBloc',
      );
      try {
        await _userSelectionRepository.updateTeamMemberVehicleInfo(
          currentState.user.uniqueKey,
          event.vehicleInfo,
        );
        _completeActionSuccess(
          event.completion,
          event.vehicleInfo == null
              ? 'פרטי הרכב נמחקו בהצלחה'
              : 'פרטי הרכב עודכנו בהצלחה',
        );
      } catch (e) {
        _completeActionFailure(
          event.completion,
          'שגיאה בעדכון פרטי רכב: $e',
        );
      }
    } else {
      _completeActionFailure(event.completion, 'אין משתמש מחובר');
    }
  }

  /// Update user's email address
  Future<void> _onUpdateEmail(
    UpdateEmail event,
    Emitter<UserSelectionState> emit,
  ) async {
    final currentState = state;

    if (currentState is UserAuthenticated) {
      developer.log(
        'UpdateEmail requested for user=${currentState.user.id} value="${event.email}"',
        name: 'UserSelectionBloc',
      );
      try {
        final oldEmail = currentState.user.email ?? '';

        await _userSelectionRepository.updateTeamMemberEmail(
          currentState.user.uniqueKey,
          event.email,
        );

        // Dispatch OnTeamMemberEmailChanged to CalendarSyncBloc when email changed.
        // This covers first-time email entry, replacements, and deletions.
        final newEmail = event.email ?? '';
        if (oldEmail != newEmail) {
          _calendarSyncBloc?.add(OnTeamMemberEmailChanged(
            teamMemberId: currentState.user.id,
            oldEmail: oldEmail,
            newEmail: newEmail,
          ));
        }
        _completeActionSuccess(
          event.completion,
          event.email == null
              ? 'כתובת האימייל נמחקה בהצלחה'
              : 'כתובת האימייל עודכנה בהצלחה',
        );
      } catch (e) {
        _completeActionFailure(
          event.completion,
          'שגיאה בעדכון כתובת אימייל: $e',
        );
      }
    } else {
      _completeActionFailure(event.completion, 'אין משתמש מחובר');
    }
  }

  void _completeActionSuccess(
    CrudActionCompleter? completion, [
    String? message,
  ]) {
    completeCrudAction(completion, CrudActionResult.success(message));
  }

  void _completeActionFailure(
    CrudActionCompleter? completion,
    String message,
  ) {
    completeCrudAction(completion, CrudActionResult.failure(message));
  }
}

class _AuthenticatedUserUpdated extends UserSelectionEvent {
  const _AuthenticatedUserUpdated(this.user);

  final TeamMember user;

  @override
  List<Object?> get props => [user];
}
