import 'package:equatable/equatable.dart';
import '../../../domain/entities/assignment.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../screens/assignment/models/assignment_slot.dart';

/// Base state class for AssignmentBloc
abstract class AssignmentState extends Equatable {
  const AssignmentState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class AssignmentInitial extends AssignmentState {
  const AssignmentInitial();
}

/// Loading state
class AssignmentLoading extends AssignmentState {
  const AssignmentLoading();
}

/// Assignments loaded successfully
class AssignmentsLoaded extends AssignmentState {
  final List<Assignment> assignments;
  final String? filterType; // 'all', 'event', 'person', 'dateRange'
  final String? filterId; // eventId or teamMemberId
  final int totalCount;
  final int pendingCount;
  final int confirmedCount;
  final int declinedCount;
  final int conflictCount;

  const AssignmentsLoaded(
    this.assignments, {
    this.filterType,
    this.filterId,
  })  : totalCount = assignments.length,
        pendingCount = 0,
        confirmedCount = 0,
        declinedCount = 0,
        conflictCount = 0;

  AssignmentsLoaded.withCounts(
    this.assignments, {
    this.filterType,
    this.filterId,
  })  : totalCount = assignments.length,
        pendingCount = assignments.where((a) => a.isPending).length,
        confirmedCount = assignments.where((a) => a.isConfirmed).length,
        declinedCount = assignments.where((a) => a.isDeclined).length,
        conflictCount = assignments.where((a) => a.hasConflicts).length;

  @override
  List<Object?> get props => [
        assignments,
        filterType,
        filterId,
        totalCount,
        pendingCount,
        confirmedCount,
        declinedCount,
        conflictCount,
      ];
}

/// Assignment slots loaded for grid view
class AssignmentSlotsLoaded extends AssignmentState {
  final List<AssignmentSlot> slots;
  final int totalSlots;
  final int filledSlots;
  final int unfilledSlots;
  final Set<String> selectedEventIds; // Event IDs to filter by (empty = no filter)
  final Map<String, PendingOperation> pendingOperations; // Tracks pending optimistic updates

  AssignmentSlotsLoaded(
    this.slots, {
    this.selectedEventIds = const {},
    this.pendingOperations = const {},
  })  : totalSlots = slots.length,
        filledSlots = slots.where((s) => s.isFilled).length,
        unfilledSlots = slots.where((s) => !s.isFilled).length;

  @override
  List<Object?> get props => [slots, totalSlots, filledSlots, unfilledSlots, selectedEventIds, pendingOperations];

  /// Create a copy with new filter or pending operations
  AssignmentSlotsLoaded copyWith({
    Set<String>? selectedEventIds,
    Map<String, PendingOperation>? pendingOperations,
  }) {
    return AssignmentSlotsLoaded(
      slots,
      selectedEventIds: selectedEventIds ?? this.selectedEventIds,
      pendingOperations: pendingOperations ?? this.pendingOperations,
    );
  }
}

/// Single assignment detail loaded
class AssignmentDetailLoaded extends AssignmentState {
  final Assignment assignment;

  const AssignmentDetailLoaded(this.assignment);

  @override
  List<Object?> get props => [assignment];
}

/// Assignment statistics loaded
class AssignmentStatsLoaded extends AssignmentState {
  final Map<String, dynamic> stats;

  const AssignmentStatsLoaded(this.stats);

  @override
  List<Object?> get props => [stats];
}

/// Event assignment statistics loaded
class EventAssignmentStatsLoaded extends AssignmentState {
  final String eventId;
  final Map<dynamic, AssignmentStats> roleStats;

  const EventAssignmentStatsLoaded(this.eventId, this.roleStats);

  @override
  List<Object?> get props => [eventId, roleStats];
}

/// No assignments found
class AssignmentsEmpty extends AssignmentState {
  final String message;

  const AssignmentsEmpty(this.message);

  @override
  List<Object?> get props => [message];
}

/// Assignment operation in progress (create/update/delete)
class AssignmentOperating extends AssignmentState {
  final String operation; // 'creating', 'updating', 'deleting'

  const AssignmentOperating(this.operation);

  @override
  List<Object?> get props => [operation];
}

/// Assignment operation succeeded
class AssignmentOperationSuccess extends AssignmentState {
  final String message;

  const AssignmentOperationSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

/// Assignment has conflicts warning
class AssignmentConflictWarning extends AssignmentState {
  final List<String> conflicts;
  final Assignment assignment;

  const AssignmentConflictWarning(this.conflicts, this.assignment);

  @override
  List<Object?> get props => [conflicts, assignment];
}

/// Pending operation type for optimistic updates
enum PendingOperationType {
  createAssignment,
  updateAssignment,
  deleteAssignment,
}

/// Tracks a pending optimistic operation
class PendingOperation extends Equatable {
  final String id;
  final PendingOperationType type;
  final String slotKey; // "${eventId}_${roleType}_${slotIndex}"
  final Assignment? optimisticAssignment;
  final DateTime timestamp;

  const PendingOperation({
    required this.id,
    required this.type,
    required this.slotKey,
    this.optimisticAssignment,
    required this.timestamp,
  });

  /// Expire operations after 5 minutes
  /// This is a safety net for truly failed operations (network error, DB error, etc.)
  /// Normally, Firestore stream will confirm the operation long before this expires.
  /// The optimistic state persists until the database confirms it, regardless of network speed.
  bool get isExpired =>
      DateTime.now().difference(timestamp).inMinutes > 5;

  @override
  List<Object?> get props => [id, type, slotKey, optimisticAssignment, timestamp];
}

/// Error state
class AssignmentError extends AssignmentState {
  final String message;

  const AssignmentError(this.message);

  @override
  List<Object?> get props => [message];
}
