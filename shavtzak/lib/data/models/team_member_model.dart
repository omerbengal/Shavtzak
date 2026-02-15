import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/constraint_status.dart';
import '../../domain/entities/team_member.dart';
import '../../domain/entities/vehicle_info.dart';

/// Data model for TeamMember with JSON serialization
class TeamMemberModel {
  final String id;
  final String name;
  final bool isActive;
  final bool isPermanent;
  final bool isArchived;
  final List<DateConstraintModel> constraints;
  final Map<String, bool>
      roleCapabilities; // Stored as string keys in Firestore
  final String comments;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Feature 13: User authentication fields
  final String uniqueKey; // UUID for user identification (not shown in UI)
  final bool isAdmin; // Admin status (defaults to false for non-admin)

  // Passcode security fields
  final String? passcode; // 4 or 6 digit passcode (null = no passcode)
  final int? passcodeLength; // Length of passcode (4 or 6, null = no passcode)

  // Multiple assignment field
  final bool
      allowMultipleAssignments; // Allow assigning to same event multiple times

  // Phone number field
  final String? phoneNumber; // Optional Israeli phone number

  // Email field
  final String? email; // Optional email address

  // Birthday field
  final DateTime? birthday; // Optional birthday date

  // Summary screen access field
  final bool
      canAccessSummaryScreen; // Whether non-admin can access summary screen

  // Vehicle info field
  final VehicleInfoModel? vehicleInfo; // Optional vehicle information

  // Event-based availability for non-permanent members
  final List<String>
      availableEventIds; // List of event IDs this member is available for

  const TeamMemberModel({
    required this.id,
    required this.name,
    required this.isActive,
    this.isPermanent = false,
    this.isArchived = false,
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
    this.phoneNumber,
    this.email,
    this.birthday,
    this.canAccessSummaryScreen = false,
    this.vehicleInfo,
    this.availableEventIds = const [],
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
      isArchived: entity.isArchived,
      constraints: entity.constraints
          .map((c) => DateConstraintModel.fromEntity(c))
          .toList(),
      roleCapabilities: Map<String, bool>.from(entity.roleCapabilities),
      comments: entity.comments,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      uniqueKey: entity.uniqueKey,
      isAdmin: entity.isAdmin,
      passcode: entity.passcode,
      passcodeLength: entity.passcodeLength,
      allowMultipleAssignments: entity.allowMultipleAssignments,
      phoneNumber: entity.phoneNumber,
      email: entity.email,
      birthday: entity.birthday,
      canAccessSummaryScreen: entity.canAccessSummaryScreen,
      vehicleInfo: entity.vehicleInfo != null
          ? VehicleInfoModel.fromEntity(entity.vehicleInfo!)
          : null,
      availableEventIds: List<String>.from(entity.availableEventIds),
    );
  }

  /// Convert to domain entity
  TeamMember toEntity() {
    return TeamMember(
      id: id,
      name: name,
      isActive: isActive,
      isPermanent: isPermanent,
      isArchived: isArchived,
      constraints: constraints.map((c) => c.toEntity()).toList(),
      roleCapabilities: Map<String, bool>.from(roleCapabilities),
      comments: comments,
      createdAt: createdAt,
      updatedAt: updatedAt,
      uniqueKey: uniqueKey,
      isAdmin: isAdmin,
      passcode: passcode,
      passcodeLength: passcodeLength,
      allowMultipleAssignments: allowMultipleAssignments,
      phoneNumber: phoneNumber,
      email: email,
      birthday: birthday,
      canAccessSummaryScreen: canAccessSummaryScreen,
      vehicleInfo: vehicleInfo?.toEntity(),
      availableEventIds: List<String>.from(availableEventIds),
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
    final allowMultipleAssignments =
        data['allowMultipleAssignments'] as bool? ?? false;

    // Handle migration - phone number is optional, default to null for existing members
    final phoneNumber = data['phoneNumber'] as String?;

    // Handle migration - email is optional, default to null for existing members
    final email = data['email'] as String?;

    // Handle migration - birthday is optional, default to null for existing members
    final birthday = data['birthday'] != null
        ? (data['birthday'] as Timestamp).toDate()
        : null;

    // Handle migration - default to false for existing members missing canAccessSummaryScreen
    final canAccessSummaryScreen =
        data['canAccessSummaryScreen'] as bool? ?? false;

    // Handle migration - vehicleInfo is optional, default to null for existing members
    final vehicleInfoData = data['vehicleInfo'] as Map<String, dynamic>?;
    final vehicleInfo = vehicleInfoData != null
        ? VehicleInfoModel.fromJson(vehicleInfoData)
        : null;

    // Handle migration - isArchived is optional, if missing derive from !isActive for backward compatibility
    final isActiveValue = data['isActive'] as bool? ?? true;
    final isArchived = data['isArchived'] as bool? ?? !isActiveValue;

    // Handle migration - availableEventIds is optional, default to empty list for existing members
    final availableEventIds = (data['availableEventIds'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];

    final model = TeamMemberModel(
      id: doc.id,
      name: data['name'] as String,
      isActive: isActiveValue,
      isPermanent: data['isPermanent'] as bool? ?? false,
      isArchived: isArchived,
      constraints: (data['constraints'] as List<dynamic>?)
              ?.map((c) =>
                  DateConstraintModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      roleCapabilities:
          Map<String, bool>.from(data['roleCapabilities'] as Map? ?? {}),
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
      phoneNumber: phoneNumber,
      email: email,
      birthday: birthday,
      canAccessSummaryScreen: canAccessSummaryScreen,
      vehicleInfo: vehicleInfo,
      availableEventIds: availableEventIds,
    );

    // If migration was needed (UUID was generated), update the document
    if (existingUniqueKey == null) {
      _updateDocumentWithMigrationFields(doc.reference, model);
    }

    return model;
  }

  /// Update document with migration fields (async operation)
  static void _updateDocumentWithMigrationFields(
      DocumentReference ref, TeamMemberModel model) {
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
      'isArchived': isArchived,
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
      'phoneNumber': phoneNumber,
      'email': email,
      'birthday': birthday != null ? Timestamp.fromDate(birthday!) : null,
      'canAccessSummaryScreen': canAccessSummaryScreen,
      'vehicleInfo': vehicleInfo?.toJson(),
      'availableEventIds': availableEventIds,
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
    final allowMultipleAssignments =
        json['allowMultipleAssignments'] as bool? ?? false;

    // Handle migration - phone number is optional, default to null for existing members
    final phoneNumber = json['phoneNumber'] as String?;

    // Handle migration - email is optional, default to null for existing members
    final email = json['email'] as String?;

    // Handle migration - birthday is optional, default to null for existing members
    final birthday = json['birthday'] != null
        ? DateTime.parse(json['birthday'] as String)
        : null;

    // Handle migration - default to false for existing members missing canAccessSummaryScreen
    final canAccessSummaryScreen =
        json['canAccessSummaryScreen'] as bool? ?? false;

    // Handle migration - vehicleInfo is optional, default to null for existing members
    final vehicleInfoData = json['vehicleInfo'] as Map<String, dynamic>?;
    final vehicleInfo = vehicleInfoData != null
        ? VehicleInfoModel.fromJson(vehicleInfoData)
        : null;

    // Handle migration - isArchived is optional, if missing derive from !isActive for backward compatibility
    final isActiveValue = json['isActive'] as bool? ?? true;
    final isArchived = json['isArchived'] as bool? ?? !isActiveValue;

    // Handle migration - availableEventIds is optional, default to empty list for existing members
    final availableEventIds = (json['availableEventIds'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];

    return TeamMemberModel(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: isActiveValue,
      isPermanent: json['isPermanent'] as bool? ?? false,
      isArchived: isArchived,
      constraints: (json['constraints'] as List<dynamic>?)
              ?.map((c) =>
                  DateConstraintModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      roleCapabilities:
          Map<String, bool>.from(json['roleCapabilities'] as Map? ?? {}),
      comments: json['comments'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      uniqueKey: generatedUniqueKey,
      isAdmin: isAdmin,
      passcode: passcode,
      passcodeLength: passcodeLength,
      allowMultipleAssignments: allowMultipleAssignments,
      phoneNumber: phoneNumber,
      email: email,
      birthday: birthday,
      canAccessSummaryScreen: canAccessSummaryScreen,
      vehicleInfo: vehicleInfo,
      availableEventIds: availableEventIds,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isActive': isActive,
      'isPermanent': isPermanent,
      'isArchived': isArchived,
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
      'phoneNumber': phoneNumber,
      'email': email,
      'birthday': birthday?.toIso8601String(),
      'canAccessSummaryScreen': canAccessSummaryScreen,
      'vehicleInfo': vehicleInfo?.toJson(),
      'availableEventIds': availableEventIds,
    };
  }
}

/// Data model for VehicleInfo
class VehicleInfoModel {
  final String vehicleNumber;
  final String manufacturer;
  final String model;
  final String color;

  const VehicleInfoModel({
    required this.vehicleNumber,
    required this.manufacturer,
    required this.model,
    required this.color,
  });

  factory VehicleInfoModel.fromEntity(VehicleInfo entity) {
    return VehicleInfoModel(
      vehicleNumber: entity.vehicleNumber,
      manufacturer: entity.manufacturer,
      model: entity.model,
      color: entity.color,
    );
  }

  VehicleInfo toEntity() {
    return VehicleInfo(
      vehicleNumber: vehicleNumber,
      manufacturer: manufacturer,
      model: model,
      color: color,
    );
  }

  factory VehicleInfoModel.fromJson(Map<String, dynamic> json) {
    return VehicleInfoModel(
      vehicleNumber: json['vehicleNumber'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      model: json['model'] as String? ?? '',
      color: json['color'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vehicleNumber': vehicleNumber,
      'manufacturer': manufacturer,
      'model': model,
      'color': color,
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
  final String? startTime; // Start time in "HH:mm" format (optional)
  final String? endTime; // End time in "HH:mm" format (optional)
  final String? repeatType; // RepeatType enum name
  final int? repeatDay; // Weekly weekday (1..7) or monthly day-of-month (1..31)
  final DateTime? repeatEndDate; // End date for recurring constraints

  const DateConstraintModel({
    required this.id,
    required this.startDate,
    this.endDate,
    this.note,
    this.status = ConstraintStatus
        .approved, // default to approved for existing constraints
    this.constraintType = ConstraintType
        .unavailability, // default to unavailability for backward compatibility
    this.wasAutoRejectedFromCalendar =
        false, // default to false for existing constraints
    this.startTime,
    this.endTime,
    this.repeatType,
    this.repeatDay,
    this.repeatEndDate,
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
      startTime: entity.startTime,
      endTime: entity.endTime,
      repeatType: entity.repeatType?.name,
      repeatDay: entity.repeatDay,
      repeatEndDate: entity.repeatEndDate,
    );
  }

  DateConstraint toEntity() {
    final parsedRepeatType =
        repeatType != null && RepeatType.values.any((t) => t.name == repeatType)
            ? RepeatType.values.firstWhere((t) => t.name == repeatType)
            : null;

    return DateConstraint(
      id: id, // Use the id field from this model
      startDate: startDate,
      endDate: endDate,
      note: note,
      status: status,
      constraintType: constraintType,
      wasAutoRejectedFromCalendar: wasAutoRejectedFromCalendar,
      startTime: startTime,
      endTime: endTime,
      repeatType: parsedRepeatType,
      repeatDay: repeatDay,
      repeatEndDate: repeatEndDate,
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
    final wasAutoRejectedFromCalendar =
        json['wasAutoRejectedFromCalendar'] as bool? ?? false;

    // Handle migration - time fields are optional, default to null for existing constraints
    final startTime = json['startTime'] as String?;
    final endTime = json['endTime'] as String?;
    final repeatType = json['repeatType'] as String?;
    final repeatDay = (json['repeatDay'] as num?)?.toInt();
    final repeatEndDate = json['repeatEndDate'] == null
        ? null
        : json['repeatEndDate'] is Timestamp
            ? (json['repeatEndDate'] as Timestamp).toDate()
            : DateTime.parse(json['repeatEndDate'] as String);

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
      startTime: startTime,
      endTime: endTime,
      repeatType: repeatType,
      repeatDay: repeatDay,
      repeatEndDate: repeatEndDate,
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
      'startTime': startTime,
      'endTime': endTime,
      'repeatType': repeatType,
      'repeatDay': repeatDay,
      'repeatEndDate': repeatEndDate?.toIso8601String(),
    };
  }
}
