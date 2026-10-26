import 'package:equatable/equatable.dart';
import '../../core/constants/constraint_status.dart';
import '../../core/utils/event_stretch.dart';
import '../../core/utils/time_range_utils.dart';
import 'vehicle_info.dart';
import 'event.dart';

/// Date constraint representing when a team member is unavailable or available
class DateConstraint extends Equatable {
  final String id; // unique identifier for the constraint
  final DateTime startDate;
  final DateTime? endDate; // null means single day constraint
  final String? note; // optional note for the constraint
  final ConstraintStatus status; // status of the constraint request
  final ConstraintType
      constraintType; // type of constraint (unavailability/availability)
  final bool
      wasAutoRejectedFromCalendar; // true if constraint was auto-rejected due to calendar event deletion
  final String?
      startTime; // Start time in "HH:mm" format (optional, null = entire day)
  final String?
      endTime; // End time in "HH:mm" format (optional, null = entire day)
  final RepeatType? repeatType; // null = one-time, non-null = recurring pattern
  final int?
      repeatDay; // Weekly: weekday (Mon=1..Sun=7), Monthly: day-of-month (1..31)
  final DateTime? repeatEndDate; // Required for recurring constraints

  const DateConstraint({
    required this.id,
    required this.startDate,
    this.endDate,
    this.note,
    this.status = ConstraintStatus
        .approved, // default to approved for existing constraints
    required this.constraintType, // constraint type must be explicitly provided
    this.wasAutoRejectedFromCalendar = false, // default to false
    this.startTime,
    this.endTime,
    this.repeatType,
    this.repeatDay,
    this.repeatEndDate,
  });

  /// Check if a given date falls within this constraint
  bool conflictsWith(DateTime date) {
    if (repeatType != null) {
      return _matchesRepeatPattern(date);
    }

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

  bool _matchesRepeatPattern(DateTime date) {
    if (repeatEndDate == null) return false;

    final dateOnly = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(
      repeatEndDate!.year,
      repeatEndDate!.month,
      repeatEndDate!.day,
    );

    if (dateOnly.isBefore(start) || dateOnly.isAfter(end)) {
      return false;
    }

    switch (repeatType!) {
      case RepeatType.daily:
        return true;
      case RepeatType.weekly:
        return repeatDay != null && dateOnly.weekday == repeatDay;
      case RepeatType.monthly:
        return repeatDay != null && dateOnly.day == repeatDay;
    }
  }

  @override
  List<Object?> get props => [
        id,
        startDate,
        endDate,
        note,
        status,
        constraintType,
        wasAutoRejectedFromCalendar,
        startTime,
        endTime,
        repeatType,
        repeatDay,
        repeatEndDate,
      ];

  @override
  String toString() {
    if (repeatType != null) {
      final endDateStr = repeatEndDate != null
          ? '${repeatEndDate!.day.toString().padLeft(2, '0')}/${repeatEndDate!.month.toString().padLeft(2, '0')}/${repeatEndDate!.year}'
          : '?';
      final pattern = repeatPatternDescription();
      if (startTime != null && endTime != null) {
        return '$pattern ($startTime-$endTime), עד $endDateStr';
      }
      return '$pattern, עד $endDateStr';
    }

    // If endDate is null or same as startDate, display single date
    final dateStr = endDate == null || _isSameDay(startDate, endDate!)
        ? '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year}'
        : '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year} - ${endDate!.day.toString().padLeft(2, '0')}/${endDate!.month.toString().padLeft(2, '0')}/${endDate!.year}';

    // Add time range if specified
    if (startTime != null && endTime != null) {
      return '$dateStr ($startTime-$endTime)';
    } else if (startTime != null || endTime != null) {
      // Only one time specified (shouldn't happen normally, but handle it)
      return '$dateStr (${startTime ?? '?'}-${endTime ?? '?'})';
    }

    return dateStr;
  }

  /// The recurrence in Hebrew ("כל יום", "כל יום שלישי", "כל 15 לחודש").
  /// Only for a recurring constraint ([repeatType] set).
  String repeatPatternDescription() {
    switch (repeatType!) {
      case RepeatType.daily:
        return 'כל יום';
      case RepeatType.weekly:
        return 'כל יום ${_weekdayHebrewName(repeatDay)}';
      case RepeatType.monthly:
        return 'כל ${repeatDay ?? '?'} לחודש';
    }
  }

  String _weekdayHebrewName(int? weekday) {
    switch (weekday) {
      case 1:
        return 'שני';
      case 2:
        return 'שלישי';
      case 3:
        return 'רביעי';
      case 4:
        return 'חמישי';
      case 5:
        return 'שישי';
      case 6:
        return 'שבת';
      case 7:
        return 'ראשון';
      default:
        return '?';
    }
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
    String? startTime,
    String? endTime,
    RepeatType? repeatType,
    int? repeatDay,
    DateTime? repeatEndDate,
    bool clearStartTime = false,
    bool clearEndTime = false,
    bool clearRepeatType = false,
    bool clearRepeatDay = false,
    bool clearRepeatEndDate = false,
  }) {
    return DateConstraint(
      id: id ?? this.id,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      note: note ?? this.note,
      status: status ?? this.status,
      constraintType: constraintType ?? this.constraintType,
      wasAutoRejectedFromCalendar:
          wasAutoRejectedFromCalendar ?? this.wasAutoRejectedFromCalendar,
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      repeatType: clearRepeatType ? null : (repeatType ?? this.repeatType),
      repeatDay: clearRepeatDay ? null : (repeatDay ?? this.repeatDay),
      repeatEndDate:
          clearRepeatEndDate ? null : (repeatEndDate ?? this.repeatEndDate),
    );
  }

  /// This constraint's hours on [date] as (start, end); a null bound runs to
  /// that edge of the day. A one-time constraint over several days is one
  /// continuous block (see [TimeRangeUtils.rangeWindowOn]); a recurring one
  /// repeats [startTime]–[endTime] on every matching day.
  (String?, String?) timeWindowOn(DateTime date) {
    if (repeatType != null) return (startTime, endTime);
    return TimeRangeUtils.rangeWindowOn(
      day: date,
      firstDay: startDate,
      lastDay: endDate ?? startDate,
      startTime: startTime,
      endTime: endTime,
    );
  }

  /// Whether any of this constraint's time overlaps the event's continuous
  /// stretch (assembly on the first day → team end on the last day, nights
  /// included; see `event_stretch.dart`). Every occurrence of a recurring
  /// constraint counts. Status and type are the caller's business.
  bool blocksEventAssignment(Event event) =>
      constraintOverlapsStretch(this, eventStretch(event));

  /// Check if this constraint's hours on [date] overlap the event's hours.
  /// The caller has already matched [date] against the constraint ([conflictsWith]).
  ///
  /// Legacy, per-day comparison: only the date-based availability of
  /// non-permanent members ([TeamMember.isAvailableForEventWithTime]) still
  /// uses it, and it keeps that path's behaviour (start → show end on each
  /// day). Unavailability is judged by [blocksEventAssignment] instead.
  bool blocksEventOn(Event event, DateTime date) {
    // Use assemblyTime as the event's start time if available, otherwise startTime
    final eventStart =
        event.assemblyTime.isNotEmpty ? event.assemblyTime : event.startTime;
    final eventEnd = event.endTime;

    // If constraint has no time on this day, it applies to entire day (blocks assignment)
    final (windowStart, windowEnd) = timeWindowOn(date);
    if (windowStart == null && windowEnd == null) {
      return true; // Member is unavailable all day
    }

    // If event has no times but constraint does, the constraint still blocks
    // (member is unavailable during those hours on that day)
    if (eventStart.isEmpty && eventEnd.isEmpty) {
      return true;
    }

    // Check if the constraint's time range overlaps with event's time range
    // If they overlap, member is unavailable during the event
    return TimeRangeUtils.timesOverlap(
        windowStart, windowEnd, eventStart, eventEnd);
  }

  /// Helper methods to check constraint status
  bool isPending() => status == ConstraintStatus.pending;
  bool isApproved() => status == ConstraintStatus.approved;
  bool isRejected() => status == ConstraintStatus.rejected;

  /// Helper methods to check constraint type
  bool get isAvailability => constraintType == ConstraintType.availability;
  bool get isUnavailability => constraintType == ConstraintType.unavailability;

  /// Whether this constraint takes a permanent member out of assignments.
  /// A pending unavailability blocks just like an approved one — the member
  /// asked not to be assigned, and waiting for the admin's review must not
  /// leave the dates open. Only a rejected request stops blocking.
  bool get blocksAssignments =>
      isUnavailability && (isApproved() || isPending());
}

/// Team member domain entity
class TeamMember extends Equatable {
  final String id;
  final String name;
  final bool isActive;
  final bool isPermanent; // Whether this is a permanent team member
  final bool
      isArchived; // Whether this team member is archived (hidden from main lists)
  final List<DateConstraint> constraints; // When unavailable
  final Map<String, bool>
      roleCapabilities; // Which roles can they perform (role key -> bool)
  final String comments; // Comments about the team member
  final DateTime createdAt;
  final DateTime updatedAt;

  // Feature 13: User authentication fields
  final String uniqueKey; // UUID for user identification (not shown in UI)
  final bool isAdmin; // Admin status (defaults to false for non-admin)

  // Passcode security fields
  final String? passcode; // 4 or 6 digit passcode (null = no passcode)
  final int? passcodeLength; // Length of passcode (4 or 6, null = no passcode)

  // Multiple assignment field
  final bool
      allowMultipleAssignments; // Allow assigning to same event multiple times

  // Phone number field
  final String? phoneNumber; // Optional Israeli phone number

  // Email field
  final String? email; // Optional email address

  // Birthday field
  final DateTime? birthday; // Optional birthday date

  // Summary screen access field
  final bool
      canAccessSummaryScreen; // Whether non-admin can access summary screen

  // Shamap export access field
  final bool
      canAccessShamapExport; // Whether team member can access shamap export flow

  // Constraints examining access field
  final bool
      canAccessConstraintsExamining; // Whether team member can access constraints examining flow

  // Task management access field
  final bool
      canManageTasks; // Whether a non-admin can create, edit and delete tasks

  // Vehicle info field
  final VehicleInfo? vehicleInfo; // Optional vehicle information

  // Event-based availability for non-permanent members
  final List<String>
      availableEventIds; // List of event IDs this member is available for (non-permanent only)

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
    this.email,
    this.birthday,
    this.canAccessSummaryScreen = false,
    this.canAccessShamapExport = false,
    this.canAccessConstraintsExamining = false,
    this.canManageTasks = false,
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

      if (constraint.blocksAssignments && constraint.conflictsWith(date)) {
        // Permanent member constraint - approved or still pending
        return false;
      }
    }

    // Default availability based on member type
    return isPermanent; // Permanent: available by default, Non-permanent: unavailable unless specified
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

  /// Whether the member can be assigned to [event].
  ///
  /// - Inactive or archived: never.
  /// - Permanent: available unless an approved or pending unavailability
  ///   overlaps the event's continuous stretch ([constraintsBlockingEvent]).
  /// - Non-permanent: only when the event is in [availableEventIds], or
  ///   through the legacy date-based availability covering every event day.
  ///
  /// The backend's `memberAvailableForEvent` applies the same rule; both run
  /// shared/test-fixtures/event_conflict_cases.json.
  bool isAvailableForEventWithTime(Event event) {
    if (isArchived || !isActive) return false;

    if (isPermanent) {
      return constraintsBlockingEvent(event).isEmpty;
    } else {
      // Non-permanent members: unavailable by default
      // Check event-based availability first (new system used by AvailabilityScreen)
      if (availableEventIds.contains(event.id)) {
        return true;
      }

      // Fall back to date-based availability constraints (legacy system)
      // Must have availability for ALL event days, each judged per day by
      // blocksEventOn (this path keeps its old behaviour on purpose).
      final eventStart = DateTime(
          event.startDate.year, event.startDate.month, event.startDate.day);
      final eventEnd =
          DateTime(event.endDate.year, event.endDate.month, event.endDate.day);
      DateTime currentDate = eventStart;
      while (!currentDate.isAfter(eventEnd)) {
        bool availableOnDay = false;
        for (final constraint in constraints) {
          if (!constraint.isApproved()) continue;
          if (!constraint.isAvailability) continue;
          if (!constraint.conflictsWith(currentDate)) continue;

          // Date matches — check if the availability's time range covers the event
          if (constraint.blocksEventOn(event, currentDate)) {
            availableOnDay = true;
            break;
          }
        }
        if (!availableOnDay) return false;
        currentDate = currentDate.add(const Duration(days: 1));
      }
      return true; // Available on all event days
    }
  }

  /// The approved or pending unavailability constraints that overlap
  /// [event]'s continuous stretch — the rule [isAvailableForEventWithTime]
  /// applies to permanent members. Lets callers name the blockers and tell
  /// pending from approved.
  List<DateConstraint> constraintsBlockingEvent(Event event) {
    if (!isPermanent) return const [];
    final stretch = eventStretch(event);
    return constraints
        .where((constraint) =>
            constraint.blocksAssignments &&
            constraintOverlapsStretch(constraint, stretch))
        .toList();
  }

  /// Get list of all role keys this team member can perform
  List<String> get availableRoleKeys {
    return roleCapabilities.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  bool get hasPasscode => (passcodeLength ?? 0) > 0;

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
    String? email,
    bool clearEmail = false,
    DateTime? birthday,
    bool clearBirthday = false,
    bool? canAccessSummaryScreen,
    bool? canAccessShamapExport,
    bool? canAccessConstraintsExamining,
    bool? canManageTasks,
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
      passcodeLength:
          clearPasscode ? null : (passcodeLength ?? this.passcodeLength),
      allowMultipleAssignments:
          allowMultipleAssignments ?? this.allowMultipleAssignments,
      phoneNumber: clearPhone ? null : (phoneNumber ?? this.phoneNumber),
      email: clearEmail ? null : (email ?? this.email),
      birthday: clearBirthday ? null : (birthday ?? this.birthday),
      canAccessSummaryScreen:
          canAccessSummaryScreen ?? this.canAccessSummaryScreen,
      canAccessShamapExport:
          canAccessShamapExport ?? this.canAccessShamapExport,
      canAccessConstraintsExamining:
          canAccessConstraintsExamining ?? this.canAccessConstraintsExamining,
      canManageTasks: canManageTasks ?? this.canManageTasks,
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
        email,
        birthday,
        canAccessSummaryScreen,
        canAccessShamapExport,
        canAccessConstraintsExamining,
        canManageTasks,
        vehicleInfo,
        availableEventIds,
      ];

  @override
  String toString() =>
      'TeamMember($id, $name, active: $isActive, admin: $isAdmin)';
}
