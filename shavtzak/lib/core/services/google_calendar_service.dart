import 'dart:convert';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'dart:developer' as developer;

import '../constants/calendar_constants.dart';
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
      // Use yellow color in test mode, otherwise use appropriate color
      final colorId = _isTestMode
          ? CalendarEventColors.testMode
          : (isUnavailability
              ? CalendarEventColors.unavailability
              : CalendarEventColors.availability);

      // Build start/end based on whether constraint has specific times
      final hasTimeRange = constraint.startTime != null && constraint.endTime != null;
      final calendar.EventDateTime eventStart;
      final calendar.EventDateTime eventEnd;

      if (hasTimeRange) {
        // Timed event: combine date + time with Israel timezone
        eventStart = calendar.EventDateTime(
          dateTime: _combineDateAndTime(constraint.startDate, constraint.startTime!),
          timeZone: _timeZone,
        );
        final endBaseDate = constraint.endDate ?? constraint.startDate;
        eventEnd = calendar.EventDateTime(
          dateTime: _combineDateAndTime(endBaseDate, constraint.endTime!),
          timeZone: _timeZone,
        );
      } else {
        // All-day event: use date property with date-only DateTime
        final startDate = _toDateOnly(constraint.startDate);
        final endDate = _toDateOnly(
          constraint.endDate?.add(const Duration(days: 1)) ??
              constraint.startDate.add(const Duration(days: 1)),
        );
        eventStart = calendar.EventDateTime(date: startDate);
        eventEnd = calendar.EventDateTime(date: endDate);
      }

      final event = calendar.Event(
        summary: title,
        description: description,
        start: eventStart,
        end: eventEnd,
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
      // Use yellow color in test mode, otherwise use appropriate color
      final colorId = _isTestMode
          ? CalendarEventColors.testMode
          : (isUnavailability
              ? CalendarEventColors.unavailability
              : CalendarEventColors.availability);

      // Build start/end based on whether constraint has specific times
      final hasTimeRange = constraint.startTime != null && constraint.endTime != null;
      final calendar.EventDateTime eventStart;
      final calendar.EventDateTime eventEnd;

      if (hasTimeRange) {
        // Timed event: combine date + time with Israel timezone
        eventStart = calendar.EventDateTime(
          dateTime: _combineDateAndTime(constraint.startDate, constraint.startTime!),
          timeZone: _timeZone,
        );
        final endBaseDate = constraint.endDate ?? constraint.startDate;
        eventEnd = calendar.EventDateTime(
          dateTime: _combineDateAndTime(endBaseDate, constraint.endTime!),
          timeZone: _timeZone,
        );
      } else {
        // All-day event: use date property with date-only DateTime
        final startDate = _toDateOnly(constraint.startDate);
        final endDate = _toDateOnly(
          constraint.endDate?.add(const Duration(days: 1)) ??
              constraint.startDate.add(const Duration(days: 1)),
        );
        eventStart = calendar.EventDateTime(date: startDate);
        eventEnd = calendar.EventDateTime(date: endDate);
      }

      final event = calendar.Event(
        summary: title,
        description: description,
        start: eventStart,
        end: eventEnd,
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

  /// Israel timezone for timed events
  static const String _timeZone = 'Asia/Jerusalem';

  /// Convert DateTime to date-only DateTime (midnight UTC) for all-day events
  DateTime _toDateOnly(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  /// Combine a date with a "HH:mm" time string into a full DateTime
  DateTime _combineDateAndTime(DateTime date, String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Create calendar events for an app event
  /// Creates 2 events:
  /// 1. Assembly event: [name] - התייצבות והכנות (assemblyTime → actualShowStartTime)
  /// 2. Main event: [name] (actualShowStartTime → endTime)
  /// Returns map with 'assembly' and 'main' calendar event IDs
  /// In test mode, events are created with yellow color and "שבצק טסטינג: " prefix
  Future<Map<String, String>> createAppEventCalendarEvents({
    required String eventId,
    required String eventName,
    required DateTime startDate,
    required DateTime endDate,
    required String assemblyTime,
    required String actualShowStartTime,
    required String endTime,
    String? location,
  }) async {
    _ensureInitialized();

    final result = <String, String>{};

    try {
      // Use yellow color in test mode, otherwise use peacock color
      final colorId = _isTestMode
          ? CalendarEventColors.testMode
          : CalendarEventColors.appEvent;

      // Create assembly event if assemblyTime and actualShowStartTime are provided
      if (assemblyTime.isNotEmpty && actualShowStartTime.isNotEmpty) {
        final assemblyTitle = CalendarEventTitles.eventAssembly(eventName, isTestMode: _isTestMode);
        final assemblyStart = _combineDateAndTime(startDate, assemblyTime);
        final assemblyEnd = _combineDateAndTime(startDate, actualShowStartTime);

        final assemblyEvent = calendar.Event(
          summary: assemblyTitle,
          description: 'התייצבות והכנות לאירוע\n\n--- נוצר אוטומטית על ידי שבצק ---',
          start: calendar.EventDateTime(
            dateTime: assemblyStart,
            timeZone: _timeZone,
          ),
          end: calendar.EventDateTime(
            dateTime: assemblyEnd,
            timeZone: _timeZone,
          ),
          location: location,
          colorId: colorId,
          extendedProperties: calendar.EventExtendedProperties(
            private: {
              'eventId': eventId,
              'eventType': 'assembly',
              'isTestMode': _isTestMode.toString(),
            },
          ),
        );

        final createdAssembly = await _calendarApi!.events.insert(assemblyEvent, _calendarId!);
        result['assembly'] = createdAssembly.id!;

        developer.log(
          'GoogleCalendarService: Created assembly event ${createdAssembly.id} for event $eventId${_isTestMode ? ' [TEST MODE]' : ''}',
          name: 'GoogleCalendar',
        );
      }

      // Create main event if actualShowStartTime and endTime are provided
      if (actualShowStartTime.isNotEmpty && endTime.isNotEmpty) {
        final mainTitle = CalendarEventTitles.eventMain(eventName, isTestMode: _isTestMode);
        final mainStart = _combineDateAndTime(startDate, actualShowStartTime);
        // Main event can span to endDate for multi-day events
        final mainEnd = _combineDateAndTime(endDate, endTime);

        final mainEvent = calendar.Event(
          summary: mainTitle,
          description: 'אירוע ראשי\n\n--- נוצר אוטומטית על ידי שבצק ---',
          start: calendar.EventDateTime(
            dateTime: mainStart,
            timeZone: _timeZone,
          ),
          end: calendar.EventDateTime(
            dateTime: mainEnd,
            timeZone: _timeZone,
          ),
          location: location,
          colorId: colorId,
          extendedProperties: calendar.EventExtendedProperties(
            private: {
              'eventId': eventId,
              'eventType': 'main',
              'isTestMode': _isTestMode.toString(),
            },
          ),
        );

        final createdMain = await _calendarApi!.events.insert(mainEvent, _calendarId!);
        result['main'] = createdMain.id!;

        developer.log(
          'GoogleCalendarService: Created main event ${createdMain.id} for event $eventId${_isTestMode ? ' [TEST MODE]' : ''}',
          name: 'GoogleCalendar',
        );
      }

      return result;
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to create app event calendar events - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  /// Update existing app event calendar events
  /// Updates both assembly and main events with new data
  /// If calendar event IDs are empty but time fields are provided, creates new events
  /// If calendar events were deleted, recreates them and returns new IDs
  /// In test mode, events are updated with yellow color and "שבצק טסטינג: " prefix
  /// Returns map with new calendar event IDs if events were recreated, null otherwise
  Future<Map<String, String>?> updateAppEventCalendarEvents({
    required String assemblyCalendarEventId,
    required String mainCalendarEventId,
    required String eventId,
    required String eventName,
    required DateTime startDate,
    required DateTime endDate,
    required String assemblyTime,
    required String actualShowStartTime,
    required String endTime,
    String? location,
  }) async {
    _ensureInitialized();

    Map<String, String>? recreatedIds;
    bool needsAssemblyRecreation = false;
    bool needsMainRecreation = false;

    try {
      // Use yellow color in test mode, otherwise use peacock color
      final colorId = _isTestMode
          ? CalendarEventColors.testMode
          : CalendarEventColors.appEvent;

      // Determine which events should exist based on time fields
      final shouldHaveAssembly = assemblyTime.isNotEmpty && actualShowStartTime.isNotEmpty;
      final shouldHaveMain = actualShowStartTime.isNotEmpty && endTime.isNotEmpty;

      // Handle assembly event
      if (shouldHaveAssembly) {
        // If ID is empty, we need to create it
        if (assemblyCalendarEventId.isEmpty) {
          needsAssemblyRecreation = true;
        } else {
          // Try to update existing event
          final assemblyTitle = CalendarEventTitles.eventAssembly(eventName, isTestMode: _isTestMode);
          final assemblyStart = _combineDateAndTime(startDate, assemblyTime);
          final assemblyEnd = _combineDateAndTime(startDate, actualShowStartTime);

          final assemblyEvent = calendar.Event(
            summary: assemblyTitle,
            description: 'התייצבות והכנות לאירוע\n\n--- נוצר אוטומטית על ידי שבצק ---',
            start: calendar.EventDateTime(
              dateTime: assemblyStart,
              timeZone: _timeZone,
            ),
            end: calendar.EventDateTime(
              dateTime: assemblyEnd,
              timeZone: _timeZone,
            ),
            location: location,
            colorId: colorId,
            extendedProperties: calendar.EventExtendedProperties(
              private: {
                'eventId': eventId,
                'eventType': 'assembly',
                'isTestMode': _isTestMode.toString(),
              },
            ),
          );

          try {
            await _calendarApi!.events.update(assemblyEvent, _calendarId!, assemblyCalendarEventId);

            developer.log(
              'GoogleCalendarService: Updated assembly event $assemblyCalendarEventId for event $eventId${_isTestMode ? ' [TEST MODE]' : ''}',
              name: 'GoogleCalendar',
            );
          } on calendar.DetailedApiRequestError catch (e) {
            // If event not found (deleted from calendar), recreate it
            if (e.status == 404 || e.status == 410) {
              developer.log(
                'GoogleCalendarService: Assembly event $assemblyCalendarEventId not found, will recreate',
                name: 'GoogleCalendar',
              );
              needsAssemblyRecreation = true;
            } else {
              rethrow;
            }
          }
        }
      }

      // Handle main event
      if (shouldHaveMain) {
        // If ID is empty, we need to create it
        if (mainCalendarEventId.isEmpty) {
          needsMainRecreation = true;
        } else {
          // Try to update existing event
          final mainTitle = CalendarEventTitles.eventMain(eventName, isTestMode: _isTestMode);
          final mainStart = _combineDateAndTime(startDate, actualShowStartTime);
          final mainEnd = _combineDateAndTime(endDate, endTime);

          final mainEvent = calendar.Event(
            summary: mainTitle,
            description: 'אירוע ראשי\n\n--- נוצר אוטומטית על ידי שבצק ---',
            start: calendar.EventDateTime(
              dateTime: mainStart,
              timeZone: _timeZone,
            ),
            end: calendar.EventDateTime(
              dateTime: mainEnd,
              timeZone: _timeZone,
            ),
            location: location,
            colorId: colorId,
            extendedProperties: calendar.EventExtendedProperties(
              private: {
                'eventId': eventId,
                'eventType': 'main',
                'isTestMode': _isTestMode.toString(),
              },
            ),
          );

          try {
            await _calendarApi!.events.update(mainEvent, _calendarId!, mainCalendarEventId);

            developer.log(
              'GoogleCalendarService: Updated main event $mainCalendarEventId for event $eventId${_isTestMode ? ' [TEST MODE]' : ''}',
              name: 'GoogleCalendar',
            );
          } on calendar.DetailedApiRequestError catch (e) {
            // If event not found (deleted from calendar), recreate it
            if (e.status == 404 || e.status == 410) {
              developer.log(
                'GoogleCalendarService: Main event $mainCalendarEventId not found, will recreate',
                name: 'GoogleCalendar',
              );
              needsMainRecreation = true;
            } else {
              rethrow;
            }
          }
        }
      }

      // Create only the specific events that need recreation
      if (needsAssemblyRecreation || needsMainRecreation) {
        developer.log(
          'GoogleCalendarService: Creating missing calendar events for event $eventId',
          name: 'GoogleCalendar',
        );

        recreatedIds = {};

        // Only create assembly event if it needs recreation
        if (needsAssemblyRecreation) {
          final assemblyTitle = CalendarEventTitles.eventAssembly(eventName, isTestMode: _isTestMode);
          final assemblyStart = _combineDateAndTime(startDate, assemblyTime);
          final assemblyEnd = _combineDateAndTime(startDate, actualShowStartTime);

          final assemblyEvent = calendar.Event(
            summary: assemblyTitle,
            description: 'התייצבות והכנות לאירוע\n\n--- נוצר אוטומטית על ידי שבצק ---',
            start: calendar.EventDateTime(
              dateTime: assemblyStart,
              timeZone: _timeZone,
            ),
            end: calendar.EventDateTime(
              dateTime: assemblyEnd,
              timeZone: _timeZone,
            ),
            location: location,
            colorId: _isTestMode ? CalendarEventColors.testMode : CalendarEventColors.appEvent,
            extendedProperties: calendar.EventExtendedProperties(
              private: {
                'eventId': eventId,
                'eventType': 'assembly',
                'isTestMode': _isTestMode.toString(),
              },
            ),
          );

          final createdAssembly = await _calendarApi!.events.insert(assemblyEvent, _calendarId!);
          recreatedIds['assembly'] = createdAssembly.id!;

          developer.log(
            'GoogleCalendarService: Created assembly event ${createdAssembly.id} for event $eventId${_isTestMode ? ' [TEST MODE]' : ''}',
            name: 'GoogleCalendar',
          );
        }

        // Only create main event if it needs recreation
        if (needsMainRecreation) {
          final mainTitle = CalendarEventTitles.eventMain(eventName, isTestMode: _isTestMode);
          final mainStart = _combineDateAndTime(startDate, actualShowStartTime);
          final mainEnd = _combineDateAndTime(endDate, endTime);

          final mainEvent = calendar.Event(
            summary: mainTitle,
            description: 'אירוע ראשי\n\n--- נוצר אוטומטית על ידי שבצק ---',
            start: calendar.EventDateTime(
              dateTime: mainStart,
              timeZone: _timeZone,
            ),
            end: calendar.EventDateTime(
              dateTime: mainEnd,
              timeZone: _timeZone,
            ),
            location: location,
            colorId: _isTestMode ? CalendarEventColors.testMode : CalendarEventColors.appEvent,
            extendedProperties: calendar.EventExtendedProperties(
              private: {
                'eventId': eventId,
                'eventType': 'main',
                'isTestMode': _isTestMode.toString(),
              },
            ),
          );

          final createdMain = await _calendarApi!.events.insert(mainEvent, _calendarId!);
          recreatedIds['main'] = createdMain.id!;

          developer.log(
            'GoogleCalendarService: Created main event ${createdMain.id} for event $eventId${_isTestMode ? ' [TEST MODE]' : ''}',
            name: 'GoogleCalendar',
          );
        }
      }

      return recreatedIds;
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to update app event calendar events - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  /// Delete app event calendar events
  /// Deletes both assembly and main events
  /// Handles 404/410 errors gracefully (events already deleted)
  Future<void> deleteAppEventCalendarEvents({
    String? assemblyCalendarEventId,
    String? mainCalendarEventId,
  }) async {
    _ensureInitialized();

    try {
      // Delete assembly event if ID is provided
      if (assemblyCalendarEventId != null && assemblyCalendarEventId.isNotEmpty) {
        try {
          await _calendarApi!.events.delete(_calendarId!, assemblyCalendarEventId);
          developer.log(
            'GoogleCalendarService: Deleted assembly event $assemblyCalendarEventId${_isTestMode ? ' [TEST MODE]' : ''}',
            name: 'GoogleCalendar',
          );
        } on calendar.DetailedApiRequestError catch (e) {
          // If event not found, consider it already deleted
          if (e.status == 404 || e.status == 410) {
            developer.log(
              'GoogleCalendarService: Assembly event $assemblyCalendarEventId already deleted or not found',
              name: 'GoogleCalendar',
            );
          } else {
            rethrow;
          }
        }
      }

      // Delete main event if ID is provided
      if (mainCalendarEventId != null && mainCalendarEventId.isNotEmpty) {
        try {
          await _calendarApi!.events.delete(_calendarId!, mainCalendarEventId);
          developer.log(
            'GoogleCalendarService: Deleted main event $mainCalendarEventId${_isTestMode ? ' [TEST MODE]' : ''}',
            name: 'GoogleCalendar',
          );
        } on calendar.DetailedApiRequestError catch (e) {
          // If event not found, consider it already deleted
          if (e.status == 404 || e.status == 410) {
            developer.log(
              'GoogleCalendarService: Main event $mainCalendarEventId already deleted or not found',
              name: 'GoogleCalendar',
            );
          } else {
            rethrow;
          }
        }
      }
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to delete app event calendar events - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
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
