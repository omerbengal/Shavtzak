import 'dart:developer' as developer;
import 'dart:math' as math;

import '../../domain/entities/team_member.dart';
import 'backend_api_service.dart';
import 'environment_service.dart';
import 'google_oauth_service.dart';

class AppEventAttendeeSyncResult {
  final int scannedCount;
  final int syncedCount;
  final int skippedCount;
  final int failedCount;
  final List<String> failedEventIds;

  const AppEventAttendeeSyncResult({
    required this.scannedCount,
    required this.syncedCount,
    required this.skippedCount,
    required this.failedCount,
    this.failedEventIds = const [],
  });
}

class EventsAndConstraintsSyncResult {
  final int scannedEventCount;
  final int syncedEventCount;
  final int skippedEventCount;
  final int failedEventCount;
  final List<String> failedEventIds;
  final int scannedConstraintCount;
  final int rejectedConstraintCount;
  final int retriedConstraintCount;
  final int successfulConstraintRetryCount;
  final int skippedConstraintCount;
  final int failedConstraintCount;
  final List<String> failedConstraintIds;
  final String message;

  const EventsAndConstraintsSyncResult({
    required this.scannedEventCount,
    required this.syncedEventCount,
    required this.skippedEventCount,
    required this.failedEventCount,
    this.failedEventIds = const [],
    required this.scannedConstraintCount,
    required this.rejectedConstraintCount,
    required this.retriedConstraintCount,
    required this.successfulConstraintRetryCount,
    required this.skippedConstraintCount,
    required this.failedConstraintCount,
    this.failedConstraintIds = const [],
    required this.message,
  });
}

/// Service for interacting with Google Calendar through backend endpoints.
/// The browser never talks to Google Calendar directly.
class GoogleCalendarService {
  static GoogleCalendarService? _instance;

  final BackendApiService _backendApiService;
  final GoogleOAuthService _oauthService;
  bool _isInitialized = false;
  bool _isTestMode = false;

  GoogleCalendarService._({
    BackendApiService? backendApiService,
    GoogleOAuthService? oauthService,
  })  : _backendApiService = backendApiService ?? BackendApiService(),
        _oauthService = oauthService ?? GoogleOAuthService.instance;

  static GoogleCalendarService get instance {
    _instance ??= GoogleCalendarService._();
    return _instance!;
  }

  bool get isInitialized => _isInitialized;

  bool get isTestMode => _isTestMode;

  bool get isAuthenticated => _oauthService.isAuthenticated;

  Future<void> initialize({
    required String calendarId,
    bool testMode = false,
  }) async {
    _isTestMode = testMode || EnvironmentService.instance.isTestMode;

    try {
      await _oauthService.initialize();
      _isInitialized = true;
      developer.log(
        'GoogleCalendarService: Initialized with calendar ID: $calendarId${_isTestMode ? ' [TEST MODE]' : ''}',
        name: 'GoogleCalendar',
      );
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to initialize - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  Future<void> _ensureAuthenticated() async {
    if (!_isInitialized) {
      throw StateError(
        'GoogleCalendarService not initialized. Call initialize() first.',
      );
    }

    final isConnected = await _oauthService.refreshStatus();
    if (!isConnected) {
      throw StateError('Not authenticated. User must sign in with Google.');
    }
  }

  Future<void> ensureAuthenticatedForBatchOperation() async {
    await _ensureAuthenticated();
  }

  void dispose() {
    _isInitialized = false;
  }

  Future<Map<String, dynamic>> _calendarAction(
    String action, {
    Map<String, dynamic>? payload,
  }) async {
    await _ensureAuthenticated();
    return await _backendApiService.calendarAction(
      action,
      payload: payload,
    );
  }

  Future<String> createConstraintEvent({
    required String constraintId,
    required TeamMember teamMember,
    required DateConstraint constraint,
  }) async {
    final response = await _calendarAction(
      'createConstraintEvent',
      payload: {
        'teamMember': _serializeTeamMember(teamMember),
        'constraint':
            _serializeConstraint(constraint.copyWith(id: constraintId)),
        'isTestMode': _isTestMode,
      },
    );

    final calendarEventId = response['calendarEventId'] as String?;
    if (calendarEventId == null || calendarEventId.isEmpty) {
      throw GoogleCalendarException('Missing calendar event ID from backend');
    }
    return calendarEventId;
  }

  Future<void> updateConstraintEvent({
    required String calendarEventId,
    required String constraintId,
    required TeamMember teamMember,
    required DateConstraint constraint,
  }) async {
    await _calendarAction(
      'updateConstraintEvent',
      payload: {
        'calendarEventId': calendarEventId,
        'teamMember': _serializeTeamMember(teamMember),
        'constraint':
            _serializeConstraint(constraint.copyWith(id: constraintId)),
        'isTestMode': _isTestMode,
      },
    );
  }

  Future<void> deleteConstraintEvent(
    String calendarEventId, {
    String? teamMemberId,
  }) async {
    if (teamMemberId == null || teamMemberId.isEmpty) {
      throw GoogleCalendarException(
          'Missing team member ID for constraint deletion');
    }

    await _calendarAction(
      'deleteConstraintEvent',
      payload: {
        'calendarEventId': calendarEventId,
        'teamMemberId': teamMemberId,
      },
    );
  }

  Future<void> listAllEvents() async {
    await _calendarAction('listEvents');
  }

  Future<bool> eventExists(String calendarEventId) async {
    final response = await _calendarAction(
      'eventExists',
      payload: {
        'calendarEventId': calendarEventId,
      },
    );
    return response['exists'] == true;
  }

  Future<Map<String, String>> createAppEventCalendarEvents({
    required String eventId,
    required String eventName,
    required DateTime startDate,
    required DateTime endDate,
    required String assemblyTime,
    required String separatorTime,
    required String endTime,
    String? location,
  }) async {
    final response = await _calendarAction(
      'createAppEventCalendarEvents',
      payload: {
        'event': _serializeAppEvent(
          eventId: eventId,
          eventName: eventName,
          startDate: startDate,
          endDate: endDate,
          assemblyTime: assemblyTime,
          separatorTime: separatorTime,
          endTime: endTime,
          location: location,
        ),
      },
    );
    return _stringMap(response['result']);
  }

  Future<Map<String, String>?> updateAppEventCalendarEvents({
    required String assemblyCalendarEventId,
    required String mainCalendarEventId,
    required String eventId,
    required String eventName,
    required DateTime startDate,
    required DateTime endDate,
    required String assemblyTime,
    required String separatorTime,
    required String endTime,
    String? location,
  }) async {
    final response = await _calendarAction(
      'updateAppEventCalendarEvents',
      payload: {
        'assemblyCalendarEventId': assemblyCalendarEventId,
        'mainCalendarEventId': mainCalendarEventId,
        'event': _serializeAppEvent(
          eventId: eventId,
          eventName: eventName,
          startDate: startDate,
          endDate: endDate,
          assemblyTime: assemblyTime,
          separatorTime: separatorTime,
          endTime: endTime,
          location: location,
        ),
      },
    );

    final result = response['result'];
    if (result == null) {
      return null;
    }
    return _stringMap(result);
  }

  Future<void> deleteAppEventCalendarEvents({
    String? assemblyCalendarEventId,
    String? mainCalendarEventId,
  }) async {
    await _calendarAction(
      'deleteAppEventCalendarEvents',
      payload: {
        'assemblyCalendarEventId': assemblyCalendarEventId,
        'mainCalendarEventId': mainCalendarEventId,
      },
    );
  }

  Future<void> addAttendeeToEvent(String calendarEventId, String email) async {
    await _calendarAction(
      'addAttendeeToEvent',
      payload: {
        'calendarEventId': calendarEventId,
        'email': email,
      },
    );
  }

  Future<void> removeAttendeeFromEvent(
    String calendarEventId,
    String email,
  ) async {
    await _calendarAction(
      'removeAttendeeFromEvent',
      payload: {
        'calendarEventId': calendarEventId,
        'email': email,
      },
    );
  }

  Future<void> updateEventAttendees(
    String calendarEventId,
    List<String> emails,
  ) async {
    await _calendarAction(
      'updateEventAttendees',
      payload: {
        'calendarEventId': calendarEventId,
        'emails': emails,
      },
    );
  }

  Future<AppEventAttendeeSyncResult> syncAppEventAttendees({
    String? eventId,
  }) async {
    await _ensureAuthenticated();

    final response = await _backendApiService.post(
      'calendar/sync-app-event-attendees',
      requireAuth: true,
      body: {
        if (eventId != null && eventId.isNotEmpty) 'eventId': eventId,
      },
    );

    final failedEventIds =
        (response['failedEventIds'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);

    return AppEventAttendeeSyncResult(
      scannedCount: _readInt(response['scannedCount']),
      syncedCount: _readInt(response['syncedCount']),
      skippedCount: _readInt(response['skippedCount']),
      failedCount: _readInt(response['failedCount']),
      failedEventIds: failedEventIds,
    );
  }

  /// Number of events reconciled per backend request during a chunked sync.
  /// Small enough that a single request stays well under the client's 30s
  /// request timeout even when every event needs Google Calendar API calls.
  static const int _eventSyncChunkSize = 10;

  /// Sync all in-scope events and constraints to Google Calendar.
  ///
  /// Runs as a *chunked* sequence of short backend requests instead of one long
  /// request: first it fetches the work list ('plan'), then reconciles events a
  /// handful at a time, then constraints. This keeps every request short enough
  /// to avoid the client/function timeout that made the one-shot sync fail once
  /// many events existed. [onEventProgress] reports `(done, total)` events as
  /// each chunk completes so callers can show live progress.
  Future<EventsAndConstraintsSyncResult> syncEventsAndConstraints({
    void Function(int done, int total)? onEventProgress,
  }) async {
    await _ensureAuthenticated();

    // 1. Fetch the list of events to sync (cheap: Firestore only, no Google).
    final planResponse = await _backendApiService.post(
      'calendar/sync-events-and-constraints',
      requireAuth: true,
      body: const {'mode': 'plan'},
    );
    final eventIds = _readStringList(planResponse['eventIds']);
    final totalEvents = eventIds.length;

    var scannedEventCount = 0;
    var syncedEventCount = 0;
    var skippedEventCount = 0;
    var failedEventCount = 0;
    final failedEventIds = <String>[];

    onEventProgress?.call(0, totalEvents);

    // 2. Reconcile events in small chunks, one short request each.
    for (var start = 0; start < eventIds.length; start += _eventSyncChunkSize) {
      final end = math.min(start + _eventSyncChunkSize, eventIds.length);
      final chunk = eventIds.sublist(start, end);

      final response = await _backendApiService.post(
        'calendar/sync-events-and-constraints',
        requireAuth: true,
        body: {'mode': 'events', 'eventIds': chunk},
      );

      scannedEventCount += _readInt(response['scannedEventCount']);
      syncedEventCount += _readInt(response['syncedEventCount']);
      skippedEventCount += _readInt(response['skippedEventCount']);
      failedEventCount += _readInt(response['failedEventCount']);
      failedEventIds.addAll(_readStringList(response['failedEventIds']));

      onEventProgress?.call(end, totalEvents);
    }

    // 3. Sync constraints in a single bounded request (far fewer than events).
    final constraintResponse = await _backendApiService.post(
      'calendar/sync-events-and-constraints',
      requireAuth: true,
      body: const {'mode': 'constraints'},
    );

    final scannedConstraintCount =
        _readInt(constraintResponse['scannedConstraintCount']);
    final rejectedConstraintCount =
        _readInt(constraintResponse['rejectedConstraintCount']);
    final retriedConstraintCount =
        _readInt(constraintResponse['retriedConstraintCount']);
    final successfulConstraintRetryCount =
        _readInt(constraintResponse['successfulConstraintRetryCount']);
    final skippedConstraintCount =
        _readInt(constraintResponse['skippedConstraintCount']);
    final failedConstraintCount =
        _readInt(constraintResponse['failedConstraintCount']);
    final failedConstraintIds =
        _readStringList(constraintResponse['failedConstraintIds']);

    return EventsAndConstraintsSyncResult(
      scannedEventCount: scannedEventCount,
      syncedEventCount: syncedEventCount,
      skippedEventCount: skippedEventCount,
      failedEventCount: failedEventCount,
      failedEventIds: failedEventIds,
      scannedConstraintCount: scannedConstraintCount,
      rejectedConstraintCount: rejectedConstraintCount,
      retriedConstraintCount: retriedConstraintCount,
      successfulConstraintRetryCount: successfulConstraintRetryCount,
      skippedConstraintCount: skippedConstraintCount,
      failedConstraintCount: failedConstraintCount,
      failedConstraintIds: failedConstraintIds,
      message: _buildCombinedSyncMessage(
        scannedEventCount: scannedEventCount,
        syncedEventCount: syncedEventCount,
        skippedEventCount: skippedEventCount,
        failedEventCount: failedEventCount,
        scannedConstraintCount: scannedConstraintCount,
        syncedConstraintCount: successfulConstraintRetryCount,
        skippedConstraintCount: skippedConstraintCount,
        failedConstraintCount: failedConstraintCount,
        rejectedConstraintCount: rejectedConstraintCount,
      ),
    );
  }

  /// Hebrew summary shown after a chunked sync. Mirrors the backend's
  /// `buildCombinedSyncMessage` so the wording stays consistent with the
  /// legacy one-shot path.
  String _buildCombinedSyncMessage({
    required int scannedEventCount,
    required int syncedEventCount,
    required int skippedEventCount,
    required int failedEventCount,
    required int scannedConstraintCount,
    required int syncedConstraintCount,
    required int skippedConstraintCount,
    required int failedConstraintCount,
    required int rejectedConstraintCount,
  }) {
    final parts = <String>[
      'אירועים: בוצעו שינויים ב-$syncedEventCount מתוך $scannedEventCount, '
          'כבר היו תקינים $skippedEventCount, נכשלו $failedEventCount.',
      'מגבלות: בוצעו שינויים ב-$syncedConstraintCount מתוך $scannedConstraintCount, '
          'כבר היו תקינות $skippedConstraintCount, נכשלו $failedConstraintCount.',
    ];
    if (rejectedConstraintCount > 0) {
      parts.add('מגבלות: $rejectedConstraintCount מגבלות נדחו בעקבות מחיקה ביומן.');
    }
    return 'סנכרון אירועים ומגבלות הושלם. ${parts.join(' ')}';
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((entry) => entry.toString())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> _serializeTeamMember(TeamMember teamMember) {
    return {
      'id': teamMember.id,
      'name': teamMember.name,
      'email': teamMember.email,
      'availableRoleKeys': teamMember.availableRoleKeys,
    };
  }

  Map<String, dynamic> _serializeConstraint(DateConstraint constraint) {
    return {
      'id': constraint.id,
      'startDate': _formatDateOnly(constraint.startDate),
      'endDate': constraint.endDate != null
          ? _formatDateOnly(constraint.endDate!)
          : null,
      'note': constraint.note,
      'constraintType': constraint.constraintType.name,
      'startTime': constraint.startTime,
      'endTime': constraint.endTime,
      'repeatType': constraint.repeatType?.name,
      'repeatDay': constraint.repeatDay,
      'repeatEndDate': constraint.repeatEndDate != null
          ? _formatDateOnly(constraint.repeatEndDate!)
          : null,
    };
  }

  Map<String, dynamic> _serializeAppEvent({
    required String eventId,
    required String eventName,
    required DateTime startDate,
    required DateTime endDate,
    required String assemblyTime,
    required String separatorTime,
    required String endTime,
    String? location,
  }) {
    return {
      'eventId': eventId,
      'eventName': eventName,
      'startDate': _formatDateOnly(startDate),
      'endDate': _formatDateOnly(endDate),
      'assemblyTime': assemblyTime,
      'separatorTime': separatorTime,
      'endTime': endTime,
      'location': location,
      'isTestMode': _isTestMode,
    };
  }

  Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    return value.map(
      (key, entry) => MapEntry(key.toString(), entry?.toString() ?? ''),
    );
  }

  int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  String _formatDateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class GoogleCalendarException implements Exception {
  final String message;
  final dynamic originalError;
  final bool isRetryable;

  GoogleCalendarException(
    this.message, {
    this.originalError,
    this.isRetryable = true,
  });

  @override
  String toString() => 'GoogleCalendarException: $message';
}
