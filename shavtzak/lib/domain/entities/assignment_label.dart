import 'package:equatable/equatable.dart';

/// Structured semantic label for assignments.
class AssignmentLabel extends Equatable {
  final String id;
  final String key;
  final String hebrewName;
  final String color;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AssignmentLabel({
    required this.id,
    required this.key,
    required this.hebrewName,
    required this.color,
    required this.sortOrder,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  AssignmentLabel copyWith({
    String? id,
    String? key,
    String? hebrewName,
    String? color,
    int? sortOrder,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AssignmentLabel(
      id: id ?? this.id,
      key: key ?? this.key,
      hebrewName: hebrewName ?? this.hebrewName,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        key,
        hebrewName,
        color,
        sortOrder,
        isActive,
        createdAt,
        updatedAt,
      ];
}
