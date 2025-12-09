import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/constants/constraint_status.dart';
import '../../../core/state/constraint_manager.dart';
import '../../../core/services/environment_service.dart';
import 'team_event.dart';
import 'team_state.dart';
import 'dart:developer' as developer;

/// BLoC for managing team members
class TeamBloc extends Bloc<TeamEvent, TeamState> {
  final TeamRepository _repository;
  final AssignmentRepository _assignmentRepository;

  // Store constraint managers for each team member
  final Map<String, LocalConstraintManager> _constraintManagers = {};

  TeamBloc(this._repository, this._assignmentRepository) : super(const TeamInitial()) {
    // Register event handlers - using emit.forEach for real-time updates
    on<LoadTeamMembers>(_onLoadTeamMembers);
    on<LoadActiveTeamMembers>(_onLoadActiveTeamMembers);
    on<SearchTeamMembers>(_onSearchTeamMembers);
    on<LoadTeamMemberById>(_onLoadTeamMemberById);
    on<CreateTeamMember>(_onCreateTeamMember);
    on<UpdateTeamMember>(_onUpdateTeamMember);
    on<DeleteTeamMember>(_onDeleteTeamMember);
    on<DeactivateTeamMember>(_onDeactivateTeamMember);
    on<ReactivateTeamMember>(_onReactivateTeamMember);
    on<RefreshTeamMembers>(_onRefreshTeamMembers);
    on<UpdateConstraintStatus>(_onUpdateConstraintStatus);
    on<AddConstraintRequest>(_onAddConstraintRequest);
    on<RemoveConstraintRequest>(_onRemoveConstraintRequest);

    // Hybrid constraint state management events
    on<InitializeConstraintManager>(_onInitializeConstraintManager);
    on<UpdateConstraintStatusLocal>(_onUpdateConstraintStatusLocal);
    on<AddConstraintLocal>(_onAddConstraintLocal);
    on<RemoveConstraintLocal>(_onRemoveConstraintLocal);
    on<SyncConstraintsWithDatabase>(_onSyncConstraintsWithDatabase);
    on<SavePendingConstraintChanges>(_onSavePendingConstraintChanges);
    on<ClearLocalConstraintState>(_onClearLocalConstraintState);

    // State management
    on<ClearTeamState>(_onClearTeamState);
  }

  /// Load all team members with real-time updates
  Future<void> _onLoadTeamMembers(
    LoadTeamMembers event,
    Emitter<TeamState> emit,
  ) async {
    developer.log('TeamBloc._onLoadTeamMembers: Starting to load team members', name: 'TeamBloc');
    final currentEnv = EnvironmentService.instance.isTestMode ? 'TEST' : 'PROD';
    developer.log('TeamBloc._onLoadTeamMembers: Current environment is $currentEnv', name: 'TeamBloc');

    emit(const TeamLoading());

    try {
      // Use emit.forEach to subscribe to real-time stream
      await emit.forEach<List<TeamMember>>(
        _repository.watchTeamMembers(),
        onData: (members) {
          developer.log('TeamBloc._onLoadTeamMembers: Received ${members.length} team members', name: 'TeamBloc');
          if (members.isEmpty) {
            return const TeamEmpty('אין חברי צוות במערכת');
          } else {
            return TeamLoaded(members);
          }
        },
        onError: (error, stackTrace) {
          developer.log('TeamBloc._onLoadTeamMembers: Error - $error', name: 'TeamBloc', error: error, stackTrace: stackTrace);
          return TeamError('שגיאה בטעינת חברי הצוות: $error');
        },
      );
    } catch (e) {
      developer.log('TeamBloc._onLoadTeamMembers: Exception - $e', name: 'TeamBloc', error: e);
      emit(TeamError('שגיאה בטעינת חברי הצוות: $e'));
    }
  }

  /// Load active team members only (with real-time updates)
  Future<void> _onLoadActiveTeamMembers(
    LoadActiveTeamMembers event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamLoading());

    try {
      // Use emit.forEach to subscribe to real-time stream
      await emit.forEach<List<TeamMember>>(
        _repository.watchTeamMembers(),
        onData: (allMembers) {
          // Filter for active members only
          final activeMembers = allMembers.where((m) => m.isActive).toList();

          if (activeMembers.isEmpty) {
            // Check if database is truly empty or just filtered empty
            final isFiltered = allMembers.isNotEmpty;
            return TeamEmpty('אין חברי צוות פעילים', isFiltered: isFiltered);
          } else {
            return TeamLoaded(activeMembers);
          }
        },
        onError: (error, stackTrace) {
          return TeamError('שגיאה בטעינת חברי הצוות: $error');
        },
      );
    } catch (e) {
      emit(TeamError('שגיאה בטעינת חברי הצוות: $e'));
    }
  }

  /// Search team members
  Future<void> _onSearchTeamMembers(
    SearchTeamMembers event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamLoading());

    try {
      final members = await _repository.searchTeamMembers(event.query);

      if (members.isEmpty) {
        emit(const TeamEmpty('לא נמצאו חברי צוות'));
      } else {
        emit(TeamLoaded(members, searchQuery: event.query));
      }
    } catch (e) {
      emit(TeamError('שגיאה בחיפוש: $e'));
    }
  }

  /// Load team member by ID
  Future<void> _onLoadTeamMemberById(
    LoadTeamMemberById event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamLoading());

    try {
      final member = await _repository.getTeamMemberById(event.id);

      if (member == null) {
        emit(TeamError('חבר/ת צוות לא נמצא/ה'));
      } else {
        emit(TeamMemberDetailLoaded(member));
      }
    } catch (e) {
      emit(TeamError('שגיאה בטעינת פרטי חבר/ת הצוות: $e'));
    }
  }

  /// Create new team member
  Future<void> _onCreateTeamMember(
    CreateTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Don't emit TeamMemberOperating to avoid UI rebuild
      await _repository.createTeamMember(event.member);

      // NOTE: We don't emit TeamMemberOperationSuccess here to avoid UI state issues
      // The real-time stream from emit.forEach will automatically update the UI
      // If a success message is needed, the UI layer should handle it

    } catch (e) {
      emit(TeamError('שגיאה בהוספת חבר/ת צוות: $e'));
    }
  }

  /// Update team member
  Future<void> _onUpdateTeamMember(
    UpdateTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Don't emit TeamMemberOperating to avoid UI rebuild
      // Get the old member data to check for removed capabilities
      final oldMember = await _repository.getTeamMemberById(event.member.id);

      // Update the team member
      await _repository.updateTeamMember(event.member);

      // Check if any role capabilities were removed
      if (oldMember != null) {
        final removedRoles = <String>[];

        // Find roles that were removed (were true, now false or missing)
        for (final entry in oldMember.roleCapabilities.entries) {
          final oldValue = entry.value;
          final newValue = event.member.roleCapabilities[entry.key] ?? false;

          if (oldValue && !newValue) {
            removedRoles.add(entry.key.name);
          }
        }

        // Delete assignments for removed roles
        if (removedRoles.isNotEmpty) {
          final assignments = await _assignmentRepository.getAssignmentsByPerson(event.member.id);

          for (final assignment in assignments) {
            if (removedRoles.contains(assignment.roleType.name)) {
              await _assignmentRepository.deleteAssignment(assignment.id);
            }
          }
        }
      }

      // Emit success to show snackbar, UI will keep showing last state
      emit(const TeamMemberOperationSuccess('בקשת מגבלה עודכנה בהצלחה וממתינה לאישור'));

      // Restart stream subscription to pick up database changes
      emit(const TeamLoading());

      await emit.forEach<List<TeamMember>>(
        _repository.watchTeamMembers(),
        onData: (members) {
          if (members.isEmpty) {
            return const TeamEmpty('אין חברי צוות במערכת');
          } else {
            return TeamLoaded(members);
          }
        },
        onError: (error, stackTrace) {
          return TeamError('שגיאה בטעינת חברי הצוות: $error');
        },
      );
    } catch (e) {
      emit(TeamError('שגיאה בעדכון פרטי חבר/ת הצוות: $e'));
    }
  }

  /// Delete team member
  Future<void> _onDeleteTeamMember(
    DeleteTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Don't emit TeamMemberOperating to avoid UI rebuild
      await _repository.deleteTeamMember(event.id);

      // NOTE: We don't emit TeamMemberOperationSuccess here to avoid UI state issues
      // The real-time stream from emit.forEach will automatically update the UI
      // If a success message is needed, the UI layer should handle it

    } catch (e) {
      emit(TeamError('שגיאה במחיקת חבר/ת הצוות: $e'));
    }
  }

  /// Deactivate team member
  Future<void> _onDeactivateTeamMember(
    DeactivateTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Don't emit TeamMemberOperating to avoid UI rebuild
      await _repository.deactivateTeamMember(event.id);

      // NOTE: We don't emit TeamMemberOperationSuccess here to avoid UI state issues
      // The real-time stream from emit.forEach will automatically update the UI
      // If a success message is needed, the UI layer should handle it
    } catch (e) {
      emit(TeamError('שגיאה בהסרת חבר/ת הצוות: $e'));
    }
  }

  /// Reactivate team member
  Future<void> _onReactivateTeamMember(
    ReactivateTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Don't emit TeamMemberOperating to avoid UI rebuild
      await _repository.reactivateTeamMember(event.id);

      // NOTE: We don't emit TeamMemberOperationSuccess here to avoid UI state issues
      // The real-time stream from emit.forEach will automatically update the UI
      // If a success message is needed, the UI layer should handle it
    } catch (e) {
      emit(TeamError('שגיאה בהפעלת חבר/ת הצוות: $e'));
    }
  }

  /// Refresh team members
  Future<void> _onRefreshTeamMembers(
    RefreshTeamMembers event,
    Emitter<TeamState> emit,
  ) async {
    // Simply reload
    add(const LoadTeamMembers());
  }

  /// Update constraint status
  Future<void> _onUpdateConstraintStatus(
    UpdateConstraintStatus event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Use the repository's database to update constraint status
      await _repository.database.updateConstraintStatus(
        event.teamMemberId,
        event.constraintIndex,
        event.newStatus,
      );

      // Emit success message
      final statusText = event.newStatus.hebrewName;
      emit(TeamMemberOperationSuccess('סטטוס המגבלה עודכן ל$statusText בהצלחה'));
    } catch (e) {
      emit(TeamError('שגיאה בעדכון סטטוס המגבלה: $e'));
    }
  }

  /// Add constraint request
  Future<void> _onAddConstraintRequest(
    AddConstraintRequest event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Get the current team member
      final currentMember = await _repository.getTeamMemberById(event.teamMemberId);
      if (currentMember == null) {
        emit(const TeamError('חבר/ת צוות לא נמצא/ה'));
        return;
      }

      // Create new constraint with pending status
      // If endDate is null, set it to startDate (single-day constraint)
      final DateTime effectiveEndDate = event.endDate ?? event.startDate;

      final newConstraint = DateConstraint(
        id: const Uuid().v4(), // Generate unique ID for new constraint
        startDate: event.startDate,
        endDate: effectiveEndDate,
        note: event.note,
        status: ConstraintStatus.pending,
        constraintType: ConstraintType.unavailability, // For permanent members
      );

      // Add to constraints list
      final updatedConstraints = List<DateConstraint>.from(currentMember.constraints);
      updatedConstraints.add(newConstraint);

      // Update team member
      final updatedMember = currentMember.copyWith(
        constraints: updatedConstraints,
        updatedAt: DateTime.now(),
      );

      await _repository.updateTeamMember(updatedMember);

      emit(const TeamMemberOperationSuccess('בקשת מגבלה נוספה בהצלחה וממתינה לאישור'));

      // Restart stream subscription to pick up database changes
      emit(const TeamLoading());

      await emit.forEach<List<TeamMember>>(
        _repository.watchTeamMembers(),
        onData: (members) {
          if (members.isEmpty) {
            return const TeamEmpty('אין חברי צוות במערכת');
          } else {
            return TeamLoaded(members);
          }
        },
        onError: (error, stackTrace) {
          return TeamError('שגיאה בטעינת חברי הצוות: $error');
        },
      );
    } catch (e) {
      emit(TeamError('שגיאה בהוספת בקשת מגבלה: $e'));
    }
  }

  /// Remove constraint request
  Future<void> _onRemoveConstraintRequest(
    RemoveConstraintRequest event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Get the current team member
      final currentMember = await _repository.getTeamMemberById(event.teamMemberId);
      if (currentMember == null) {
        emit(const TeamError('חבר/ת צוות לא נמצא/ה'));
        return;
      }

      // Check if constraint index is valid
      if (event.constraintIndex < 0 || event.constraintIndex >= currentMember.constraints.length) {
        emit(const TeamError('אינדקס מגבלה לא תקין'));
        return;
      }

      // Remove constraint (users can delete their own constraints regardless of status)
      final updatedConstraints = List<DateConstraint>.from(currentMember.constraints);
      updatedConstraints.removeAt(event.constraintIndex);

      // Update team member
      final updatedMember = currentMember.copyWith(
        constraints: updatedConstraints,
        updatedAt: DateTime.now(),
      );

      await _repository.updateTeamMember(updatedMember);

      emit(const TeamMemberOperationSuccess('בקשת מגבלה נמחקה בהצלחה'));

      // Restart stream subscription to pick up database changes
      emit(const TeamLoading());

      await emit.forEach<List<TeamMember>>(
        _repository.watchTeamMembers(),
        onData: (members) {
          if (members.isEmpty) {
            return const TeamEmpty('אין חברי צוות במערכת');
          } else {
            return TeamLoaded(members);
          }
        },
        onError: (error, stackTrace) {
          return TeamError('שגיאה בטעינת חברי הצוות: $error');
        },
      );
    } catch (e) {
      emit(TeamError('שגיאה במחיקת בקשת מגבלה: $e'));
    }
  }

  /// Helper method to check if two dates are the same day
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  // === Hybrid Constraint State Management Event Handlers ===

  /// Initialize constraint manager for a team member
  Future<void> _onInitializeConstraintManager(
    InitializeConstraintManager event,
    Emitter<TeamState> emit,
  ) async {
    try {
      final constraintManager = LocalConstraintManager();
      constraintManager.initializeFromDatabase(event.databaseConstraints);

      _constraintManagers[event.teamMemberId] = constraintManager;

      emit(ConstraintManagerInitialized(
        teamMemberId: event.teamMemberId,
        constraintManager: constraintManager,
      ));
    } catch (e) {
      emit(TeamError('שגיאה באתחול מנהל מגבלות: $e'));
    }
  }

  /// Update constraint status locally (immediate UI update)
  Future<void> _onUpdateConstraintStatusLocal(
    UpdateConstraintStatusLocal event,
    Emitter<TeamState> emit,
  ) async {
    try {
      final constraintManager = _constraintManagers[event.teamMemberId];
      if (constraintManager == null) {
        emit(TeamError('מנהל מגבלות לא אותחל עבור חבר הצוות'));
        return;
      }

      constraintManager.updateConstraintStatus(event.constraintId, event.newStatus);

      emit(ConstraintOperationSuccess(
        'סטטוס מגבלה עודכן במקומי',
        teamMemberId: event.teamMemberId,
      ));
    } catch (e) {
      emit(TeamError('שגיאה בעדכון סטטוס מגבלה: $e'));
    }
  }

  /// Add new constraint locally (immediate UI update)
  Future<void> _onAddConstraintLocal(
    AddConstraintLocal event,
    Emitter<TeamState> emit,
  ) async {
    try {
      final constraintManager = _constraintManagers[event.teamMemberId];
      if (constraintManager == null) {
        emit(TeamError('מנהל מגבלות לא אותחל עבור חבר הצוות'));
        return;
      }

      final newConstraint = DateConstraint(
        id: const Uuid().v4(), // Generate unique ID for new local constraint
        startDate: event.startDate,
        endDate: event.endDate,
        note: event.note,
        status: event.status,
        constraintType: ConstraintType.unavailability, // For permanent members
      );

      constraintManager.addConstraintLocally(newConstraint);

      emit(ConstraintOperationSuccess(
        'מגבלה חדשה נוספה במקומי',
        teamMemberId: event.teamMemberId,
      ));
    } catch (e) {
      emit(TeamError('שגיאה בהוספת מגבלה: $e'));
    }
  }

  /// Remove constraint locally (immediate UI update)
  Future<void> _onRemoveConstraintLocal(
    RemoveConstraintLocal event,
    Emitter<TeamState> emit,
  ) async {
    try {
      final constraintManager = _constraintManagers[event.teamMemberId];
      if (constraintManager == null) {
        emit(TeamError('מנהל מגבלות לא אותחל עבור חבר הצוות'));
        return;
      }

      constraintManager.deleteConstraint(event.constraintId, isLocalId: event.isLocalId);

      emit(ConstraintOperationSuccess(
        'מגבלה הוסרה במקומי',
        teamMemberId: event.teamMemberId,
      ));
    } catch (e) {
      emit(TeamError('שגיאה בהסרת מגבלה: $e'));
    }
  }

  /// Sync constraint manager with database changes and detect conflicts
  Future<void> _onSyncConstraintsWithDatabase(
    SyncConstraintsWithDatabase event,
    Emitter<TeamState> emit,
  ) async {
    try {
      final constraintManager = _constraintManagers[event.teamMemberId];
      if (constraintManager == null) {
        emit(TeamError('מנהל מגבלות לא אותחל עבור חבר הצוות'));
        return;
      }

      final conflicts = constraintManager.syncWithDatabaseChanges(event.remoteConstraints);

      if (conflicts.isNotEmpty) {
        emit(ConstraintConflictsDetected(
          teamMemberId: event.teamMemberId,
          conflicts: conflicts,
        ));
      } else {
        emit(ConstraintOperationSuccess(
          'סנכרון מגבלות הושלם',
          teamMemberId: event.teamMemberId,
        ));
      }
    } catch (e) {
      emit(TeamError('שגיאה בסנכרון מגבלות: $e'));
    }
  }

  /// Save all pending constraint changes to database
  Future<void> _onSavePendingConstraintChanges(
    SavePendingConstraintChanges event,
    Emitter<TeamState> emit,
  ) async {
    try {
      final constraintManager = _constraintManagers[event.teamMemberId];
      if (constraintManager == null) {
        emit(TeamError('מנהל מגבלות לא אותחל עבור חבר הצוות'));
        return;
      }

      // Get current team member data
      final currentState = state;
      if (currentState is! TeamLoaded) {
        emit(TeamError('נתוני צוות לא זמינים'));
        return;
      }

      final currentMember = currentState.members.firstWhere(
        (member) => member.id == event.teamMemberId,
        orElse: () => throw Exception('חבר צוות לא נמצא'),
      );

      // Get effective constraints from manager
      final effectiveConstraints = constraintManager.getEffectiveConstraints();

      // Update team member with new constraints
      final updatedMember = currentMember.copyWith(
        constraints: effectiveConstraints,
        updatedAt: DateTime.now(),
      );

      await _repository.updateTeamMember(updatedMember);

      emit(ConstraintOperationSuccess(
        'שינויי מגבלות נשמרו בהצלחה',
        teamMemberId: event.teamMemberId,
      ));
    } catch (e) {
      emit(TeamError('שגיאה בשמירת שינויי מגבלות: $e'));
    }
  }

  /// Clear local constraint state (discard changes)
  Future<void> _onClearLocalConstraintState(
    ClearLocalConstraintState event,
    Emitter<TeamState> emit,
  ) async {
    try {
      final constraintManager = _constraintManagers[event.teamMemberId];
      if (constraintManager == null) {
        emit(TeamError('מנהל מגבלות לא אותחל עבור חבר הצוות'));
        return;
      }

      constraintManager.clearLocalState();

      emit(ConstraintOperationSuccess(
        'שינויים מקומיים בוטלו',
        teamMemberId: event.teamMemberId,
      ));
    } catch (e) {
      emit(TeamError('שגיאה בניקוי שינויים מקומיים: $e'));
    }
  }

  /// Clear all state (used when user signs out)
  Future<void> _onClearTeamState(
    ClearTeamState event,
    Emitter<TeamState> emit,
  ) async {
    // Clear constraint managers
    _constraintManagers.clear();
    // Reset to initial state
    emit(const TeamInitial());
  }

  @override
  Future<void> close() {
    // Clear constraint managers
    _constraintManagers.clear();
    return super.close();
  }
}
