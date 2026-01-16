import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/role_types.dart';
import '../../domain/entities/event.dart';

/// Data model for Event with JSON serialization
class EventModel {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String startTime;
  final String endTime;
  final String assemblyTime;
  final String actualShowStartTime;
  final String location;
  final String? parkingLocation;
  final List<String> parkingEditorIds;
  final bool requiresArmed;
  final String comments;
  final Map<String, int> roleRequirements; // Stored as string keys in Firestore
  final DateTime createdAt;
  final DateTime updatedAt;

  // Google Drive integration fields
  final String? driveFolderId;
  final String? driveFolderLink;
  final bool isArchived;

  const EventModel({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.assemblyTime,
    this.actualShowStartTime = '',
    required this.location,
    this.parkingLocation,
    this.parkingEditorIds = const [],
    required this.requiresArmed,
    this.comments = '',
    required this.roleRequirements,
    required this.createdAt,
    required this.updatedAt,
    this.driveFolderId,
    this.driveFolderLink,
    this.isArchived = false,
  });

  /// Convert from domain entity
  factory EventModel.fromEntity(Event entity) {
    return EventModel(
      id: entity.id,
      name: entity.name,
      startDate: entity.startDate,
      endDate: entity.endDate,
      startTime: entity.startTime,
      endTime: entity.endTime,
      assemblyTime: entity.assemblyTime,
      actualShowStartTime: entity.actualShowStartTime,
      location: entity.location,
      parkingLocation: entity.parkingLocation,
      parkingEditorIds: entity.parkingEditorIds,
      requiresArmed: entity.requiresArmed,
      comments: entity.comments,
      roleRequirements: Map.fromEntries(
        entity.roleRequirements.entries.map(
          (e) => MapEntry(e.key.key, e.value),
        ),
      ),
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      driveFolderId: entity.driveFolderId,
      driveFolderLink: entity.driveFolderLink,
      isArchived: entity.isArchived,
    );
  }

  /// Convert to domain entity
  Event toEntity() {
    return Event(
      id: id,
      name: name,
      startDate: startDate,
      endDate: endDate,
      startTime: startTime,
      endTime: endTime,
      assemblyTime: assemblyTime,
      actualShowStartTime: actualShowStartTime,
      location: location,
      parkingLocation: parkingLocation,
      parkingEditorIds: parkingEditorIds,
      requiresArmed: requiresArmed,
      comments: comments,
      roleRequirements: Map.fromEntries(
        roleRequirements.entries.map(
          (e) => MapEntry(
            RoleType.values.firstWhere((r) => r.key == e.key),
            e.value,
          ),
        ),
      ),
      createdAt: createdAt,
      updatedAt: updatedAt,
      driveFolderId: driveFolderId,
      driveFolderLink: driveFolderLink,
      isArchived: isArchived,
    );
  }

  /// Convert from Firestore document
  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return EventModel(
      id: doc.id,
      name: data['name'] as String,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      startTime: data['startTime'] as String,
      endTime: data['endTime'] as String,
      assemblyTime: data['assemblyTime'] as String,
      actualShowStartTime: data['actualShowStartTime'] as String? ?? '',
      location: data['location'] as String? ?? '',
      parkingLocation: data['parkingLocation'] as String?,
      parkingEditorIds: List<String>.from(data['parkingEditorIds'] as List? ?? const []),
      requiresArmed: data['requiresArmed'] as bool? ?? false,
      comments: data['comments'] as String? ?? data['notes'] as String? ?? '',
      roleRequirements: Map<String, int>.from(data['roleRequirements'] as Map? ?? {}),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      driveFolderId: data['driveFolderId'] as String?,
      driveFolderLink: data['driveFolderLink'] as String?,
      isArchived: data['isArchived'] as bool? ?? false,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'startTime': startTime,
      'endTime': endTime,
      'assemblyTime': assemblyTime,
      'actualShowStartTime': actualShowStartTime,
      'location': location,
      'parkingLocation': parkingLocation,
      'parkingEditorIds': parkingEditorIds,
      'requiresArmed': requiresArmed,
      'comments': comments,
      'roleRequirements': roleRequirements,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'driveFolderId': driveFolderId,
      'driveFolderLink': driveFolderLink,
      'isArchived': isArchived,
    };
  }

  /// Convert from JSON
  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      name: json['name'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      assemblyTime: json['assemblyTime'] as String,
      actualShowStartTime: json['actualShowStartTime'] as String? ?? '',
      location: json['location'] as String? ?? '',
      parkingLocation: json['parkingLocation'] as String?,
      parkingEditorIds: List<String>.from(json['parkingEditorIds'] as List? ?? const []),
      requiresArmed: json['requiresArmed'] as bool? ?? false,
      comments: json['comments'] as String? ?? json['notes'] as String? ?? '',
      roleRequirements: Map<String, int>.from(json['roleRequirements'] as Map? ?? {}),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      driveFolderId: json['driveFolderId'] as String?,
      driveFolderLink: json['driveFolderLink'] as String?,
      isArchived: json['isArchived'] as bool? ?? false,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'startTime': startTime,
      'endTime': endTime,
      'assemblyTime': assemblyTime,
      'actualShowStartTime': actualShowStartTime,
      'location': location,
      'parkingLocation': parkingLocation,
      'parkingEditorIds': parkingEditorIds,
      'requiresArmed': requiresArmed,
      'comments': comments,
      'roleRequirements': roleRequirements,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'driveFolderId': driveFolderId,
      'driveFolderLink': driveFolderLink,
      'isArchived': isArchived,
    };
  }
}
