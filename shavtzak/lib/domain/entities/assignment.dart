import 'package:equatable/equatable.dart';
import '../../core/constants/role_types.dart';
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
  final String? alternativePhoneNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Computed fields (populated via joins, not stored)
  final Event? event;
  final TeamMember? teamMember;

  const Assignment({
    required this.id,
    required this.eventId,
    required this.teamMemberId,
    required this.roleType,
    required this.slotIndex,
    required this.status,
    required this.notes,
    this.alternativePhoneNumber,
    required this.createdAt,
    required this.updatedAt,
    this.event,
    this.teamMember,
  });

  /// Check if this assignment is confirmed
  bool get isConfirmed => status == AssignmentStatus.confirmed;

  /// Check if this assignment is pending
  bool get isPending => status == AssignmentStatus.pending;

  /// Check if this assignment is declined
  bool get isDeclined => status == AssignmentStatus.declined;

  /// Get the event name (from populated event)
  String? get eventName => event?.name;

  /// Get the team member name (from populated teamMember)
  String? get teamMemberName => teamMember?.name;

  /// Check if this assignment conflicts with team member availability
  /// Returns true if team member is unavailable on ANY of the event dates
  /// Includes time-based conflict detection
  bool hasAvailabilityConflict() {
    if (event == null || teamMember == null) return false;

    // Use event-aware availability check that considers both dates and times
    return !teamMember!.isAvailableForEventWithTime(event!);
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
  }) {
    return Assignment(
      id: id,
      eventId: eventId,
      teamMemberId: teamMemberId,
      roleType: roleType,
      slotIndex: slotIndex,
      status: status,
      notes: notes,
      alternativePhoneNumber: alternativePhoneNumber,
      createdAt: createdAt,
      updatedAt: updatedAt,
      event: event ?? this.event,
      teamMember: teamMember ?? this.teamMember,
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
    String? Function()? alternativePhoneNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    Event? event,
    TeamMember? teamMember,
  }) {
    return Assignment(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      teamMemberId: teamMemberId ?? this.teamMemberId,
      roleType: roleType ?? this.roleType,
      slotIndex: slotIndex ?? this.slotIndex,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      alternativePhoneNumber: alternativePhoneNumber != null ? alternativePhoneNumber() : this.alternativePhoneNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      event: event ?? this.event,
      teamMember: teamMember ?? this.teamMember,
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
        alternativePhoneNumber,
        createdAt,
        updatedAt,
        // Include event and teamMember in equality so that
        // changes to nested objects trigger UI updates
        event,
        teamMember,
      ];

  @override
  String toString() =>
      'Assignment($id, event: ${eventName ?? eventId}, member: ${teamMemberName ?? teamMemberId}, role: $roleType)';
}
