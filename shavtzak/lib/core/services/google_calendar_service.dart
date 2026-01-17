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

  /// Check if running in test mode (events created with yellow color and prefix)
  bool get isTestMode => _isTestMode;

  /// Initialize the service with service account credentials
  /// In test mode, events are created with yellow color and "שבצק טסטינג: " prefix
  Future<void> initialize({
    required String serviceAccountJson,
    required String calendarId,
    bool testMode = false,
  }) async {

    _isTestMode = testMode || EnvironmentService.instance.isTestMode;
    _calendarId = calendarId;

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
        'GoogleCalendarService: Initialized successfully with calendar ID: $calendarId${_isTestMode ? ' [TEST MODE - events will be yellow with prefix]' : ''}',
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

  /// Dispose of resources
  void dispose() {
    _authClient?.close();
    _authClient = null;
    _calendarApi = null;
    _isInitialized = false;
  }

  /// Create a calendar event for a constraint
  /// Returns the created event ID
  /// In test mode, events are created with yellow color and "שבצק טסטינג: " prefix
  Future<String> createConstraintEvent({
    required String constraintId,
    required TeamMember teamMember,
    required DateConstraint constraint,
  }) async {

    _ensureInitialized();

    final isUnavailability = constraint.isUnavailability;
    // Use test mode prefix in title when in test mode
    final title = isUnavailability
        ? CalendarEventTitles.unavailability(teamMember.name, isTestMode: _isTestMode)
        : CalendarEventTitles.availability(teamMember.name, isTestMode: _isTestMode);


    final description = CalendarEventDescriptions.constraint(
      memberName: teamMember.name,
      roles: teamMember.availableRoleKeys, // Pass role keys instead of Hebrew names
      note: constraint.note,
      isUnavailability: isUnavailability,
    );

    try {
      // For all-day events, use date property with date-only DateTime
      final startDate = _toDateOnly(constraint.startDate);
      final endDate = _toDateOnly(
        constraint.endDate?.add(const Duration(days: 1)) ??
            constraint.startDate.add(const Duration(days: 1)),
      );

      // Use yellow color in test mode, otherwise use appropriate color
      final colorId = _isTestMode
          ? CalendarEventColors.testMode
          : (isUnavailability
              ? CalendarEventColors.unavailability
              : CalendarEventColors.availability);

      final event = calendar.Event(
        summary: title,
        description: description,
        start: calendar.EventDateTime(date: startDate),
        end: calendar.EventDateTime(date: endDate),
        colorId: colorId,
        extendedProperties: calendar.EventExtendedProperties(
          private: {
            'constraintId': constraintId,
            'teamMemberId': teamMember.id,
            'constraintType': constraint.constraintType.name,
            'isTestMode': _isTestMode.toString(),
          },
        ),
      );

      final createdEvent = await _calendarApi!.events.insert(event, _calendarId!);


      developer.log(
        'GoogleCalendarService: Created event ${createdEvent.id} for constraint $constraintId${_isTestMode ? ' [TEST MODE]' : ''}',
        name: 'GoogleCalendar',
      );

      return createdEvent.id!;
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to create event - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  /// Update an existing calendar event
  /// In test mode, events are updated with yellow color and "שבצק טסטינג: " prefix
  Future<void> updateConstraintEvent({
    required String calendarEventId,
    required String constraintId,
    required TeamMember teamMember,
    required DateConstraint constraint,
  }) async {
    _ensureInitialized();

    final isUnavailability = constraint.isUnavailability;
    // Use test mode prefix in title when in test mode
    final title = isUnavailability
        ? CalendarEventTitles.unavailability(teamMember.name, isTestMode: _isTestMode)
        : CalendarEventTitles.availability(teamMember.name, isTestMode: _isTestMode);

    final description = CalendarEventDescriptions.constraint(
      memberName: teamMember.name,
      roles: teamMember.availableRoleKeys, // Pass role keys instead of Hebrew names
      note: constraint.note,
      isUnavailability: isUnavailability,
    );

    try {
      // For all-day events, use date property with date-only DateTime
      final startDate = _toDateOnly(constraint.startDate);
      final endDate = _toDateOnly(
        constraint.endDate?.add(const Duration(days: 1)) ??
            constraint.startDate.add(const Duration(days: 1)),
      );

      // Use yellow color in test mode, otherwise use appropriate color
      final colorId = _isTestMode
          ? CalendarEventColors.testMode
          : (isUnavailability
              ? CalendarEventColors.unavailability
              : CalendarEventColors.availability);

      final event = calendar.Event(
        summary: title,
        description: description,
        start: calendar.EventDateTime(date: startDate),
        end: calendar.EventDateTime(date: endDate),
        colorId: colorId,
        extendedProperties: calendar.EventExtendedProperties(
          private: {
            'constraintId': constraintId,
            'teamMemberId': teamMember.id,
            'constraintType': constraint.constraintType.name,
            'isTestMode': _isTestMode.toString(),
          },
        ),
      );

      await _calendarApi!.events.update(event, _calendarId!, calendarEventId);

      developer.log(
        'GoogleCalendarService: Updated event $calendarEventId for constraint $constraintId${_isTestMode ? ' [TEST MODE]' : ''}',
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

    try {
      await _calendarApi!.events.delete(_calendarId!, calendarEventId);

      developer.log(
        'GoogleCalendarService: Deleted event $calendarEventId${_isTestMode ? ' [TEST MODE]' : ''}',
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
        for (final _ in events.items!) {
          // Process events if needed
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// Get an event by ID to check if it exists
  Future<bool> eventExists(String calendarEventId) async {

    _ensureInitialized();

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
