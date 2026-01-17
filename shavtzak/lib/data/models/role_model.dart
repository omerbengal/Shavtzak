import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/role.dart';

/// Data model for Role with Firestore serialization
class RoleModel {
  final String id;
  final String key;
  final String hebrewName;
  final bool isVisible;
  final bool isArchived;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleModel({
    required this.id,
    required this.key,
    required this.hebrewName,
    required this.isVisible,
    required this.isArchived,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convert from domain entity
  factory RoleModel.fromEntity(Role entity) {
    return RoleModel(
      id: entity.id,
      key: entity.key,
      hebrewName: entity.hebrewName,
      isVisible: entity.isVisible,
      isArchived: entity.isArchived,
      sortOrder: entity.sortOrder,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  /// Convert to domain entity
  Role toEntity() {
    return Role(
      id: id,
      key: key,
      hebrewName: hebrewName,
      isVisible: isVisible,
      isArchived: isArchived,
      sortOrder: sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Convert from Firestore document
  factory RoleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return RoleModel(
      id: doc.id,
      key: data['key'] as String,
      hebrewName: data['hebrewName'] as String,
      isVisible: data['isVisible'] as bool? ?? true,
      isArchived: data['isArchived'] as bool? ?? false,
      sortOrder: data['sortOrder'] as int? ?? 0,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'key': key,
      'hebrewName': hebrewName,
      'isVisible': isVisible,
      'isArchived': isArchived,
      'sortOrder': sortOrder,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Convert from JSON
  factory RoleModel.fromJson(Map<String, dynamic> json) {
    return RoleModel(
      id: json['id'] as String,
      key: json['key'] as String,
      hebrewName: json['hebrewName'] as String,
      isVisible: json['isVisible'] as bool? ?? true,
      isArchived: json['isArchived'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key': key,
      'hebrewName': hebrewName,
      'isVisible': isVisible,
      'isArchived': isArchived,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
