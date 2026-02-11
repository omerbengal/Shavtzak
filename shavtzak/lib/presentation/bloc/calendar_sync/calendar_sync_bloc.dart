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
    on<SyncAppEventToCalendar>(_onSyncAppEvent);
    on<RemoveAppEventFromCalendar>(_onRemoveAppEvent);
  }

  /// Initialize the calendar sync service
  Future<void> _onInitialize(
    InitializeCalendarSync event,
    Emitter<CalendarSyncState> emit,
  ) async {
    emit(const CalendarSyncInitializing());

    try {
      // Check if credentials are provided
      if (event.serviceAccountJson == null || event.calendarId == null) {
        developer.log(
          'CalendarSyncBloc: No credentials provided, sync disabled',
          name: 'CalendarSyncBloc',
        );
        emit(const CalendarSyncDisabled(
          reason: 'לא הוגדרו פרטי התחברות ליומן גוגל',
        ));
        return;
      }


      // Initialize Google Calendar service
      await _calendarService.initialize(
        serviceAccountJson: event.serviceAccountJson!,
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
    } catch (e) {
      developer.log(
        'CalendarSyncBloc: Initialization failed - $e',
        name: 'CalendarSyncBloc',
        error: e,
      );
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

    final approvedConstraints = event.teamMember.constraints
        .where((c) => c.isApproved())
        .toList();

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
        message: 'מסנכרן מגבלות ליומן גוגל... (${successCount + failureCount + 1}/${approvedConstraints.length})',
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
      final syncState = await _database.getCalendarSyncState(event.constraintId);

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
      final rejectedCount = await _syncService!.validateSyncedEventsWithCalendar();

      if (rejectedCount > 0) {
        emit(CalendarSyncValidationComplete(
          rejectedCount: rejectedCount,
          message: 'נמצאו $rejectedCount מגבלות שאירועי היומן שלהן נמחקו וסטטוסן עודכן ל"דחוי"',
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
      // Step 1: Validate synced events and update constraints if calendar events were deleted
      final rejectedCount = await _syncService!.validateSyncedEventsWithCalendar();

      // Step 2: Get all failed syncs and retry them
      final failedSyncs = await _syncService!.getFailedSyncs();
      int retriedCount = 0;
      int successCount = 0;

      for (final syncState in failedSyncs) {
        try {
          // Get team member and constraint details for retry
          final constraintId = syncState['constraintId'] as String;
          final teamMemberId = syncState['teamMemberId'] as String;

          // Get team member from database
          final teamMembers = await _database.getTeamMembers();
          final teamMember = teamMembers.cast<TeamMember?>().firstWhere(
            (m) => m?.id == teamMemberId,
            orElse: () => null,
          );

          if (teamMember == null) {
            continue;
          }

          // Find the constraint
          final constraint = teamMember.constraints.firstWhere(
            (c) => c.id == constraintId,
            orElse: () => throw Exception('Constraint not found'),
          );

          // Retry the sync
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
          } else {
          }
        } catch (e) {
          // Ignore individual constraint sync errors during batch sync
        }
      }


      // Step 3: Emit completion state
      String message = 'הסנכרון הדו-כיווני הושלם. ';
      if (rejectedCount > 0) {
        message += '$rejectedCount מגבלות דחויות. ';
      }
      if (retriedCount > 0) {
        message += '$successCount מתוך $retriedCount סנכרונים כושלים תוקנו. ';
      }
      if (rejectedCount == 0 && retriedCount == 0) {
        message += 'כל הנתונים מסונכרנים.';
      }

      emit(CalendarSyncBidirectionalComplete(
        rejectedCount: rejectedCount,
        retriedCount: retriedCount,
        successCount: successCount,
        message: message,
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
      final result = await _syncService!.removeAppEventFromCalendar(event.eventId);

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

  @override
  Future<void> close() {
    _syncService?.dispose();
    return super.close();
  }
}
