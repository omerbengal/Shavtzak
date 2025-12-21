import 'package:equatable/equatable.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/team_member.dart';

/// Represents a single assignable slot in the assignment grid
/// Each slot represents one role requirement from an event
class AssignmentSlot extends Equatable {
  final Event event;
  final RoleType roleType;
  final int slotIndex; // 0, 1, 2... for multiple slots of same role
  final Assignment? currentAssignment;
  final List<TeamMember> availableMembers; // Members not assigned to this event
  final List<TeamMember> alreadyAssignedMembers; // Members already assigned to this event
  final bool hasDoubleAssignment; // Person assigned to multiple roles in same event
  final List<String> otherRoles; // Other roles this person has in the same event

  const AssignmentSlot({
    required this.event,
    required this.roleType,
    required this.slotIndex,
    this.currentAssignment,
    required this.availableMembers,
    this.alreadyAssignedMembers = const [],
    this.hasDoubleAssignment = false,
    this.otherRoles = const [],
  });

  /// Whether this slot is currently filled
  bool get isFilled => currentAssignment != null;

  /// Display text for the event column
  String get eventDisplay => event.name;

  /// Display text for the role column
  String get roleDisplay => roleType.hebrewName;

  /// Name of the assigned person (if any)
  String? get assignedPersonName => currentAssignment?.teamMemberName;

  @override
  List<Object?> get props => [
        event, // Full Event object (extends Equatable) - includes location, name, dates, etc.
        roleType,
        slotIndex,
        currentAssignment, // Full Assignment object for real-time updates
        availableMembers,
        alreadyAssignedMembers,
        hasDoubleAssignment,
        otherRoles,
      ];

  @override
  String toString() {
    return 'AssignmentSlot(event: ${event.name}, role: ${roleType.hebrewName}, '
        'slotIndex: $slotIndex, filled: $isFilled, '
        'availableMembers: ${availableMembers.length})';
  }
}
