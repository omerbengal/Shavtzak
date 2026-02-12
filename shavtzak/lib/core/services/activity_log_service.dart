import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/team_member.dart';
import 'environment_service.dart';

/// Singleton service for logging user actions to Firestore.
/// Each log() call is awaited so the write completes before success state is emitted.
class ActivityLogService {
  static ActivityLogService? _instance;

  static ActivityLogService get instance {
    _instance ??= ActivityLogService._();
    return _instance!;
  }

  ActivityLogService._();

  TeamMember? _currentUser;

  void setCurrentUser(TeamMember? user) => _currentUser = user;

  String get _collection =>
      '${EnvironmentService.instance.collectionPrefix}activity_logs';

  /// Log a user action to Firestore.
  Future<void> log({
    required String action,
    required String entityType,
    String? entityId,
    String? entityName,
    Map<String, dynamic>? details,
  }) async {
    await FirebaseFirestore.instance.collection(_collection).add({
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'entityName': entityName,
      'performedBy': _currentUser?.uniqueKey,
      'performedByName': _currentUser?.name,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
