import 'dart:convert';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'dart:developer' as developer;

import '../constants/calendar_constants.dart';
import '../constants/role_types.dart';
import '../../domain/entities/team_member.dart';
import 'environment_service.dart';

/// Service for interacting with Google Calendar API
/// Uses service account authentication for server-to-server communication
class GoogleCalendarService {
  static GoogleCalendarService? _instance;

  calendar.CalendarApi? _calendarApi;
  AuthClient? _authClient;
  String? _calendarId;
  bool _isInitialized = false;
  bool _isTestMode = false;

  GoogleCalendarService._();

  static GoogleCalendarService get instance {
    _instance ??= GoogleCalendarService._();
    return _instance!;
  }

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if running in test mode (mock operations)
  bool get isTestMode => _isTestMode;

  /// Initialize the service with service account credentials
  /// In test mode, operations are mocked and not sent to Google Calendar
  Future<void> initialize({
    required String serviceAccountJson,
    required String calendarId,
    bool testMode = false,
  }) async {
    print('🗓️ [GoogleCalendarService] initialize() called');
    print('🗓️ [GoogleCalendarService] Calendar ID: $calendarId');
    print('🗓️ [GoogleCalendarService] Environment test mode: ${EnvironmentService.instance.isTestMode}');

    _isTestMode = testMode || EnvironmentService.instance.isTestMode;
    _calendarId = calendarId;

    if (_isTestMode) {
      print('🗓️ [GoogleCalendarService] Running in TEST mode - operations will be mocked');
      developer.log(
        'GoogleCalendarService: Initialized in TEST mode - operations will be mocked',
        name: 'GoogleCalendar',
      );
      _isInitialized = true;
      return;
    }

    try {
      print('🗓️ [GoogleCalendarService] Parsing service account credentials...');

      // Parse the JSON and fix the private key formatting
      final Map<String, dynamic> serviceAccountData = jsonDecode(serviceAccountJson);

      // Fix the private key by replacing literal \n with actual newlines
      if (serviceAccountData.containsKey('private_key')) {
        String privateKey = serviceAccountData['private_key'] as String;
        // Replace the literal \n with actual newlines for PEM format
        privateKey = privateKey.replaceAll(r'\n', '\n');
        serviceAccountData['private_key'] = privateKey;
        print('🗓️ [GoogleCalendarService] Fixed private key formatting');
      }

      final credentials = ServiceAccountCredentials.fromJson(
        serviceAccountData,
      );
      print('🗓️ [GoogleCalendarService] Credentials parsed, client email: ${credentials.email}');

      print('🗓️ [GoogleCalendarService] Authenticating with Google...');
      _authClient = await clientViaServiceAccount(
        credentials,
        [calendar.CalendarApi.calendarScope],
      );
      print('🗓️ [GoogleCalendarService] ✅ Authentication successful');

      _calendarApi = calendar.CalendarApi(_authClient!);
      _isInitialized = true;

      print('🗓️ [GoogleCalendarService] ✅ Initialized successfully');
      developer.log(
        'GoogleCalendarService: Initialized successfully with calendar ID: $calendarId',
        name: 'GoogleCalendar',
      );
    } catch (e, stackTrace) {
      print('🗓️ [GoogleCalendarService] ❌ Failed to initialize: $e');
      print('🗓️ [GoogleCalendarService] Stack trace: $stackTrace');
      developer.log(
        'GoogleCalendarService: Failed to initialize - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  /// Dispose of resources
  void dispose() {
    _authClient?.close();
    _authClient = null;
    _calendarApi = null;
    _isInitialized = false;
  }

  /// Create a calendar event for a constraint
  /// Returns the created event ID
  Future<String> createConstraintEvent({
    required String constraintId,
    required TeamMember teamMember,
    required DateConstraint constraint,
  }) async {
    print('🗓️ [GoogleCalendarService] createConstraintEvent() called');
    print('🗓️ [GoogleCalendarService] Constraint ID: $constraintId');
    print('🗓️ [GoogleCalendarService] Team Member: ${teamMember.name}');
    print('🗓️ [GoogleCalendarService] Start Date: ${constraint.startDate}');
    print('🗓️ [GoogleCalendarService] End Date: ${constraint.endDate}');
    print('🗓️ [GoogleCalendarService] Is Unavailability: ${constraint.isUnavailability}');

    _ensureInitialized();

    final isUnavailability = constraint.isUnavailability;
    final title = isUnavailability
        ? CalendarEventTitles.unavailability(teamMember.name)
        : CalendarEventTitles.availability(teamMember.name);

    print('🗓️ [GoogleCalendarService] Event title: $title');

    final description = CalendarEventDescriptions.constraint(
      memberName: teamMember.name,
      roles: teamMember.availableRoles.map((r) => r.hebrewName).toList(),
      note: constraint.note,
      isUnavailability: isUnavailability,
    );

    if (_isTestMode) {
      final mockEventId = 'mock_event_${constraintId}_${DateTime.now().millisecondsSinceEpoch}';
      print('🗓️ [GoogleCalendarService] TEST MODE - returning mock event ID: $mockEventId');
      developer.log(
        'GoogleCalendarService [TEST]: Would create event: $title',
        name: 'GoogleCalendar',
      );
      developer.log(
        'GoogleCalendarService [TEST]: Mock event ID: $mockEventId',
        name: 'GoogleCalendar',
      );
      return mockEventId;
    }

    try {
      // For all-day events, use date property with date-only DateTime
      final startDate = _toDateOnly(constraint.startDate);
      final endDate = _toDateOnly(
        constraint.endDate?.add(const Duration(days: 1)) ??
            constraint.startDate.add(const Duration(days: 1)),
      );

      print('🗓️ [GoogleCalendarService] Creating event...');
      print('🗓️ [GoogleCalendarService] Start: $startDate, End: $endDate');
      print('🗓️ [GoogleCalendarService] Calendar ID: $_calendarId');
      print('🗓️ [GoogleCalendarService] Color ID: ${isUnavailability ? CalendarEventColors.unavailability : CalendarEventColors.availability}');

      final event = calendar.Event(
        summary: title,
        description: description,
        start: calendar.EventDateTime(date: startDate),
        end: calendar.EventDateTime(date: endDate),
        colorId: isUnavailability
            ? CalendarEventColors.unavailability
            : CalendarEventColors.availability,
        extendedProperties: calendar.EventExtendedProperties(
          private: {
            'constraintId': constraintId,
            'teamMemberId': teamMember.id,
            'constraintType': constraint.constraintType.name,
          },
        ),
      );

      print('🗓️ [GoogleCalendarService] Calling Google Calendar API...');
      final createdEvent = await _calendarApi!.events.insert(event, _calendarId!);

      print('🗓️ [GoogleCalendarService] ✅ Event created successfully!');
      print('🗓️ [GoogleCalendarService] Event ID: ${createdEvent.id}');
      print('🗓️ [GoogleCalendarService] Event Link: ${createdEvent.htmlLink}');

      developer.log(
        'GoogleCalendarService: Created event ${createdEvent.id} for constraint $constraintId',
        name: 'GoogleCalendar',
      );

      return createdEvent.id!;
    } catch (e, stackTrace) {
      print('🗓️ [GoogleCalendarService] ❌ Failed to create event: $e');
      print('🗓️ [GoogleCalendarService] Stack trace: $stackTrace');
      developer.log(
        'GoogleCalendarService: Failed to create event - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  /// Update an existing calendar event
  Future<void> updateConstraintEvent({
    required String calendarEventId,
    required String constraintId,
    required TeamMember teamMember,
    required DateConstraint constraint,
  }) async {
    _ensureInitialized();

    final isUnavailability = constraint.isUnavailability;
    final title = isUnavailability
        ? CalendarEventTitles.unavailability(teamMember.name)
        : CalendarEventTitles.availability(teamMember.name);

    final description = CalendarEventDescriptions.constraint(
      memberName: teamMember.name,
      roles: teamMember.availableRoles.map((r) => r.hebrewName).toList(),
      note: constraint.note,
      isUnavailability: isUnavailability,
    );

    if (_isTestMode) {
      developer.log(
        'GoogleCalendarService [TEST]: Would update event $calendarEventId: $title',
        name: 'GoogleCalendar',
      );
      return;
    }

    try {
      // For all-day events, use date property with date-only DateTime
      final startDate = _toDateOnly(constraint.startDate);
      final endDate = _toDateOnly(
        constraint.endDate?.add(const Duration(days: 1)) ??
            constraint.startDate.add(const Duration(days: 1)),
      );

      final event = calendar.Event(
        summary: title,
        description: description,
        start: calendar.EventDateTime(date: startDate),
        end: calendar.EventDateTime(date: endDate),
        colorId: isUnavailability
            ? CalendarEventColors.unavailability
            : CalendarEventColors.availability,
        extendedProperties: calendar.EventExtendedProperties(
          private: {
            'constraintId': constraintId,
            'teamMemberId': teamMember.id,
            'constraintType': constraint.constraintType.name,
          },
        ),
      );

      await _calendarApi!.events.update(event, _calendarId!, calendarEventId);

      developer.log(
        'GoogleCalendarService: Updated event $calendarEventId for constraint $constraintId',
        name: 'GoogleCalendar',
      );
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to update event - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  /// Delete a calendar event
  Future<void> deleteConstraintEvent(String calendarEventId) async {
    _ensureInitialized();

    if (_isTestMode) {
      developer.log(
        'GoogleCalendarService [TEST]: Would delete event $calendarEventId',
        name: 'GoogleCalendar',
      );
      return;
    }

    try {
      await _calendarApi!.events.delete(_calendarId!, calendarEventId);

      developer.log(
        'GoogleCalendarService: Deleted event $calendarEventId',
        name: 'GoogleCalendar',
      );
    } on calendar.DetailedApiRequestError catch (e) {
      // If event not found, consider it already deleted
      if (e.status == 404 || e.status == 410) {
        developer.log(
          'GoogleCalendarService: Event $calendarEventId already deleted or not found',
          name: 'GoogleCalendar',
        );
        return;
      }
      rethrow;
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to delete event - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  /// Debug method to list all events in the calendar (for testing)
  Future<void> listAllEvents() async {
    print('🗓️ [GoogleCalendarService] ==== DEBUG: Listing all events ====');
    _ensureInitialized();

    if (_isTestMode) {
      print('🗓️ [GoogleCalendarService] In test mode, skipping event list');
      return;
    }

    try {
      final now = DateTime.now();
      final events = await _calendarApi!.events.list(
        _calendarId!,
        timeMin: DateTime(now.year, now.month, 1),
        timeMax: DateTime(now.year, now.month + 1, 0),
        singleEvents: true,
        orderBy: 'startTime',
      );

      print('🗓️ [GoogleCalendarService] Found ${events.items?.length ?? 0} events');

      if (events.items != null) {
        for (final event in events.items!) {
          print('🗓️ [GoogleCalendarService] - Event: ${event.summary}');
          print('🗓️ [GoogleCalendarService]   ID: ${event.id}');
          print('🗓️ [GoogleCalendarService]   Status: ${event.status}');
          print('🗓️ [GoogleCalendarService]   Start: ${event.start?.date ?? event.start?.dateTime}');
          print('🗓️ [GoogleCalendarService]   End: ${event.end?.date ?? event.end?.dateTime}');
          print('🗓️ [GoogleCalendarService]   ---');
        }
      }
    } catch (e) {
      print('🗓️ [GoogleCalendarService] ❌ Error listing events: $e');
    }
  }

  /// Get an event by ID to check if it exists
  Future<bool> eventExists(String calendarEventId) async {
    print('🗓️ [GoogleCalendarService] eventExists() called for event ID: $calendarEventId');
    print('🗓️ [GoogleCalendarService] Test mode: $_isTestMode');
    print('🗓️ [GoogleCalendarService] Calendar ID: $_calendarId');

    _ensureInitialized();

    if (_isTestMode) {
      print('🗓️ [GoogleCalendarService] In test mode, checking if event ID starts with "mock_event_"');
      final exists = calendarEventId.startsWith('mock_event_');
      print('🗓️ [GoogleCalendarService] Event exists in test mode: $exists');
      return exists;
    }

    try {
      print('🗓️ [GoogleCalendarService] Fetching event from Google Calendar API...');
      final event = await _calendarApi!.events.get(_calendarId!, calendarEventId);
      print('🗓️ [GoogleCalendarService] ✅ Event found in Google Calendar');
      print('🗓️ [GoogleCalendarService] Event summary: ${event.summary}');
      print('🗓️ [GoogleCalendarService] Event status: ${event.status}');
      print('🗓️ [GoogleCalendarService] Event start: ${event.start?.date ?? event.start?.dateTime}');
      print('🗓️ [GoogleCalendarService] Event end: ${event.end?.date ?? event.end?.dateTime}');
      print('🗓️ [GoogleCalendarService] Event ID: ${event.id}');

      // Consider cancelled events as non-existent
      if (event.status == 'cancelled') {
        print('🗓️ [GoogleCalendarService] ❌ Event is cancelled, treating as deleted');
        return false;
      }

      return true;
    } on calendar.DetailedApiRequestError catch (e) {
      print('🗓️ [GoogleCalendarService] ❌ API Error: ${e.status} - ${e.message}');
      print('🗓️ [GoogleCalendarService] Error details: ${e.errors?.map((err) => '${err.reason}: ${err.message}').join(', ')}');
      if (e.status == 404 || e.status == 410) {
        print('🗓️ [GoogleCalendarService] Event not found (404/410), returning false');
        return false;
      }
      print('🗓️ [GoogleCalendarService] Rethrowing non-404/410 error');
      rethrow;
    } catch (e) {
      print('🗓️ [GoogleCalendarService] ❌ Unexpected error: $e');
      print('🗓️ [GoogleCalendarService] Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Convert DateTime to date-only DateTime (midnight UTC) for all-day events
  DateTime _toDateOnly(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('GoogleCalendarService not initialized. Call initialize() first.');
    }
  }
}

/// Exception for Google Calendar operations
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
