import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/israel_calendar.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/participant_group.dart';

/// Data model for Event with JSON serialization
class EventModel {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String startTime;
  final String endTime;
  final String teamEndTime;
  final String assemblyTime;
  final String actualShowStartTime;
  final List<ParticipantGroupModel> participantGroups;
  final String location;
  final String? parkingLocation;
  final List<String> parkingEditorIds;
  final bool requiresArmed;
  final String comments;
  final String? categoryId; // Foreign key to Category
  final Map<String, int> roleRequirements; // Stored as string keys in Firestore
  final DateTime createdAt;
  final DateTime updatedAt;

  // Google Drive integration fields
  final String? driveFolderId;
  final String? driveFolderLink;
  final bool relevantForExtendedTeam;

  // Lifecycle / status
  final bool isDeactivated;

  // Calendar: invite all eligible permanent members while event has 0 assignments
  final bool inviteAllPermanentWhenUnassigned;

  const EventModel({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    this.teamEndTime = '',
    required this.assemblyTime,
    this.actualShowStartTime = '',
    this.participantGroups = const [],
    required this.location,
    this.parkingLocation,
    this.parkingEditorIds = const [],
    required this.requiresArmed,
    this.comments = '',
    this.categoryId,
    required this.roleRequirements,
    required this.createdAt,
    required this.updatedAt,
    this.driveFolderId,
    this.driveFolderLink,
    this.relevantForExtendedTeam = false,
    this.isDeactivated = false,
    this.inviteAllPermanentWhenUnassigned = false,
  });

  static DateTime _normalizeDateOnly(DateTime date) {
    // Project to Asia/Jerusalem calendar so .year/.month/.day always reflect
    // the Israel day, independent of the browser's local TZ.
    return IsraelCalendar.calendarDay(date);
  }

  static DateTime _normalizeDateOnlyUtc(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  static DateTime _parseDateOnlyJsonValue(Object? value, String fieldName) {
    if (value is! String) {
      throw ArgumentError('Missing or invalid $fieldName');
    }

    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (match != null) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      return DateTime(year, month, day);
    }

    return _normalizeDateOnly(DateTime.parse(value));
  }

  static String _formatDateOnly(DateTime date) {
    final normalizedDate = _normalizeDateOnly(date);
    final year = normalizedDate.year.toString().padLeft(4, '0');
    final month = normalizedDate.month.toString().padLeft(2, '0');
    final day = normalizedDate.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Hydrate participant groups, falling back to the retired `participantCount`
  /// scalar for docs written before נגלות existed. An explicitly empty array
  /// means "no groups" and must NOT fall back — otherwise clearing every group
  /// would resurrect the old scalar.
  static List<ParticipantGroupModel> _parseParticipantGroups(
    Object? groupsRaw,
    Object? legacyCount,
  ) {
    if (groupsRaw is List) {
      return groupsRaw
          .map(ParticipantGroupModel.tryFromJson)
          .whereType<ParticipantGroupModel>()
          .toList();
    }

    final legacy = legacyCount is num ? legacyCount.toInt() : null;
    if (legacy != null && legacy >= 0) {
      return [ParticipantGroupModel(count: legacy)];
    }
    return const [];
  }

  /// Convert from domain entity
  factory EventModel.fromEntity(Event entity) {
    return EventModel(
      id: entity.id,
      name: entity.name,
      startDate: entity.startDate,
      endDate: entity.endDate,
      startTime: entity.startTime,
      endTime: entity.endTime,
      teamEndTime: entity.teamEndTime,
      assemblyTime: entity.assemblyTime,
      actualShowStartTime: entity.actualShowStartTime,
      participantGroups: entity.participantGroups
          .map(ParticipantGroupModel.fromEntity)
          .toList(),
      location: entity.location,
      parkingLocation: entity.parkingLocation,
      parkingEditorIds: entity.parkingEditorIds,
      requiresArmed: entity.requiresArmed,
      comments: entity.comments,
      categoryId: entity.categoryId,
      roleRequirements: Map<String, int>.from(entity.roleRequirements),
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      driveFolderId: entity.driveFolderId,
      driveFolderLink: entity.driveFolderLink,
      relevantForExtendedTeam: entity.relevantForExtendedTeam,
      isDeactivated: entity.isDeactivated,
      inviteAllPermanentWhenUnassigned: entity.inviteAllPermanentWhenUnassigned,
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
      teamEndTime: teamEndTime,
      assemblyTime: assemblyTime,
      actualShowStartTime: actualShowStartTime,
      participantGroups:
          participantGroups.map((group) => group.toEntity()).toList(),
      location: location,
      parkingLocation: parkingLocation,
      parkingEditorIds: parkingEditorIds,
      requiresArmed: requiresArmed,
      comments: comments,
      categoryId: categoryId,
      roleRequirements: Map<String, int>.from(roleRequirements),
      createdAt: createdAt,
      updatedAt: updatedAt,
      driveFolderId: driveFolderId,
      driveFolderLink: driveFolderLink,
      relevantForExtendedTeam: relevantForExtendedTeam,
      isDeactivated: isDeactivated,
      inviteAllPermanentWhenUnassigned: inviteAllPermanentWhenUnassigned,
    );
  }

  /// Convert from Firestore document
  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return EventModel(
      id: doc.id,
      name: data['name'] as String,
      startDate: _normalizeDateOnly((data['startDate'] as Timestamp).toDate()),
      endDate: _normalizeDateOnly((data['endDate'] as Timestamp).toDate()),
      startTime: data['startTime'] as String,
      endTime: data['endTime'] as String,
      teamEndTime: data['teamEndTime'] as String? ?? '',
      assemblyTime: data['assemblyTime'] as String,
      actualShowStartTime: data['actualShowStartTime'] as String? ?? '',
      participantGroups: _parseParticipantGroups(
        data['participantGroups'],
        data['participantCount'],
      ),
      location: data['location'] as String? ?? '',
      parkingLocation: data['parkingLocation'] as String?,
      parkingEditorIds:
          List<String>.from(data['parkingEditorIds'] as List? ?? const []),
      requiresArmed: data['requiresArmed'] as bool? ?? false,
      comments: data['comments'] as String? ?? data['notes'] as String? ?? '',
      categoryId: data['categoryId'] as String?,
      roleRequirements:
          Map<String, int>.from(data['roleRequirements'] as Map? ?? {}),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      driveFolderId: data['driveFolderId'] as String?,
      driveFolderLink: data['driveFolderLink'] as String?,
      relevantForExtendedTeam:
          data['relevantForExtendedTeam'] as bool? ?? false,
      isDeactivated: data['isDeactivated'] as bool? ?? false,
      inviteAllPermanentWhenUnassigned:
          data['inviteAllPermanentWhenUnassigned'] as bool? ?? false,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'startDate': Timestamp.fromDate(_normalizeDateOnlyUtc(startDate)),
      'endDate': Timestamp.fromDate(_normalizeDateOnlyUtc(endDate)),
      'startTime': startTime,
      'endTime': endTime,
      'teamEndTime': teamEndTime,
      'assemblyTime': assemblyTime,
      'actualShowStartTime': actualShowStartTime,
      'participantGroups':
          participantGroups.map((group) => group.toJson()).toList(),
      'location': location,
      'parkingLocation': parkingLocation,
      'parkingEditorIds': parkingEditorIds,
      'requiresArmed': requiresArmed,
      'comments': comments,
      'categoryId': categoryId,
      'roleRequirements': roleRequirements,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'driveFolderId': driveFolderId,
      'driveFolderLink': driveFolderLink,
      'relevantForExtendedTeam': relevantForExtendedTeam,
      'isDeactivated': isDeactivated,
      'inviteAllPermanentWhenUnassigned': inviteAllPermanentWhenUnassigned,
    };
  }

  /// Convert from JSON
  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      name: json['name'] as String,
      startDate: _parseDateOnlyJsonValue(json['startDate'], 'startDate'),
      endDate: _parseDateOnlyJsonValue(json['endDate'], 'endDate'),
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      teamEndTime: json['teamEndTime'] as String? ?? '',
      assemblyTime: json['assemblyTime'] as String,
      actualShowStartTime: json['actualShowStartTime'] as String? ?? '',
      participantGroups: _parseParticipantGroups(
        json['participantGroups'],
        json['participantCount'],
      ),
      location: json['location'] as String? ?? '',
      parkingLocation: json['parkingLocation'] as String?,
      parkingEditorIds:
          List<String>.from(json['parkingEditorIds'] as List? ?? const []),
      requiresArmed: json['requiresArmed'] as bool? ?? false,
      comments: json['comments'] as String? ?? json['notes'] as String? ?? '',
      categoryId: json['categoryId'] as String?,
      roleRequirements:
          Map<String, int>.from(json['roleRequirements'] as Map? ?? {}),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      driveFolderId: json['driveFolderId'] as String?,
      driveFolderLink: json['driveFolderLink'] as String?,
      relevantForExtendedTeam:
          json['relevantForExtendedTeam'] as bool? ?? false,
      isDeactivated: json['isDeactivated'] as bool? ?? false,
      inviteAllPermanentWhenUnassigned:
          json['inviteAllPermanentWhenUnassigned'] as bool? ?? false,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'startDate': _formatDateOnly(startDate),
      'endDate': _formatDateOnly(endDate),
      'startTime': startTime,
      'endTime': endTime,
      'teamEndTime': teamEndTime,
      'assemblyTime': assemblyTime,
      'actualShowStartTime': actualShowStartTime,
      'participantGroups':
          participantGroups.map((group) => group.toJson()).toList(),
      'location': location,
      'parkingLocation': parkingLocation,
      'parkingEditorIds': parkingEditorIds,
      'requiresArmed': requiresArmed,
      'comments': comments,
      'categoryId': categoryId,
      'roleRequirements': roleRequirements,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'driveFolderId': driveFolderId,
      'driveFolderLink': driveFolderLink,
      'relevantForExtendedTeam': relevantForExtendedTeam,
      'isDeactivated': isDeactivated,
      'inviteAllPermanentWhenUnassigned': inviteAllPermanentWhenUnassigned,
    };
  }
}

/// Data model for ParticipantGroup
class ParticipantGroupModel {
  final String? label;
  final int count;

  const ParticipantGroupModel({this.label, required this.count});

  factory ParticipantGroupModel.fromEntity(ParticipantGroup entity) {
    return ParticipantGroupModel(
      label: entity.normalizedLabel,
      count: entity.count,
    );
  }

  ParticipantGroup toEntity() => ParticipantGroup(label: label, count: count);

  /// Parse one stored group, returning null for anything malformed so a single
  /// bad entry is dropped instead of breaking the whole event. Not a `fromJson`
  /// factory, because a factory cannot report "this entry is garbage".
  static ParticipantGroupModel? tryFromJson(Object? raw) {
    if (raw is! Map) return null;

    final rawCount = raw['count'];
    final count = rawCount is num ? rawCount.toInt() : null;
    if (count == null || count < 0) return null;

    final label = raw['label'];
    final trimmed = label is String ? label.trim() : null;
    return ParticipantGroupModel(
      label: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      count: count,
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'count': count};
}
