import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/role.dart';
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
  final RoleRepository _roleRepository;

  // Stream subscriptions for manual control
  StreamSubscription? _assignmentSubscription;
  StreamSubscription? _teamMemberSubscription;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _roleSubscription;

  // Stream subscriptions for user assignments view
  StreamSubscription? _userAssignmentSubscription;
  StreamSubscription? _userEventSubscription;

  // Keep the current event filter independent of state
  Set<String> _currentEventFilter = <String>{};

  // Keep pending operations independent of state (survives error states)
  Map<String, PendingOperation> _pendingOperations = {};

  AssignmentBloc(
    this._repository,
    this._eventRepository,
    this._teamRepository,
    this._roleRepository,
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
    on<OptimisticCreateAssignment>(_onOptimisticCreateAssignment);
    on<OptimisticUpdateAssignment>(_onOptimisticUpdateAssignment);
    on<OptimisticDeleteAssignment>(_onOptimisticDeleteAssignment);
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
      } else if (previousState is! AssignmentSlotsLoaded) {
        // Only reload if not in slots view (real-time stream handles slots view)
        add(const LoadAssignments());
      }
      // If previousState is AssignmentSlotsLoaded, do nothing - real-time stream will handle it
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
      } else if (previousState is! AssignmentSlotsLoaded) {
        // Only reload if not in slots view (real-time stream handles slots view)
        add(const LoadAssignments());
      }
      // If previousState is AssignmentSlotsLoaded, do nothing - real-time stream will handle it
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
      } else if (previousState is! AssignmentSlotsLoaded) {
        // Only reload if not in slots view (real-time stream handles slots view)
        add(const LoadAssignments());
      }
      // If previousState is AssignmentSlotsLoaded, do nothing - real-time stream will handle it
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
      await _roleSubscription?.cancel();

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
          print('📡 [STREAM] Assignment stream FIRED!');
          print('  Assignments count: ${assignments.length}');
          print('  Triggering rebuild...');
          // Cache current assignments for rebuild purposes
          _repository.cacheCurrentAssignments(assignments);
          // Rebuild slots using cached data - use _currentEventFilter to preserve user's filter
          add(RebuildAssignmentSlotsFromData(assignments, cachedEventsMap, cachedMembersMap, _currentEventFilter));
        },
        onError: (e) {
          print('❌ [STREAM] Assignment stream ERROR: $e');
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

          // CRITICAL FIX: Add a small delay to ensure Firestore consistency
          // This prevents stale cached data after quota changes
          await Future.delayed(const Duration(milliseconds: 100));

          // Fetch FRESH assignments from DB when events change
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

      // Also listen for role changes
      _roleSubscription = _roleRepository.watchRoles().listen(
        (updatedRoles) async {
          // When roles change (e.g., reordering), rebuild slots with fresh assignments
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
          emit(AssignmentError('שגיאה בהאזנה לתפקידים: $e'));
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
    await _roleSubscription?.cancel();
    await _userAssignmentSubscription?.cancel();
    await _userEventSubscription?.cancel();
    return super.close();
  }

  /// Get slot key for AssignmentSlot
  String _getSlotKey(AssignmentSlot slot) {
    return '${slot.event.id}_${slot.role.key}_${slot.slotIndex}';
  }

  /// Apply optimistic update to a specific slot only
  List<AssignmentSlot> _applyOptimisticUpdate(
    List<AssignmentSlot> slots,
    String targetSlotKey,
    Assignment? optimisticAssignment, {
    required bool isDelete,
  }) {
    return slots.map((slot) {
      final slotKey = _getSlotKey(slot);

      if (slotKey == targetSlotKey) {
        // This is the target slot - apply the optimistic change
        return AssignmentSlot(
          event: slot.event,
          role: slot.role,
          slotIndex: slot.slotIndex,
          currentAssignment: isDelete ? null : optimisticAssignment,
          // CRITICAL: Keep database member lists unchanged
          availableMembers: slot.availableMembers,
          alreadyAssignedMembers: slot.alreadyAssignedMembers,
          hasDoubleAssignment: isDelete ? false : slot.hasDoubleAssignment,
          otherRoles: isDelete ? const [] : slot.otherRoles,
        );
      }

      // For all other slots, keep database state as-is
      return slot;
    }).toList();
  }

  /// Merge slots from database with pending optimistic operations
  /// Also recalculates member availability for affected events
  List<AssignmentSlot> _mergeSlotsWithOptimisticUpdates(
    List<AssignmentSlot> databaseSlots,
    Map<String, PendingOperation> pendingOperations,
  ) {
    print('  🔀 [MERGE_DEBUG] _mergeSlotsWithOptimisticUpdates START');
    print('    Database slots: ${databaseSlots.length}');
    print('    Pending operations: ${pendingOperations.length}');

    if (pendingOperations.isEmpty) {
      print('    ℹ️ No pending operations, returning database slots as-is');
      return databaseSlots;
    }

    // Remove expired operations (older than 5 seconds)
    print('    🧹 Checking for expired operations...');
    final activeOperations = Map<String, PendingOperation>.fromEntries(
      pendingOperations.entries.where((entry) => !entry.value.isExpired),
    );

    final expiredCount = pendingOperations.length - activeOperations.length;
    if (expiredCount > 0) {
      print('    ⏰ Removed $expiredCount expired operations');
    }
    print('    Active operations: ${activeOperations.length}');

    // CRITICAL FIX: Track slots with delete operations (including expired ones)
    // This ensures deleted slots stay empty even after operations expire
    // IMPORTANT: Only include a slot in deletedSlots if the CURRENT operation is DELETE
    // If a slot has CREATE/UPDATE, it's not deleted even if there was an old DELETE op
    final deletedSlots = <String>{}; // Set of slotKeys that were deleted
    for (final operation in pendingOperations.values) {
      if (operation.type == PendingOperationType.deleteAssignment) {
        deletedSlots.add(operation.slotKey);
      } else if (operation.type == PendingOperationType.createAssignment ||
                 operation.type == PendingOperationType.updateAssignment) {
        // Slot has CREATE/UPDATE, so it's NOT deleted (remove from set if present)
        deletedSlots.remove(operation.slotKey);
      }
    }

    // Group pending operations by event ID (only active ones for processing)
    final operationsByEvent = <String, List<PendingOperation>>{};
    for (final operation in activeOperations.values) {
      final eventId = operation.slotKey.split('_')[0];
      operationsByEvent.putIfAbsent(eventId, () => []).add(operation);
    }

    // CRITICAL FIX: Also add events that have deleted slots, even if no active ops
    // This ensures member lists are recalculated even after operations expire
    for (final slotKey in deletedSlots) {
      final eventId = slotKey.split('_')[0];
      operationsByEvent.putIfAbsent(eventId, () => []); // Add empty list if not present
    }

    // Build a map of slots by event for efficient updates
    final slotsByEvent = <String, List<AssignmentSlot>>{};
    for (final slot in databaseSlots) {
      slotsByEvent.putIfAbsent(slot.event.id, () => []).add(slot);
    }

    // Process each event that has pending operations
    for (final entry in operationsByEvent.entries) {
      final eventId = entry.key;
      final operations = entry.value;
      final eventSlots = slotsByEvent[eventId] ?? [];

      if (eventSlots.isEmpty) continue;

      // CRITICAL FIX: Rebuild effectiveAssignedMemberIds from scratch to avoid cross-slot interference
      // Instead of modifying a set incrementally (which can remove members from wrong slots),
      // we build a fresh map of which member is assigned to which slot.

      // Map: slotKey -> member ID (null if empty)
      final slotAssignments = <String, String?>{};

      // Start with database assignments
      for (final slot in eventSlots) {
        final slotKey = _getSlotKey(slot);
        slotAssignments[slotKey] = slot.currentAssignment?.teamMemberId;
      }

      // Apply pending operations (this overrides DB state for specific slots)
      for (final operation in operations) {
        final slotKey = operation.slotKey;

        if (operation.type == PendingOperationType.deleteAssignment) {
          slotAssignments[slotKey] = null; // Slot is now empty
        } else if (operation.type == PendingOperationType.createAssignment ||
                   operation.type == PendingOperationType.updateAssignment) {
          if (operation.optimisticAssignment != null) {
            slotAssignments[slotKey] = operation.optimisticAssignment!.teamMemberId;
          }
        }
      }

      // Collect all non-null member IDs
      final effectiveAssignedMemberIds = slotAssignments.values
          .where((id) => id != null)
          .cast<String>()
          .toSet();

      // Recalculate member availability for all slots in this event
      for (final slot in eventSlots) {
        final slotKey = _getSlotKey(slot);
        final operation = activeOperations[slotKey];

        // Build new member lists based on effective assigned IDs
        final availableMembersMap = <String, TeamMember>{};
        final alreadyAssignedMembersMap = <String, TeamMember>{};

        // Combine all members from both lists
        final allMembers = [
          ...slot.availableMembers,
          ...slot.alreadyAssignedMembers,
        ];

        for (final member in allMembers) {
          // Check capability
          if (!member.canPerformRole(slot.role.key)) continue;

          // Check availability for entire event duration
          if (!member.allowMultipleAssignments &&
              !member.isAvailableForDateRange(slot.event.startDate, slot.event.endDate)) {
            continue;
          }

          // Separate based on effective assignment status
          if (member.allowMultipleAssignments) {
            availableMembersMap[member.id] = member;
          } else if (effectiveAssignedMemberIds.contains(member.id)) {
            alreadyAssignedMembersMap[member.id] = member;
          } else {
            availableMembersMap[member.id] = member;
          }
        }

        // Update the slot with recalculated member lists
        // Reset double assignment flags - will be recomputed after all updates
        final slotIndex = eventSlots.indexOf(slot);
        eventSlots[slotIndex] = AssignmentSlot(
          event: slot.event,
          role: slot.role,
          slotIndex: slot.slotIndex,
          currentAssignment: slot.currentAssignment,
          availableMembers: availableMembersMap.values.toList(),
          alreadyAssignedMembers: alreadyAssignedMembersMap.values.toList(),
          hasDoubleAssignment: false,  // Will be recomputed
          otherRoles: const [],  // Will be recomputed
        );
      }
    }

    // Now apply the optimistic currentAssignment changes
    // After this, we need to re-run double assignment detection for affected events
    final resultSlots = databaseSlots.map((dbSlot) {
      final slotKey = _getSlotKey(dbSlot);
      final operation = activeOperations[slotKey];

      // CRITICAL FIX: Check if this slot was deleted (even if operation expired)
      if (deletedSlots.contains(slotKey)) {
        // This slot was deleted - keep it empty even if DB has old data
        final eventSlots = slotsByEvent[dbSlot.event.id];
        final baseSlot = eventSlots != null
            ? eventSlots.firstWhere(
                (s) => s.role.key == dbSlot.role.key && s.slotIndex == dbSlot.slotIndex,
                orElse: () => dbSlot,
              )
            : dbSlot;
        return AssignmentSlot(
          event: baseSlot.event,
          role: baseSlot.role,
          slotIndex: baseSlot.slotIndex,
          currentAssignment: null,
          availableMembers: baseSlot.availableMembers,
          alreadyAssignedMembers: baseSlot.alreadyAssignedMembers,
          hasDoubleAssignment: false,
          otherRoles: const [],
        );
      }

      if (operation == null) {
        // No pending operation - use updated slot (if it was recalculated) or original
        final eventSlots = slotsByEvent[dbSlot.event.id];
        if (eventSlots != null) {
          final updatedSlot = eventSlots.firstWhere(
            (s) => s.role.key == dbSlot.role.key && s.slotIndex == dbSlot.slotIndex,
            orElse: () => dbSlot,
          );
          return updatedSlot;
        }
        return dbSlot;
      }

      // Apply optimistic operation to this slot
      if (operation.type == PendingOperationType.deleteAssignment) {
        final eventSlots = slotsByEvent[dbSlot.event.id];
        final baseSlot = eventSlots != null
            ? eventSlots.firstWhere(
                (s) => s.role.key == dbSlot.role.key && s.slotIndex == dbSlot.slotIndex,
                orElse: () => dbSlot,
              )
            : dbSlot;
        return AssignmentSlot(
          event: baseSlot.event,
          role: baseSlot.role,
          slotIndex: baseSlot.slotIndex,
          currentAssignment: null,
          availableMembers: baseSlot.availableMembers,
          alreadyAssignedMembers: baseSlot.alreadyAssignedMembers,
          hasDoubleAssignment: false,
          otherRoles: const [],
        );
      } else {
        // Create or Update
        final eventSlots = slotsByEvent[dbSlot.event.id];
        final baseSlot = eventSlots != null
            ? eventSlots.firstWhere(
                (s) => s.role.key == dbSlot.role.key && s.slotIndex == dbSlot.slotIndex,
                orElse: () => dbSlot,
              )
            : dbSlot;
        return AssignmentSlot(
          event: baseSlot.event,
          role: baseSlot.role,
          slotIndex: baseSlot.slotIndex,
          currentAssignment: operation.optimisticAssignment,
          availableMembers: baseSlot.availableMembers,
          alreadyAssignedMembers: baseSlot.alreadyAssignedMembers,
          hasDoubleAssignment: baseSlot.hasDoubleAssignment ?? false,
          otherRoles: baseSlot.otherRoles ?? const [],
        );
      }
    }).toList();

    // Re-run double assignment detection for affected events
    // This ensures hasDoubleAssignment and otherRoles are correct after optimistic updates
    for (final eventId in operationsByEvent.keys) {
      final eventResultSlots = resultSlots.where((s) => s.event.id == eventId).toList();

      for (final slot in eventResultSlots) {
        if (slot.isFilled) {
          // Check if member has allowMultipleAssignments - skip double assignment warning
          final teamMember = slot.currentAssignment!.teamMember;
          final skipDoubleAssignmentWarning = teamMember?.allowMultipleAssignments ?? false;

          // Check if this person has other assignments in the same event
          final otherAssignments = eventResultSlots.where((s) =>
              s.event.id == slot.event.id &&
              s.isFilled &&
              s.currentAssignment!.teamMemberId ==
                  slot.currentAssignment!.teamMemberId &&
              s.role.key != slot.role.key).toList();

          if (otherAssignments.isNotEmpty && !skipDoubleAssignmentWarning) {
            // This person has multiple roles in this event
            final otherRoleNames =
                otherAssignments.map((s) => s.role.hebrewName).toList();

            // Find and update this slot in resultSlots
            final slotIndex = resultSlots.indexOf(slot);
            resultSlots[slotIndex] = AssignmentSlot(
              event: slot.event,
              role: slot.role,
              slotIndex: slot.slotIndex,
              currentAssignment: slot.currentAssignment,
              availableMembers: slot.availableMembers,
              alreadyAssignedMembers: slot.alreadyAssignedMembers,
              hasDoubleAssignment: true,
              otherRoles: otherRoleNames,
            );
          }
        }
      }
    }

    print('  ✅ [MERGE_DEBUG] Merged slots count: ${resultSlots.length}');
    print('  🔚 [MERGE_DEBUG] _mergeSlotsWithOptimisticUpdates END');
    return resultSlots;
  }

  /// Optimistic create assignment handler
  Future<void> _onOptimisticCreateAssignment(
    OptimisticCreateAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    print('🎯 [BLOC_DEBUG] _onOptimisticCreateAssignment START');
    print('  Assignment ID: ${event.assignment.id}');
    print('  Slot Key: ${event.slotKey}');
    print('  Team Member: ${event.assignment.teamMember?.name} (${event.assignment.teamMemberId})');
    print('  Event: ${event.assignment.event?.name} (${event.assignment.eventId})');
    print('  Role: ${event.assignment.roleType}');
    print('  Slot Index: ${event.assignment.slotIndex}');

    if (state is! AssignmentSlotsLoaded) {
      print('  ❌ ERROR: State is not AssignmentSlotsLoaded!');
      print('    Current state: ${state.runtimeType}');
      return;
    }

    final currentState = state as AssignmentSlotsLoaded;

    // Create pending operation
    final operation = PendingOperation(
      id: event.operationId,
      type: PendingOperationType.createAssignment,
      slotKey: event.slotKey,
      optimisticAssignment: event.assignment,
      timestamp: DateTime.now(),
    );

    print('  📝 Created pending operation: ${operation.id}');

    // Add to BLoC-level pending operations map
    _pendingOperations = Map<String, PendingOperation>.from(_pendingOperations);
    _pendingOperations[event.slotKey] = operation;
    print('  📦 Pending operations count: ${_pendingOperations.length}');

    // Apply optimistic update
    print('  🎨 Applying optimistic update...');
    final updatedSlots = _applyOptimisticUpdate(
      currentState.slots,
      event.slotKey,
      event.assignment,
      isDelete: false,
    );

    print('  ✅ Optimistic update applied. Slots count: ${updatedSlots.length}');

    emit(AssignmentSlotsLoaded(
      updatedSlots,
      selectedEventIds: currentState.selectedEventIds,
      pendingOperations: _pendingOperations,
    ));

    print('  📤 State emitted with optimistic update');

    // Execute database operation
    print('  💾 Starting database write...');
    try {
      if (event.bypassConflicts) {
        await _repository.createAssignmentWithBypass(event.assignment);
      } else {
        await _repository.createAssignment(event.assignment);
      }
      print('  ✅ Database write SUCCESSFUL');
      print('  🧹 Removing completed pending operation: ${event.slotKey}');
      print('  🔄 Firestore stream will emit fresh state automatically');
      // CRITICAL FIX: Remove pending operation after successful write
      _pendingOperations.remove(event.slotKey);
      // Firestore stream will emit fresh state automatically
    } catch (e) {
      print('  ❌ Database write FAILED: $e');
      print('  🔙 Reverting to database state...');
      // On error: remove operation, revert to database state
      _pendingOperations.remove(event.slotKey);
      emit(AssignmentSlotsLoaded(
        currentState.slots,
        selectedEventIds: currentState.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
    }
    print('🏁 [BLOC_DEBUG] _onOptimisticCreateAssignment END');
  }

  /// Optimistic update assignment handler
  Future<void> _onOptimisticUpdateAssignment(
    OptimisticUpdateAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    print('🎯 [BLOC_DEBUG] _onOptimisticUpdateAssignment START');
    print('  Assignment ID: ${event.assignment.id}');
    print('  Slot Key: ${event.slotKey}');
    print('  Team Member: ${event.assignment.teamMember?.name} (${event.assignment.teamMemberId})');
    print('  Event: ${event.assignment.event?.name} (${event.assignment.eventId})');
    print('  Role: ${event.assignment.roleType}');

    if (state is! AssignmentSlotsLoaded) {
      print('  ❌ ERROR: State is not AssignmentSlotsLoaded!');
      print('    Current state: ${state.runtimeType}');
      return;
    }

    final currentState = state as AssignmentSlotsLoaded;

    // Create pending operation
    final operation = PendingOperation(
      id: event.operationId,
      type: PendingOperationType.updateAssignment,
      slotKey: event.slotKey,
      optimisticAssignment: event.assignment,
      timestamp: DateTime.now(),
    );

    print('  📝 Created pending operation: ${operation.id}');

    // Add to BLoC-level pending operations map
    _pendingOperations = Map<String, PendingOperation>.from(_pendingOperations);
    _pendingOperations[event.slotKey] = operation;
    print('  📦 Pending operations count: ${_pendingOperations.length}');

    // Apply optimistic update
    print('  🎨 Applying optimistic update...');
    final updatedSlots = _applyOptimisticUpdate(
      currentState.slots,
      event.slotKey,
      event.assignment,
      isDelete: false,
    );

    print('  ✅ Optimistic update applied. Slots count: ${updatedSlots.length}');

    emit(AssignmentSlotsLoaded(
      updatedSlots,
      selectedEventIds: currentState.selectedEventIds,
      pendingOperations: _pendingOperations,
    ));

    print('  📤 State emitted with optimistic update');

    // Execute database operation
    print('  💾 Starting database write...');
    try {
      await _repository.updateAssignment(event.assignment);
      print('  ✅ Database write SUCCESSFUL');
      print('  🧹 Removing completed pending operation: ${event.slotKey}');
      print('  🔄 Firestore stream will emit fresh state automatically');
      // CRITICAL FIX: Remove pending operation after successful write
      _pendingOperations.remove(event.slotKey);
      // Firestore stream will emit fresh state automatically
    } catch (e) {
      print('  ❌ Database write FAILED: $e');
      print('  🔙 Reverting to database state...');
      // On error: remove operation, revert to database state
      _pendingOperations.remove(event.slotKey);
      emit(AssignmentSlotsLoaded(
        currentState.slots,
        selectedEventIds: currentState.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
    }
    print('🏁 [BLOC_DEBUG] _onOptimisticUpdateAssignment END');
  }

  /// Optimistic delete assignment handler
  Future<void> _onOptimisticDeleteAssignment(
    OptimisticDeleteAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    if (state is! AssignmentSlotsLoaded) return;

    final currentState = state as AssignmentSlotsLoaded;

    // Create pending operation
    final operation = PendingOperation(
      id: event.operationId,
      type: PendingOperationType.deleteAssignment,
      slotKey: event.slotKey,
      optimisticAssignment: null,
      timestamp: DateTime.now(),
    );

    // Add to BLoC-level pending operations map
    _pendingOperations = Map<String, PendingOperation>.from(_pendingOperations);
    _pendingOperations[event.slotKey] = operation;

    // Apply optimistic update (clear slot)
    final updatedSlots = _applyOptimisticUpdate(
      currentState.slots,
      event.slotKey,
      null,
      isDelete: true,
    );

    emit(AssignmentSlotsLoaded(
      updatedSlots,
      selectedEventIds: currentState.selectedEventIds,
      pendingOperations: _pendingOperations,
    ));

    // Execute database operation
    try {
      await _repository.deleteAssignment(event.assignmentId);
      // CRITICAL FIX: Remove pending operation after successful delete
      _pendingOperations.remove(event.slotKey);
      // Firestore stream will emit fresh state automatically
    } catch (e) {
      // On error: remove operation, revert to database state
      _pendingOperations.remove(event.slotKey);
      emit(AssignmentSlotsLoaded(
        currentState.slots,
        selectedEventIds: currentState.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
    }
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

    // 4. Load roles and sort by sortOrder
    final allRoles = await _roleRepository.getAllRoles();
    final sortedRoles = allRoles
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Create a mapping from role key to Role for easy lookup
    final roleKeyToRole = <String, Role>{};
    for (final role in sortedRoles) {
      roleKeyToRole[role.key] = role;
    }

    // 5. Build slots
    final slots = <AssignmentSlot>[];

      for (final event in events) {
        // Iterate through roles in sortOrder (not enum order)
        for (final role in sortedRoles) {
          final requiredCount = event.roleRequirements[role.key] ?? 0;
          if (requiredCount == 0) continue; // Skip roles with 0 requirement

          // Get assignments for this event+role
          final roleAssignments = assignments
              .where((a) => a.eventId == event.id && a.roleType == role.key)
              .toList();

          // Create slots (one per required count)
          for (int i = 0; i < requiredCount; i++) {
            // Find if this slot is filled (match by slotIndex, not array position)
            final assignment = roleAssignments
                .cast<Assignment?>()
                .firstWhere((a) => a?.slotIndex == i, orElse: () => null);

            // CRITICAL: Verify the assignment still exists in the fresh assignment list
            // This prevents showing deleted assignments from stale cache
            if (assignment != null) {
              final stillExists = assignments.any((a) => a.id == assignment.id);
              if (!stillExists) {
                // Assignment was deleted, treat this slot as empty
                continue;
              }
            }

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
              if (!member.canPerformRole(role.key)) continue;

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
              role: role,
              slotIndex: i,
              currentAssignment: assignment,
              availableMembers: availableMembers,
              alreadyAssignedMembers: alreadyAssignedMembers,
            ));
          }
        }
      }

      // 6. Detect double assignments (person assigned to multiple roles in same event)
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
              s.role.key != slot.role.key).toList();

          if (otherAssignments.isNotEmpty && !skipDoubleAssignmentWarning) {
            // This person has multiple roles in this event
            final otherRoleNames =
                otherAssignments.map((s) => s.role.hebrewName).toList();
            slotsWithDoubleAssignmentDetection.add(AssignmentSlot(
              event: slot.event,
              role: slot.role,
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

    // 7. Sort slots by event date, then event name, then role sortOrder
    slotsWithDoubleAssignmentDetection.sort((a, b) {
      final dateCompare = a.event.startDate.compareTo(b.event.startDate);
      if (dateCompare != 0) return dateCompare;

      final nameCompare = a.event.name.compareTo(b.event.name);
      if (nameCompare != 0) return nameCompare;

      // Sort by role sortOrder (not enum order)
      return a.role.sortOrder.compareTo(b.role.sortOrder);
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

      // Build slots from database data (base state)
      final databaseSlots = await _buildSlotsFromAssignments(
        await _repository.getAllAssignments(),
        selectedEventIds: filterToUse,
      );

      // Merge optimistic updates on top of database state using BLoC-level pending operations
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        databaseSlots.slots,
        _pendingOperations,
      );

      emit(AssignmentSlotsLoaded(
        mergedSlots,
        selectedEventIds: filterToUse,
        pendingOperations: _pendingOperations,
      ));
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Rebuild slots using pre-loaded data (for real-time updates)
  Future<void> _onRebuildAssignmentSlotsFromData(
    RebuildAssignmentSlotsFromData rebuildEvent,
    Emitter<AssignmentState> emit,
  ) async {
    print('🔄 [STREAM_DEBUG] _onRebuildAssignmentSlotsFromData START');
    print('  Assignments count: ${rebuildEvent.assignments.length}');
    print('  Events count: ${rebuildEvent.events.length}');
    print('  Team Members count: ${rebuildEvent.teamMembers.length}');
    print('  Selected Event IDs: ${rebuildEvent.selectedEventIds}');
    print('  Current pending operations: ${_pendingOperations.length}');

    try {
      // Update the repository's cached assignments
      _repository.cacheCurrentAssignments(rebuildEvent.assignments);

      // Convert maps to lists for the build method
      final eventsList = rebuildEvent.events.values.toList();
      final teamMembersMap = rebuildEvent.teamMembers;
      final teamMembers = rebuildEvent.teamMembers.values.toList();

      // Load roles and sort by sortOrder
      final allRoles = await _roleRepository.getAllRoles();
      final sortedRoles = allRoles
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      // Create a mapping from role key to Role for easy lookup
      final roleKeyToRole = <String, Role>{};
      for (final role in sortedRoles) {
        roleKeyToRole[role.key] = role;
      }

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
        // Iterate through roles in sortOrder (not enum order)
        for (final role in sortedRoles) {
          final requiredCount = eventData.roleRequirements[role.key] ?? 0;
          if (requiredCount == 0) continue; // Skip roles with 0 requirement

          // Get assignments for this event+role from the assignments list
          final roleAssignments = rebuildEvent.assignments
              .where((a) => a.eventId == eventData.id && a.roleType == role.key)
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
              if (!member.canPerformRole(role.key)) continue;

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
              role: role,
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
              s.role.key != slot.role.key).toList();

          if (otherAssignments.isNotEmpty && !skipDoubleAssignmentWarning) {
            // This person has multiple roles in this event
            final otherRoleNames =
                otherAssignments.map((s) => s.role.hebrewName).toList();
            slotsWithDoubleAssignmentDetection.add(AssignmentSlot(
              event: slot.event,
              role: slot.role,
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

      // Sort slots by event date, then event name, then role sortOrder
      slotsWithDoubleAssignmentDetection.sort((a, b) {
        final dateCompare = a.event.startDate.compareTo(b.event.startDate);
        if (dateCompare != 0) return dateCompare;

        final nameCompare = a.event.name.compareTo(b.event.name);
        if (nameCompare != 0) return nameCompare;

        // Sort by role sortOrder (not enum order)
        return a.role.sortOrder.compareTo(b.role.sortOrder);
      });

      // Apply filter if needed
      final filteredSlots = rebuildEvent.selectedEventIds.isNotEmpty
          ? slotsWithDoubleAssignmentDetection.where((slot) => rebuildEvent.selectedEventIds.contains(slot.event.id)).toList()
          : slotsWithDoubleAssignmentDetection;

      // Remember the filter
      _currentEventFilter = rebuildEvent.selectedEventIds;

      // Merge optimistic updates on top of database state using BLoC-level pending operations
      print('  🔀 Merging with pending operations...');
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        filteredSlots,
        _pendingOperations,
      );

      print('  📤 Emitting AssignmentSlotsLoaded with ${mergedSlots.length} slots');
      emit(AssignmentSlotsLoaded(
        mergedSlots,
        selectedEventIds: rebuildEvent.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
      print('✅ [STREAM_DEBUG] _onRebuildAssignmentSlotsFromData END');
    } catch (e) {
      print('  ❌ ERROR in rebuild: $e');
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
      await _repository.updateAssignmentNotes(event.id, event.notes, alternativePhoneNumber: event.alternativePhoneNumber);
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
