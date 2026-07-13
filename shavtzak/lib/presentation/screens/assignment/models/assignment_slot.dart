import 'package:equatable/equatable.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/role.dart';
import '../../../../domain/entities/team_member.dart';

/// Represents a single assignable slot in the assignment grid
/// Each slot represents one role requirement from an event
class AssignmentSlot extends Equatable {
  final Event event;
  final Role role;
  final int slotIndex; // 0, 1, 2... for multiple slots of same role
  final Assignment? currentAssignment;
  final List<TeamMember> availableMembers; // Members not assigned to this event
  final List<TeamMember> alreadyAssignedMembers; // Members already assigned to this event
  final bool hasDoubleAssignment; // Person assigned to multiple roles in same event
  final List<String> otherRoles; // Other roles this person has in the same event
  final List<TeamMember> sameDayAssignedMembers; // Members assigned to OTHER events on same day(s)
  final Map<String, List<String>> sameDayEventInfo; // memberId -> other event names

  /// Other events sharing a calendar day that the slot's ASSIGNED member is
  /// also assigned to. Empty when the slot is unfilled or the member is not
  /// double-booked. Distinct from [sameDayAssignedMembers], which is about
  /// CANDIDATES for this slot, not the person already in it.
  final List<Event> sameDayOtherEvents;

  /// True when this row represents an assignment that has no matching quota
  /// slot (quota reduced below its slotIndex, duplicate slotIndex, or a
  /// permanently-deleted role). Rendered as "מחוץ למכסה" and delete-only.
  final bool isOffQuota;

  const AssignmentSlot({
    required this.event,
    required this.role,
    required this.slotIndex,
    this.currentAssignment,
    required this.availableMembers,
    this.alreadyAssignedMembers = const [],
    this.hasDoubleAssignment = false,
    this.otherRoles = const [],
    this.sameDayAssignedMembers = const [],
    this.sameDayEventInfo = const {},
    this.sameDayOtherEvents = const [],
    this.isOffQuota = false,
  });

  /// Create a copy with updated fields (preserves every field, incl. isOffQuota)
  AssignmentSlot copyWith({
    Event? event,
    Role? role,
    int? slotIndex,
    Assignment? currentAssignment,
    List<TeamMember>? availableMembers,
    List<TeamMember>? alreadyAssignedMembers,
    bool? hasDoubleAssignment,
    List<String>? otherRoles,
    List<TeamMember>? sameDayAssignedMembers,
    Map<String, List<String>>? sameDayEventInfo,
    List<Event>? sameDayOtherEvents,
    bool? isOffQuota,
  }) {
    return AssignmentSlot(
      event: event ?? this.event,
      role: role ?? this.role,
      slotIndex: slotIndex ?? this.slotIndex,
      currentAssignment: currentAssignment ?? this.currentAssignment,
      availableMembers: availableMembers ?? this.availableMembers,
      alreadyAssignedMembers:
          alreadyAssignedMembers ?? this.alreadyAssignedMembers,
      hasDoubleAssignment: hasDoubleAssignment ?? this.hasDoubleAssignment,
      otherRoles: otherRoles ?? this.otherRoles,
      sameDayAssignedMembers:
          sameDayAssignedMembers ?? this.sameDayAssignedMembers,
      sameDayEventInfo: sameDayEventInfo ?? this.sameDayEventInfo,
      sameDayOtherEvents: sameDayOtherEvents ?? this.sameDayOtherEvents,
      isOffQuota: isOffQuota ?? this.isOffQuota,
    );
  }

  /// Whether this slot is currently filled
  bool get isFilled => currentAssignment != null;

  /// Display text for the event column
  String get eventDisplay => event.name;

  /// Display text for the role column
  String get roleDisplay => role.hebrewName;

  /// Role key (for compatibility with roleType.key)
  String get roleKey => role.key;

  /// Name of the assigned person (if any)
  String? get assignedPersonName => currentAssignment?.teamMemberName;

  @override
  List<Object?> get props => [
        event, // Full Event object (extends Equatable) - includes location, name, dates, etc.
        role, // Full Role object (extends Equatable)
        slotIndex,
        currentAssignment, // Full Assignment object for real-time updates
        availableMembers,
        alreadyAssignedMembers,
        hasDoubleAssignment,
        otherRoles,
        sameDayAssignedMembers,
        sameDayEventInfo,
        sameDayOtherEvents,
        isOffQuota,
      ];

  @override
  String toString() {
    return 'AssignmentSlot(event: ${event.name}, role: ${role.hebrewName}, '
        'slotIndex: $slotIndex, filled: $isFilled, '
        'availableMembers: ${availableMembers.length})';
  }
}
