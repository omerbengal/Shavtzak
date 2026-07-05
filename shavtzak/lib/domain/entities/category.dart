import 'package:equatable/equatable.dart';

/// Category domain entity for organizing events
class Category extends Equatable {
  final String id;
  final String name;
  final int sortOrder;
  final bool isArchived; // Soft delete support
  final int? colorValue; // ARGB color value (e.g. 0xFF2196F3); null = no color
  final DateTime createdAt;
  final DateTime updatedAt;

  const Category({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.isArchived = false,
    this.colorValue,
    required this.createdAt,
    required this.updatedAt,
  });

  Category copyWith({
    String? id,
    String? name,
    int? sortOrder,
    bool? isArchived,
    int? colorValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearColorValue = false, // Flag to explicitly clear the nullable color
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isArchived: isArchived ?? this.isArchived,
      colorValue: clearColorValue ? null : (colorValue ?? this.colorValue),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, sortOrder, isArchived, colorValue, createdAt, updatedAt];
}
