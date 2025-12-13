import 'dart:async';
import 'dart:developer' as developer;

import '../../data/data_sources/database_interface.dart';
import '../../domain/entities/team_member.dart';
import '../constants/calendar_constants.dart';
import '../constants/constraint_status.dart';
import 'google_calendar_service.dart';

/// Result of a sync operation
class SyncResult {
  final bool success;
  final String? calendarEventId;
  final String? errorMessage;
  final bool isRetryable;

  const SyncResult.success(this.calendarEventId)
      : success = true,
        errorMessage = null,
        isRetryable = false;

  const SyncResult.failure(this.errorMessage, {this.isRetryable = true})
      : success = false,
        calendarEventId = null;

  @override
  String toString() => success
      ? 'SyncResult.success($calendarEventId)'
      : 'SyncResult.failure($errorMessage, retryable: $isRetryable)';
}

/// Service for orchestrating calendar sync operations
/// Handles sync state management, retry logic, and error handling
class CalendarSyncService {
  final DatabaseInterface _database;
  final GoogleCalendarService _calendarService;

  // Debouncing for rapid sync requests
  final Map<String, Timer> _debounceTimers = {};

  CalendarSyncService({
    required DatabaseInterface database,
    required GoogleCalendarService calendarService,
  })  : _database = database,
        _calendarService = calendarService;

  /// Sync a constraint to the calendar when it's approved
  /// Uses atomic transaction to prevent race conditions when multiple users sync simultaneously
  Future<SyncResult> syncConstraintToCalendar({
    required String constraintId,
    required TeamMember teamMember,
    required DateConstraint constraint,
  }) async {
    // Cancel any pending debounced sync for this constraint
    _cancelDebounce(constraintId);

    developer.log(
      'CalendarSyncService: Starting ATOMIC sync for constraint $constraintId',
      name: 'CalendarSync',
    );

    try {
      // Atomically check and set sync state to prevent race conditions
      final syncAction = await _database.atomicCheckAndSetSyncState(
        constraintId,
        teamMember.id,
      );

      if (syncAction == null) {
        developer.log(
          'CalendarSyncService: Failed to acquire sync lock for constraint $constraintId',
          name: 'CalendarSync',
        );
        return SyncResult.failure('Failed to acquire sync lock');
      }

      final action = syncAction['action'] as String;
      final calendarEventId = syncAction['calendarEventId'] as String?;

      if (action == 'update') {
        // Already synced - update existing event
        if (calendarEventId == null || calendarEventId.isEmpty) {
          throw StateError('Update action requested but no calendar event ID found');
        }

        developer.log(
          'CalendarSyncService: Constraint $constraintId already synced, updating existing event $calendarEventId',
          name: 'CalendarSync',
        );

        await _calendarService.updateConstraintEvent(
          calendarEventId: calendarEventId,
          constraintId: constraintId,
          teamMember: teamMember,
          constraint: constraint,
        );

        return SyncResult.success(calendarEventId);
      } else if (action == 'create') {
        // Create new calendar event
        developer.log(
          'CalendarSyncService: Creating new calendar event for constraint $constraintId',
          name: 'CalendarSync',
        );

        final newCalendarEventId = await _calendarService.createConstraintEvent(
          constraintId: constraintId,
          teamMember: teamMember,
          constraint: constraint,
        );

        // Update sync state with the actual calendar event ID
        await _database.saveCalendarSyncState(
          constraintId: constraintId,
          calendarEventId: newCalendarEventId,
          teamMemberId: teamMember.id,
          status: CalendarSyncStatus.synced,
        );

        developer.log(
          'CalendarSyncService: Successfully synced constraint $constraintId -> new event $newCalendarEventId',
          name: 'CalendarSync',
        );

        return SyncResult.success(newCalendarEventId);
      } else {
        throw StateError('Unknown sync action: $action');
      }
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to sync constraint $constraintId - $e',
        name: 'CalendarSync',
        error: e,
      );

      // Save failed state for retry
      try {
        await _database.saveCalendarSyncState(
          constraintId: constraintId,
          calendarEventId: '',
          teamMemberId: teamMember.id,
          status: CalendarSyncStatus.failed,
        );
        await _database.updateCalendarSyncStatus(
          constraintId,
          CalendarSyncStatus.failed,
          errorMessage: e.toString(),
          retryCount: 0,
        );
      } catch (dbError) {
        developer.log(
          'CalendarSyncService: Failed to save failed sync state - $dbError',
          name: 'CalendarSync',
          error: dbError,
        );
      }

      return SyncResult.failure(e.toString());
    }
  }

  /// Remove a constraint from the calendar
  Future<SyncResult> removeConstraintFromCalendar(String constraintId) async {
    developer.log(
      'CalendarSyncService: Removing constraint $constraintId from calendar',
      name: 'CalendarSync',
    );

    try {
      // Get existing sync state
      final existingState = await _database.getCalendarSyncState(constraintId);
      if (existingState == null) {
        developer.log(
          'CalendarSyncService: No sync state found for constraint $constraintId',
          name: 'CalendarSync',
        );
        return const SyncResult.success(null);
      }

      final calendarEventId = existingState['calendarEventId'] as String?;
      if (calendarEventId != null && calendarEventId.isNotEmpty) {
        // Delete from Google Calendar
        await _calendarService.deleteConstraintEvent(calendarEventId);
      }

      // Remove sync state from database
      await _database.removeCalendarSyncState(constraintId);

      developer.log(
        'CalendarSyncService: Successfully removed constraint $constraintId from calendar',
        name: 'CalendarSync',
      );

      return const SyncResult.success(null);
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to remove constraint $constraintId - $e',
        name: 'CalendarSync',
        error: e,
      );

      return SyncResult.failure(e.toString());
    }
  }

  /// Retry a failed sync with exponential backoff
  Future<SyncResult> retrySyncWithBackoff({
    required String constraintId,
    required TeamMember teamMember,
    required DateConstraint constraint,
    required int currentRetryCount,
  }) async {
    if (currentRetryCount >= CalendarSyncConfig.maxRetryAttempts) {
      developer.log(
        'CalendarSyncService: Max retries reached for constraint $constraintId',
        name: 'CalendarSync',
      );
      return const SyncResult.failure(
        'Maximum retry attempts exceeded',
        isRetryable: false,
      );
    }

    // Calculate delay with exponential backoff
    final delayMs = (CalendarSyncConfig.initialRetryDelayMs *
            (CalendarSyncConfig.backoffMultiplier * currentRetryCount))
        .round()
        .clamp(
          CalendarSyncConfig.initialRetryDelayMs,
          CalendarSyncConfig.maxRetryDelayMs,
        );

    developer.log(
      'CalendarSyncService: Retrying sync for $constraintId in ${delayMs}ms (attempt ${currentRetryCount + 1})',
      name: 'CalendarSync',
    );

    await Future.delayed(Duration(milliseconds: delayMs));

    try {
      final result = await syncConstraintToCalendar(
        constraintId: constraintId,
        teamMember: teamMember,
        constraint: constraint,
      );

      if (!result.success) {
        // Update retry count
        await _database.updateCalendarSyncStatus(
          constraintId,
          CalendarSyncStatus.failed,
          errorMessage: result.errorMessage,
          retryCount: currentRetryCount + 1,
        );
      }

      return result;
    } catch (e) {
      // Update retry count on exception
      await _database.updateCalendarSyncStatus(
        constraintId,
        CalendarSyncStatus.failed,
        errorMessage: e.toString(),
        retryCount: currentRetryCount + 1,
      );

      return SyncResult.failure(e.toString());
    }
  }

  /// Get all failed syncs for retry processing
  Future<List<Map<String, dynamic>>> getFailedSyncs() async {
    return await _database.getFailedSyncStates();
  }

  /// Get sync state for a constraint
  Future<Map<String, dynamic>?> getSyncState(String constraintId) async {
    return await _database.getCalendarSyncState(constraintId);
  }

  /// Debounce sync operation for rapid successive changes
  void debouncedSync({
    required String constraintId,
    required TeamMember teamMember,
    required DateConstraint constraint,
    required void Function(SyncResult) onComplete,
  }) {
    _cancelDebounce(constraintId);

    _debounceTimers[constraintId] = Timer(
      Duration(milliseconds: CalendarSyncConfig.debounceDelayMs),
      () async {
        final result = await syncConstraintToCalendar(
          constraintId: constraintId,
          teamMember: teamMember,
          constraint: constraint,
        );
        onComplete(result);
      },
    );
  }

  void _cancelDebounce(String constraintId) {
    _debounceTimers[constraintId]?.cancel();
    _debounceTimers.remove(constraintId);
  }

  /// Check synced events in Google Calendar and update constraint status if events were deleted
  /// Returns the number of constraints that were rejected due to deleted calendar events
  Future<int> validateSyncedEventsWithCalendar() async {
    print('🗓️ [CalendarSyncService] Starting validation of synced events with Google Calendar');
    developer.log(
      'CalendarSyncService: Starting validation of synced events with Google Calendar',
      name: 'CalendarSync',
    );

    try {
      // Get all synced constraints
      final syncedStates = await _database.getSyncedConstraintsForAllMembers();
      print('🗓️ [CalendarSyncService] Found ${syncedStates.length} synced constraints to validate');
      int rejectedCount = 0;

      for (final syncState in syncedStates) {
        final constraintId = syncState['constraintId'] as String;
        final calendarEventId = syncState['calendarEventId'] as String?;

        if (calendarEventId == null || calendarEventId.isEmpty) {
          print('🗓️ [CalendarSyncService] Constraint $constraintId has empty calendar event ID, skipping');
          developer.log(
            'CalendarSyncService: Constraint $constraintId has empty calendar event ID, skipping validation',
            name: 'CalendarSync',
          );
          continue;
        }

        print('🗓️ [CalendarSyncService] Checking if event $calendarEventId still exists for constraint $constraintId');

        // Check if the event still exists in Google Calendar
        final eventExists = await _calendarService.eventExists(calendarEventId);
        print('🗓️ [CalendarSyncService] Event $calendarEventId exists: $eventExists');

        if (!eventExists) {
          print('🗓️ [CalendarSyncService] ❌ Event $calendarEventId not found in Google Calendar, rejecting constraint $constraintId');
          developer.log(
            'CalendarSyncService: Event $calendarEventId not found in Google Calendar, rejecting constraint $constraintId',
            name: 'CalendarSync',
          );

          // Get the existing constraint to preserve its note
          final teamMembers = await _database.getTeamMembers();
          String? existingNote = null;

          for (final teamMember in teamMembers) {
            final constraint = teamMember.constraints.cast<DateConstraint?>().firstWhere(
              (c) => c?.id == constraintId,
              orElse: () => null,
            );
            if (constraint != null) {
              existingNote = constraint.note;
              break;
            }
          }

          // Build the new note - preserve existing note and add the rejection reason if not already present
          String newNote;
          const rejectionMessage = '(מגבלה זו נדחתה באופן אוטומטי בגלל שאחד מהמנהלים מחק את המגבלה מגוגל קלנדר)';

          if (existingNote != null && existingNote.isNotEmpty) {
            // Check if the rejection message is already present at the end
            if (existingNote.trim().endsWith(rejectionMessage)) {
              newNote = existingNote; // Already has the rejection message
            } else {
              newNote = '$existingNote\n\n$rejectionMessage';
            }
          } else {
            newNote = rejectionMessage;
          }

          // Update the constraint status to rejected
          await _database.updateConstraintStatus(
            constraintId,
            null, // constraintIndex is null when using constraintId
            ConstraintStatus.rejected,
            note: newNote,
          );
          print('🗓️ [CalendarSyncService] ✅ Updated constraint $constraintId status to rejected');

          // Remove the sync state
          await _database.removeCalendarSyncState(constraintId);
          print('🗓️ [CalendarSyncService] ✅ Removed sync state for constraint $constraintId');

          rejectedCount++;
        } else {
          print('🗓️ [CalendarSyncService] ✅ Event $calendarEventId exists in Google Calendar');
        }
      }

      print('🗓️ [CalendarSyncService] Validation complete - rejected $rejectedCount constraints due to deleted calendar events');
      developer.log(
        'CalendarSyncService: Validation complete - rejected $rejectedCount constraints due to deleted calendar events',
        name: 'CalendarSync',
      );

      return rejectedCount;
    } catch (e) {
      print('🗓️ [CalendarSyncService] ❌ Failed to validate synced events: $e');
      developer.log(
        'CalendarSyncService: Failed to validate synced events - $e',
        name: 'CalendarSync',
        error: e,
      );
      return 0;
    }
  }

  /// Clean up all debounce timers
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }
}
