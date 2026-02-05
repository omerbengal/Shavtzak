import 'package:equatable/equatable.dart';
import '../../core/constants/constraint_status.dart';
import 'vehicle_info.dart';

/// Date constraint representing when a team member is unavailable or available
class DateConstraint extends Equatable {
  final String id; // unique identifier for the constraint
  final DateTime startDate;
  final DateTime? endDate; // null means single day constraint
  final String? note; // optional note for the constraint
  final ConstraintStatus status; // status of the constraint request
  final ConstraintType constraintType; // type of constraint (unavailability/availability)
  final bool wasAutoRejectedFromCalendar; // true if constraint was auto-rejected due to calendar event deletion

  const DateConstraint({
    required this.id,
    required this.startDate,
    this.endDate,
    this.note,
    this.status = ConstraintStatus.approved, // default to approved for existing constraints
    required this.constraintType, // constraint type must be explicitly provided
    this.wasAutoRejectedFromCalendar = false, // default to false
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
  List<Object?> get props => [id, startDate, endDate, note, status, constraintType, wasAutoRejectedFromCalendar];

  @override
  String toString() {
    // If endDate is null or same as startDate, display single date
    if (endDate == null || _isSameDay(startDate, endDate!)) {
      return '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year}';
    }
    // Otherwise display date range
    return '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year} - ${endDate!.day.toString().padLeft(2, '0')}/${endDate!.month.toString().padLeft(2, '0')}/${endDate!.year}';
  }

  /// Copy with method for immutability
  DateConstraint copyWith({
    String? id,
    DateTime? startDate,
    DateTime? endDate,
    String? note,
    ConstraintStatus? status,
    ConstraintType? constraintType,
    bool? wasAutoRejectedFromCalendar,
  }) {
    return DateConstraint(
      id: id ?? this.id,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      note: note ?? this.note,
      status: status ?? this.status,
      constraintType: constraintType ?? this.constraintType,
      wasAutoRejectedFromCalendar: wasAutoRejectedFromCalendar ?? this.wasAutoRejectedFromCalendar,
    );
  }

  /// Helper methods to check constraint status
  bool isPending() => status == ConstraintStatus.pending;
  bool isApproved() => status == ConstraintStatus.approved;
  bool isRejected() => status == ConstraintStatus.rejected;

  /// Helper methods to check constraint type
  bool get isAvailability => constraintType == ConstraintType.availability;
  bool get isUnavailability => constraintType == ConstraintType.unavailability;
}

/// Team member domain entity
class TeamMember extends Equatable {
  final String id;
  final String name;
  final bool isActive;
  final bool isPermanent; // Whether this is a permanent team member
  final bool isArchived; // Whether this team member is archived (hidden from main lists)
  final List<DateConstraint> constraints; // When unavailable
  final Map<String, bool> roleCapabilities; // Which roles can they perform (role key -> bool)
  final String comments; // Comments about the team member
  final DateTime createdAt;
  final DateTime updatedAt;

  // Feature 13: User authentication fields
  final String uniqueKey; // UUID for user identification (not shown in UI)
  final bool isAdmin;     // Admin status (defaults to false for non-admin)

  // Passcode security fields
  final String? passcode;        // 4 or 6 digit passcode (null = no passcode)
  final int? passcodeLength;     // Length of passcode (4 or 6, null = no passcode)

  // Multiple assignment field
  final bool allowMultipleAssignments; // Allow assigning to same event multiple times

  // Phone number field
  final String? phoneNumber; // Optional Israeli phone number

  // Birthday field
  final DateTime? birthday; // Optional birthday date

  // Summary screen access field
  final bool canAccessSummaryScreen; // Whether non-admin can access summary screen

  // Vehicle info field
  final VehicleInfo? vehicleInfo; // Optional vehicle information

  // Event-based availability for non-permanent members
  final List<String> availableEventIds; // List of event IDs this member is available for (non-permanent only)

  const TeamMember({
    required this.id,
    required this.name,
    required this.isActive,
    this.isPermanent = false,
    this.isArchived = false,
    required this.constraints,
    required this.roleCapabilities,
    this.comments = '',
    required this.createdAt,
    required this.updatedAt,
    required this.uniqueKey,
    this.isAdmin = false,
    this.passcode,
    this.passcodeLength,
    this.allowMultipleAssignments = false,
    this.phoneNumber,
    this.birthday,
    this.canAccessSummaryScreen = false,
    this.vehicleInfo,
    this.availableEventIds = const [],
  });

  /// Check if team member is available on a given date
  /// Logic depends on member type and constraint type
  bool isAvailableOn(DateTime date) {
    if (!isActive || isArchived) return false;

    for (final constraint in constraints) {
      if (constraint.isAvailability && constraint.conflictsWith(date)) {
        // Non-permanent member availability - immediate effect
        return true; // Available if availability constraint matches
      }

      if (constraint.isUnavailability &&
          constraint.isApproved() &&
          constraint.conflictsWith(date)) {
        // Permanent member constraint - requires approval
        return false;
      }
    }

    // Default availability based on member type
    return isPermanent; // Permanent: available by default, Non-permanent: unavailable unless specified
  }

  /// Check if team member is available for ALL dates in a range
  /// Returns true if available on every day from startDate to endDate (inclusive)
  bool isAvailableForDateRange(DateTime startDate, DateTime? endDate) {
    if (!isActive || isArchived) return false;

    // Normalize dates to remove time component
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = endDate != null
        ? DateTime(endDate.year, endDate.month, endDate.day)
        : start;

    // Check each day in the range
    DateTime currentDate = start;
    while (!currentDate.isAfter(end)) {
      if (!isAvailableOn(currentDate)) {
        return false; // Not available on this day
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return true; // Available on all days
  }

  /// Check if team member can perform a given role
  bool canPerformRole(String roleKey) {
    return roleCapabilities[roleKey] == true;
  }

  /// Check if team member is qualified and available for a role on a date
  bool isQualifiedAndAvailableFor(String roleKey, DateTime date) {
    return canPerformRole(roleKey) && isAvailableOn(date);
  }

  /// Check if this team member can have constraints (permanent members only)
  bool get canHaveConstraints => isPermanent;

  /// Check if this team member can have availability (non-permanent members only)
  bool get canHaveAvailability => !isPermanent;

  /// Check if team member is available for a specific event
  /// For non-permanent members, uses event-based availability (availableEventIds)
  /// For permanent members, always returns true (they use date-based constraints instead)
  bool isAvailableForEvent(String eventId) {
    if (isArchived) return false;
    if (!isActive) return false;
    if (!isPermanent) {
      // Non-permanent members use event-based availability
      return availableEventIds.contains(eventId);
    }
    // Permanent members are available by default (constraints handle unavailability)
    return true;
  }

  /// Get list of all role keys this team member can perform
  List<String> get availableRoleKeys {
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
    bool? isArchived,
    List<DateConstraint>? constraints,
    Map<String, bool>? roleCapabilities,
    String? comments,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? uniqueKey,
    bool? isAdmin,
    String? passcode,
    int? passcodeLength,
    bool clearPasscode = false,
    bool? allowMultipleAssignments,
    String? phoneNumber,
    bool clearPhone = false,
    DateTime? birthday,
    bool clearBirthday = false,
    bool? canAccessSummaryScreen,
    VehicleInfo? vehicleInfo,
    bool clearVehicleInfo = false,
    List<String>? availableEventIds,
  }) {
    return TeamMember(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      isPermanent: isPermanent ?? this.isPermanent,
      isArchived: isArchived ?? this.isArchived,
      constraints: constraints ?? this.constraints,
      roleCapabilities: roleCapabilities ?? this.roleCapabilities,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      uniqueKey: uniqueKey ?? this.uniqueKey,
      isAdmin: isAdmin ?? this.isAdmin,
      passcode: clearPasscode ? null : (passcode ?? this.passcode),
      passcodeLength: clearPasscode ? null : (passcodeLength ?? this.passcodeLength),
      allowMultipleAssignments: allowMultipleAssignments ?? this.allowMultipleAssignments,
      phoneNumber: clearPhone ? null : (phoneNumber ?? this.phoneNumber),
      birthday: clearBirthday ? null : (birthday ?? this.birthday),
      canAccessSummaryScreen: canAccessSummaryScreen ?? this.canAccessSummaryScreen,
      vehicleInfo: clearVehicleInfo ? null : (vehicleInfo ?? this.vehicleInfo),
      availableEventIds: availableEventIds ?? this.availableEventIds,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        isActive,
        isPermanent,
        isArchived,
        constraints,
        roleCapabilities,
        comments,
        createdAt,
        updatedAt,
        uniqueKey,
        isAdmin,
        passcode,
        passcodeLength,
        allowMultipleAssignments,
        phoneNumber,
        birthday,
        canAccessSummaryScreen,
        vehicleInfo,
        availableEventIds,
      ];

  @override
  String toString() => 'TeamMember($id, $name, active: $isActive, admin: $isAdmin)';
}
