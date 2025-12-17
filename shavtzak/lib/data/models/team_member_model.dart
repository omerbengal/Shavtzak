import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/role_types.dart';
import '../../core/constants/constraint_status.dart';
import '../../domain/entities/team_member.dart';

/// Data model for TeamMember with JSON serialization
class TeamMemberModel {
  final String id;
  final String name;
  final bool isActive;
  final bool isPermanent;
  final List<DateConstraintModel> constraints;
  final Map<String, bool> roleCapabilities; // Stored as string keys in Firestore
  final String comments;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Feature 13: User authentication fields
  final String uniqueKey; // UUID for user identification (not shown in UI)
  final bool isAdmin;     // Admin status (defaults to false for non-admin)

  // Passcode security fields
  final String? passcode;        // 4 or 6 digit passcode (null = no passcode)
  final int? passcodeLength;     // Length of passcode (4 or 6, null = no passcode)

  // Multiple assignment field
  final bool allowMultipleAssignments; // Allow assigning to same event multiple times

  const TeamMemberModel({
    required this.id,
    required this.name,
    required this.isActive,
    this.isPermanent = false,
    required this.constraints,
    required this.roleCapabilities,
    this.comments = '',
    required this.createdAt,
    required this.updatedAt,
    required this.uniqueKey,
    this.isAdmin = false,
    this.passcode,
    this.passcodeLength,
    this.allowMultipleAssignments = false,
  });

  /// Generate a UUID for team members
  static String _generateUUID() {
    return const Uuid().v4();
  }

  /// Convert from domain entity
  factory TeamMemberModel.fromEntity(TeamMember entity) {
    return TeamMemberModel(
      id: entity.id,
      name: entity.name,
      isActive: entity.isActive,
      isPermanent: entity.isPermanent,
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
      uniqueKey: entity.uniqueKey,
      isAdmin: entity.isAdmin,
      passcode: entity.passcode,
      passcodeLength: entity.passcodeLength,
      allowMultipleAssignments: entity.allowMultipleAssignments,
    );
  }

  /// Convert to domain entity
  TeamMember toEntity() {
    return TeamMember(
      id: id,
      name: name,
      isActive: isActive,
      isPermanent: isPermanent,
      constraints: constraints.map((c) => c.toEntity()).toList(),
      roleCapabilities: Map.fromEntries(
        roleCapabilities.entries.map((e) {
          final roleType = RoleType.values.where((r) => r.key == e.key).firstOrNull;
          return roleType != null ? MapEntry(roleType, e.value) : null;
        }).whereType<MapEntry<RoleType, bool>>(),
      ),
      comments: comments,
      createdAt: createdAt,
      updatedAt: updatedAt,
      uniqueKey: uniqueKey,
      isAdmin: isAdmin,
      passcode: passcode,
      passcodeLength: passcodeLength,
      allowMultipleAssignments: allowMultipleAssignments,
    );
  }

  /// Convert from Firestore document
  factory TeamMemberModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Handle migration - generate UUID for existing members missing uniqueKey
    final existingUniqueKey = data['uniqueKey'] as String?;
    final generatedUniqueKey = existingUniqueKey ?? _generateUUID();

    // Handle migration - default to false for existing members missing isAdmin
    final isAdmin = data['isAdmin'] as bool? ?? false;

    // Handle migration - passcode fields are optional, default to null for existing members
    final passcode = data['passcode'] as String?;
    final passcodeLength = data['passcodeLength'] as int?;

    // Handle migration - default to false for existing members missing allowMultipleAssignments
    final allowMultipleAssignments = data['allowMultipleAssignments'] as bool? ?? false;

    final model = TeamMemberModel(
      id: doc.id,
      name: data['name'] as String,
      isActive: data['isActive'] as bool? ?? true,
      isPermanent: data['isPermanent'] as bool? ?? false,
      constraints: (data['constraints'] as List<dynamic>?)
              ?.map((c) => DateConstraintModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      roleCapabilities: Map<String, bool>.from(data['roleCapabilities'] as Map? ?? {}),
      comments: data['comments'] as String? ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
      uniqueKey: generatedUniqueKey,
      isAdmin: isAdmin,
      passcode: passcode,
      passcodeLength: passcodeLength,
      allowMultipleAssignments: allowMultipleAssignments,
    );

    // If migration was needed (UUID was generated), update the document
    if (existingUniqueKey == null) {
      _updateDocumentWithMigrationFields(doc.reference, model);
    }

    return model;
  }

  /// Update document with migration fields (async operation)
  static void _updateDocumentWithMigrationFields(DocumentReference ref, TeamMemberModel model) {
    // Update asynchronously without blocking the read operation
    ref.update({
      'uniqueKey': model.uniqueKey,
      'isAdmin': model.isAdmin,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }).catchError((error) {
      // Silently handle migration errors without blocking read operation
    });
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'isActive': isActive,
      'isPermanent': isPermanent,
      'constraints': constraints.map((c) => c.toJson()).toList(),
      'roleCapabilities': roleCapabilities,
      'comments': comments,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'uniqueKey': uniqueKey,
      'isAdmin': isAdmin,
      'passcode': passcode,
      'passcodeLength': passcodeLength,
      'allowMultipleAssignments': allowMultipleAssignments,
    };
  }

  /// Convert from JSON
  factory TeamMemberModel.fromJson(Map<String, dynamic> json) {
    // Handle migration - generate UUID for existing members missing uniqueKey
    final existingUniqueKey = json['uniqueKey'] as String?;
    final generatedUniqueKey = existingUniqueKey ?? _generateUUID();

    // Handle migration - default to false for existing members missing isAdmin
    final isAdmin = json['isAdmin'] as bool? ?? false;

    // Handle migration - passcode fields are optional, default to null for existing members
    final passcode = json['passcode'] as String?;
    final passcodeLength = json['passcodeLength'] as int?;

    // Handle migration - default to false for existing members missing allowMultipleAssignments
    final allowMultipleAssignments = json['allowMultipleAssignments'] as bool? ?? false;

    return TeamMemberModel(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['isActive'] as bool? ?? true,
      isPermanent: json['isPermanent'] as bool? ?? false,
      constraints: (json['constraints'] as List<dynamic>?)
              ?.map((c) => DateConstraintModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      roleCapabilities: Map<String, bool>.from(json['roleCapabilities'] as Map? ?? {}),
      comments: json['comments'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      uniqueKey: generatedUniqueKey,
      isAdmin: isAdmin,
      passcode: passcode,
      passcodeLength: passcodeLength,
      allowMultipleAssignments: allowMultipleAssignments,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isActive': isActive,
      'isPermanent': isPermanent,
      'constraints': constraints.map((c) => c.toJson()).toList(),
      'roleCapabilities': roleCapabilities,
      'comments': comments,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'uniqueKey': uniqueKey,
      'isAdmin': isAdmin,
      'passcode': passcode,
      'passcodeLength': passcodeLength,
      'allowMultipleAssignments': allowMultipleAssignments,
    };
  }
}

/// Data model for DateConstraint
class DateConstraintModel {
  final String id;
  final DateTime startDate;
  final DateTime? endDate;
  final String? note;
  final ConstraintStatus status;
  final ConstraintType constraintType;
  final bool wasAutoRejectedFromCalendar;

  const DateConstraintModel({
    required this.id,
    required this.startDate,
    this.endDate,
    this.note,
    this.status = ConstraintStatus.approved, // default to approved for existing constraints
    this.constraintType = ConstraintType.unavailability, // default to unavailability for backward compatibility
    this.wasAutoRejectedFromCalendar = false, // default to false for existing constraints
  });

  factory DateConstraintModel.fromEntity(DateConstraint entity) {
    return DateConstraintModel(
      id: entity.id,
      startDate: entity.startDate,
      endDate: entity.endDate,
      note: entity.note,
      status: entity.status,
      constraintType: entity.constraintType,
      wasAutoRejectedFromCalendar: entity.wasAutoRejectedFromCalendar,
    );
  }

  DateConstraint toEntity() {
    return DateConstraint(
      id: id, // Use the id field from this model
      startDate: startDate,
      endDate: endDate,
      note: note,
      status: status,
      constraintType: constraintType,
      wasAutoRejectedFromCalendar: wasAutoRejectedFromCalendar,
    );
  }

  factory DateConstraintModel.fromJson(Map<String, dynamic> json) {
    // Handle migration - default to approved for existing constraints missing status
    final statusValue = json['status'] as String?;
    final status = statusValue != null
        ? ConstraintStatus.values.firstWhere(
            (s) => s.name == statusValue,
            orElse: () => ConstraintStatus.pending,
          )
        : ConstraintStatus.approved;

    // Handle migration - default to unavailability for existing constraints missing constraintType
    final typeValue = json['constraintType'] as String?;
    final constraintType = typeValue != null
        ? ConstraintType.values.firstWhere(
            (t) => t.name == typeValue,
            orElse: () => ConstraintType.unavailability,
          )
        : ConstraintType.unavailability;

    // Handle migration - generate ID for existing constraints missing id
    final constraintId = json['id'] as String? ?? const Uuid().v4();

    // Handle migration - default to false for existing constraints missing wasAutoRejectedFromCalendar
    final wasAutoRejectedFromCalendar = json['wasAutoRejectedFromCalendar'] as bool? ?? false;

    return DateConstraintModel(
      id: constraintId,
      startDate: json['startDate'] is Timestamp
          ? (json['startDate'] as Timestamp).toDate()
          : DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : json['endDate'] is Timestamp
              ? (json['endDate'] as Timestamp).toDate()
              : DateTime.parse(json['endDate'] as String),
      note: json['note'] as String?,
      status: status,
      constraintType: constraintType,
      wasAutoRejectedFromCalendar: wasAutoRejectedFromCalendar,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'note': note,
      'status': status.name,
      'constraintType': constraintType.name,
      'wasAutoRejectedFromCalendar': wasAutoRejectedFromCalendar,
    };
  }
}
