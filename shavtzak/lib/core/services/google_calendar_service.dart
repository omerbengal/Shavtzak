import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'dart:developer' as developer;

import '../constants/calendar_constants.dart';
import '../../domain/entities/team_member.dart';
import 'environment_service.dart';
import 'google_oauth_service.dart';

/// Service for interacting with Google Calendar API
/// Uses OAuth 2.0 authentication via GoogleOAuthService
class GoogleCalendarService {
  static GoogleCalendarService? _instance;

  calendar.CalendarApi? _calendarApi;
  AuthClient? _authClient;
  String? _calendarId;
  bool _isInitialized = false;
  bool _isTestMode = false;
  final GoogleOAuthService _oauthService = GoogleOAuthService.instance;

  GoogleCalendarService._();

  static GoogleCalendarService get instance {
    _instance ??= GoogleCalendarService._();
    return _instance!;
  }

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if running in test mode (events created with yellow color and prefix)
  bool get isTestMode => _isTestMode;

  /// Check if user is authenticated
  bool get isAuthenticated => _oauthService.isAuthenticated;

  /// Initialize the service with OAuth authentication
  /// In test mode, events are created with yellow color and "שבצק טסטינג: " prefix
  Future<void> initialize({
    required String calendarId,
    bool testMode = false,
  }) async {
    _isTestMode = testMode || EnvironmentService.instance.isTestMode;
    _calendarId = calendarId;

    try {
      developer.log(
        'GoogleCalendarService: Initializing with OAuth...',
        name: 'GoogleCalendar',
      );

      // Initialize OAuth service
      await _oauthService.initialize();

      // Get authenticated client if user is already authenticated
      if (_oauthService.isAuthenticated) {
        await _refreshAuthClient();
      }

      _isInitialized = true;

      developer.log(
        'GoogleCalendarService: Initialized successfully with calendar ID: $calendarId${_isTestMode ? ' [TEST MODE - events will be yellow with prefix]' : ''}${_oauthService.isAuthenticated ? ' (authenticated as ${_oauthService.authenticatedUserEmail})' : ' (not authenticated yet)'}',
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

  /// Refresh the auth client with latest OAuth tokens
  Future<void> _refreshAuthClient() async {
    try {
      _authClient?.close();
      _authClient = await _oauthService.getAuthClient();

      if (_authClient != null) {
        _calendarApi = calendar.CalendarApi(_authClient!);
        developer.log(
          'GoogleCalendarService: Auth client refreshed',
          name: 'GoogleCalendar',
        );
      } else {
        _calendarApi = null;
        developer.log(
          'GoogleCalendarService: Failed to get auth client (re-authentication needed)',
          name: 'GoogleCalendar',
        );
      }
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to refresh auth client - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      _authClient = null;
      _calendarApi = null;
    }
  }

  /// Ensure we have a valid authenticated client before making API calls
  Future<void> _ensureAuthenticated() async {
    if (!_isInitialized) {
      throw StateError('GoogleCalendarService not initialized. Call initialize() first.');
    }

    // If no auth client or not authenticated, refresh
    if (_calendarApi == null || !_oauthService.isAuthenticated) {
      await _refreshAuthClient();
    }

    // If still no auth client, user needs to authenticate
    if (_calendarApi == null) {
      throw StateError('Not authenticated. User must sign in with Google.');
    }
  }

  /// Run a Calendar API call and retry once on 401 by forcing token refresh.
  Future<T> _withCalendarAuthRetry<T>(
    Future<T> Function() operation, {
    required String operationName,
  }) async {
    await _ensureAuthenticated();

    try {
      return await operation();
    } on calendar.DetailedApiRequestError catch (e) {
      if (e.status == 401) {
        developer.log(
          'GoogleCalendarService: 401 during $operationName, forcing token refresh and retrying once',
          name: 'GoogleCalendar',
        );

        final refreshed = await _oauthService.forceRefreshAccessToken();
        if (!refreshed) {
          rethrow;
        }

        await _refreshAuthClient();
        if (_calendarApi == null) {
          rethrow;
        }

        return await operation();
      }
      rethrow;
    }
  }

  Future<calendar.Event> _eventsInsert(calendar.Event event) {
    return _withCalendarAuthRetry(
      () => _calendarApi!.events.insert(event, _calendarId!),
      operationName: 'events.insert',
    );
  }

  Future<calendar.Event> _eventsUpdate(
    calendar.Event event,
    String eventId, {
    int? conferenceDataVersion,
    String? sendUpdates,
  }) {
    return _withCalendarAuthRetry(
      () => _calendarApi!.events.update(
        event,
        _calendarId!,
        eventId,
        conferenceDataVersion: conferenceDataVersion,
        sendUpdates: sendUpdates,
      ),
      operationName: 'events.update',
    );
  }

  Future<void> _eventsDelete(String eventId) {
    return _withCalendarAuthRetry(
      () => _calendarApi!.events.delete(_calendarId!, eventId),
      operationName: 'events.delete',
    );
  }

  Future<calendar.Event> _eventsGet(String eventId) {
    return _withCalendarAuthRetry(
      () => _calendarApi!.events.get(_calendarId!, eventId),
      operationName: 'events.get',
    );
  }

  Future<calendar.Events> _eventsList({
    DateTime? timeMin,
    DateTime? timeMax,
    bool? singleEvents,
    String? orderBy,
  }) {
    return _withCalendarAuthRetry(
      () => _calendarApi!.events.list(
        _calendarId!,
        timeMin: timeMin,
        timeMax: timeMax,
        singleEvents: singleEvents,
        orderBy: orderBy,
      ),
      operationName: 'events.list',
    );
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

    await _ensureAuthenticated();

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

      final createdEvent = await _eventsInsert(event);


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
    await _ensureAuthenticated();

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

      await _eventsUpdate(event, calendarEventId);

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
    await _ensureAuthenticated();

    try {
      await _eventsDelete(calendarEventId);

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
    await _ensureAuthenticated();

    if (_isTestMode) {
      return;
    }

    try {
      final now = DateTime.now();
      final events = await _eventsList(
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

    await _ensureAuthenticated();

    try {
      final event = await _eventsGet(calendarEventId);

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
  static const int _allDayReminderMinutesBefore = 420; // Previous day at 17:00

  /// Convert DateTime to date-only DateTime (midnight UTC) for all-day events
  DateTime _toDateOnly(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  /// Full-day app events reminder override: previous day at 17:00.
  calendar.EventReminders _buildAllDayEventReminders() {
    return calendar.EventReminders(
      useDefault: false,
      overrides: [
        calendar.EventReminder(
          method: 'popup',
          minutes: _allDayReminderMinutesBefore,
        ),
      ],
    );
  }

  /// Combine a date with a "HH:mm" time string into a full DateTime
  DateTime _combineDateAndTime(DateTime date, String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Create calendar events for an app event
  /// Creates up to 2 events based on available time fields:
  /// 1. Assembly event: [name] - התייצבות והכנות (assemblyTime → separatorTime)
  /// 2. Main event: [name] (separatorTime → endTime)
  /// If no separator but assemblyTime and endTime exist: creates single main event (assemblyTime → endTime)
  /// If endTime is empty/missing: creates an all-day event instead
  /// Returns map with 'assembly' and 'main' calendar event IDs
  /// In test mode, events are created with yellow color and "שבצק טסטינג: " prefix
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
    await _ensureAuthenticated();

    final result = <String, String>{};

    try {
      // Use yellow color in test mode, otherwise use peacock color
      final colorId = _isTestMode
          ? CalendarEventColors.testMode
          : CalendarEventColors.appEvent;

      // Check if this should be an all-day event (no endTime OR no assemblyTime specified)
      final isAllDayEvent = assemblyTime.isEmpty || endTime.isEmpty;

      if (isAllDayEvent) {
        // Create a single all-day event spanning the full date range
        final allDayTitle = CalendarEventTitles.eventMain(eventName, isTestMode: _isTestMode);

        // For all-day events, use date-only DateTime (midnight UTC)
        final eventStart = _toDateOnly(startDate);
        // End date is exclusive in Google Calendar, so add 1 day
        final eventEnd = _toDateOnly(
          endDate.add(const Duration(days: 1)),
        );

        final allDayEvent = calendar.Event(
          summary: allDayTitle,
          description: null,
          start: calendar.EventDateTime(date: eventStart),
          end: calendar.EventDateTime(date: eventEnd),
          reminders: _buildAllDayEventReminders(),
          location: location,
          colorId: colorId,
          extendedProperties: calendar.EventExtendedProperties(
            private: {
              'eventId': eventId,
              'eventType': 'allDay',
              'isTestMode': _isTestMode.toString(),
            },
          ),
        );

        final createdEvent = await _eventsInsert(allDayEvent);
        result['main'] = createdEvent.id!;

        developer.log(
          'GoogleCalendarService: Created all-day event ${createdEvent.id} for event $eventId${_isTestMode ? ' [TEST MODE]' : ''}',
          name: 'GoogleCalendar',
        );
      } else {
        // Create timed events
        // Create assembly event if assemblyTime and separatorTime are provided
        if (assemblyTime.isNotEmpty && separatorTime.isNotEmpty) {
          final assemblyTitle = CalendarEventTitles.eventAssembly(eventName, isTestMode: _isTestMode);
          final assemblyStart = _combineDateAndTime(startDate, assemblyTime);
          final assemblyEnd = _combineDateAndTime(startDate, separatorTime);

          final assemblyEvent = calendar.Event(
            summary: assemblyTitle,
            description: null,
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

          final createdAssembly = await _eventsInsert(assemblyEvent);
          result['assembly'] = createdAssembly.id!;

          developer.log(
            'GoogleCalendarService: Created assembly event ${createdAssembly.id} for event $eventId${_isTestMode ? ' [TEST MODE]' : ''}',
            name: 'GoogleCalendar',
          );
        }

        // Create main event
        // Case 1: separatorTime and endTime exist → normal main event (separatorTime → endTime)
        // Case 2: no separatorTime but assemblyTime and endTime exist → single main event (assemblyTime → endTime)
        final mainTitle = CalendarEventTitles.eventMain(eventName, isTestMode: _isTestMode);

        // Determine main event start time
        final DateTime mainStart;
        if (separatorTime.isNotEmpty) {
          // Normal case: use separator time
          mainStart = _combineDateAndTime(startDate, separatorTime);
        } else if (assemblyTime.isNotEmpty) {
          // Special case: no separator, use assembly time
          mainStart = _combineDateAndTime(startDate, assemblyTime);
        } else {
          // Skip if no valid start time (shouldn't happen if we're here since endTime is not empty)
          return result;
        }

        // Main event can span to endDate for multi-day events
        final mainEnd = _combineDateAndTime(endDate, endTime);

        final mainEvent = calendar.Event(
          summary: mainTitle,
          description: null,
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

        final createdMain = await _eventsInsert(mainEvent);
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
  /// Uses separatorTime (fallback logic already applied by caller)
  /// If endTime is empty/missing, creates an all-day event instead of timed events
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
    required String separatorTime,
    required String endTime,
    String? location,
  }) async {
    await _ensureAuthenticated();

    Map<String, String>? recreatedIds;
    bool needsAssemblyRecreation = false;
    bool needsMainRecreation = false;

    try {
      // Use yellow color in test mode, otherwise use peacock color
      final colorId = _isTestMode
          ? CalendarEventColors.testMode
          : CalendarEventColors.appEvent;

      // Check if this should be an all-day event (no endTime OR no assemblyTime specified)
      final isAllDayEvent = assemblyTime.isEmpty || endTime.isEmpty;

      if (isAllDayEvent) {
        // Handle all-day event: delete any existing timed events and create all-day event
        if (assemblyCalendarEventId.isNotEmpty) {
          try {
            await _eventsDelete(assemblyCalendarEventId);
            developer.log(
              'GoogleCalendarService: Deleted assembly event $assemblyCalendarEventId (switching to all-day)',
              name: 'GoogleCalendar',
            );
          } on calendar.DetailedApiRequestError catch (e) {
            if (e.status != 404 && e.status != 410) rethrow;
          }
          recreatedIds = recreatedIds ?? {};
          recreatedIds['assembly'] = '';
        }

        final allDayTitle = CalendarEventTitles.eventMain(eventName, isTestMode: _isTestMode);
        final eventStart = _toDateOnly(startDate);
        final eventEnd = _toDateOnly(endDate.add(const Duration(days: 1)));

        // Update or create all-day event
        if (mainCalendarEventId.isNotEmpty) {
          final allDayEvent = calendar.Event(
            summary: allDayTitle,
            description: null,
            start: calendar.EventDateTime(date: eventStart),
            end: calendar.EventDateTime(date: eventEnd),
            reminders: _buildAllDayEventReminders(),
            location: location,
            colorId: colorId,
            extendedProperties: calendar.EventExtendedProperties(
              private: {
                'eventId': eventId,
                'eventType': 'allDay',
                'isTestMode': _isTestMode.toString(),
              },
            ),
          );

          try {
            await _eventsUpdate(allDayEvent, mainCalendarEventId);
            developer.log(
              'GoogleCalendarService: Updated all-day event $mainCalendarEventId for event $eventId',
              name: 'GoogleCalendar',
            );
          } on calendar.DetailedApiRequestError catch (e) {
            if (e.status == 404 || e.status == 410) {
              developer.log(
                'GoogleCalendarService: Main event $mainCalendarEventId not found, will recreate as all-day',
                name: 'GoogleCalendar',
              );
              needsMainRecreation = true;
            } else {
              rethrow;
            }
          }
        } else {
          needsMainRecreation = true;
        }

        if (needsMainRecreation) {
          final allDayEvent = calendar.Event(
            summary: allDayTitle,
            description: null,
            start: calendar.EventDateTime(date: eventStart),
            end: calendar.EventDateTime(date: eventEnd),
            reminders: _buildAllDayEventReminders(),
            location: location,
            colorId: colorId,
            extendedProperties: calendar.EventExtendedProperties(
              private: {
                'eventId': eventId,
                'eventType': 'allDay',
                'isTestMode': _isTestMode.toString(),
              },
            ),
          );

          final createdEvent = await _eventsInsert(allDayEvent);
          recreatedIds = recreatedIds ?? {};
          recreatedIds['main'] = createdEvent.id!;
          recreatedIds['assembly'] = '';

          developer.log(
            'GoogleCalendarService: Created all-day event ${createdEvent.id} for event $eventId',
            name: 'GoogleCalendar',
          );
        }

        return recreatedIds;
      }

      // Timed events - original logic
      // Determine which events should exist based on time fields
      final shouldHaveAssembly = assemblyTime.isNotEmpty && separatorTime.isNotEmpty;
      // Main event can exist with separator OR with just assemblyTime + endTime
      final shouldHaveMain = endTime.isNotEmpty && (separatorTime.isNotEmpty || assemblyTime.isNotEmpty);

      // Handle assembly event
      if (shouldHaveAssembly) {
        // If ID is empty, we need to create it
        if (assemblyCalendarEventId.isEmpty) {
          needsAssemblyRecreation = true;
        } else {
          // Try to update existing event
          final assemblyTitle = CalendarEventTitles.eventAssembly(eventName, isTestMode: _isTestMode);
          final assemblyStart = _combineDateAndTime(startDate, assemblyTime);
          final assemblyEnd = _combineDateAndTime(startDate, separatorTime);

          final assemblyEvent = calendar.Event(
            summary: assemblyTitle,
            description: null,
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
            await _eventsUpdate(assemblyEvent, assemblyCalendarEventId);

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

          // Determine main event start time (same logic as create)
          final DateTime mainStart;
          if (separatorTime.isNotEmpty) {
            // Normal case: use separator time
            mainStart = _combineDateAndTime(startDate, separatorTime);
          } else {
            // Special case: no separator, use assembly time
            mainStart = _combineDateAndTime(startDate, assemblyTime);
          }

          final mainEnd = _combineDateAndTime(endDate, endTime);

          final mainEvent = calendar.Event(
            summary: mainTitle,
            description: null,
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
            await _eventsUpdate(mainEvent, mainCalendarEventId);

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
          final assemblyEnd = _combineDateAndTime(startDate, separatorTime);

          final assemblyEvent = calendar.Event(
            summary: assemblyTitle,
            description: null,
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

          final createdAssembly = await _eventsInsert(assemblyEvent);
          recreatedIds['assembly'] = createdAssembly.id!;

          developer.log(
            'GoogleCalendarService: Created assembly event ${createdAssembly.id} for event $eventId${_isTestMode ? ' [TEST MODE]' : ''}',
            name: 'GoogleCalendar',
          );
        }

        // Only create main event if it needs recreation
        if (needsMainRecreation) {
          final mainTitle = CalendarEventTitles.eventMain(eventName, isTestMode: _isTestMode);

          // Determine main event start time (same logic as create and update)
          final DateTime mainStart;
          if (separatorTime.isNotEmpty) {
            // Normal case: use separator time
            mainStart = _combineDateAndTime(startDate, separatorTime);
          } else {
            // Special case: no separator, use assembly time
            mainStart = _combineDateAndTime(startDate, assemblyTime);
          }

          final mainEnd = _combineDateAndTime(endDate, endTime);

          final mainEvent = calendar.Event(
            summary: mainTitle,
            description: null,
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

          final createdMain = await _eventsInsert(mainEvent);
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
    await _ensureAuthenticated();

    try {
      // Delete assembly event if ID is provided
      if (assemblyCalendarEventId != null && assemblyCalendarEventId.isNotEmpty) {
        try {
          await _eventsDelete(assemblyCalendarEventId);
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
          await _eventsDelete(mainCalendarEventId);
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

  /// Add attendee to event
  Future<void> addAttendeeToEvent(String calendarEventId, String email) async {
    await _ensureAuthenticated();

    try {
      // Get current event
      final event = await _eventsGet(calendarEventId);

      // Add attendee if not already present
      final currentAttendees = event.attendees ?? [];
      final alreadyHasAttendee = currentAttendees.any((a) => a.email == email);

      if (!alreadyHasAttendee) {
        final updatedAttendees = [
          ...currentAttendees,
          calendar.EventAttendee(email: email),
        ];

        // Update the existing event object to preserve all fields
        event.attendees = updatedAttendees;

        await _eventsUpdate(
          event,
          calendarEventId,
          conferenceDataVersion: 1,
          sendUpdates: 'none', // Don't send email invites (requires Domain-Wide Delegation)
        );

        developer.log(
          'GoogleCalendarService: Added attendee $email to event $calendarEventId',
          name: 'GoogleCalendar',
        );
      } else {
        developer.log(
          'GoogleCalendarService: Attendee $email already in event $calendarEventId',
          name: 'GoogleCalendar',
        );
      }
    } on calendar.DetailedApiRequestError catch (e) {
      if (e.status == 404 || e.status == 410) {
        developer.log(
          'GoogleCalendarService: Event $calendarEventId not found while adding attendee $email, skipping',
          name: 'GoogleCalendar',
        );
        return;
      }
      rethrow;
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to add attendee to event $calendarEventId - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  /// Remove attendee from event
  Future<void> removeAttendeeFromEvent(String calendarEventId, String email) async {
    await _ensureAuthenticated();

    try {
      // Get current event
      final event = await _eventsGet(calendarEventId);

      // Remove attendee if present
      final currentAttendees = event.attendees ?? [];
      final filteredAttendees = currentAttendees
          .where((a) => a.email != email)
          .toList();

      if (filteredAttendees.length != currentAttendees.length) {
        // Update the existing event object to preserve all fields
        event.attendees = filteredAttendees.isNotEmpty ? filteredAttendees : null;

        await _eventsUpdate(
          event,
          calendarEventId,
          conferenceDataVersion: 1,
          sendUpdates: 'none', // Don't send email invites (requires Domain-Wide Delegation)
        );

        developer.log(
          'GoogleCalendarService: Removed attendee $email from event $calendarEventId',
          name: 'GoogleCalendar',
        );
      } else {
        developer.log(
          'GoogleCalendarService: Attendee $email not in event $calendarEventId',
          name: 'GoogleCalendar',
        );
      }
    } on calendar.DetailedApiRequestError catch (e) {
      if (e.status == 404 || e.status == 410) {
        developer.log(
          'GoogleCalendarService: Event $calendarEventId not found while removing attendee $email, skipping',
          name: 'GoogleCalendar',
        );
        return;
      }
      rethrow;
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to remove attendee from event $calendarEventId - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
    }
  }

  /// Update attendees for event (replaces entire list)
  Future<void> updateEventAttendees(String calendarEventId, List<String> emails) async {
    await _ensureAuthenticated();

    try {
      // Get current event
      final event = await _eventsGet(calendarEventId);

      // Build attendee list from emails
      final attendees = emails
          .map((email) => calendar.EventAttendee(email: email))
          .toList();

      // Update the existing event object to preserve all fields
      event.attendees = attendees.isNotEmpty ? attendees : null;

      await _eventsUpdate(
        event,
        calendarEventId,
        conferenceDataVersion: 1,
        sendUpdates: 'none', // Don't send email invites (requires Domain-Wide Delegation)
      );

      developer.log(
        'GoogleCalendarService: Updated ${attendees.length} attendees for event $calendarEventId',
        name: 'GoogleCalendar',
      );
    } on calendar.DetailedApiRequestError catch (e) {
      if (e.status == 404 || e.status == 410) {
        developer.log(
          'GoogleCalendarService: Event $calendarEventId not found while syncing attendees, skipping',
          name: 'GoogleCalendar',
        );
        return;
      }
      rethrow;
    } catch (e) {
      developer.log(
        'GoogleCalendarService: Failed to update attendees for event $calendarEventId - $e',
        name: 'GoogleCalendar',
        error: e,
      );
      rethrow;
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
