import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/constants/constraint_status.dart';
import '../../../core/state/constraint_manager.dart';
import '../../../core/services/environment_service.dart';
import '../calendar_sync/calendar_sync_bloc.dart';
import '../calendar_sync/calendar_sync_event.dart';
import 'team_event.dart';
import 'team_state.dart';
import 'dart:developer' as developer;

/// BLoC for managing team members
class TeamBloc extends Bloc<TeamEvent, TeamState> {
  final TeamRepository _repository;
  final AssignmentRepository _assignmentRepository;
  final CalendarSyncBloc? _calendarSyncBloc;

  // Stream subscription for manual control to prevent memory leaks
  StreamSubscription<List<TeamMember>>? _teamSubscription;

  // Store constraint managers for each team member
  final Map<String, LocalConstraintManager> _constraintManagers = {};

  TeamBloc(
    this._repository,
    this._assignmentRepository, {
    CalendarSyncBloc? calendarSyncBloc,
  })  : _calendarSyncBloc = calendarSyncBloc,
        super(const TeamInitial()) {
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
    on<EditConstraintRequest>(_onEditConstraintRequest);

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

    // Internal event for stream updates
    on<_TeamMembersUpdated>(_onTeamMembersUpdated);
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
      // Cancel previous subscription before starting new one to prevent memory leaks
      await _teamSubscription?.cancel();

      // Use explicit subscription management instead of emit.forEach
      _teamSubscription = _repository.watchTeamMembers().listen(
        (members) {
          developer.log('TeamBloc._onLoadTeamMembers: Received ${members.length} team members', name: 'TeamBloc');
          add(_TeamMembersUpdated(members, activeOnly: false));
        },
        onError: (error, stackTrace) {
          developer.log('TeamBloc._onLoadTeamMembers: Error - $error', name: 'TeamBloc', error: error, stackTrace: stackTrace);
          add(_TeamMembersUpdated(const [], activeOnly: false));
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
      // Cancel previous subscription before starting new one to prevent memory leaks
      await _teamSubscription?.cancel();

      // Use explicit subscription management instead of emit.forEach
      _teamSubscription = _repository.watchTeamMembers().listen(
        (allMembers) {
          add(_TeamMembersUpdated(allMembers, activeOnly: true));
        },
        onError: (error, stackTrace) {
          add(_TeamMembersUpdated(const [], activeOnly: true));
        },
      );
    } catch (e) {
      emit(TeamError('שגיאה בטעינת חברי הצוות: $e'));
    }
  }

  /// Handle stream updates - this is the single place where stream data is processed
  Future<void> _onTeamMembersUpdated(
    _TeamMembersUpdated event,
    Emitter<TeamState> emit,
  ) async {
    final members = event.members;

    if (event.activeOnly) {
      // Filter for active members only
      final activeMembers = members.where((m) => m.isActive).toList();

      if (activeMembers.isEmpty) {
        // Check if database is truly empty or just filtered empty
        final isFiltered = members.isNotEmpty;
        emit(TeamEmpty('אין חברי צוות פעילים', isFiltered: isFiltered));
      } else {
        emit(TeamLoaded(activeMembers));
      }
    } else {
      if (members.isEmpty) {
        emit(const TeamEmpty('אין חברי צוות במערכת'));
      } else {
        emit(TeamLoaded(members));
      }
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
      // Emit success to show snackbar, UI will keep showing last state
      emit(const TeamMemberOperationSuccess('חבר/ת הצוות נוסף/ה בהצלחה'));

      // Don't restart listener here - the modal will handle it with the correct filter
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
            removedRoles.add(entry.key);
          }
        }

        // Delete assignments for removed roles
        if (removedRoles.isNotEmpty) {
          final assignments = await _assignmentRepository.getAssignmentsByPerson(event.member.id);

          for (final assignment in assignments) {
            if (removedRoles.contains(assignment.roleType)) {
              await _assignmentRepository.deleteAssignment(assignment.id);
            }
          }
        }

        // === Calendar Sync: Check for constraint status changes ===

        if (_calendarSyncBloc != null) {
          // Build a map of old constraints by ID for easy lookup
          final oldConstraintsById = <String, DateConstraint>{};
          for (final constraint in oldMember.constraints) {
            oldConstraintsById[constraint.id] = constraint;
          }

          // Check each new constraint for status changes
          for (final newConstraint in event.member.constraints) {
            final oldConstraint = oldConstraintsById[newConstraint.id];

            if (oldConstraint != null) {
              // Existing constraint - check for status change
              if (oldConstraint.status != newConstraint.status) {

                if (newConstraint.status == ConstraintStatus.approved) {
                  // Constraint changed to approved - sync to calendar ONLY for unavailability constraints
                  if (newConstraint.isUnavailability) {
                    developer.log(
                      'TeamBloc: Unavailability constraint approved via UpdateTeamMember, triggering calendar sync',
                      name: 'TeamBloc',
                    );
                    _calendarSyncBloc?.add(SyncConstraintToCalendar(
                      constraintId: newConstraint.id,
                      teamMember: event.member,
                      constraint: newConstraint,
                    ));
                  }
                } else if (oldConstraint.status == ConstraintStatus.approved) {
                  // Constraint changed from approved - remove from calendar ONLY if it was unavailability
                  if (oldConstraint.isUnavailability) {
                    developer.log(
                      'TeamBloc: Unavailability constraint un-approved via UpdateTeamMember, removing from calendar',
                      name: 'TeamBloc',
                    );
                    _calendarSyncBloc?.add(RemoveConstraintFromCalendar(
                      constraintId: newConstraint.id,
                    ));
                  }
                }
              }
            }
            // Note: New constraints don't need sync yet - they start as pending
          }

          // Check for deleted constraints that were approved
          for (final oldConstraint in oldMember.constraints) {
            final stillExists = event.member.constraints.any((c) => c.id == oldConstraint.id);
            if (!stillExists && oldConstraint.status == ConstraintStatus.approved) {
              // Only remove from calendar if it was an unavailability constraint
              if (oldConstraint.isUnavailability) {
                developer.log(
                  'TeamBloc: Approved unavailability constraint deleted via UpdateTeamMember, removing from calendar',
                  name: 'TeamBloc',
                );
                _calendarSyncBloc?.add(RemoveConstraintFromCalendar(
                  constraintId: oldConstraint.id,
                ));
              }
            }
          }
        } else {
        }
      }

      // Explicitly reload ALL members to ensure the archive dialog updates in real-time
      // This includes both archived and non-archived members
      final allMembers = await _repository.getAllTeamMembers();

      // Emit TeamLoaded state with ALL members to trigger BlocBuilder rebuilds
      final searchQuery = state is TeamLoaded ? (state as TeamLoaded).searchQuery : null;
      emit(TeamLoaded(allMembers, searchQuery: searchQuery));

      // Note: We don't emit TeamMemberOperationSuccess here because it would change the state type
      // from TeamLoaded, causing the archive dialog (which checks 'state is TeamLoaded') to show empty.
      // The stream listener will emit additional updates as needed.
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
      // Emit success to show snackbar, UI will keep showing last state
      emit(const TeamMemberOperationSuccess('חבר/ת הצוות נמחק/ה בהצלחה'));

      // Don't restart listener here - the modal/screen will handle it with the correct filter
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
      emit(const TeamMemberOperationSuccess('חבר/ת הצוות הוסר/ה בהצלחה'));

      // Don't restart listener here - the screen will handle it with the correct filter
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
      emit(const TeamMemberOperationSuccess('חבר/ת הצוות הופעל/ה בהצלחה'));

      // Don't restart listener here - the screen will handle it with the correct filter
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
      // Get the current team member to check old status
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

      // Get the old status before updating
      final constraint = currentMember.constraints[event.constraintIndex];
      final oldStatus = constraint.status;

      // Use the repository's database to update constraint status
      await _repository.database.updateConstraintStatus(
        event.teamMemberId,
        event.constraintIndex,
        event.newStatus,
      );

      // Trigger calendar sync if status changed to/from approved

      if (_calendarSyncBloc != null && oldStatus != event.newStatus) {
        if (event.newStatus == ConstraintStatus.approved) {
          // Status changed to approved - sync to calendar ONLY for unavailability constraints
          if (constraint.isUnavailability) {
            developer.log(
              'TeamBloc: Unavailability constraint approved, triggering calendar sync',
              name: 'TeamBloc',
            );
            _calendarSyncBloc!.add(SyncConstraintToCalendar(
              constraintId: constraint.id,
              teamMember: currentMember,
              constraint: constraint.copyWith(status: ConstraintStatus.approved),
            ));
          }
        } else if (oldStatus == ConstraintStatus.approved) {
          // Status changed from approved - remove from calendar ONLY if it was unavailability
          if (constraint.isUnavailability) {
            developer.log(
              'TeamBloc: Unavailability constraint status changed from approved, removing from calendar',
              name: 'TeamBloc',
            );
            _calendarSyncBloc!.add(RemoveConstraintFromCalendar(
              constraintId: constraint.id,
            ));
          }
        }
      } else if (_calendarSyncBloc == null) {
      } else {
      }

      // Emit success message
      final statusText = event.newStatus.hebrewName;
      emit(TeamMemberOperationSuccess('סטטוס המגבלה עודכן ל$statusText בהצלחה'));
    } catch (e) {
      emit(TeamError('שגיאה בעדכון סטטוס המגבלה: $e'));
    }
  }

  /// Add constraint request (targeted update - only writes constraints field)
  Future<void> _onAddConstraintRequest(
    AddConstraintRequest event,
    Emitter<TeamState> emit,
  ) async {
    try {
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
        startTime: event.startTime,
        endTime: event.endTime,
      );

      // Use targeted database method (atomic append, only writes constraints field)
      await _repository.database.addConstraint(
        event.teamMemberId,
        newConstraint,
      );

      // Emit success to show snackbar
      // The existing stream subscription will automatically pick up the database changes
      emit(const TeamMemberOperationSuccess('בקשת מגבלה נוספה בהצלחה וממתינה לאישור'));
    } catch (e) {
      emit(TeamError('שגיאה בהוספת בקשת מגבלה: $e'));
    }
  }

  /// Remove constraint by ID (targeted update - only writes constraints field)
  Future<void> _onRemoveConstraintRequest(
    RemoveConstraintRequest event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Use targeted database method that finds by ID and only updates constraints field
      final removedConstraint = await _repository.database.removeConstraintById(
        event.teamMemberId,
        event.constraintId,
      );

      if (removedConstraint == null) {
        // Constraint was already removed (idempotent) - not an error
        emit(const TeamMemberOperationSuccess('בקשת מגבלה נמחקה בהצלחה'));
        return;
      }

      // If constraint was approved AND it's an unavailability constraint, remove from calendar
      if (_calendarSyncBloc != null && removedConstraint.isApproved() && removedConstraint.isUnavailability) {
        developer.log(
          'TeamBloc: Removing approved unavailability constraint from calendar',
          name: 'TeamBloc',
        );
        _calendarSyncBloc!.add(RemoveConstraintFromCalendar(
          constraintId: event.constraintId,
        ));
      }

      // Emit success to show snackbar
      // The existing stream subscription will automatically pick up the database changes
      emit(const TeamMemberOperationSuccess('בקשת מגבלה נמחקה בהצלחה'));
    } catch (e) {
      emit(TeamError('שגיאה במחיקת בקשת מגבלה: $e'));
    }
  }

  /// Edit constraint by ID (targeted update - reads latest from DB, only writes constraints field)
  Future<void> _onEditConstraintRequest(
    EditConstraintRequest event,
    Emitter<TeamState> emit,
  ) async {
    try {
      // Build the updated constraint
      final updatedConstraint = DateConstraint(
        id: event.constraintId,
        startDate: event.startDate,
        endDate: event.endDate,
        note: event.note,
        status: event.status,
        constraintType: event.constraintType,
        wasAutoRejectedFromCalendar: event.wasAutoRejectedFromCalendar,
        startTime: event.startTime,
        endTime: event.endTime,
      );

      // Use targeted database method that finds by ID and only updates constraints field
      await _repository.database.editConstraintById(
        event.teamMemberId,
        event.constraintId,
        updatedConstraint,
      );

      // Handle calendar sync for status changes
      if (_calendarSyncBloc != null) {
        // Get the old constraint to detect status changes
        final currentMember = await _repository.getTeamMemberById(event.teamMemberId);
        if (currentMember != null) {
          final oldConstraint = currentMember.constraints
              .where((c) => c.id == event.constraintId)
              .firstOrNull;

          if (oldConstraint != null && oldConstraint.status != event.status) {
            if (event.status == ConstraintStatus.approved && updatedConstraint.isUnavailability) {
              _calendarSyncBloc!.add(SyncConstraintToCalendar(
                constraintId: event.constraintId,
                teamMember: currentMember,
                constraint: updatedConstraint,
              ));
            } else if (oldConstraint.status == ConstraintStatus.approved && oldConstraint.isUnavailability) {
              _calendarSyncBloc!.add(RemoveConstraintFromCalendar(
                constraintId: event.constraintId,
              ));
            }
          }
        }
      }

      emit(const TeamMemberOperationSuccess('מגבלה עודכנה בהצלחה'));
    } catch (e) {
      emit(TeamError('שגיאה בעדכון מגבלה: $e'));
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
    // Cancel stream subscription
    await _teamSubscription?.cancel();
    _teamSubscription = null;
    // Clear constraint managers
    _constraintManagers.clear();
    // Reset to initial state
    emit(const TeamInitial());
  }

  @override
  Future<void> close() async {
    // Cancel stream subscription to prevent memory leaks
    await _teamSubscription?.cancel();
    // Clear constraint managers
    _constraintManagers.clear();
    return super.close();
  }
}

/// Internal event: Received team members update from stream
/// This is used to properly manage stream subscriptions and prevent memory leaks
class _TeamMembersUpdated extends TeamEvent {
  final List<TeamMember> members;
  final bool activeOnly;

  const _TeamMembersUpdated(this.members, {this.activeOnly = false});

  @override
  List<Object?> get props => [members, activeOnly];
}
