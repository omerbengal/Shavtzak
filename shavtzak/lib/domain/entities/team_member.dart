import 'package:equatable/equatable.dart';
import '../../core/constants/role_types.dart';

/// Date constraint representing when a team member is unavailable
class DateConstraint extends Equatable {
  final DateTime startDate;
  final DateTime? endDate; // null means single day constraint

  const DateConstraint({
    required this.startDate,
    this.endDate,
  });

  /// Check if a given date falls within this constraint
  bool conflictsWith(DateTime date) {
    if (endDate == null) {
      // Single day constraint - check if dates match (ignoring time)
      return _isSameDay(date, startDate);
    }

    // Range constraint - check if date is within range
    final dateOnly = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate!.year, endDate!.month, endDate!.day);

    return dateOnly.isAfter(start.subtract(const Duration(days: 1))) &&
        dateOnly.isBefore(end.add(const Duration(days: 1)));
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  List<Object?> get props => [startDate, endDate];

  @override
  String toString() {
    if (endDate == null) {
      return '${startDate.day}/${startDate.month}/${startDate.year}';
    }
    return '${startDate.day}/${startDate.month}/${startDate.year} - ${endDate!.day}/${endDate!.month}/${endDate!.year}';
  }
}

/// Team member domain entity
class TeamMember extends Equatable {
  final String id;
  final String name;
  final bool isActive;
  final bool isPermanent; // Whether this is a permanent team member
  final List<DateConstraint> constraints; // When unavailable
  final Map<RoleType, bool> roleCapabilities; // Which roles can they perform
  final String comments; // Comments about the team member
  final DateTime createdAt;
  final DateTime updatedAt;

  const TeamMember({
    required this.id,
    required this.name,
    required this.isActive,
    this.isPermanent = false,
    required this.constraints,
    required this.roleCapabilities,
    this.comments = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Check if team member is available on a given date
  bool isAvailableOn(DateTime date) {
    if (!isActive) return false;

    for (final constraint in constraints) {
      if (constraint.conflictsWith(date)) {
        return false;
      }
    }
    return true;
  }

  /// Check if team member can perform a given role
  bool canPerformRole(RoleType role) {
    return roleCapabilities[role] == true;
  }

  /// Check if team member is qualified and available for a role on a date
  bool isQualifiedAndAvailableFor(RoleType role, DateTime date) {
    return canPerformRole(role) && isAvailableOn(date);
  }

  /// Get list of all roles this team member can perform
  List<RoleType> get availableRoles {
    return roleCapabilities.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  /// Copy with method for immutability
  TeamMember copyWith({
    String? id,
    String? name,
    bool? isActive,
    bool? isPermanent,
    List<DateConstraint>? constraints,
    Map<RoleType, bool>? roleCapabilities,
    String? comments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TeamMember(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      isPermanent: isPermanent ?? this.isPermanent,
      constraints: constraints ?? this.constraints,
      roleCapabilities: roleCapabilities ?? this.roleCapabilities,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        isActive,
        isPermanent,
        constraints,
        roleCapabilities,
        comments,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() => 'TeamMember($id, $name, active: $isActive)';
}
