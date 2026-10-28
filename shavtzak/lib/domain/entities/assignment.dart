import 'package:equatable/equatable.dart';
import '../../core/constants/role_types.dart';
import '../../core/utils/event_stretch.dart';
import 'assignment_label.dart';
import 'event.dart';
import 'team_member.dart';

/// Assignment domain entity

/// Assignment domain entity
/// THIS IS THE KEY ENTITY THAT FIXES THE V1 SYNC PROBLEM
///
/// Each assignment stores explicit foreign keys (eventId, teamMemberId)
/// instead of relying on positional data like V1's spreadsheet columns.
/// This ensures assignments always maintain correct links even when data changes.
class Assignment extends Equatable {
  final String id;
  final String eventId; // FK → Event
  final String teamMemberId; // FK → TeamMember
  final String roleType; // Role key (e.g., "eventCommander", "medic", or custom role)
  final int slotIndex; // Which slot (0, 1, 2...) for this role in the event
  final AssignmentStatus status;
  final String notes;
  final String? semanticLabelId;
  final String? alternativePhoneNumber;

  /// The member's own hours for this assignment (custom hours): two Israel
  /// wall-clock moments stored as `yyyy-MM-ddTHH:mm`, both set or both null.
  /// Null means the member is held for the whole event ([windowIn]). Read
  /// them through [customWindow], which never throws on a bad value.
  final String? customStartAt;
  final String? customEndAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Computed fields (populated via joins, not stored)
  final Event? event;
  final TeamMember? teamMember;
  final AssignmentLabel? semanticLabel;

  const Assignment({
    required this.id,
    required this.eventId,
    required this.teamMemberId,
    required this.roleType,
    required this.slotIndex,
    required this.status,
    required this.notes,
    this.semanticLabelId,
    this.alternativePhoneNumber,
    this.customStartAt,
    this.customEndAt,
    required this.createdAt,
    required this.updatedAt,
    this.event,
    this.teamMember,
    this.semanticLabel,
  });

  /// Check if this assignment is confirmed
  bool get isConfirmed => status == AssignmentStatus.confirmed;

  /// Check if this assignment is pending
  bool get isPending => status == AssignmentStatus.pending;

  /// Check if this assignment is declined
  bool get isDeclined => status == AssignmentStatus.declined;

  /// The custom hours as an interval, or null when the assignment has none or
  /// they cannot be used (unreadable, or the end is not after the start).
  WallInterval? get customWindow =>
      customHoursInterval(customStartAt, customEndAt);

  /// Whether the member has usable hours of their own for this assignment.
  bool get hasCustomHours => customWindow != null;

  /// The window the member is held for in [event]: their custom hours, else
  /// the event's whole stretch.
  WallInterval windowIn(Event event) => customWindow ?? eventStretch(event);

  /// Get the event name (from populated event)
  String? get eventName => event?.name;

  /// Get the team member name (from populated teamMember)
  String? get teamMemberName => teamMember?.name;

  /// Check if this assignment conflicts with team member availability
  /// Returns true if team member is unavailable in the assignment's window:
  /// their custom hours when set, else the event's whole stretch.
  /// Includes time-based conflict detection
  bool hasAvailabilityConflict() {
    if (event == null || teamMember == null) return false;

    // Use event-aware availability check that considers both dates and times
    return !teamMember!
        .isAvailableForEventWithTime(event!, window: windowIn(event!));
  }

  /// Check if team member is qualified for this role
  /// Returns true if team member cannot perform this role
  bool hasQualificationConflict() {
    if (teamMember == null) return false;
    return !teamMember!.canPerformRole(roleType);
  }

  /// Check if this assignment has any conflicts
  bool get hasConflicts {
    return hasAvailabilityConflict() || hasQualificationConflict();
  }

  /// Get list of conflict warnings
  List<String> get conflictWarnings {
    final warnings = <String>[];

    if (hasAvailabilityConflict()) {
      warnings.add('חבר הצוות לא זמין בתאריכים אלו');
    }

    if (hasQualificationConflict()) {
      warnings.add('חבר הצוות לא יכול לבצע תפקיד זה');
    }

    return warnings;
  }

  /// Create an assignment with populated event and team member
  /// This is used after fetching related entities from database
  Assignment withRelations({
    Event? event,
    TeamMember? teamMember,
    AssignmentLabel? Function()? semanticLabel,
  }) {
    return Assignment(
      id: id,
      eventId: eventId,
      teamMemberId: teamMemberId,
      roleType: roleType,
      slotIndex: slotIndex,
      status: status,
      notes: notes,
      semanticLabelId: semanticLabelId,
      alternativePhoneNumber: alternativePhoneNumber,
      customStartAt: customStartAt,
      customEndAt: customEndAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      event: event ?? this.event,
      teamMember: teamMember ?? this.teamMember,
      semanticLabel:
          semanticLabel != null ? semanticLabel() : this.semanticLabel,
    );
  }

  /// Copy with method for immutability
  Assignment copyWith({
    String? id,
    String? eventId,
    String? teamMemberId,
    String? roleType,
    int? slotIndex,
    AssignmentStatus? status,
    String? notes,
    String? Function()? semanticLabelId,
    String? Function()? alternativePhoneNumber,
    String? Function()? customStartAt,
    String? Function()? customEndAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Event? event,
    TeamMember? teamMember,
    AssignmentLabel? Function()? semanticLabel,
  }) {
    return Assignment(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      teamMemberId: teamMemberId ?? this.teamMemberId,
      roleType: roleType ?? this.roleType,
      slotIndex: slotIndex ?? this.slotIndex,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      semanticLabelId:
          semanticLabelId != null ? semanticLabelId() : this.semanticLabelId,
      alternativePhoneNumber: alternativePhoneNumber != null ? alternativePhoneNumber() : this.alternativePhoneNumber,
      customStartAt:
          customStartAt != null ? customStartAt() : this.customStartAt,
      customEndAt: customEndAt != null ? customEndAt() : this.customEndAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      event: event ?? this.event,
      teamMember: teamMember ?? this.teamMember,
      semanticLabel:
          semanticLabel != null ? semanticLabel() : this.semanticLabel,
    );
  }

  @override
  List<Object?> get props => [
        id,
        eventId,
        teamMemberId,
        roleType,
        slotIndex,
        status,
        notes,
        semanticLabelId,
        alternativePhoneNumber,
        customStartAt,
        customEndAt,
        createdAt,
        updatedAt,
        // Include event and teamMember in equality so that
        // changes to nested objects trigger UI updates
        event,
        teamMember,
        semanticLabel,
      ];

  @override
  String toString() =>
      'Assignment($id, event: ${eventName ?? eventId}, member: ${teamMemberName ?? teamMemberId}, role: $roleType)';
}
