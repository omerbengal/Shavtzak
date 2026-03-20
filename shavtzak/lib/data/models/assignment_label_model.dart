import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/assignment_label.dart';

class AssignmentLabelModel {
  final String id;
  final String key;
  final String hebrewName;
  final String color;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AssignmentLabelModel({
    required this.id,
    required this.key,
    required this.hebrewName,
    required this.color,
    required this.sortOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AssignmentLabelModel.fromEntity(AssignmentLabel entity) {
    return AssignmentLabelModel(
      id: entity.id,
      key: entity.key,
      hebrewName: entity.hebrewName,
      color: entity.color,
      sortOrder: entity.sortOrder,
      isActive: entity.isActive,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  AssignmentLabel toEntity() {
    return AssignmentLabel(
      id: id,
      key: key,
      hebrewName: hebrewName,
      color: color,
      sortOrder: sortOrder,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory AssignmentLabelModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return AssignmentLabelModel(
      id: doc.id,
      key: data['key'] as String,
      hebrewName: data['hebrewName'] as String,
      color: data['color'] as String? ?? '#1565C0',
      sortOrder: data['sortOrder'] as int? ?? 0,
      isActive: data['isActive'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'key': key,
      'hebrewName': hebrewName,
      'color': color,
      'sortOrder': sortOrder,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory AssignmentLabelModel.fromJson(Map<String, dynamic> json) {
    return AssignmentLabelModel(
      id: json['id'] as String,
      key: json['key'] as String,
      hebrewName: json['hebrewName'] as String,
      color: json['color'] as String? ?? '#1565C0',
      sortOrder: json['sortOrder'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key': key,
      'hebrewName': hebrewName,
      'color': color,
      'sortOrder': sortOrder,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
