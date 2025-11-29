import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/role_types.dart';
import '../../domain/entities/team_member.dart';

/// Data model for TeamMember with JSON serialization
class TeamMemberModel {
  final String id;
  final String name;
  final bool isActive;
  final List<DateConstraintModel> constraints;
  final Map<String, bool> roleCapabilities; // Stored as string keys in Firestore
  final String comments;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TeamMemberModel({
    required this.id,
    required this.name,
    required this.isActive,
    required this.constraints,
    required this.roleCapabilities,
    this.comments = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convert from domain entity
  factory TeamMemberModel.fromEntity(TeamMember entity) {
    return TeamMemberModel(
      id: entity.id,
      name: entity.name,
      isActive: entity.isActive,
      constraints: entity.constraints
          .map((c) => DateConstraintModel.fromEntity(c))
          .toList(),
      roleCapabilities: Map.fromEntries(
        entity.roleCapabilities.entries.map(
          (e) => MapEntry(e.key.key, e.value),
        ),
      ),
      comments: entity.comments,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  /// Convert to domain entity
  TeamMember toEntity() {
    return TeamMember(
      id: id,
      name: name,
      isActive: isActive,
      constraints: constraints.map((c) => c.toEntity()).toList(),
      roleCapabilities: Map.fromEntries(
        roleCapabilities.entries.map(
          (e) => MapEntry(RoleType.values.firstWhere((r) => r.key == e.key), e.value),
        ),
      ),
      comments: comments,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Convert from Firestore document
  factory TeamMemberModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return TeamMemberModel(
      id: doc.id,
      name: data['name'] as String,
      isActive: data['isActive'] as bool? ?? true,
      constraints: (data['constraints'] as List<dynamic>?)
              ?.map((c) => DateConstraintModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      roleCapabilities: Map<String, bool>.from(data['roleCapabilities'] as Map? ?? {}),
      comments: data['comments'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'isActive': isActive,
      'constraints': constraints.map((c) => c.toJson()).toList(),
      'roleCapabilities': roleCapabilities,
      'comments': comments,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Convert from JSON
  factory TeamMemberModel.fromJson(Map<String, dynamic> json) {
    return TeamMemberModel(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['isActive'] as bool? ?? true,
      constraints: (json['constraints'] as List<dynamic>?)
              ?.map((c) => DateConstraintModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      roleCapabilities: Map<String, bool>.from(json['roleCapabilities'] as Map? ?? {}),
      comments: json['comments'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isActive': isActive,
      'constraints': constraints.map((c) => c.toJson()).toList(),
      'roleCapabilities': roleCapabilities,
      'comments': comments,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Data model for DateConstraint
class DateConstraintModel {
  final DateTime startDate;
  final DateTime? endDate;

  const DateConstraintModel({
    required this.startDate,
    this.endDate,
  });

  factory DateConstraintModel.fromEntity(DateConstraint entity) {
    return DateConstraintModel(
      startDate: entity.startDate,
      endDate: entity.endDate,
    );
  }

  DateConstraint toEntity() {
    return DateConstraint(
      startDate: startDate,
      endDate: endDate,
    );
  }

  factory DateConstraintModel.fromJson(Map<String, dynamic> json) {
    return DateConstraintModel(
      startDate: json['startDate'] is Timestamp
          ? (json['startDate'] as Timestamp).toDate()
          : DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : json['endDate'] is Timestamp
              ? (json['endDate'] as Timestamp).toDate()
              : DateTime.parse(json['endDate'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }
}
