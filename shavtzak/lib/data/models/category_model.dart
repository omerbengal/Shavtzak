import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/category.dart';

/// Data model for Category with Firestore serialization
class CategoryModel {
  final String id;
  final String name;
  final int sortOrder;
  final bool isArchived;
  final int? colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.isArchived = false,
    this.colorValue,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convert from domain entity
  factory CategoryModel.fromEntity(Category entity) {
    return CategoryModel(
      id: entity.id,
      name: entity.name,
      sortOrder: entity.sortOrder,
      isArchived: entity.isArchived,
      colorValue: entity.colorValue,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  /// Convert to domain entity
  Category toEntity() {
    return Category(
      id: id,
      name: name,
      sortOrder: sortOrder,
      isArchived: isArchived,
      colorValue: colorValue,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Convert from Firestore document
  factory CategoryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return CategoryModel(
      id: doc.id,
      name: data['name'] as String,
      sortOrder: data['sortOrder'] as int? ?? 0,
      isArchived: data['isArchived'] as bool? ?? false,
      // Handle migration - null for existing categories without a color
      colorValue: data['colorValue'] as int?,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'sortOrder': sortOrder,
      'isArchived': isArchived,
      'colorValue': colorValue,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Convert from JSON
  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: json['sortOrder'] as int? ?? 0,
      isArchived: json['isArchived'] as bool? ?? false,
      // Handle migration - null for existing categories without a color
      colorValue: json['colorValue'] as int?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sortOrder': sortOrder,
      'isArchived': isArchived,
      'colorValue': colorValue,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
