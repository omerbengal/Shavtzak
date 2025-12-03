import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/role_types.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../domain/entities/assignment.dart';
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

        // Reload slots to ensure UI shows current state
        if (previousState is AssignmentSlotsLoaded) {
          await _reloadSlotsAfterOperation(emit);
        }

        return;
      }

      await _repository.createAssignment(event.assignment);
      emit(const AssignmentOperationSuccess('השיבוץ נוסף בהצלחה'));

      // Check if we're in slots view and reload silently
      if (previousState is AssignmentSlotsLoaded) {
        await _reloadSlotsAfterOperation(emit);
      } else if (previousState is AssignmentsLoaded) {
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

        // Reload slots to ensure UI shows current state
        if (previousState is AssignmentSlotsLoaded) {
          await _reloadSlotsAfterOperation(emit);
        }

        return;
      }

      await _repository.updateAssignment(event.assignment);
      emit(const AssignmentOperationSuccess('השיבוץ עודכן בהצלחה'));

      // Check if we're in slots view and reload silently
      if (previousState is AssignmentSlotsLoaded) {
        await _reloadSlotsAfterOperation(emit);
      } else if (previousState is AssignmentsLoaded) {
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

      // Check if we're in slots view and reload silently
      if (previousState is AssignmentSlotsLoaded) {
        await _reloadSlotsAfterOperation(emit);
      } else if (previousState is AssignmentsLoaded) {
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
    emit(const AssignmentLoading());

    try {
      // Watch assignments, team members, and events
      final assignmentsStream = _repository.watchAssignments();
      final teamMembersStream = _teamRepository.watchTeamMembers();
      final eventsStream = _eventRepository.watchEvents();

      // Create a combined stream that rebuilds slots when any source changes
      // Map team member changes to trigger assignment fetch
      final teamMemberTriggerStream = teamMembersStream.asyncMap((_) async {
        // When team members change, fetch current assignments and rebuild
        final assignments = await _repository.getAllAssignments();
        return await _buildSlotsFromAssignments(assignments);
      });

      // Map assignment changes to rebuild slots
      final assignmentTriggerStream = assignmentsStream.asyncMap((assignments) async {
        return await _buildSlotsFromAssignments(assignments);
      });

      // Map event changes to trigger assignment fetch
      final eventTriggerStream = eventsStream.asyncMap((_) async {
        // When events change, fetch current assignments and rebuild
        final assignments = await _repository.getAllAssignments();
        return await _buildSlotsFromAssignments(assignments);
      });

      // Use a stream controller to merge all three streams manually
      final controller = StreamController<AssignmentSlotsLoaded>();

      final assignmentSub = assignmentTriggerStream.listen(
        (slots) => controller.add(slots),
        onError: (e) => controller.addError(e),
      );

      final teamMemberSub = teamMemberTriggerStream.listen(
        (slots) => controller.add(slots),
        onError: (e) => controller.addError(e),
      );

      final eventSub = eventTriggerStream.listen(
        (slots) => controller.add(slots),
        onError: (e) => controller.addError(e),
      );

      try {
        // Listen to the combined stream for real-time updates
        await emit.forEach<AssignmentSlotsLoaded>(
          controller.stream,
          onData: (slotsState) => slotsState,
          onError: (error, stackTrace) {
            return AssignmentError('שגיאה בטעינת שיבוצים: $error');
          },
        );
      } finally {
        // Clean up subscriptions and controller
        await assignmentSub.cancel();
        await teamMemberSub.cancel();
        await eventSub.cancel();
        await controller.close();
      }
    } catch (e) {
      emit(AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Build complete slots state from assignments
  /// Fetches latest events and team members, then builds slot grid
  Future<AssignmentSlotsLoaded> _buildSlotsFromAssignments(
    List<Assignment> assignments,
  ) async {
    // 1. Load all events
    final events = await _eventRepository.getAllEvents();

    // 2. Load all active team members
    final allMembers = await _teamRepository.getActiveTeamMembers();

    // 3. Build slots
    final slots = <AssignmentSlot>[];

      for (final event in events) {
        // For each role requirement in the event (in enum order)
        for (final role in RoleType.values) {
          final requiredCount = event.roleRequirements[role] ?? 0;
          if (requiredCount == 0) continue; // Skip roles with 0 requirement

          // Get assignments for this event+role
          final roleAssignments = assignments
              .where((a) => a.eventId == event.id && a.roleType == role)
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
              if (!member.canPerformRole(role)) continue;

              // Check availability
              if (!member.isAvailableOn(event.startDate)) continue;

              // Separate based on whether already assigned to this event
              if (assignedMemberIds.contains(member.id)) {
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
      final slotsWithDoubleAssignmentDetection = <AssignmentSlot>[];
      for (final slot in slots) {
        if (slot.isFilled) {
          // Check if this person has other assignments in the same event
          final otherAssignments = slots.where((s) =>
              s.event.id == slot.event.id &&
              s.isFilled &&
              s.currentAssignment!.teamMemberId ==
                  slot.currentAssignment!.teamMemberId &&
              s.roleType != slot.roleType).toList();

          if (otherAssignments.isNotEmpty) {
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

    // 4. Sort slots by event date, then event name, then role
    slotsWithDoubleAssignmentDetection.sort((a, b) {
      final dateCompare = a.event.startDate.compareTo(b.event.startDate);
      if (dateCompare != 0) return dateCompare;

      final nameCompare = a.event.name.compareTo(b.event.name);
      if (nameCompare != 0) return nameCompare;

      // Sort by enum order (not alphabetically)
      return a.roleType.index.compareTo(b.roleType.index);
    });

    return AssignmentSlotsLoaded(slotsWithDoubleAssignmentDetection);
  }

  /// Reload slots silently without emitting loading state
  /// Used after CRUD operations to update the UI without flickering
  Future<void> _reloadSlotsAfterOperation(Emitter<AssignmentState> emit) async {
    try {
      // 1. Load all events
      final events = await _eventRepository.getAllEvents();

      // 2. Load all active team members
      final allMembers = await _teamRepository.getActiveTeamMembers();

      // 3. Load all assignments
      final assignments = await _repository.getAllAssignments();

      // 4. Build slots
      final slots = <AssignmentSlot>[];

      for (final event in events) {
        // For each role requirement in the event (in enum order)
        for (final role in RoleType.values) {
          final requiredCount = event.roleRequirements[role] ?? 0;
          if (requiredCount == 0) continue; // Skip roles with 0 requirement

          // Get assignments for this event+role
          final roleAssignments = assignments
              .where((a) => a.eventId == event.id && a.roleType == role)
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
              if (!member.canPerformRole(role)) continue;

              // Check availability
              if (!member.isAvailableOn(event.startDate)) continue;

              // Separate based on whether already assigned to this event
              if (assignedMemberIds.contains(member.id)) {
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

      // 5. Detect double assignments
      final slotsWithDoubleAssignmentDetection = <AssignmentSlot>[];
      for (final slot in slots) {
        if (slot.isFilled) {
          // Check if this person has other assignments in the same event
          final otherAssignments = slots.where((s) =>
              s.event.id == slot.event.id &&
              s.isFilled &&
              s.currentAssignment!.teamMemberId ==
                  slot.currentAssignment!.teamMemberId &&
              s.roleType != slot.roleType).toList();

          if (otherAssignments.isNotEmpty) {
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

      emit(AssignmentSlotsLoaded(slotsWithDoubleAssignmentDetection));
    } catch (e) {
      // Don't silently fail - emit the slots loaded state even if there's an error
      // This ensures the UI doesn't disappear
      emit(AssignmentError('שגיאה ברענון שיבוצים: $e'));
    }
  }

  /// Apply event filter to current slots
  Future<void> _onApplyEventFilter(
    ApplyEventFilter event,
    Emitter<AssignmentState> emit,
  ) async {
    if (state is AssignmentSlotsLoaded) {
      final currentState = state as AssignmentSlotsLoaded;
      emit(currentState.copyWith(selectedEventIds: event.eventIds));
    }
  }

  /// Clear event filter
  Future<void> _onClearEventFilter(
    ClearEventFilter event,
    Emitter<AssignmentState> emit,
  ) async {
    if (state is AssignmentSlotsLoaded) {
      final currentState = state as AssignmentSlotsLoaded;
      emit(currentState.copyWith(selectedEventIds: {}));
    }
  }
}
