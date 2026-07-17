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

  /// True when older history remains to be loaded via "load more".
  final bool hasMorePast;

  /// True while a "load more" fetch is in flight.
  final bool isLoadingMorePast;

  /// Slot keys ("${eventId}_${roleType}_${slotIndex}") with an unsaved staged
  /// change. Drives dirty-border UI and the Save/discard affordances.
  final Set<String> stagedSlotKeys;

  /// Subset of [stagedSlotKeys] whose underlying DB assignment was DELETED
  /// remotely while the row stayed dirty (a filled staged row anchored to a
  /// real DB assignment that no longer exists in the current DB snapshot).
  /// The row is deliberately kept visible (its staged state) and drives the
  /// red diagonal-stripe "deleted upstream, kept because dirty" overlay.
  final Set<String> stagedGoneSlotKeys;

  AssignmentSlotsLoaded(
    this.slots, {
    this.selectedEventIds = const {},
    this.pendingOperations = const {},
    this.hasMorePast = false,
    this.isLoadingMorePast = false,
    this.stagedSlotKeys = const {},
    this.stagedGoneSlotKeys = const {},
  })  : totalSlots = slots.length,
        filledSlots = slots.where((s) => s.isFilled).length,
        unfilledSlots = slots.where((s) => !s.isFilled).length;

  /// Number of slots with an unsaved staged change.
  int get stagedCount => stagedSlotKeys.length;

  @override
  List<Object?> get props => [
        slots,
        totalSlots,
        filledSlots,
        unfilledSlots,
        selectedEventIds,
        pendingOperations,
        hasMorePast,
        isLoadingMorePast,
        stagedSlotKeys,
        stagedGoneSlotKeys,
      ];

  /// Create a copy with new filter or pending operations
  AssignmentSlotsLoaded copyWith({
    Set<String>? selectedEventIds,
    Map<String, PendingOperation>? pendingOperations,
    bool? hasMorePast,
    bool? isLoadingMorePast,
    Set<String>? stagedSlotKeys,
    Set<String>? stagedGoneSlotKeys,
  }) {
    return AssignmentSlotsLoaded(
      slots,
      selectedEventIds: selectedEventIds ?? this.selectedEventIds,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      hasMorePast: hasMorePast ?? this.hasMorePast,
      isLoadingMorePast: isLoadingMorePast ?? this.isLoadingMorePast,
      stagedSlotKeys: stagedSlotKeys ?? this.stagedSlotKeys,
      stagedGoneSlotKeys: stagedGoneSlotKeys ?? this.stagedGoneSlotKeys,
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
  final bool persistent;

  const PendingOperation({
    required this.id,
    required this.type,
    required this.slotKey,
    this.optimisticAssignment,
    required this.timestamp,
    this.persistent = false,
  });

  /// Expire operations after 5 minutes
  /// This is a safety net for truly failed operations (network error, DB error, etc.)
  /// Normally, Firestore stream will confirm the operation long before this expires.
  /// The optimistic state persists until the database confirms it, regardless of network speed.
  /// Persistent operations never expire.
  bool get isExpired =>
      !persistent && DateTime.now().difference(timestamp).inMinutes > 5;

  @override
  List<Object?> get props => [id, type, slotKey, optimisticAssignment, timestamp, persistent];
}

/// Error state
class AssignmentError extends AssignmentState {
  final String message;

  const AssignmentError(this.message);

  @override
  List<Object?> get props => [message];
}
