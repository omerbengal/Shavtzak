import 'package:equatable/equatable.dart';

/// Role entity representing a dynamic role in the system
/// Replaces the hardcoded RoleType enum with a flexible Firestore-backed system
class Role extends Equatable {
  /// Unique identifier (same as key for simplicity)
  final String id;

  /// Database key matching existing usage in Event/TeamMember/Assignment
  /// e.g., "eventCommander", "medic", "paramedic"
  final String key;

  /// Hebrew display name for the role
  final String hebrewName;

  /// Controls whether role appears in event quota configuration
  /// true = active (shows in EventFormModal), false = inactive (hidden from quota UI)
  final bool isVisible;

  /// If true, role is archived (moved to archive list)
  /// Archived roles are effectively inactive and don't appear in quota configuration
  final bool isArchived;

  /// Display order for sorting (0 = first)
  final int sortOrder;

  /// Creation timestamp
  final DateTime createdAt;

  /// Last update timestamp
  final DateTime updatedAt;

  const Role({
    required this.id,
    required this.key,
    required this.hebrewName,
    this.isVisible = true,
    this.isArchived = false,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Helper: role is shown in EventFormModal only if visible AND not archived
  bool get isActiveForQuotas => isVisible && !isArchived;

  /// Create a copy with updated fields
  Role copyWith({
    String? id,
    String? key,
    String? hebrewName,
    bool? isVisible,
    bool? isArchived,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Role(
      id: id ?? this.id,
      key: key ?? this.key,
      hebrewName: hebrewName ?? this.hebrewName,
      isVisible: isVisible ?? this.isVisible,
      isArchived: isArchived ?? this.isArchived,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        key,
        hebrewName,
        isVisible,
        isArchived,
        sortOrder,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'Role(id: $id, key: $key, hebrewName: $hebrewName, isVisible: $isVisible, isArchived: $isArchived, sortOrder: $sortOrder)';
  }
}
