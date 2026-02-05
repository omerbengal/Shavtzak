import 'package:equatable/equatable.dart';

/// Event domain entity
class Event extends Equatable {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String startTime; // Format: "HH:mm" - Audience gathering time (שעת התכנסות קהל)
  final String endTime; // Format: "HH:mm"
  final String assemblyTime; // Format: "HH:mm"
  final String actualShowStartTime; // Format: "HH:mm" - Actual show start time (שעת תחילת המופע בפועל)
  final String location;
  final String? parkingLocation; // Parking location in "Name||lat,lng" format
  final List<String> parkingEditorIds; // IDs of team members who can edit parking
  final bool requiresArmed;
  final String comments; // Comments about the event
  final String? categoryId; // Foreign key to Category (null = uncategorized)
  final Map<String, int> roleRequirements; // How many people needed per role (role key -> count)
  final DateTime createdAt;
  final DateTime updatedAt;

  // Google Drive integration fields
  final String? driveFolderId; // Google Drive folder ID for event files
  final String? driveFolderLink; // Direct link to the Drive folder
  final bool isArchived; // True when folder has been moved to archive

  const Event({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.assemblyTime,
    this.actualShowStartTime = '',
    this.location = '',
    this.parkingLocation,
    this.parkingEditorIds = const [],
    required this.requiresArmed,
    this.comments = '',
    this.categoryId,
    required this.roleRequirements,
    required this.createdAt,
    required this.updatedAt,
    this.driveFolderId,
    this.driveFolderLink,
    this.isArchived = false,
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

  /// Get list of role keys required for this event
  List<String> get requiredRoleKeys {
    return roleRequirements.entries
        .where((entry) => entry.value > 0)
        .map((entry) => entry.key)
        .toList();
  }

  /// Get number of people required for a specific role
  int getRequiredCountForRole(String roleKey) {
    return roleRequirements[roleKey] ?? 0;
  }

  /// Check if a role is required for this event
  bool requiresRole(String roleKey) {
    return getRequiredCountForRole(roleKey) > 0;
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

  /// Check if event has a Drive folder attached
  bool get hasDriveFolder => driveFolderId != null && driveFolderId!.isNotEmpty;

  /// Copy with method for immutability
  Event copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    String? startTime,
    String? endTime,
    String? assemblyTime,
    String? actualShowStartTime,
    String? location,
    String? parkingLocation,
    List<String>? parkingEditorIds,
    bool? requiresArmed,
    String? comments,
    String? categoryId,
    Map<String, int>? roleRequirements,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? driveFolderId,
    String? driveFolderLink,
    bool? isArchived,
    bool clearParkingLocation = false, // Flag to explicitly clear nullable fields
    bool clearCategoryId = false,
  }) {
    return Event(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      assemblyTime: assemblyTime ?? this.assemblyTime,
      actualShowStartTime: actualShowStartTime ?? this.actualShowStartTime,
      location: location ?? this.location,
      parkingLocation: clearParkingLocation ? null : (parkingLocation ?? this.parkingLocation),
      parkingEditorIds: parkingEditorIds ?? this.parkingEditorIds,
      requiresArmed: requiresArmed ?? this.requiresArmed,
      comments: comments ?? this.comments,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      roleRequirements: roleRequirements ?? this.roleRequirements,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      driveFolderId: driveFolderId ?? this.driveFolderId,
      driveFolderLink: driveFolderLink ?? this.driveFolderLink,
      isArchived: isArchived ?? this.isArchived,
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
        actualShowStartTime,
        location,
        parkingLocation,
        parkingEditorIds,
        requiresArmed,
        comments,
        categoryId,
        roleRequirements,
        createdAt,
        updatedAt,
        driveFolderId,
        driveFolderLink,
        isArchived,
      ];

  @override
  String toString() => 'Event($id, $name, $dateRangeString)';
}
