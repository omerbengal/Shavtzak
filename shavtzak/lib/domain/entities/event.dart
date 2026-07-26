import 'package:equatable/equatable.dart';
import 'participant_group.dart';
import 'slot_annotation.dart';

/// Event domain entity
class Event extends Equatable {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String startTime; // Format: "HH:mm" - Audience gathering time (שעת התכנסות קהל)
  final String endTime; // Format: "HH:mm" - Show estimated end time (שעת סיום משוערת של המופע)
  final String teamEndTime; // Format: "HH:mm" - Team estimated end time (שעת סיום משוערת של הצוות)
  final String assemblyTime; // Format: "HH:mm"
  final String actualShowStartTime; // Format: "HH:mm" - Actual show start time (שעת תחילת המופע בפועל)
  final List<ParticipantGroup> participantGroups; // Audience per סבב; empty = unset
  final String location;
  final String? parkingLocation; // Parking location in "Name||lat,lng" format
  final List<String> parkingEditorIds; // IDs of team members who can edit parking
  final bool requiresArmed;
  final String comments; // Comments about the event
  final String? categoryId; // Foreign key to Category (null = uncategorized)
  final Map<String, int> roleRequirements; // How many people needed per role (role key -> count)
  // Per-slot job annotations (note + label), keyed by "<roleKey>#<slotIndex>".
  // Independent of any assignment; shown on empty gaps and carried onto the
  // member when a gap is filled. See docs/superpowers/specs/2026-07-22-*.
  final Map<String, SlotAnnotation> slotAnnotations;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Google Drive integration fields
  final String? driveFolderId; // Google Drive folder ID for event files
  final String? driveFolderLink; // Direct link to the Drive folder
  final bool relevantForExtendedTeam; // Event is relevant for extended team (non-permanent members)

  // Lifecycle / status
  final bool isDeactivated; // Admin-controlled "on hold": hides from /admin/assignments, /user/assignments, summary; deletes calendar events; assignments preserved for reactivation

  // Calendar: when true AND the event is permanent-only AND the event has zero
  // assignments, invite all eligible permanent members to the calendar event(s)
  final bool inviteAllPermanentWhenUnassigned;

  const Event({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    this.teamEndTime = '',
    required this.assemblyTime,
    this.actualShowStartTime = '',
    this.participantGroups = const [],
    this.location = '',
    this.parkingLocation,
    this.parkingEditorIds = const [],
    required this.requiresArmed,
    this.comments = '',
    this.categoryId,
    required this.roleRequirements,
    this.slotAnnotations = const {},
    required this.createdAt,
    required this.updatedAt,
    this.driveFolderId,
    this.driveFolderLink,
    this.relevantForExtendedTeam = false,
    this.isDeactivated = false,
    this.inviteAllPermanentWhenUnassigned = false,
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

  /// Formatted audience size, or null when no groups are set.
  ///
  /// A lone unlabeled group renders as a bare number ("500"), so events created
  /// before סבבים existed look exactly as they did. Otherwise each group is
  /// prefixed by its label, falling back to its 1-based position ("סבב 2").
  String? get participantsSummary {
    if (participantGroups.isEmpty) return null;

    if (participantGroups.length == 1 &&
        participantGroups.first.normalizedLabel == null) {
      return '${participantGroups.first.count}';
    }

    final segments = <String>[];
    for (var i = 0; i < participantGroups.length; i++) {
      final group = participantGroups[i];
      final label = group.normalizedLabel ?? 'סבב ${i + 1}';
      segments.add('$label: ${group.count}');
    }
    return segments.join(', ');
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
    String? teamEndTime,
    String? assemblyTime,
    String? actualShowStartTime,
    List<ParticipantGroup>? participantGroups,
    String? location,
    String? parkingLocation,
    List<String>? parkingEditorIds,
    bool? requiresArmed,
    String? comments,
    String? categoryId,
    Map<String, int>? roleRequirements,
    Map<String, SlotAnnotation>? slotAnnotations,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? driveFolderId,
    String? driveFolderLink,
    bool? relevantForExtendedTeam,
    bool? isDeactivated,
    bool? inviteAllPermanentWhenUnassigned,
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
      teamEndTime: teamEndTime ?? this.teamEndTime,
      assemblyTime: assemblyTime ?? this.assemblyTime,
      actualShowStartTime: actualShowStartTime ?? this.actualShowStartTime,
      participantGroups: participantGroups ?? this.participantGroups,
      location: location ?? this.location,
      parkingLocation: clearParkingLocation ? null : (parkingLocation ?? this.parkingLocation),
      parkingEditorIds: parkingEditorIds ?? this.parkingEditorIds,
      requiresArmed: requiresArmed ?? this.requiresArmed,
      comments: comments ?? this.comments,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      roleRequirements: roleRequirements ?? this.roleRequirements,
      slotAnnotations: slotAnnotations ?? this.slotAnnotations,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      driveFolderId: driveFolderId ?? this.driveFolderId,
      driveFolderLink: driveFolderLink ?? this.driveFolderLink,
      relevantForExtendedTeam: relevantForExtendedTeam ?? this.relevantForExtendedTeam,
      isDeactivated: isDeactivated ?? this.isDeactivated,
      inviteAllPermanentWhenUnassigned:
          inviteAllPermanentWhenUnassigned ?? this.inviteAllPermanentWhenUnassigned,
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
        teamEndTime,
        assemblyTime,
        actualShowStartTime,
        participantGroups,
        location,
        parkingLocation,
        parkingEditorIds,
        requiresArmed,
        comments,
        categoryId,
        roleRequirements,
        slotAnnotations,
        createdAt,
        updatedAt,
        driveFolderId,
        driveFolderLink,
        relevantForExtendedTeam,
        isDeactivated,
        inviteAllPermanentWhenUnassigned,
      ];

  @override
  String toString() => 'Event($id, $name, $dateRangeString)';
}
