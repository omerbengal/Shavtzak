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

    _isTestMode = testMode || EnvironmentService.instance.isTestMode;
    _calendarId = calendarId;

    if (_isTestMode) {
      developer.log(
        'GoogleCalendarService: Initialized in TEST mode - operations will be mocked',
        name: 'GoogleCalendar',
      );
      _isInitialized = true;
      return;
    }

    try {

      // Parse the JSON and fix the private key formatting
      final Map<String, dynamic> serviceAccountData = jsonDecode(serviceAccountJson);

      // Fix the private key by replacing literal \n with actual newlines
      if (serviceAccountData.containsKey('private_key')) {
        String privateKey = serviceAccountData['private_key'] as String;
        // Replace the literal \n with actual newlines for PEM format
        privateKey = privateKey.replaceAll(r'\n', '\n');
        serviceAccountData['private_key'] = privateKey;
      }

      final credentials = ServiceAccountCredentials.fromJson(
        serviceAccountData,
      );

      _authClient = await clientViaServiceAccount(
        credentials,
        [calendar.CalendarApi.calendarScope],
      );

      _calendarApi = calendar.CalendarApi(_authClient!);
      _isInitialized = true;

      developer.log(
        'GoogleCalendarService: Initialized successfully with calendar ID: $calendarId',
        name: 'GoogleCalendar',
      );
    } catch (e, stackTrace) {
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
      final mockEventId = 'mock_event_${constraintId}_${DateTime.now().millisecondsSinceEpoch}';
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

      final createdEvent = await _calendarApi!.events.insert(event, _calendarId!);


      developer.log(
        'GoogleCalendarService: Created event ${createdEvent.id} for constraint $constraintId',
        name: 'GoogleCalendar',
      );

      return createdEvent.id!;
    } catch (e, stackTrace) {
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
    _ensureInitialized();

    if (_isTestMode) {
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


      if (events.items != null) {
        for (final event in events.items!) {
        }
      }
    } catch (e) {
    }
  }

  /// Get an event by ID to check if it exists
  Future<bool> eventExists(String calendarEventId) async {

    _ensureInitialized();

    if (_isTestMode) {
      final exists = calendarEventId.startsWith('mock_event_');
      return exists;
    }

    try {
      final event = await _calendarApi!.events.get(_calendarId!, calendarEventId);

      // Consider cancelled events as non-existent
      if (event.status == 'cancelled') {
        return false;
      }

      return true;
    } on calendar.DetailedApiRequestError catch (e) {
      if (e.status == 404 || e.status == 410) {
        return false;
      }
      rethrow;
    } catch (e) {
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
