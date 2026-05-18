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

/// TEMP: Result summary for manual attendee backfill of constraint events.
class ConstraintAttendeeBackfillResult {
  final int scannedCount;
  final int updatedCount;
  final int skippedCount;
  final int failedCount;

  const ConstraintAttendeeBackfillResult({
    required this.scannedCount,
    required this.updatedCount,
    required this.skippedCount,
    required this.failedCount,
  });
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
          throw StateError(
              'Update action requested but no calendar event ID found');
        }

        await _calendarService.updateConstraintEvent(
          calendarEventId: calendarEventId,
          constraintId: constraintId,
          teamMember: teamMember,
          constraint: constraint,
        );

        return SyncResult.success(calendarEventId);
      } else if (action == 'create') {
        // Create new calendar event
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
    try {
      // Get existing sync state
      final existingState = await _database.getCalendarSyncState(constraintId);
      if (existingState == null) {
        return const SyncResult.success(null);
      }

      final calendarEventId = existingState['calendarEventId'] as String?;
      final teamMemberId = existingState['teamMemberId'] as String?;
      if (calendarEventId != null && calendarEventId.isNotEmpty) {
        // Delete from Google Calendar
        await _calendarService.deleteConstraintEvent(
          calendarEventId,
          teamMemberId: teamMemberId,
        );
      }

      // Remove sync state from database
      await _database.removeCalendarSyncState(constraintId);

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
    try {
      // Get all synced constraints
      final syncedStates = await _database.getSyncedConstraintsForAllMembers();
      int rejectedCount = 0;

      for (final syncState in syncedStates) {
        final constraintId = syncState['constraintId'] as String;
        final calendarEventId = syncState['calendarEventId'] as String?;

        if (calendarEventId == null || calendarEventId.isEmpty) {
          continue;
        }

        // Check if the event still exists in Google Calendar
        final eventExists = await _calendarService.eventExists(calendarEventId);

        if (!eventExists) {
          // Update the constraint status to rejected and mark as auto-rejected from calendar
          await _database.updateConstraintStatus(
            constraintId,
            null, // constraintIndex is null when using constraintId
            ConstraintStatus.rejected,
            wasAutoRejectedFromCalendar: true,
          );

          // Remove the sync state
          await _database.removeCalendarSyncState(constraintId);

          rejectedCount++;
        }
      }

      return rejectedCount;
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to validate synced events - $e',
        name: 'CalendarSync',
        error: e,
      );
      return 0;
    }
  }

  /// Sync an app event to the calendar
  /// Creates or updates both assembly and main calendar events
  /// Deletes calendar events if their required time fields are missing
  /// Uses startTime as fallback if actualShowStartTime is null
  /// Uses atomic transaction to prevent race conditions
  Future<SyncResult> syncAppEventToCalendar({
    required String eventId,
    required String eventName,
    required DateTime startDate,
    required DateTime endDate,
    required String assemblyTime,
    required String startTime,
    required String actualShowStartTime,
    required String endTime,
    String? location,
  }) async {
    // Cancel any pending debounced sync for this event
    _cancelDebounce(eventId);

    try {
      // Use startTime as fallback if actualShowStartTime is empty
      final separatorTime =
          actualShowStartTime.isNotEmpty ? actualShowStartTime : startTime;

      // Determine which events should exist based on time fields.
      // If either assemblyTime or endTime is missing, sync as a single all-day main event.
      final shouldUseAllDay = assemblyTime.isEmpty || endTime.isEmpty;
      final shouldHaveAssembly = !shouldUseAllDay &&
          assemblyTime.isNotEmpty &&
          separatorTime.isNotEmpty;
      final shouldHaveMain = shouldUseAllDay ||
          (endTime.isNotEmpty &&
              (separatorTime.isNotEmpty || assemblyTime.isNotEmpty));

      // Check if already synced
      final existingState = await _database.getEventCalendarSyncState(eventId);

      if (existingState != null) {
        // Get existing calendar event IDs
        final existingAssemblyId =
            existingState['assemblyCalendarEventId'] as String? ?? '';
        final existingMainId =
            existingState['mainCalendarEventId'] as String? ?? '';

        // Handle assembly event: delete if it should not exist but does
        String newAssemblyId = existingAssemblyId;
        if (!shouldHaveAssembly && existingAssemblyId.isNotEmpty) {
          await _calendarService.deleteAppEventCalendarEvents(
            assemblyCalendarEventId: existingAssemblyId,
          );
          newAssemblyId = '';
        }

        // Handle main event: delete if it should not exist but does
        String newMainId = existingMainId;
        if (!shouldHaveMain && existingMainId.isNotEmpty) {
          await _calendarService.deleteAppEventCalendarEvents(
            mainCalendarEventId: existingMainId,
          );
          newMainId = '';
        }

        // If both events should be deleted, remove sync state entirely
        if (!shouldHaveAssembly && !shouldHaveMain) {
          await _database.removeEventCalendarSyncState(eventId);
          return const SyncResult.success(null);
        }

        // Update or create events that should exist
        if (shouldHaveAssembly || shouldHaveMain) {
          final recreatedIds =
              await _calendarService.updateAppEventCalendarEvents(
            assemblyCalendarEventId: newAssemblyId,
            mainCalendarEventId: newMainId,
            eventId: eventId,
            eventName: eventName,
            startDate: startDate,
            endDate: endDate,
            assemblyTime: assemblyTime,
            separatorTime: separatorTime,
            endTime: endTime,
            location: location,
          );

          // If events were recreated (deleted from calendar), use new IDs
          if (recreatedIds != null) {
            newAssemblyId = recreatedIds['assembly'] ?? newAssemblyId;
            newMainId = recreatedIds['main'] ?? newMainId;
          }

          // Update sync state with current IDs
          await _database.saveEventCalendarSyncState(
            eventId: eventId,
            assemblyCalendarEventId: newAssemblyId,
            mainCalendarEventId: newMainId,
            status: CalendarSyncStatus.synced,
          );

          // Ensure attendees are preserved when events are updated/recreated
          // (including transitions between timed and all-day representations).
          await syncAttendeesForAppEvent(eventId);

          return SyncResult.success('$newAssemblyId,$newMainId');
        }

        return SyncResult.success('$newAssemblyId,$newMainId');
      } else {
        // No existing sync state - create new calendar events if needed
        if (!shouldHaveAssembly && !shouldHaveMain) {
          // No events needed, don't create sync state
          return const SyncResult.success(null);
        }

        final calendarEventIds =
            await _calendarService.createAppEventCalendarEvents(
          eventId: eventId,
          eventName: eventName,
          startDate: startDate,
          endDate: endDate,
          assemblyTime: assemblyTime,
          separatorTime: separatorTime,
          endTime: endTime,
          location: location,
        );

        // Save sync state
        await _database.saveEventCalendarSyncState(
          eventId: eventId,
          assemblyCalendarEventId: calendarEventIds['assembly'] ?? '',
          mainCalendarEventId: calendarEventIds['main'] ?? '',
          status: CalendarSyncStatus.synced,
        );

        // Sync attendees from existing assignments
        await syncAttendeesForAppEvent(eventId);

        return SyncResult.success(
            '${calendarEventIds['assembly']},${calendarEventIds['main']}');
      }
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to sync app event $eventId - $e',
        name: 'CalendarSync',
        error: e,
      );

      // Save failed state
      try {
        await _database.saveEventCalendarSyncState(
          eventId: eventId,
          assemblyCalendarEventId: '',
          mainCalendarEventId: '',
          status: CalendarSyncStatus.failed,
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

  /// Remove an app event from the calendar
  /// Deletes both assembly and main calendar events
  Future<SyncResult> removeAppEventFromCalendar(String eventId) async {
    try {
      // Get existing sync state
      final existingState = await _database.getEventCalendarSyncState(eventId);
      if (existingState == null) {
        return const SyncResult.success(null);
      }

      final assemblyId = existingState['assemblyCalendarEventId'] as String?;
      final mainId = existingState['mainCalendarEventId'] as String?;

      // Delete from Google Calendar
      await _calendarService.deleteAppEventCalendarEvents(
        assemblyCalendarEventId: assemblyId,
        mainCalendarEventId: mainId,
      );

      // Remove sync state from database
      await _database.removeEventCalendarSyncState(eventId);

      return const SyncResult.success(null);
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to remove app event $eventId - $e',
        name: 'CalendarSync',
        error: e,
      );

      return SyncResult.failure(e.toString());
    }
  }

  /// Add attendee to app event calendar event
  /// Used when assignment is created for team member with email
  Future<void> addAttendeeToAppEvent({
    required String eventId,
    required String email,
  }) async {
    try {
      // Get event sync state
      final syncState = await _database.getEventCalendarSyncState(eventId);
      if (syncState == null) {
        return;
      }

      final assemblyId = syncState['assemblyCalendarEventId'] as String?;
      final mainId = syncState['mainCalendarEventId'] as String?;

      // Add attendee to both events if they exist
      if (assemblyId != null && assemblyId.isNotEmpty) {
        try {
          await _calendarService.addAttendeeToEvent(assemblyId, email);
        } catch (e) {
          developer.log(
            'CalendarSyncService: Failed to add attendee to assembly event $assemblyId - $e',
            name: 'CalendarSync',
            error: e,
          );
        }
      }

      if (mainId != null && mainId.isNotEmpty) {
        try {
          await _calendarService.addAttendeeToEvent(mainId, email);
        } catch (e) {
          developer.log(
            'CalendarSyncService: Failed to add attendee to main event $mainId - $e',
            name: 'CalendarSync',
            error: e,
          );
        }
      }
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to add attendee to app event $eventId - $e',
        name: 'CalendarSync',
        error: e,
      );
    }
  }

  /// Remove attendee from app event calendar event
  /// Used when assignment is deleted
  Future<void> removeAttendeeFromAppEvent({
    required String eventId,
    required String email,
  }) async {
    try {
      // Get event sync state
      final syncState = await _database.getEventCalendarSyncState(eventId);
      if (syncState == null) {
        return;
      }

      final assemblyId = syncState['assemblyCalendarEventId'] as String?;
      final mainId = syncState['mainCalendarEventId'] as String?;

      // Remove attendee from both events if they exist
      if (assemblyId != null && assemblyId.isNotEmpty) {
        try {
          await _calendarService.removeAttendeeFromEvent(assemblyId, email);
        } catch (e) {
          developer.log(
            'CalendarSyncService: Failed to remove attendee from assembly event $assemblyId - $e',
            name: 'CalendarSync',
            error: e,
          );
        }
      }

      if (mainId != null && mainId.isNotEmpty) {
        try {
          await _calendarService.removeAttendeeFromEvent(mainId, email);
        } catch (e) {
          developer.log(
            'CalendarSyncService: Failed to remove attendee from main event $mainId - $e',
            name: 'CalendarSync',
            error: e,
          );
        }
      }
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to remove attendee from app event $eventId - $e',
        name: 'CalendarSync',
        error: e,
      );
    }
  }

  /// A member is eligible for the "invite all permanent staff" calendar
  /// behavior when they are a permanent, active, non-archived member with a
  /// non-empty email address.
  bool _isEligiblePermanentMember(TeamMember member) {
    final email = member.email?.trim() ?? '';
    return member.isPermanent &&
        member.isActive &&
        !member.isArchived &&
        email.isNotEmpty;
  }

  /// Sync all attendees for app event
  /// Fetches all assignments for event and adds all team member emails as attendees.
  /// Special case: when the event opted into "invite all permanent staff" and it
  /// is permanent-only and currently has zero assignments, all eligible permanent
  /// members are invited instead.
  Future<void> syncAttendeesForAppEvent(String eventId) async {
    try {
      // Get event sync state
      final syncState = await _database.getEventCalendarSyncState(eventId);
      if (syncState == null) {
        return;
      }

      final assemblyId = syncState['assemblyCalendarEventId'] as String?;
      final mainId = syncState['mainCalendarEventId'] as String?;

      // Get all assignments for this event
      final assignments = await _database.getAssignmentsByEvent(eventId);

      // Collect all unique attendee emails.
      final emails = <String>{};

      final event = await _database.getEventById(eventId);
      final useAllPermanent = assignments.isEmpty &&
          event != null &&
          event.inviteAllPermanentWhenUnassigned &&
          !event.relevantForExtendedTeam;

      if (useAllPermanent) {
        // No assignments yet and the event opted in: invite all eligible
        // permanent members.
        final members = await _database.getTeamMembers();
        for (final member in members) {
          if (_isEligiblePermanentMember(member)) {
            emails.add(member.email!.trim());
          }
        }
      } else {
        // Default behavior: attendees are exactly the assignees.
        for (final assignment in assignments) {
          final teamMember =
              await _database.getTeamMemberById(assignment.teamMemberId);
          if (teamMember != null &&
              teamMember.email != null &&
              teamMember.email!.isNotEmpty) {
            emails.add(teamMember.email!);
          }
        }
      }

      // Update attendees for both events if they exist
      if (assemblyId != null && assemblyId.isNotEmpty) {
        try {
          await _calendarService.updateEventAttendees(
              assemblyId, emails.toList());
        } catch (e) {
          developer.log(
            'CalendarSyncService: Failed to sync attendees for assembly event $assemblyId - $e',
            name: 'CalendarSync',
            error: e,
          );
        }
      }

      if (mainId != null && mainId.isNotEmpty) {
        try {
          await _calendarService.updateEventAttendees(mainId, emails.toList());
        } catch (e) {
          developer.log(
            'CalendarSyncService: Failed to sync attendees for main event $mainId - $e',
            name: 'CalendarSync',
            error: e,
          );
        }
      }
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to sync attendees for app event $eventId - $e',
        name: 'CalendarSync',
        error: e,
      );
    }
  }

  /// Handle team member email change
  /// Updates attendee email in all future events where this member is assigned
  Future<void> onTeamMemberEmailChanged({
    required String teamMemberId,
    required String oldEmail,
    required String newEmail,
  }) async {
    try {
      final normalizedOldEmail = oldEmail.trim();
      final normalizedNewEmail = newEmail.trim();

      if (normalizedOldEmail == normalizedNewEmail) {
        return;
      }

      // Nothing to sync when both are empty.
      if (normalizedOldEmail.isEmpty && normalizedNewEmail.isEmpty) {
        return;
      }

      // Get all assignments for this team member
      final assignments = await _database.getAssignmentsByPerson(teamMemberId);

      // Get event IDs for all assignments
      final eventIds = assignments.map((a) => a.eventId).toSet();

      // For each event, update the attendee
      for (final eventId in eventIds) {
        try {
          if (normalizedOldEmail.isNotEmpty) {
            // Remove old email when replacing or deleting an address.
            await removeAttendeeFromAppEvent(
                eventId: eventId, email: normalizedOldEmail);
          }
          if (normalizedNewEmail.isNotEmpty) {
            await addAttendeeToAppEvent(
                eventId: eventId, email: normalizedNewEmail);
          }
        } catch (e) {
          developer.log(
            'CalendarSyncService: Failed to update attendee for event $eventId - $e',
            name: 'CalendarSync',
            error: e,
          );
        }
      }
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to handle email change for team member $teamMemberId - $e',
        name: 'CalendarSync',
        error: e,
      );
    }
  }

  /// TEMP: One-time attendee backfill for existing synced constraint events.
  /// Best-effort operation; continues after per-item failures.
  Future<ConstraintAttendeeBackfillResult>
      backfillConstraintEventAttendees() async {
    int scannedCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    int failedCount = 0;

    try {
      final syncedStates = await _database.getSyncedConstraintsForAllMembers();
      scannedCount = syncedStates.length;

      for (final syncState in syncedStates) {
        final calendarEventId = (syncState['calendarEventId'] as String?) ?? '';
        final teamMemberId = (syncState['teamMemberId'] as String?) ?? '';

        if (calendarEventId.isEmpty || teamMemberId.isEmpty) {
          skippedCount++;
          continue;
        }

        try {
          final teamMember = await _database.getTeamMemberById(teamMemberId);
          final email = (teamMember?.email ?? '').trim();

          if (email.isEmpty) {
            skippedCount++;
            continue;
          }

          await _calendarService.addAttendeeToEvent(calendarEventId, email);
          updatedCount++;
        } catch (e) {
          failedCount++;
          developer.log(
            'CalendarSyncService: Failed attendee backfill for calendar event $calendarEventId - $e',
            name: 'CalendarSync',
            error: e,
          );
        }
      }
    } catch (e) {
      developer.log(
        'CalendarSyncService: Failed to run constraint attendee backfill - $e',
        name: 'CalendarSync',
        error: e,
      );
      failedCount++;
    }

    return ConstraintAttendeeBackfillResult(
      scannedCount: scannedCount,
      updatedCount: updatedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
    );
  }

  /// Clean up all debounce timers
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }
}
