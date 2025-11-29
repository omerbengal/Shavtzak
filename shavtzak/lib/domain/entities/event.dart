import 'package:equatable/equatable.dart';
import '../../core/constants/role_types.dart';

/// Event domain entity
class Event extends Equatable {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String startTime; // Format: "HH:mm"
  final String endTime; // Format: "HH:mm"
  final String assemblyTime; // Format: "HH:mm"
  final String location;
  final bool requiresArmed;
  final String comments; // Comments about the event
  final Map<RoleType, int> roleRequirements; // How many people needed per role
  final DateTime createdAt;
  final DateTime updatedAt;

  const Event({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.assemblyTime,
    required this.location,
    required this.requiresArmed,
    this.comments = '',
    required this.roleRequirements,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Check if event occurs on a given date
  bool occursOn(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    return dateOnly.isAfter(start.subtract(const Duration(days: 1))) &&
        dateOnly.isBefore(end.add(const Duration(days: 1)));
  }

  /// Check if event is in the past
  bool get isPast {
    return endDate.isBefore(DateTime.now());
  }

  /// Check if event is upcoming (starts in the future)
  bool get isUpcoming {
    return startDate.isAfter(DateTime.now());
  }

  /// Check if event is currently active
  bool get isActive {
    final now = DateTime.now();
    return startDate.isBefore(now) && endDate.isAfter(now);
  }

  /// Get total number of people required for this event
  int get totalPeopleRequired {
    return roleRequirements.values.fold(0, (sum, count) => sum + count);
  }

  /// Get list of roles required for this event
  List<RoleType> get requiredRoles {
    return roleRequirements.entries
        .where((entry) => entry.value > 0)
        .map((entry) => entry.key)
        .toList();
  }

  /// Get number of people required for a specific role
  int getRequiredCountForRole(RoleType role) {
    return roleRequirements[role] ?? 0;
  }

  /// Check if a role is required for this event
  bool requiresRole(RoleType role) {
    return getRequiredCountForRole(role) > 0;
  }

  /// Get formatted date range string
  String get dateRangeString {
    if (_isSameDay(startDate, endDate)) {
      return '${startDate.day}/${startDate.month}/${startDate.year}';
    }
    return '${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// Copy with method for immutability
  Event copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    String? startTime,
    String? endTime,
    String? assemblyTime,
    String? location,
    bool? requiresArmed,
    String? comments,
    Map<RoleType, int>? roleRequirements,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Event(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      assemblyTime: assemblyTime ?? this.assemblyTime,
      location: location ?? this.location,
      requiresArmed: requiresArmed ?? this.requiresArmed,
      comments: comments ?? this.comments,
      roleRequirements: roleRequirements ?? this.roleRequirements,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        startDate,
        endDate,
        startTime,
        endTime,
        assemblyTime,
        location,
        requiresArmed,
        comments,
        roleRequirements,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() => 'Event($id, $name, $dateRangeString)';
}
