import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/constants/calendar_constants.dart';
import '../../../core/services/calendar_sync_service.dart';
import '../../../core/services/google_calendar_service.dart';
import '../../../data/data_sources/database_interface.dart';
import '../../../domain/entities/team_member.dart';
import 'calendar_sync_event.dart';
import 'calendar_sync_state.dart';

/// BLoC for managing calendar sync operations
class CalendarSyncBloc extends Bloc<CalendarSyncEvent, CalendarSyncState> {
  final DatabaseInterface _database;
  CalendarSyncService? _syncService;
  final GoogleCalendarService _calendarService;
  bool _pendingAdminStartupAuthCheck = false;

  CalendarSyncBloc({
    required DatabaseInterface database,
    GoogleCalendarService? calendarService,
  })  : _database = database,
        _calendarService = calendarService ?? GoogleCalendarService.instance,
        super(const CalendarSyncInitial()) {
    on<InitializeCalendarSync>(_onInitialize);
    on<SyncConstraintToCalendar>(_onSyncConstraint);
    on<RemoveConstraintFromCalendar>(_onRemoveConstraint);
    on<SyncAllApprovedConstraints>(_onSyncAllApproved);
    on<RetryFailedSyncs>(_onRetryFailedSyncs);
    on<RetryFailedSync>(_onRetryFailedSync);
    on<ClearConstraintSyncState>(_onClearSyncState);
    on<CheckSyncStatus>(_onCheckSyncStatus);
    on<ValidateSyncedEvents>(_onValidateSyncedEvents);
    on<PerformBidirectionalSync>(_onPerformBidirectionalSync);
    on<SyncEventsAndConstraints>(_onSyncEventsAndConstraints);
    on<SyncAppEventToCalendar>(_onSyncAppEvent);
    on<RemoveAppEventFromCalendar>(_onRemoveAppEvent);
    on<AddAttendeeToAppEvent>(_onAddAttendeeToAppEvent);
    on<RemoveAttendeeFromAppEvent>(_onRemoveAttendeeFromAppEvent);
    on<SyncAttendeesForAppEvent>(_onSyncAttendeesForAppEvent);
    on<OnTeamMemberEmailChanged>(_onTeamMemberEmailChanged);
    on<BackfillConstraintEventAttendees>(_onBackfillConstraintEventAttendees);
    on<CheckCalendarAuthOnAdminAppLoad>(_onCheckCalendarAuthOnAdminAppLoad);
  }

  /// Initialize the calendar sync service
  Future<void> _onInitialize(
    InitializeCalendarSync event,
    Emitter<CalendarSyncState> emit,
  ) async {
    emit(const CalendarSyncInitializing());

    try {
      // Check if calendar ID is provided
      if (event.calendarId == null) {
        developer.log(
          'CalendarSyncBloc: No calendar ID provided, sync disabled',
          name: 'CalendarSyncBloc',
        );
        _pendingAdminStartupAuthCheck = false;
        emit(const CalendarSyncDisabled(
          reason: 'לא הוגדר מזהה יומן גוגל',
        ));
        return;
      }

      // Initialize Google Calendar service with OAuth
      await _calendarService.initialize(
        calendarId: event.calendarId!,
      );

      // Create sync service
      _syncService = CalendarSyncService(
        database: _database,
        calendarService: _calendarService,
      );

      // Get initial failed sync count
      final failedSyncs = await _database.getFailedSyncStates();

      developer.log(
        'CalendarSyncBloc: Initialized with ${failedSyncs.length} failed syncs pending',
        name: 'CalendarSyncBloc',
      );

      emit(CalendarSyncReady(
        isTestMode: _calendarService.isTestMode,
        failedSyncs: failedSyncs.length,
      ));

      // If admin startup check was requested before initialization completed,
      // run it now once the sync service is ready.
      if (_pendingAdminStartupAuthCheck) {
        _pendingAdminStartupAuthCheck = false;
        add(const CheckCalendarAuthOnAdminAppLoad());
      }
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Initialization failed - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      _pendingAdminStartupAuthCheck = false;
      emit(CalendarSyncInitializationFailed(errorMessage: e.toString()));
    }
  }

  /// Sync a constraint to the calendar
  Future<void> _onSyncConstraint(
    SyncConstraintToCalendar event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized, skipping sync',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    emit(CalendarSyncInProgress(
      constraintId: event.constraintId,
      message: 'מסנכרן מגבלה ליומן גוגל...',
    ));

    try {
      final result = await _syncService!.syncConstraintToCalendar(
        constraintId: event.constraintId,
        teamMember: event.teamMember,
        constraint: event.constraint,
      );

      if (result.success) {
        emit(CalendarSyncSuccess(
          constraintId: event.constraintId,
          calendarEventId: result.calendarEventId,
          message: 'המגבלה סונכרנה ליומן גוגל בהצלחה',
        ));
      } else {
        emit(CalendarSyncFailure(
          constraintId: event.constraintId,
          errorMessage: result.errorMessage ?? 'שגיאה לא ידועה',
          isRetryable: result.isRetryable,
        ));
      }
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Sync failed - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      emit(CalendarSyncFailure(
        constraintId: event.constraintId,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Remove a constraint from the calendar
  Future<void> _onRemoveConstraint(
    RemoveConstraintFromCalendar event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized, skipping removal',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    emit(CalendarSyncInProgress(
      constraintId: event.constraintId,
      message: 'מסיר מגבלה מיומן גוגל...',
    ));

    try {
      final result = await _syncService!.removeConstraintFromCalendar(
        event.constraintId,
      );

      if (result.success) {
        emit(CalendarSyncRemovalSuccess(
          constraintId: event.constraintId,
          message: 'המגבלה הוסרה מיומן גוגל בהצלחה',
        ));
      } else {
        emit(CalendarSyncFailure(
          constraintId: event.constraintId,
          errorMessage: result.errorMessage ?? 'שגיאה בהסרה מהיומן',
          isRetryable: result.isRetryable,
        ));
      }
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Removal failed - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      emit(CalendarSyncFailure(
        constraintId: event.constraintId,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Sync all approved constraints for a team member
  Future<void> _onSyncAllApproved(
    SyncAllApprovedConstraints event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    final approvedConstraints =
        event.teamMember.constraints.where((c) => c.isApproved()).toList();

    if (approvedConstraints.isEmpty) {
      emit(const CalendarSyncBatchComplete(
        successCount: 0,
        failureCount: 0,
      ));
      return;
    }

    int successCount = 0;
    int failureCount = 0;
    final failedIds = <String>[];

    for (final constraint in approvedConstraints) {
      emit(CalendarSyncInProgress(
        constraintId: constraint.id,
        message:
            'מסנכרן מגבלות ליומן גוגל... (${successCount + failureCount + 1}/${approvedConstraints.length})',
      ));

      try {
        final result = await _syncService!.syncConstraintToCalendar(
          constraintId: constraint.id,
          teamMember: event.teamMember,
          constraint: constraint,
        );

        if (result.success) {
          successCount++;
        } else {
          failureCount++;
          failedIds.add(constraint.id);
        }
      } catch (e) {
        failureCount++;
        failedIds.add(constraint.id);
      }
    }

    emit(CalendarSyncBatchComplete(
      successCount: successCount,
      failureCount: failureCount,
      failedConstraintIds: failedIds,
    ));
  }

  /// Retry all failed syncs
  Future<void> _onRetryFailedSyncs(
    RetryFailedSyncs event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      return;
    }

    final failedSyncs = await _syncService!.getFailedSyncs();

    if (failedSyncs.isEmpty) {
      emit(const CalendarSyncBatchComplete(
        successCount: 0,
        failureCount: 0,
      ));
      return;
    }

    developer.log(
      'CalendarSyncBloc: Retrying ${failedSyncs.length} failed syncs',
      name: 'CalendarSyncBloc',
    );

    // Note: This requires fetching the team member and constraint data
    // For now, we just update the state to indicate retries are needed
    emit(CalendarSyncReady(
      isTestMode: _calendarService.isTestMode,
      failedSyncs: failedSyncs.length,
    ));
  }

  /// Retry a specific failed sync
  Future<void> _onRetryFailedSync(
    RetryFailedSync event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      return;
    }

    final syncState = await _syncService!.getSyncState(event.constraintId);
    final retryCount = syncState?['retryCount'] as int? ?? 0;

    emit(CalendarSyncInProgress(
      constraintId: event.constraintId,
      message: 'מנסה שוב לסנכרן... (ניסיון ${retryCount + 1})',
    ));

    try {
      final result = await _syncService!.retrySyncWithBackoff(
        constraintId: event.constraintId,
        teamMember: event.teamMember,
        constraint: event.constraint,
        currentRetryCount: retryCount,
      );

      if (result.success) {
        emit(CalendarSyncSuccess(
          constraintId: event.constraintId,
          calendarEventId: result.calendarEventId,
          message: 'הסנכרון הושלם בהצלחה לאחר ניסיון נוסף',
        ));
      } else {
        emit(CalendarSyncFailure(
          constraintId: event.constraintId,
          errorMessage: result.errorMessage ?? 'שגיאה בסנכרון',
          isRetryable: result.isRetryable,
          retryCount: retryCount + 1,
        ));
      }
    } catch (e) {
      emit(CalendarSyncFailure(
        constraintId: event.constraintId,
        errorMessage: e.toString(),
        retryCount: retryCount + 1,
      ));
    }
  }

  /// Clear sync state for a constraint
  Future<void> _onClearSyncState(
    ClearConstraintSyncState event,
    Emitter<CalendarSyncState> emit,
  ) async {
    try {
      await _database.removeCalendarSyncState(event.constraintId);
      emit(CalendarSyncRemovalSuccess(
        constraintId: event.constraintId,
        message: 'מצב סנכרון נוקה',
      ));
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Failed to clear sync state - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
    }
  }

  /// Check sync status for a constraint
  Future<void> _onCheckSyncStatus(
    CheckSyncStatus event,
    Emitter<CalendarSyncState> emit,
  ) async {
    try {
      final syncState =
          await _database.getCalendarSyncState(event.constraintId);

      if (syncState == null) {
        emit(ConstraintSyncStatus(
          constraintId: event.constraintId,
          status: CalendarSyncStatus.pending,
        ));
        return;
      }

      emit(ConstraintSyncStatus(
        constraintId: event.constraintId,
        status: CalendarSyncStatusExtension.fromString(
          syncState['status'] as String? ?? 'pending',
        ),
        calendarEventId: syncState['calendarEventId'] as String?,
        errorMessage: syncState['errorMessage'] as String?,
      ));
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Failed to check sync status - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
    }
  }

  /// Validate all synced events with Google Calendar
  Future<void> _onValidateSyncedEvents(
    ValidateSyncedEvents event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    emit(const CalendarSyncInProgress(
      constraintId: 'validation',
      message: 'בודק אירועים מסונכרנים ביומן גוגל...',
    ));

    try {
      final rejectedCount =
          await _syncService!.validateSyncedEventsWithCalendar();

      if (rejectedCount > 0) {
        emit(CalendarSyncValidationComplete(
          rejectedCount: rejectedCount,
          message:
              'נמצאו $rejectedCount מגבלות שאירועי היומן שלהן נמחקו וסטטוסן עודכן ל"דחוי"',
        ));
      } else {
        emit(const CalendarSyncValidationComplete(
          rejectedCount: 0,
          message: 'כל אירועי היומן מסונכרנים כראוי',
        ));
      }
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Failed to validate synced events - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      emit(CalendarSyncFailure(
        constraintId: 'validation',
        errorMessage: 'נכשל בבדיקת אירועים מסונכרנים: ${e.toString()}',
      ));
    }
  }

  /// Perform bidirectional sync between app and Google Calendar
  Future<void> _onPerformBidirectionalSync(
    PerformBidirectionalSync event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized',
        name: 'CalendarSyncBloc',
      );
      emit(const CalendarSyncFailure(
        constraintId: 'bidirectional',
        errorMessage: 'שירות הסנכרון אינו מאותחל',
        isRetryable: false,
      ));
      return;
    }

    emit(const CalendarSyncInProgress(
      constraintId: 'bidirectional',
      message: 'מבצע סנכרון דו-כיווני עם יומן גוגל...',
    ));

    try {
      final summary = await _runBidirectionalSyncWorkflow();

      emit(CalendarSyncBidirectionalComplete(
        rejectedCount: summary.rejectedCount,
        retriedCount: summary.retriedCount,
        successCount: summary.successCount,
        message: summary.message,
      ));
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Bidirectional sync failed - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      emit(CalendarSyncFailure(
        constraintId: 'bidirectional',
        errorMessage: 'סנכרון דו-כיווני נכשל: ${e.toString()}',
        isRetryable: true,
      ));
    }
  }

  Future<void> _onSyncEventsAndConstraints(
    SyncEventsAndConstraints event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Combined admin sync requested before initialization',
        name: 'CalendarSyncBloc',
      );
      emit(const CalendarSyncFailure(
        constraintId: 'events_and_constraints',
        errorMessage: 'שירות הסנכרון אינו מאותחל',
        isRetryable: false,
      ));
      return;
    }

    emit(const CalendarSyncInProgress(
      constraintId: 'events_and_constraints',
      message: 'מסנכרן אירועים ומגבלות עם יומן גוגל...',
    ));

    try {
      final result = await _calendarService.syncEventsAndConstraints(
        onEventProgress: (done, total) {
          // Keep the same constraintId so the dialog's in-progress spinner
          // stays up while the chunked sync advances event by event.
          if (total > 0 && !emit.isDone) {
            emit(CalendarSyncInProgress(
              constraintId: 'events_and_constraints',
              message: 'מסנכרן אירועים עם יומן גוגל... $done/$total',
            ));
          }
        },
      );

      emit(CalendarEventsAndConstraintsSyncComplete(
        scannedEventCount: result.scannedEventCount,
        syncedEventCount: result.syncedEventCount,
        skippedEventCount: result.skippedEventCount,
        failedEventCount: result.failedEventCount,
        failedEventIds: result.failedEventIds,
        rejectedConstraintCount: result.rejectedConstraintCount,
        retriedConstraintCount: result.retriedConstraintCount,
        successfulConstraintRetryCount: result.successfulConstraintRetryCount,
        message: result.message,
      ));
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Combined admin sync failed - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      emit(CalendarSyncFailure(
        constraintId: 'events_and_constraints',
        errorMessage: 'סנכרון אירועים ומגבלות נכשל: ${e.toString()}',
        isRetryable: true,
      ));
    }
  }

  /// Sync an app event to the calendar
  Future<void> _onSyncAppEvent(
    SyncAppEventToCalendar event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized, skipping app event sync',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    emit(CalendarSyncInProgress(
      constraintId: event.eventId,
      message: 'מסנכרן אירוע ליומן גוגל...',
    ));

    try {
      final result = await _syncService!.syncAppEventToCalendar(
        eventId: event.eventId,
        eventName: event.eventName,
        startDate: event.startDate,
        endDate: event.endDate,
        assemblyTime: event.assemblyTime,
        startTime: event.startTime,
        actualShowStartTime: event.actualShowStartTime,
        endTime: event.endTime,
        location: event.location,
      );

      if (result.success) {
        emit(CalendarSyncSuccess(
          constraintId: event.eventId,
          calendarEventId: result.calendarEventId,
          message: 'האירוע סונכרן ליומן גוגל בהצלחה',
        ));
      } else {
        emit(CalendarSyncFailure(
          constraintId: event.eventId,
          errorMessage: result.errorMessage ?? 'שגיאה לא ידועה',
          isRetryable: result.isRetryable,
        ));
      }
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: App event sync failed - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      emit(CalendarSyncFailure(
        constraintId: event.eventId,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Remove an app event from the calendar
  Future<void> _onRemoveAppEvent(
    RemoveAppEventFromCalendar event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized, skipping app event removal',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    emit(CalendarSyncInProgress(
      constraintId: event.eventId,
      message: 'מסיר אירוע מיומן גוגל...',
    ));

    try {
      final result =
          await _syncService!.removeAppEventFromCalendar(event.eventId);

      if (result.success) {
        emit(CalendarSyncRemovalSuccess(
          constraintId: event.eventId,
          message: 'האירוע הוסר מיומן גוגל בהצלחה',
        ));
      } else {
        emit(CalendarSyncFailure(
          constraintId: event.eventId,
          errorMessage: result.errorMessage ?? 'שגיאה בהסרה מהיומן',
          isRetryable: result.isRetryable,
        ));
      }
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: App event removal failed - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      emit(CalendarSyncFailure(
        constraintId: event.eventId,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Add attendee to app event
  Future<void> _onAddAttendeeToAppEvent(
    AddAttendeeToAppEvent event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized, skipping attendee add',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    try {
      await _syncService!.addAttendeeToAppEvent(
        eventId: event.eventId,
        email: event.email,
      );
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Failed to add attendee - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      // Best-effort: don't rethrow
    }
  }

  /// Remove attendee from app event
  Future<void> _onRemoveAttendeeFromAppEvent(
    RemoveAttendeeFromAppEvent event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized, skipping attendee remove',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    try {
      await _syncService!.removeAttendeeFromAppEvent(
        eventId: event.eventId,
        email: event.email,
      );
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Failed to remove attendee - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      // Best-effort: don't rethrow
    }
  }

  /// Sync all attendees for app event
  Future<void> _onSyncAttendeesForAppEvent(
    SyncAttendeesForAppEvent event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized, skipping attendee sync',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    try {
      await _syncService!.syncAttendeesForAppEvent(event.eventId);
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Failed to sync attendees - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      // Best-effort: don't rethrow
    }
  }

  /// Handle team member email changed
  Future<void> _onTeamMemberEmailChanged(
    OnTeamMemberEmailChanged event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized, skipping email change',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    try {
      await _syncService!.onTeamMemberEmailChanged(
        teamMemberId: event.teamMemberId,
        oldEmail: event.oldEmail,
        newEmail: event.newEmail,
      );
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Failed to handle email change - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      // Best-effort: don't rethrow
    }
  }

  /// TEMP: Manually backfill attendee emails for existing constraint events.
  Future<void> _onBackfillConstraintEventAttendees(
    BackfillConstraintEventAttendees event,
    Emitter<CalendarSyncState> emit,
  ) async {
    if (_syncService == null) {
      developer.log(
        'CalendarSyncBloc: Sync service not initialized, skipping backfill',
        name: 'CalendarSyncBloc',
      );
      return;
    }

    emit(const CalendarSyncInProgress(
      constraintId: 'constraint_attendee_backfill',
      message: 'מבצע עדכון זמני של משתתפים במגבלות מסונכרנות...',
    ));

    try {
      final result = await _syncService!.backfillConstraintEventAttendees();
      emit(ConstraintAttendeeBackfillComplete(
        scannedCount: result.scannedCount,
        updatedCount: result.updatedCount,
        skippedCount: result.skippedCount,
        failedCount: result.failedCount,
        message:
            'הושלם עדכון משתתפים: נסרקו ${result.scannedCount}, עודכנו ${result.updatedCount}, דולגו ${result.skippedCount}, נכשלו ${result.failedCount}',
      ));
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Backfill failed - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
      emit(CalendarSyncFailure(
        constraintId: 'constraint_attendee_backfill',
        errorMessage: 'עדכון המשתתפים הזמני נכשל: $e',
      ));
    }
  }

  /// Check calendar auth once when admin enters the app.
  Future<void> _onCheckCalendarAuthOnAdminAppLoad(
    CheckCalendarAuthOnAdminAppLoad event,
    Emitter<CalendarSyncState> emit,
  ) async {
    // If calendar sync is not configured/initialized, skip the check silently.
    if (_syncService == null) {
      _pendingAdminStartupAuthCheck = true;
      return;
    }

    try {
      await _calendarService.ensureAuthenticatedForBatchOperation();
    } catch (e) {
      final rawError = e.toString();
      final isAuthError = rawError.contains(
        'Not authenticated. User must sign in with Google.',
      );

      emit(CalendarSyncFailure(
        constraintId: 'calendar_startup_auth_check',
        errorMessage: isAuthError
            ? 'נדרש חיבור מחדש לגוגל קלנדר. יש להיכנס להגדרות יומן גוגל במסך הבית ולהתחבר מחדש.'
            : 'בדיקת חיבור לגוגל קלנדר נכשלה: $rawError',
        isRetryable: !isAuthError,
      ));
    }
  }

  Future<_BidirectionalSyncSummary> _runBidirectionalSyncWorkflow() async {
    if (_syncService == null) {
      throw StateError('Calendar sync service is not initialized');
    }

    final rejectedCount =
        await _syncService!.validateSyncedEventsWithCalendar();
    final failedSyncs = await _syncService!.getFailedSyncs();
    int retriedCount = 0;
    int successCount = 0;

    for (final syncState in failedSyncs) {
      try {
        final constraintId = syncState['constraintId'] as String;
        final teamMemberId = syncState['teamMemberId'] as String;
        final teamMembers = await _database.getTeamMembers();
        final teamMember = teamMembers.cast<TeamMember?>().firstWhere(
              (member) => member?.id == teamMemberId,
              orElse: () => null,
            );

        if (teamMember == null) {
          continue;
        }

        final constraint = teamMember.constraints.firstWhere(
          (item) => item.id == constraintId,
          orElse: () => throw Exception('Constraint not found'),
        );

        final retryCount = syncState['retryCount'] as int? ?? 0;
        final result = await _syncService!.retrySyncWithBackoff(
          constraintId: constraintId,
          teamMember: teamMember,
          constraint: constraint,
          currentRetryCount: retryCount,
        );

        retriedCount++;
        if (result.success) {
          successCount++;
        }
      } catch (_) {
        // Ignore individual constraint sync errors during batch sync.
      }
    }

    var message = 'הסנכרון הדו-כיווני הושלם. ';
    if (rejectedCount > 0) {
      message += '$rejectedCount מגבלות דחויות. ';
    }
    if (retriedCount > 0) {
      message += '$successCount מתוך $retriedCount סנכרונים כושלים תוקנו. ';
    }
    if (rejectedCount == 0 && retriedCount == 0) {
      message += 'כל הנתונים מסונכרנים.';
    }

    return _BidirectionalSyncSummary(
      rejectedCount: rejectedCount,
      retriedCount: retriedCount,
      successCount: successCount,
      message: message,
    );
  }

  @override
  Future<void> close() {
    _syncService?.dispose();
    return super.close();
  }
}

class _BidirectionalSyncSummary {
  final int rejectedCount;
  final int retriedCount;
  final int successCount;
  final String message;

  const _BidirectionalSyncSummary({
    required this.rejectedCount,
    required this.retriedCount,
    required this.successCount,
    required this.message,
  });
}
