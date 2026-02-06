import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/role_types.dart';
import '../../domain/entities/assignment.dart';

/// Data model for Assignment with JSON serialization
/// THIS IS THE KEY MODEL THAT FIXES THE V1 SYNC PROBLEM
///
/// Stores explicit foreign keys (eventId, teamMemberId) in Firestore
/// instead of relying on positional data like V1's spreadsheet columns
class AssignmentModel {
  final String id;
  final String eventId; // FK → Event
  final String teamMemberId; // FK → TeamMember
  final String roleType; // Stored as string key
  final int slotIndex; // Which slot (0, 1, 2...) for this role in the event
  final String status; // Stored as string key
  final String notes;
  final String? alternativePhoneNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AssignmentModel({
    required this.id,
    required this.eventId,
    required this.teamMemberId,
    required this.roleType,
    required this.slotIndex,
    required this.status,
    required this.notes,
    this.alternativePhoneNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convert from domain entity
  factory AssignmentModel.fromEntity(Assignment entity) {
    return AssignmentModel(
      id: entity.id,
      eventId: entity.eventId,
      teamMemberId: entity.teamMemberId,
      roleType: entity.roleType,
      slotIndex: entity.slotIndex,
      status: entity.status.key,
      notes: entity.notes,
      alternativePhoneNumber: entity.alternativePhoneNumber,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  /// Convert to domain entity (without populated relations)
  Assignment toEntity() {
    return Assignment(
      id: id,
      eventId: eventId,
      teamMemberId: teamMemberId,
      roleType: roleType,
      slotIndex: slotIndex,
      status: AssignmentStatusExtension.fromString(status),
      notes: notes,
      alternativePhoneNumber: alternativePhoneNumber,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Convert from Firestore document
  factory AssignmentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return AssignmentModel(
      id: doc.id,
      eventId: data['eventId'] as String,
      teamMemberId: data['teamMemberId'] as String,
      roleType: data['roleType'] as String,
      slotIndex: data['slotIndex'] as int? ?? 0, // Default to 0 for old data
      status: data['status'] as String? ?? 'pending',
      notes: data['notes'] as String? ?? '',
      alternativePhoneNumber: data['alternativePhoneNumber'] as String?,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'eventId': eventId,
      'teamMemberId': teamMemberId,
      'roleType': roleType,
      'slotIndex': slotIndex,
      'status': status,
      'notes': notes,
      if (alternativePhoneNumber != null) 'alternativePhoneNumber': alternativePhoneNumber,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Convert from JSON
  factory AssignmentModel.fromJson(Map<String, dynamic> json) {
    return AssignmentModel(
      id: json['id'] as String,
      eventId: json['eventId'] as String,
      teamMemberId: json['teamMemberId'] as String,
      roleType: json['roleType'] as String,
      slotIndex: json['slotIndex'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      notes: json['notes'] as String? ?? '',
      alternativePhoneNumber: json['alternativePhoneNumber'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eventId': eventId,
      'teamMemberId': teamMemberId,
      'roleType': roleType,
      'slotIndex': slotIndex,
      'status': status,
      'notes': notes,
      if (alternativePhoneNumber != null) 'alternativePhoneNumber': alternativePhoneNumber,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
