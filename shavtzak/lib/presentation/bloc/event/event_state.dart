import 'package:equatable/equatable.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/assignment.dart';
import '../../../core/utils/event_sorting.dart';
import '../../../core/utils/event_stretch.dart';
import '../../screens/event/quota_reduction_analyzer.dart';
import 'duplication_availability.dart';

/// Base state class for EventBloc
abstract class EventState extends Equatable {
  const EventState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class EventInitial extends EventState {
  const EventInitial();
}

/// Loading state
class EventLoading extends EventState {
  const EventLoading();
}

/// Events loaded successfully
class EventsLoaded extends EventState {
  final List<Event> events;
  final String? searchQuery;
  final int totalCount;
  final int upcomingCount;
  final int pastCount;
  final int activeCount;
  final Map<String, int> assignmentCounts; // Event ID -> count of assignments
  final Map<String, List<String>>
      eventBirthdays; // Event ID -> list of team member names with birthdays during event

  const EventsLoaded(
    this.events, {
    this.searchQuery,
    this.assignmentCounts = const {},
    this.eventBirthdays = const {},
  })  : totalCount = events.length,
        upcomingCount = 0,
        pastCount = 0,
        activeCount = 0;

  EventsLoaded.withCounts(
    List<Event> events, {
    this.searchQuery,
    this.assignmentCounts = const {},
    this.eventBirthdays = const {},
  })  : events = (List<Event>.from(events)..sort(compareEventsChronologically)),
        totalCount = events.length,
        upcomingCount = events.where((e) => e.isUpcoming).length,
        pastCount = events.where((e) => e.isPast).length,
        activeCount = events.where((e) => e.isActive).length;

  @override
  List<Object?> get props => [
        events,
        searchQuery,
        totalCount,
        upcomingCount,
        pastCount,
        activeCount,
        assignmentCounts,
        eventBirthdays,
      ];
}

/// Single event detail loaded
class EventDetailLoaded extends EventState {
  final Event event;

  const EventDetailLoaded(this.event);

  @override
  List<Object?> get props => [event];
}

/// No events found
class EventsEmpty extends EventState {
  final String message;
  final bool
      isFiltered; // true if empty due to filter, false if database is empty

  const EventsEmpty(this.message, {this.isFiltered = false});

  @override
  List<Object?> get props => [message, isFiltered];
}

/// Event operation in progress (create/update/delete)
class EventOperating extends EventState {
  final String operation; // 'creating', 'updating', 'deleting'

  const EventOperating(this.operation);

  @override
  List<Object?> get props => [operation];
}

/// Event operation succeeded
class EventOperationSuccess extends EventState {
  final String message;

  const EventOperationSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

/// Error state
class EventError extends EventState {
  final String message;

  const EventError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Event duplicated with conflicts
class EventDuplicatedWithConflicts extends EventState {
  final Event duplicatedEvent;
  final List<AssignmentConflict> assignmentConflicts;

  const EventDuplicatedWithConflicts({
    required this.duplicatedEvent,
    required this.assignmentConflicts,
  });

  @override
  List<Object?> get props => [duplicatedEvent, assignmentConflicts];
}

/// Event duplicated with quota reduction conflicts
class EventDuplicatedWithQuotaConflicts extends EventState {
  final Event duplicatedEvent;
  final List<RoleQuotaConflict> quotaConflicts;
  final Map<String, String>
      oldToNewAssignmentIds; // Map old assignment IDs to new ones

  const EventDuplicatedWithQuotaConflicts({
    required this.duplicatedEvent,
    required this.quotaConflicts,
    required this.oldToNewAssignmentIds,
  });

  @override
  List<Object?> get props =>
      [duplicatedEvent, quotaConflicts, oldToNewAssignmentIds];
}

/// Assignment conflict information
class AssignmentConflict extends Equatable {
  final String assignmentId;
  final String teamMemberName;
  final String roleName;
  final List<String> conflictReasons;

  const AssignmentConflict({
    required this.assignmentId,
    required this.teamMemberName,
    required this.roleName,
    required this.conflictReasons,
  });

  @override
  List<Object?> get props =>
      [assignmentId, teamMemberName, roleName, conflictReasons];
}

/// State emitted when duplication has conflicts that need user resolution
/// BEFORE any database writes occur
class DuplicationRequiresConflictResolution extends EventState {
  final Event originalEvent;
  final Event proposedEvent;
  final List<AssignmentDuplicationInfo> assignmentInfos;
  final Map<String, int> roleQuotas; // New quotas from proposed event

  const DuplicationRequiresConflictResolution({
    required this.originalEvent,
    required this.proposedEvent,
    required this.assignmentInfos,
    required this.roleQuotas,
  });

  /// Get assignments grouped by role
  Map<String, List<AssignmentDuplicationInfo>> get assignmentsByRole {
    final grouped = <String, List<AssignmentDuplicationInfo>>{};
    for (final info in assignmentInfos) {
      final roleKey = info.assignment.roleType;
      grouped.putIfAbsent(roleKey, () => []);
      grouped[roleKey]!.add(info);
    }
    return grouped;
  }

  /// Check if there are any conflicts
  bool get hasConflicts => assignmentInfos.any((a) => a.hasAnyConflict);

  /// Whether any copy would carry custom hours moved to the new dates: the
  /// dialog then lists them for the admin to confirm.
  bool get copiesCustomHours =>
      assignmentInfos.any((a) => a.hasMovedCustomHours);

  /// Get all assignments with availability conflicts
  List<AssignmentDuplicationInfo> get availabilityConflicts =>
      assignmentInfos.where((a) => a.hasAvailabilityConflict).toList();

  /// Get suggested exclusions (all availability-conflicted assignments, and
  /// every one the backend would refuse even with the bypass)
  Set<String> get suggestedExclusions => assignmentInfos
      .where((a) => a.hasAvailabilityConflict || !a.canKeep)
      .map((a) => a.assignment.id)
      .toSet();

  @override
  List<Object?> get props =>
      [originalEvent, proposedEvent, assignmentInfos, roleQuotas];
}

/// Information about a single assignment during duplication conflict analysis
class AssignmentDuplicationInfo extends Equatable {
  final Assignment assignment;
  final bool hasAvailabilityConflict;
  final String? availabilityReason;
  final bool
      isInOverQuotaRole; // True if this role has more assignments than new quota

  /// False when the backend would refuse this member even with the bypass
  /// (member gone, inactive, or no longer able to do the role): the dialog
  /// locks the row to removal.
  final bool canKeep;

  /// The hours the copy would carry when custom hours are duplicated: the
  /// member's hours moved to the new dates (`yyyy-MM-ddTHH:mm`). Both null when
  /// the copy would carry none. [hasAvailabilityConflict], [availabilityReason]
  /// and [canKeep] are judged with these hours.
  final String? movedCustomStartAt;
  final String? movedCustomEndAt;

  /// The same judgement made as if the admin did not copy the moved hours, so
  /// the copy held the member for the whole new event. Null when the copy
  /// carries no moved hours (there is only one judgement then).
  final DuplicationAvailability? availabilityWithEventHours;

  const AssignmentDuplicationInfo({
    required this.assignment,
    required this.hasAvailabilityConflict,
    this.availabilityReason,
    required this.isInOverQuotaRole,
    this.canKeep = true,
    this.movedCustomStartAt,
    this.movedCustomEndAt,
    this.availabilityWithEventHours,
  });

  /// True if this assignment has any type of conflict
  bool get hasAnyConflict => hasAvailabilityConflict || isInOverQuotaRole;

  /// The moved hours as an interval; null when the copy carries none or they
  /// cannot be read.
  WallInterval? get movedCustomWindow =>
      customHoursInterval(movedCustomStartAt, movedCustomEndAt);

  /// Whether the copy would carry moved custom hours.
  bool get hasMovedCustomHours => movedCustomWindow != null;

  @override
  List<Object?> get props => [
        assignment,
        hasAvailabilityConflict,
        availabilityReason,
        isInOverQuotaRole,
        canKeep,
        movedCustomStartAt,
        movedCustomEndAt,
        availabilityWithEventHours,
      ];
}
