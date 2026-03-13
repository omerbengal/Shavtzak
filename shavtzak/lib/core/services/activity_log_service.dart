import 'dart:developer' as developer;

import '../../domain/entities/team_member.dart';

/// Client-side Firestore activity logs are disabled.
/// Trusted mutation logs now belong in backend functions.
class ActivityLogService {
  static ActivityLogService? _instance;

  static ActivityLogService get instance {
    _instance ??= ActivityLogService._();
    return _instance!;
  }

  ActivityLogService._();

  TeamMember? _currentUser;

  void setCurrentUser(TeamMember? user) => _currentUser = user;

  /// Log a user action locally until backend-backed audit log reads are added.
  Future<void> log({
    required String action,
    required String entityType,
    String? entityId,
    String? entityName,
    Map<String, dynamic>? details,
  }) async {
    developer.log(
      'ActivityLogService: $action/$entityType entityId=$entityId entityName=$entityName performedBy=${_currentUser?.uniqueKey} details=$details',
      name: 'ActivityLog',
    );
  }
}
