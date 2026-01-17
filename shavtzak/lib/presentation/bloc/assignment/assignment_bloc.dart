import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import 'assignment_event.dart';
import 'assignment_state.dart';
import '../../screens/assignment/models/assignment_slot.dart';

/// BLoC for managing assignments
/// This is the KEY BLoC that solves the V1 sync problem
class AssignmentBloc extends Bloc<AssignmentEvent, AssignmentState> {
  final AssignmentRepository _repository;
  final EventRepository _eventRepository;
  final TeamRepository _teamRepository;

  // Stream subscriptions for manual control
  StreamSubscription? _assignmentSubscription;
  StreamSubscription? _teamMemberSubscription;
  StreamSubscription? _eventSubscription;

  // Stream subscriptions for user assignments view
  StreamSubscription? _userAssignmentSubscription;
  StreamSubscription? _userEventSubscription;

  // Keep the current event filter independent of state
  Set<String> _currentEventFilter = <String>{};

  AssignmentBloc(
    this._repository,
    this._eventRepository,
    this._teamRepository,
  ) : super(const AssignmentInitial()) {
    // Register event handlers
    on<LoadAssignments>(_onLoadAssignments);
    on<LoadAssignmentsByEvent>(_onLoadAssignmentsByEvent);
    on<LoadAssignmentsByPerson>(_onLoadAssignmentsByPerson);
    on<LoadAssignmentsByDateRange>(_onLoadAssignmentsByDateRange);
    on<LoadAssignmentById>(_onLoadAssignmentById);
    on<CreateAssignment>(_onCreateAssignment);
    on<CreateAssignmentWithBypass>(_onCreateAssignmentWithBypass);
    on<UpdateAssignment>(_onUpdateAssignment);
    on<DeleteAssignment>(_onDeleteAssignment);
    on<UpdateAssignmentStatus>(_onUpdateAssignmentStatus);
    on<ConfirmAssignment>(_onConfirmAssignment);
    on<DeclineAssignment>(_onDeclineAssignment);
    on<LoadAssignmentsWithConflicts>(_onLoadAssignmentsWithConflicts);
    on<LoadEventAssignmentStats>(_onLoadEventAssignmentStats);
    on<RefreshAssignments>(_onRefreshAssignments);
    on<LoadAssignmentSlots>(_onLoadAssignmentSlots);
    on<ApplyEventFilter>(_onApplyEventFilter);
    on<ClearEventFilter>(_onClearEventFilter);
    on<RebuildAssignmentSlots>(_onRebuildAssignmentSlots);
    on<RebuildAssignmentSlotsFromData>(_onRebuildAssignmentSlotsFromData);
    on<LoadUserAssignments>(_onLoadUserAssignments);
    on<RebuildUserAssignments>(_onRebuildUserAssignments);
    on<UpdateAssignmentNotes>(_onUpdateAssignmentNotes);
  }

  /// Load all assignments with real-time updates
  Future<void> _onLoadAssignments(
    LoadAssignments event,
    Emitter<AssignmentState> emit,
  ) async {
    emit(const AssignmentLoading());

    try {
      // Use emit.forEach to subscribe to real-time stream
      await emit.forEach<List<Assignment>>(
        _repository.watchAssignments(),
        onData: (assignments) {
          if (assignments.isEmpty) {
            return const AssignmentsEmpty('אין שיבוצים במערכת');
          } else {
            return AssignmentsLoaded.withCounts(
              assignments,
              filterType: 'all',
            );
          }
        },
        onError: (error, stackTrace) {
          return AssignmentError('שגיאה בטעינת שיבוצים: $error');
        },
      );
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Load assignments for a specific event with real-time updates
  Future<void> _onLoadAssignmentsByEvent(
    LoadAssignmentsByEvent event,
    Emitter<AssignmentState> emit,
  ) async {
    emit(const AssignmentLoading());

    try {
      await emit.forEach<List<Assignment>>(
        _repository.watchAssignmentsByEvent(event.eventId),
        onData: (assignments) {
          if (assignments.isEmpty) {
            return const AssignmentsEmpty('אין שיבוצים לאירוע זה');
          } else {
            return AssignmentsLoaded.withCounts(
              assignments,
              filterType: 'event',
              filterId: event.eventId,
            );
          }
        },
        onError: (error, stackTrace) {
          return AssignmentError('שגיאה בטעינת שיבוצים: $error');
        },
      );
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Load assignments for a specific team member with real-time updates
  Future<void> _onLoadAssignmentsByPerson(
    LoadAssignmentsByPerson event,
    Emitter<AssignmentState> emit,
  ) async {
    emit(const AssignmentLoading());

    try {
      await emit.forEach<List<Assignment>>(
        _repository.watchAssignmentsByPerson(event.teamMemberId),
        onData: (assignments) {
          if (assignments.isEmpty) {
            return const AssignmentsEmpty('אין שיבוצים לחבר צוות זה');
          } else {
            return AssignmentsLoaded.withCounts(
              assignments,
              filterType: 'person',
              filterId: event.teamMemberId,
            );
          }
        },
        onError: (error, stackTrace) {
          return AssignmentError('שגיאה בטעינת שיבוצים: $error');
        },
      );
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Load assignments by date range
  Future<void> _onLoadAssignmentsByDateRange(
    LoadAssignmentsByDateRange event,
    Emitter<AssignmentState> emit,
  ) async {
    emit(const AssignmentLoading());

    try {
      final assignments = await _repository.getAssignmentsByDateRange(
        event.start,
        event.end,
      );

      if (assignments.isEmpty) {
        emit(const AssignmentsEmpty('אין שיבוצים בטווח תאריכים זה'));
      } else {
        emit(AssignmentsLoaded.withCounts(
          assignments,
          filterType: 'dateRange',
        ));
      }
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Load assignment by ID
  Future<void> _onLoadAssignmentById(
    LoadAssignmentById event,
    Emitter<AssignmentState> emit,
  ) async {
    emit(const AssignmentLoading());

    try {
      final assignment = await _repository.getAssignmentById(event.id);

      if (assignment == null) {
        emit(const AssignmentError('שיבוץ לא נמצא'));
      } else {
        emit(AssignmentDetailLoaded(assignment));
      }
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת פרטי השיבוץ: $e'));
    }
  }

  /// Create new assignment
  Future<void> _onCreateAssignment(
    CreateAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    // Store previous state BEFORE any emit
    final previousState = state;

    emit(const AssignmentOperating('creating'));

    try {
      // Check for conflicts before creating
      final conflicts = await _repository.checkConflicts(event.assignment);

      if (conflicts.isNotEmpty) {
        // Emit conflict warning but don't fail
        emit(AssignmentConflictWarning(conflicts, event.assignment));
        // Note: Real-time stream will automatically update UI, no manual reload needed
        return;
      }

      await _repository.createAssignment(event.assignment);
      emit(const AssignmentOperationSuccess('השיבוץ נוסף בהצלחה'));

      // Check if we need to reload based on view type
      // For slots view: Real-time stream handles updates automatically
      // For list view: Need to restart the listener
      if (previousState is AssignmentsLoaded) {
        // Restart real-time listener based on current filter
        final currentState = previousState;
        if (currentState.filterType == 'event' && currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' && currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else {
        add(const LoadAssignments());
      }
    } catch (e) {
      if (e is AssignmentConflictException) {
        emit(AssignmentConflictWarning(e.conflicts, event.assignment));
      } else {
        emit(AssignmentError('שגיאה בהוספת שיבוץ: $e'));
      }
    }
  }

  /// Update assignment
  Future<void> _onUpdateAssignment(
    UpdateAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    // Store previous state BEFORE any emit
    final previousState = state;

    emit(const AssignmentOperating('updating'));

    try {
      // Check for conflicts before updating
      final conflicts = await _repository.checkConflicts(event.assignment);

      if (conflicts.isNotEmpty) {
        emit(AssignmentConflictWarning(conflicts, event.assignment));
        // Note: Real-time stream will automatically update UI, no manual reload needed
        return;
      }

      await _repository.updateAssignment(event.assignment);
      emit(const AssignmentOperationSuccess('השיבוץ עודכן בהצלחה'));

      // Check if we need to reload based on view type
      // For slots view: Real-time stream handles updates automatically
      // For list view: Need to restart the listener
      if (previousState is AssignmentsLoaded) {
        // Restart real-time listener based on current filter
        final currentState = previousState;
        if (currentState.filterType == 'event' && currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' && currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else {
        add(const LoadAssignments());
      }
    } catch (e) {
      if (e is AssignmentConflictException) {
        emit(AssignmentConflictWarning(e.conflicts, event.assignment));
      } else {
        emit(AssignmentError('שגיאה בעדכון שיבוץ: $e'));
      }
    }
  }

  /// Delete assignment
  Future<void> _onDeleteAssignment(
    DeleteAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    // Store previous state BEFORE any emit
    final previousState = state;

    emit(const AssignmentOperating('deleting'));

    try {

      await _repository.deleteAssignment(event.id);
      emit(const AssignmentOperationSuccess('השיבוץ נמחק בהצלחה'));

      // Check if we need to reload based on view type
      // For slots view: Real-time stream handles updates automatically
      // For list view: Need to restart the listener
      if (previousState is AssignmentsLoaded) {
        // Restart real-time listener based on current filter
        final currentState = previousState;
        if (currentState.filterType == 'event' && currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' && currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else {
        add(const LoadAssignments());
      }
    } catch (e) {
      emit(AssignmentError('שגיאה במחיקת שיבוץ: $e'));
    }
  }

  /// Update assignment status
  Future<void> _onUpdateAssignmentStatus(
    UpdateAssignmentStatus event,
    Emitter<AssignmentState> emit,
  ) async {
    emit(const AssignmentOperating('updating'));

    try {
      await _repository.updateAssignmentStatus(event.id, event.status);
      emit(const AssignmentOperationSuccess('סטטוס השיבוץ עודכן בהצלחה'));

      // Restart real-time listener based on current filter
      if (state is AssignmentsLoaded) {
        final currentState = state as AssignmentsLoaded;
        if (currentState.filterType == 'event' && currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' && currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else {
        add(const LoadAssignments());
      }
    } catch (e) {
      emit(AssignmentError('שגיאה בעדכון סטטוס: $e'));
    }
  }

  /// Confirm assignment
  Future<void> _onConfirmAssignment(
    ConfirmAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    add(UpdateAssignmentStatus(event.id, AssignmentStatus.confirmed));
  }

  /// Decline assignment
  Future<void> _onDeclineAssignment(
    DeclineAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    add(UpdateAssignmentStatus(event.id, AssignmentStatus.declined));
  }

  /// Load assignments with conflicts
  Future<void> _onLoadAssignmentsWithConflicts(
    LoadAssignmentsWithConflicts event,
    Emitter<AssignmentState> emit,
  ) async {
    emit(const AssignmentLoading());

    try {
      final assignments = await _repository.getAssignmentsWithConflicts();

      if (assignments.isEmpty) {
        emit(const AssignmentsEmpty('אין שיבוצים עם קונפליקטים'));
      } else {
        emit(AssignmentsLoaded.withCounts(assignments));
      }
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Load event assignment statistics
  Future<void> _onLoadEventAssignmentStats(
    LoadEventAssignmentStats event,
    Emitter<AssignmentState> emit,
  ) async {
    emit(const AssignmentLoading());

    try {
      final stats = await _repository.getEventAssignmentStats(event.eventId);
      emit(EventAssignmentStatsLoaded(event.eventId, stats));
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת סטטיסטיקות: $e'));
    }
  }

  /// Refresh assignments
  Future<void> _onRefreshAssignments(
    RefreshAssignments event,
    Emitter<AssignmentState> emit,
  ) async {
    // Simply reload based on current state
    if (state is AssignmentsLoaded) {
      final currentState = state as AssignmentsLoaded;
      if (currentState.filterType == 'event' && currentState.filterId != null) {
        add(LoadAssignmentsByEvent(currentState.filterId!));
      } else if (currentState.filterType == 'person' && currentState.filterId != null) {
        add(LoadAssignmentsByPerson(currentState.filterId!));
      } else {
        add(const LoadAssignments());
      }
    } else {
      add(const LoadAssignments());
    }
  }

  /// Load assignment slots for grid view with real-time updates
  /// Rebuilds slots whenever assignments, team members, OR events change
  Future<void> _onLoadAssignmentSlots(
    LoadAssignmentSlots event,
    Emitter<AssignmentState> emit,
  ) async {
    // Preserve the current filter from state BEFORE emitting loading
    final currentFilter = state is AssignmentSlotsLoaded
        ? (state as AssignmentSlotsLoaded).selectedEventIds
        : _currentEventFilter; // use remembered value as fallback

    // Keep the internal filter in sync
    _currentEventFilter = currentFilter;

    emit(const AssignmentLoading());

    try {
      // Cancel any existing subscriptions
      await _assignmentSubscription?.cancel();
      await _teamMemberSubscription?.cancel();
      await _eventSubscription?.cancel();

      // OPTIMIZATION: Use time window instead of loading all events/assignments
      // This reduces initial load from 5000+ assignments to ~500 (90% reduction)
      const pastWindow = Duration(days: 90);  // 3 months back
      const futureWindow = Duration(days: 180); // 6 months forward

      final now = DateTime.now();
      final windowStart = now.subtract(pastWindow);
      final windowEnd = now.add(futureWindow);

      // Load events within the time window only
      final cachedEvents = await _eventRepository.getEventsByDateRange(
        windowStart,
        windowEnd,
      );

      // Load all team members (small dataset, ~50-100)
      final cachedMembers = await _teamRepository.getActiveTeamMembers();

      final cachedMembersMap = <String, TeamMember>{};
      cachedMembersMap.addAll({for (var tm in cachedMembers) tm.id: tm});
      final cachedEventsMap = <String, Event>{};
      cachedEventsMap.addAll({for (var e in cachedEvents) e.id: e});

      // Initial load - get assignments within time window FIRST
      // This ensures we emit a state immediately, preventing endless loading
      final initialAssignments = await _repository.getAssignmentsInTimeWindow(
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
      _repository.cacheCurrentAssignments(initialAssignments);

      // Emit the loaded state immediately with initial data
      add(RebuildAssignmentSlotsFromData(initialAssignments, cachedEventsMap, cachedMembersMap, currentFilter));

      // Subscribe to real-time updates on assignments within time window
      _assignmentSubscription = _repository.watchAssignmentsInTimeWindow(
        windowStart: windowStart,
        windowEnd: windowEnd,
      ).listen(
        (assignments) {
          // Cache current assignments for rebuild purposes
          _repository.cacheCurrentAssignments(assignments);
          // Rebuild slots using cached data - use _currentEventFilter to preserve user's filter
          add(RebuildAssignmentSlotsFromData(assignments, cachedEventsMap, cachedMembersMap, _currentEventFilter));
        },
        onError: (e) {
          emit(AssignmentError('שגיאה בהאזנה לשיבוצים: $e'));
        },
      );

      // Also listen for team member changes
      _teamMemberSubscription = _teamRepository.watchTeamMembers().listen(
        (updatedMembers) async {
          // Update member cache
          cachedMembersMap.clear();
          cachedMembersMap.addAll({for (var tm in updatedMembers) tm.id: tm});
          // CRITICAL FIX: Fetch FRESH assignments from DB when team members change
          // This prevents stale cached data after member changes
          final freshAssignments = await _repository.getAssignmentsInTimeWindow(
            windowStart: windowStart,
            windowEnd: windowEnd,
          );
          // Update cache with fresh data
          _repository.cacheCurrentAssignments(freshAssignments);
          // Trigger rebuild with fresh data - use _currentEventFilter to preserve user's filter
          add(RebuildAssignmentSlotsFromData(freshAssignments, cachedEventsMap, cachedMembersMap, _currentEventFilter));
        },
        onError: (e) {
          emit(AssignmentError('שגיאה בהאזנה לחברי צוות: $e'));
        },
      );

      // Also listen for event changes within time window
      _eventSubscription = _eventRepository.watchEventsByDateRange(
        windowStart,
        windowEnd,
      ).listen(
        (updatedEvents) async {
          // Update event cache
          cachedEventsMap.clear();
          cachedEventsMap.addAll({for (var e in updatedEvents) e.id: e});
          // CRITICAL FIX: Fetch FRESH assignments from DB when events change
          // This prevents stale cached data after quota changes
          final freshAssignments = await _repository.getAssignmentsInTimeWindow(
            windowStart: windowStart,
            windowEnd: windowEnd,
          );
          // Update cache with fresh data
          _repository.cacheCurrentAssignments(freshAssignments);
          // Trigger rebuild with fresh data - use _currentEventFilter to preserve user's filter
          add(RebuildAssignmentSlotsFromData(freshAssignments, cachedEventsMap, cachedMembersMap, _currentEventFilter));
        },
        onError: (e) {
          emit(AssignmentError('שגיאה בהאזנה לאירועים: $e'));
        },
      );
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  @override
  Future<void> close() async {
    await _assignmentSubscription?.cancel();
    await _teamMemberSubscription?.cancel();
    await _eventSubscription?.cancel();
    await _userAssignmentSubscription?.cancel();
    await _userEventSubscription?.cancel();
    return super.close();
  }

  /// Build complete slots state from assignments
  /// Fetches latest events and team members, then builds slot grid
  Future<AssignmentSlotsLoaded> _buildSlotsFromAssignments(
    List<Assignment> assignments, {
    Set<String>? selectedEventIds,
  }) async {
    // 1. Load all events
    var events = await _eventRepository.getAllEvents();

    // 2. Filter events based on showPastEvents flag
    if (!FilterPersistence.showPastEvents) {
      final now = DateTime.now();
      // Only include events where end date >= today (start of day)
      final todayStart = DateTime(now.year, now.month, now.day);
      events = events.where((event) => event.endDate.isAfter(todayStart.subtract(const Duration(days: 1)))).toList();
    }

    // 3. Load all active team members
    final allMembers = await _teamRepository.getActiveTeamMembers();

    // 4. Build slots
    final slots = <AssignmentSlot>[];

      for (final event in events) {
        // For each role requirement in the event (in enum order)
        for (final role in RoleType.values) {
          final requiredCount = event.roleRequirements[role.name] ?? 0;
          if (requiredCount == 0) continue; // Skip roles with 0 requirement

          // Get assignments for this event+role
          final roleAssignments = assignments
              .where((a) => a.eventId == event.id && a.roleType == role.name)
              .toList();

          // Create slots (one per required count)
          for (int i = 0; i < requiredCount; i++) {
            // Find if this slot is filled (match by slotIndex, not array position)
            final assignment = roleAssignments
                .cast<Assignment?>()
                .firstWhere((a) => a?.slotIndex == i, orElse: () => null);

            // Get all assignments for this event to check who's already assigned
            final eventAssignments = assignments
                .where((a) => a.eventId == event.id)
                .toList();
            final assignedMemberIds = eventAssignments
                .map((a) => a.teamMemberId)
                .toSet();

            // Separate members into available (not assigned to this event)
            // and already assigned (assigned to this event)
            // Use Maps to prevent duplicates
            final availableMembersMap = <String, TeamMember>{};
            final alreadyAssignedMembersMap = <String, TeamMember>{};

            for (final member in allMembers) {
              // Check capability
              if (!member.canPerformRole(role.name)) continue;

              // Check availability for entire event duration
              // Skip availability check for members with allowMultipleAssignments
              if (!member.allowMultipleAssignments &&
                  !member.isAvailableForDateRange(event.startDate, event.endDate)) {
                continue;
              }

              // Separate based on whether already assigned to this event
              // Members with allowMultipleAssignments always go to available list
              if (member.allowMultipleAssignments) {
                availableMembersMap[member.id] = member;
              } else if (assignedMemberIds.contains(member.id)) {
                alreadyAssignedMembersMap[member.id] = member;
              } else {
                availableMembersMap[member.id] = member;
              }
            }

            final availableMembers = availableMembersMap.values.toList();
            final alreadyAssignedMembers = alreadyAssignedMembersMap.values.toList();

            slots.add(AssignmentSlot(
              event: event,
              roleType: role,
              slotIndex: i,
              currentAssignment: assignment,
              availableMembers: availableMembers,
              alreadyAssignedMembers: alreadyAssignedMembers,
            ));
          }
        }
      }

      // 5. Detect double assignments (person assigned to multiple roles in same event)
      // Skip for members with allowMultipleAssignments since it's expected behavior
      final slotsWithDoubleAssignmentDetection = <AssignmentSlot>[];
      for (final slot in slots) {
        if (slot.isFilled) {
          // Check if member has allowMultipleAssignments - skip double assignment warning
          final teamMember = slot.currentAssignment!.teamMember;
          final skipDoubleAssignmentWarning = teamMember?.allowMultipleAssignments ?? false;

          // Check if this person has other assignments in the same event
          final otherAssignments = slots.where((s) =>
              s.event.id == slot.event.id &&
              s.isFilled &&
              s.currentAssignment!.teamMemberId ==
                  slot.currentAssignment!.teamMemberId &&
              s.roleType != slot.roleType).toList();

          if (otherAssignments.isNotEmpty && !skipDoubleAssignmentWarning) {
            // This person has multiple roles in this event
            final otherRoleNames =
                otherAssignments.map((s) => s.roleType.hebrewName).toList();
            slotsWithDoubleAssignmentDetection.add(AssignmentSlot(
              event: slot.event,
              roleType: slot.roleType,
              slotIndex: slot.slotIndex,
              currentAssignment: slot.currentAssignment,
              availableMembers: slot.availableMembers,
              alreadyAssignedMembers: slot.alreadyAssignedMembers,
              hasDoubleAssignment: true,
              otherRoles: otherRoleNames,
            ));
          } else {
            slotsWithDoubleAssignmentDetection.add(slot);
          }
        } else {
          slotsWithDoubleAssignmentDetection.add(slot);
        }
      }

    // 6. Sort slots by event date, then event name, then role
    slotsWithDoubleAssignmentDetection.sort((a, b) {
      final dateCompare = a.event.startDate.compareTo(b.event.startDate);
      if (dateCompare != 0) return dateCompare;

      final nameCompare = a.event.name.compareTo(b.event.name);
      if (nameCompare != 0) return nameCompare;

      // Sort by enum order (not alphabetically)
      return a.roleType.index.compareTo(b.roleType.index);
    });

    return AssignmentSlotsLoaded(
      slotsWithDoubleAssignmentDetection,
      selectedEventIds: selectedEventIds ?? {},
    );
  }

  /// Apply event filter to current slots
  Future<void> _onApplyEventFilter(
    ApplyEventFilter event,
    Emitter<AssignmentState> emit,
  ) async {
    // Remember the filter
    _currentEventFilter = event.eventIds;

    // Trigger immediate rebuild with new filter
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  /// Clear event filter
  Future<void> _onClearEventFilter(
    ClearEventFilter event,
    Emitter<AssignmentState> emit,
  ) async {
    // Clear in-memory filter
    _currentEventFilter = <String>{};

    // Trigger immediate rebuild with cleared filter
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  /// Internal handler to rebuild slots (triggered by streams or filter changes)
  Future<void> _onRebuildAssignmentSlots(
    RebuildAssignmentSlots event,
    Emitter<AssignmentState> emit,
  ) async {
    try {
      // Determine which filter to use:
      // 1. If the event provides a filter (explicit change), use it
      // 2. Otherwise, use the last known filter stored in _currentEventFilter
      final filterToUse = event.preservedFilter ?? _currentEventFilter;

      // Keep the internal field in sync
      _currentEventFilter = filterToUse;

      final assignments = await _repository.getAllAssignments();
      final updatedSlots = await _buildSlotsFromAssignments(
        assignments,
        selectedEventIds: filterToUse,
      );
      emit(updatedSlots);
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Rebuild slots using pre-loaded data (for real-time updates)
  Future<void> _onRebuildAssignmentSlotsFromData(
    RebuildAssignmentSlotsFromData rebuildEvent,
    Emitter<AssignmentState> emit,
  ) async {
    try {
      // Update the repository's cached assignments
      _repository.cacheCurrentAssignments(rebuildEvent.assignments);

      // Convert maps to lists for the build method
      final eventsList = rebuildEvent.events.values.toList();
      final teamMembersMap = rebuildEvent.teamMembers;
      final teamMembers = rebuildEvent.teamMembers.values.toList();

      // Filter events based on showPastEvents flag
      var filteredEvents = eventsList;
      if (!FilterPersistence.showPastEvents) {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        filteredEvents = filteredEvents.where((e) => e.endDate.isAfter(todayStart.subtract(const Duration(days: 1)))).toList();
      }

      // Build slots using the existing method
      final slots = <AssignmentSlot>[];
      for (final eventData in filteredEvents) {
        // For each role requirement in the event (in enum order)
        for (final role in RoleType.values) {
          final requiredCount = eventData.roleRequirements[role.name] ?? 0;
          if (requiredCount == 0) continue; // Skip roles with 0 requirement

          // Get assignments for this event+role from the assignments list
          final roleAssignments = rebuildEvent.assignments
              .where((a) => a.eventId == eventData.id && a.roleType == role.name)
              .map((a) => a.withRelations(
                event: eventData,
                teamMember: teamMembersMap[a.teamMemberId],
              ))
              .toList();

          // Create slots (one per required count)
          for (int i = 0; i < requiredCount; i++) {
            // Find if this slot is filled (match by slotIndex, not array position)
            final assignment = roleAssignments
                .cast<Assignment?>()
                .firstWhere((a) => a?.slotIndex == i, orElse: () => null);

            // Get all assignments for this event to check who's already assigned
            final eventAssignments = rebuildEvent.assignments
                .where((a) => a.eventId == eventData.id)
                .toList();
            final assignedMemberIds = eventAssignments
                .map((a) => a.teamMemberId)
                .toSet();

            // Separate members into available (not assigned to this event)
            // and already assigned (assigned to this event)
            // Use Maps to prevent duplicates
            final availableMembersMap = <String, TeamMember>{};
            final alreadyAssignedMembersMap = <String, TeamMember>{};

            for (final member in teamMembers) {
              // Check capability
              if (!member.canPerformRole(role.name)) continue;

              // Check availability for entire event duration
              // Skip availability check for members with allowMultipleAssignments
              if (!member.allowMultipleAssignments &&
                  !member.isAvailableForDateRange(eventData.startDate, eventData.endDate)) {
                continue;
              }

              // Separate based on whether already assigned to this event
              // Members with allowMultipleAssignments always go to available list
              if (member.allowMultipleAssignments) {
                availableMembersMap[member.id] = member;
              } else if (assignedMemberIds.contains(member.id)) {
                alreadyAssignedMembersMap[member.id] = member;
              } else {
                availableMembersMap[member.id] = member;
              }
            }

            final availableMembers = availableMembersMap.values.toList();
            final alreadyAssignedMembers = alreadyAssignedMembersMap.values.toList();

            slots.add(AssignmentSlot(
              event: eventData,
              roleType: role,
              slotIndex: i,
              currentAssignment: assignment,
              availableMembers: availableMembers,
              alreadyAssignedMembers: alreadyAssignedMembers,
            ));
          }
        }
      }

      // Detect double assignments
      final slotsWithDoubleAssignmentDetection = <AssignmentSlot>[];
      for (final slot in slots) {
        if (slot.isFilled) {
          // Check if member has allowMultipleAssignments - skip double assignment warning
          final teamMember = slot.currentAssignment!.teamMember;
          final skipDoubleAssignmentWarning = teamMember?.allowMultipleAssignments ?? false;

          // Check if this person has other assignments in the same event
          final otherAssignments = slots.where((s) =>
              s.event.id == slot.event.id &&
              s.isFilled &&
              s.currentAssignment!.teamMemberId ==
                  slot.currentAssignment!.teamMemberId &&
              s.roleType != slot.roleType).toList();

          if (otherAssignments.isNotEmpty && !skipDoubleAssignmentWarning) {
            // This person has multiple roles in this event
            final otherRoleNames =
                otherAssignments.map((s) => s.roleType.hebrewName).toList();
            slotsWithDoubleAssignmentDetection.add(AssignmentSlot(
              event: slot.event,
              roleType: slot.roleType,
              slotIndex: slot.slotIndex,
              currentAssignment: slot.currentAssignment,
              availableMembers: slot.availableMembers,
              alreadyAssignedMembers: slot.alreadyAssignedMembers,
              hasDoubleAssignment: true,
              otherRoles: otherRoleNames,
            ));
          } else {
            slotsWithDoubleAssignmentDetection.add(slot);
          }
        } else {
          slotsWithDoubleAssignmentDetection.add(slot);
        }
      }

      // Sort slots by event date, then event name, then role
      slotsWithDoubleAssignmentDetection.sort((a, b) {
        final dateCompare = a.event.startDate.compareTo(b.event.startDate);
        if (dateCompare != 0) return dateCompare;

        final nameCompare = a.event.name.compareTo(b.event.name);
        if (nameCompare != 0) return nameCompare;

        // Sort by enum order (not alphabetically)
        return a.roleType.index.compareTo(b.roleType.index);
      });

      // Apply filter if needed
      final filteredSlots = rebuildEvent.selectedEventIds.isNotEmpty
          ? slotsWithDoubleAssignmentDetection.where((slot) => rebuildEvent.selectedEventIds.contains(slot.event.id)).toList()
          : slotsWithDoubleAssignmentDetection;

      // Remember the filter
      _currentEventFilter = rebuildEvent.selectedEventIds;

      emit(AssignmentSlotsLoaded(
        filteredSlots,
        selectedEventIds: rebuildEvent.selectedEventIds,
      ));
    } catch (e) {
      emit(AssignmentError('שגיאה בבניית שיבוצים: $e'));
    }
  }

  /// Create new assignment bypassing conflict checks (for manual assignments)
  Future<void> _onCreateAssignmentWithBypass(
    CreateAssignmentWithBypass event,
    Emitter<AssignmentState> emit,
  ) async {
    // Store previous state BEFORE any emit
    final previousState = state;

    emit(const AssignmentOperating('creating'));

    try {
      // Skip conflict checks for bypass assignments
      await _repository.createAssignmentWithBypass(event.assignment);
      emit(const AssignmentOperationSuccess('השיבוץ נוסף בהצלחה'));

      // Check if we need to reload based on view type
      // For slots view: Real-time stream handles updates automatically
      // For list view: Need to restart the listener
      if (previousState is AssignmentsLoaded) {
        // Restart real-time listener based on current filter
        final currentState = previousState;
        if (currentState.filterType == 'event' && currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' && currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else if (previousState is! AssignmentSlotsLoaded) {
        // Only reload if not in slots view (real-time stream handles slots view)
        add(const LoadAssignments());
      }
    } catch (e) {
      if (e is AssignmentConflictException) {
        emit(AssignmentConflictWarning(e.conflicts, event.assignment));
        // Note: Real-time stream will automatically update UI, no manual reload needed
      } else {
        emit(AssignmentError('שגיאה ביצירת שיבוץ: $e'));
      }
    }
  }

  /// Load user assignments with real-time updates for both assignments AND events
  /// This ensures UI updates when event details change or events are deleted
  Future<void> _onLoadUserAssignments(
    LoadUserAssignments event,
    Emitter<AssignmentState> emit,
  ) async {
    emit(const AssignmentLoading());

    try {
      // Cancel any existing user assignment subscriptions
      await _userAssignmentSubscription?.cancel();
      await _userEventSubscription?.cancel();

      // Subscribe to assignments stream for this user
      _userAssignmentSubscription = _repository.watchAssignmentsByPerson(event.teamMemberId).listen(
        (_) {
          add(RebuildUserAssignments(event.teamMemberId));
        },
        onError: (e) {
          add(RebuildUserAssignments(event.teamMemberId));
        },
      );

      // Subscribe to events stream to detect changes/deletions
      _userEventSubscription = _eventRepository.watchEvents().listen(
        (_) {
          add(RebuildUserAssignments(event.teamMemberId));
        },
        onError: (e) {
          add(RebuildUserAssignments(event.teamMemberId));
        },
      );

      // Initial load
      add(RebuildUserAssignments(event.teamMemberId));
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Internal handler to rebuild user assignments (triggered by streams)
  /// Note: No debounce flag - we always want fresh data when streams fire
  Future<void> _onRebuildUserAssignments(
    RebuildUserAssignments event,
    Emitter<AssignmentState> emit,
  ) async {
    try {
      // Fetch fresh data from repository (with populated relations)
      final assignments = await _repository.getAssignmentsByPerson(event.teamMemberId);

      if (assignments.isEmpty) {
        emit(const AssignmentsEmpty('אין שיבוצים לחבר צוות זה'));
      } else {
        emit(AssignmentsLoaded.withCounts(
          assignments,
          filterType: 'person',
          filterId: event.teamMemberId,
        ));
      }
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Update assignment notes
  Future<void> _onUpdateAssignmentNotes(
    UpdateAssignmentNotes event,
    Emitter<AssignmentState> emit,
  ) async {
    // Store previous state BEFORE any emit
    final previousState = state;

    try {
      await _repository.updateAssignmentNotes(event.id, event.notes);
      emit(const AssignmentOperationSuccess('הערות עודכנו בהצלחה'));

      // Trigger rebuild based on current view type
      if (previousState is AssignmentSlotsLoaded) {
        // For slots view, trigger a rebuild with preserved filter
        add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
      } else if (previousState is AssignmentsLoaded) {
        // For list view, restart listener
        final currentState = previousState;
        if (currentState.filterType == 'event' && currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' && currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else {
        // Default: reload all assignments
        add(const LoadAssignments());
      }
    } catch (e) {
      emit(AssignmentError('שגיאה בעדכון הערות: $e'));
    }
  }
}
