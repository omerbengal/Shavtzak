import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/assignment.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/utils/crud_action_result.dart';
import '../calendar_sync/calendar_sync_bloc.dart';
import '../calendar_sync/calendar_sync_event.dart';
import 'event_event.dart';
import 'event_state.dart';

/// BLoC for managing events
class EventBloc extends Bloc<EventEvent, EventState> {
  final EventRepository _repository;
  final AssignmentRepository _assignmentRepository;
  final CalendarSyncBloc? _calendarSyncBloc;

  // Stream subscriptions for manual control to prevent memory leaks
  StreamSubscription<List<Event>>? _eventsSubscription;
  StreamSubscription<List<Assignment>>? _assignmentsSubscription;

  // True once the combined streams have been subscribed. Repeat Loads then
  // re-emit from the cached values instead of tearing down + rebuilding both
  // live streams (which would re-read all events + assignments and flash
  // EventLoading). The live streams stay subscribed to preserve real-time.
  bool _isWatching = false;

  // Cache latest values for combining streams
  List<Event> _latestEvents = [];
  List<Assignment> _latestAssignments = [];
  bool _eventsLoaded = false;
  bool _assignmentsLoaded = false;
  bool _upcomingOnly = false;

  EventBloc(
    this._repository,
    this._assignmentRepository, {
    CalendarSyncBloc? calendarSyncBloc,
  })  : _calendarSyncBloc = calendarSyncBloc,
        super(const EventInitial()) {
    // Register event handlers
    on<LoadEvents>(_onLoadEvents);
    on<LoadUpcomingEvents>(_onLoadUpcomingEvents);
    on<SearchEvents>(_onSearchEvents);
    on<LoadEventById>(_onLoadEventById);
    on<CreateEvent>(_onCreateEvent);
    on<UpdateEvent>(_onUpdateEvent);
    on<DeleteEvent>(_onDeleteEvent);
    on<DuplicateEvent>(_onDuplicateEvent);
    on<ConfirmDuplicationWithExclusions>(_onConfirmDuplicationWithExclusions);
    on<RefreshEvents>(_onRefreshEvents);
    on<DeactivateEventRequested>(_onDeactivateEvent);
    on<ReactivateEventRequested>(_onReactivateEvent);
    on<_EventsDataUpdated>(_onEventsDataUpdated);
  }

  /// Load all events with real-time updates (including assignment counts)
  Future<void> _onLoadEvents(
    LoadEvents event,
    Emitter<EventState> emit,
  ) async {
    _upcomingOnly = false;
    await _ensureWatching(emit);
  }

  /// Subscribe to the combined streams exactly once. On subsequent calls
  /// (repeat Loads / filter switches) reflect the current cache through the
  /// current _upcomingOnly filter instantly — no re-subscribe, no loading flash.
  Future<void> _ensureWatching(Emitter<EventState> emit) async {
    if (_isWatching) {
      _emitCombinedIfReady();
      return;
    }
    emit(const EventLoading());
    _isWatching = true;
    try {
      // Start combined stream subscriptions (first watch only).
      await _startCombinedStreams();
    } catch (e) {
      _isWatching = false;
      emit(EventError('שגיאה בטעינת אירועים: $e'));
    }
  }

  /// Start combined stream subscriptions for events and assignments
  Future<void> _startCombinedStreams() async {
    // Cancel previous subscriptions before starting new ones to prevent memory leaks
    await _eventsSubscription?.cancel();
    await _assignmentsSubscription?.cancel();

    // Reset state
    _eventsLoaded = false;
    _assignmentsLoaded = false;
    _latestEvents = [];
    _latestAssignments = [];

    // Subscribe to events stream
    _eventsSubscription = _repository.watchEvents().listen(
      (events) {
        _latestEvents = events;
        _eventsLoaded = true;
        _emitCombinedIfReady();
      },
      onError: (error) {
        _latestEvents = [];
        _eventsLoaded = true;
        _emitCombinedIfReady();
      },
    );

    // Subscribe to assignments stream
    _assignmentsSubscription = _assignmentRepository.watchAssignments().listen(
      (assignments) {
        _latestAssignments = assignments;
        _assignmentsLoaded = true;
        _emitCombinedIfReady();
      },
      onError: (error) {
        _latestAssignments = [];
        _assignmentsLoaded = true;
        _emitCombinedIfReady();
      },
    );
  }

  /// Emit combined data when both streams have loaded
  void _emitCombinedIfReady() {
    if (!_eventsLoaded || !_assignmentsLoaded) return;

    // Calculate assignment counts per event
    final counts = <String, int>{};
    for (final assignment in _latestAssignments) {
      counts[assignment.eventId] = (counts[assignment.eventId] ?? 0) + 1;
    }

    // Calculate birthdays per event
    final birthdays = _calculateEventBirthdays();

    add(_EventsDataUpdated(
      events: _latestEvents,
      assignmentCounts: counts,
      eventBirthdays: birthdays,
      upcomingOnly: _upcomingOnly,
    ));
  }

  /// Calculate which team members have birthdays during each event
  Map<String, List<String>> _calculateEventBirthdays() {
    final result = <String, List<String>>{};

    for (final event in _latestEvents) {
      final birthdayNames = <String>[];

      // Find all assignments for this event
      final eventAssignments =
          _latestAssignments.where((a) => a.eventId == event.id);

      for (final assignment in eventAssignments) {
        final teamMember = assignment.teamMember;
        if (teamMember != null && teamMember.birthday != null) {
          if (_isBirthdayDuringEvent(
              teamMember.birthday!, event.startDate, event.endDate)) {
            birthdayNames.add(teamMember.name);
          }
        }
      }

      if (birthdayNames.isNotEmpty) {
        // Sort names alphabetically
        birthdayNames.sort();
        result[event.id] = birthdayNames;
      }
    }

    return result;
  }

  /// Check if a birthday falls within an event's date range
  bool _isBirthdayDuringEvent(
      DateTime birthday, DateTime eventStart, DateTime eventEnd) {
    // Normalize to date-only (remove time component)
    final start = DateTime(eventStart.year, eventStart.month, eventStart.day);
    final end = DateTime(eventEnd.year, eventEnd.month, eventEnd.day);

    // Check each day in the event range
    DateTime currentDay = start;
    while (!currentDay.isAfter(end)) {
      if (currentDay.month == birthday.month &&
          currentDay.day == birthday.day) {
        return true;
      }
      currentDay = currentDay.add(const Duration(days: 1));
    }

    return false;
  }

  /// Handle combined events and assignments data update
  Future<void> _onEventsDataUpdated(
    _EventsDataUpdated event,
    Emitter<EventState> emit,
  ) async {
    var events = event.events;

    if (event.upcomingOnly) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Filter for future events
      final futureEvents = events.where((e) {
        return e.endDate.isAfter(today) ||
            (e.endDate.year == today.year &&
                e.endDate.month == today.month &&
                e.endDate.day == today.day);
      }).toList();

      if (futureEvents.isEmpty) {
        final isFiltered = events.isNotEmpty;
        emit(EventsEmpty('אין אירועים עתידיים', isFiltered: isFiltered));
      } else {
        emit(EventsLoaded.withCounts(
          futureEvents,
          assignmentCounts: event.assignmentCounts,
          eventBirthdays: event.eventBirthdays,
        ));
      }
    } else {
      if (events.isEmpty) {
        emit(const EventsEmpty('אין אירועים במערכת'));
      } else {
        emit(EventsLoaded.withCounts(
          events,
          assignmentCounts: event.assignmentCounts,
          eventBirthdays: event.eventBirthdays,
        ));
      }
    }
  }

  /// Load upcoming events only (future events with real-time updates)
  Future<void> _onLoadUpcomingEvents(
    LoadUpcomingEvents event,
    Emitter<EventState> emit,
  ) async {
    _upcomingOnly = true;
    // When already watching, this re-emits from cache through the upcoming
    // filter instantly via _emitCombinedIfReady (which reads _upcomingOnly);
    // no re-subscribe.
    await _ensureWatching(emit);
  }

  /// Search events
  Future<void> _onSearchEvents(
    SearchEvents event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());

    try {
      final events = await _repository.searchEvents(event.query);

      if (events.isEmpty) {
        emit(const EventsEmpty('לא נמצאו אירועים'));
      } else {
        emit(EventsLoaded.withCounts(
          events,
          searchQuery: event.query,
          eventBirthdays: const {}, // Search doesn't include assignments, so no birthdays
        ));
      }
    } catch (e) {
      emit(EventError('שגיאה בחיפוש: $e'));
    }
  }

  /// Load event by ID
  Future<void> _onLoadEventById(
    LoadEventById event,
    Emitter<EventState> emit,
  ) async {
    emit(const EventLoading());

    try {
      final eventDetail = await _repository.getEventById(event.id);

      if (eventDetail == null) {
        emit(const EventError('אירוע לא נמצא'));
      } else {
        emit(EventDetailLoaded(eventDetail));
      }
    } catch (e) {
      emit(EventError('שגיאה בטעינת פרטי האירוע: $e'));
    }
  }

  /// Create new event
  Future<void> _onCreateEvent(
    CreateEvent event,
    Emitter<EventState> emit,
  ) async {
    try {
      // Don't emit EventOperating to avoid UI rebuild
      await _repository.createEvent(event.event);

      // Sync to Google Calendar if calendar sync is enabled
      _syncEventToCalendar(event.event);

      // Emit success to show snackbar, UI will keep showing last state
      emit(const EventOperationSuccess('האירוע נוסף בהצלחה'));
      _completeActionSuccess(event.completion, 'האירוע נוסף בהצלחה');

      // Don't restart listener here - the modal will handle it with the correct filter
    } catch (e) {
      final message = 'שגיאה בהוספת אירוע: $e';
      emit(EventError(message));
      _completeActionFailure(event.completion, message);
    }
  }

  /// Update event
  Future<void> _onUpdateEvent(
    UpdateEvent event,
    Emitter<EventState> emit,
  ) async {
    try {
      // Don't emit EventOperating to avoid UI rebuild
      await _repository.updateEvent(event.event);

      // Sync to Google Calendar if calendar sync is enabled
      // Note: We sync on every update to ensure calendar is always up-to-date
      _syncEventToCalendar(event.event);

      // Emit success to show snackbar, UI will keep showing last state
      emit(const EventOperationSuccess('פרטי האירוע עודכנו בהצלחה'));
      _completeActionSuccess(event.completion, 'פרטי האירוע עודכנו בהצלחה');

      // Don't restart listener here - the modal will handle it with the correct filter
    } catch (e) {
      final message = 'שגיאה בעדכון פרטי האירוע: $e';
      emit(EventError(message));
      _completeActionFailure(event.completion, message);
    }
  }

  /// Delete event
  Future<void> _onDeleteEvent(
    DeleteEvent event,
    Emitter<EventState> emit,
  ) async {
    try {
      // Delete the event
      await _repository.deleteEvent(event.id);

      // Immediately reload events to get updated state
      // This ensures the UI reflects the deletion immediately
      add(const LoadEvents());

      // Emit success to show snackbar
      emit(const EventOperationSuccess('האירוע נמחק בהצלחה'));
      _completeActionSuccess(event.completion, 'האירוע נמחק בהצלחה');
    } catch (e) {
      final message = 'שגיאה במחיקת האירוע: $e';
      emit(EventError(message));
      _completeActionFailure(event.completion, message);
    }
  }

  /// Refresh events
  Future<void> _onRefreshEvents(
    RefreshEvents event,
    Emitter<EventState> emit,
  ) async {
    // Simply reload
    add(const LoadEvents());
  }

  /// Duplicate event with new date/time
  /// NEW FLOW: Check for conflicts FIRST, emit conflict state if any,
  /// and DON'T create anything until user confirms via ConfirmDuplicationWithExclusions
  Future<void> _onDuplicateEvent(
    DuplicateEvent event,
    Emitter<EventState> emit,
  ) async {
    try {
      // Get the original event
      final originalEvent = await _repository.getEventById(event.eventId);
      if (originalEvent == null) {
        emit(const EventError('האירוע לא נמצא'));
        return;
      }

      // Create the proposed duplicated event with all new values
      // Note: Drive fields (driveFolderId, driveFolderLink) will be null
      // and will be created automatically when duplicating
      final proposedEvent = Event(
        id: const Uuid().v4(), // Generate unique ID for the duplicated event
        name: event.newName,
        location: event.newLocation,
        comments: event.newComments,
        startDate: event.newStartDate,
        endDate: event.newEndDate,
        startTime: event.newStartTime,
        endTime: event.newEndTime,
        assemblyTime: event.newAssemblyTime,
        actualShowStartTime: event.newActualShowStartTime,
        requiresArmed: event.newRequiresArmed,
        roleRequirements: Map.from(event.newRoleRequirements),
        categoryId: event.categoryId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        // Drive fields are omitted - they will be created by createEvent
        relevantForExtendedTeam: event.newRelevantForExtendedTeam,
      );

      // If not duplicating assignments, just create the event directly
      if (!event.duplicateAssignments) {
        await _repository.duplicateEvent(
          originalEvent,
          proposedEvent,
          [],
        );
        emit(const EventOperationSuccess('האירוע שוכפל בהצלחה ללא שיבוצים'));
        add(const LoadEvents());
        return;
      }

      // Get assignments to duplicate
      final assignments =
          await _assignmentRepository.getAssignmentsByEvent(event.eventId);

      if (assignments.isEmpty) {
        // No assignments to duplicate, just create the event
        await _repository.duplicateEvent(
          originalEvent,
          proposedEvent,
          [],
        );
        emit(const EventOperationSuccess(
            'האירוע שוכפל בהצלחה (ללא שיבוצים קיימים)'));
        add(const LoadEvents());
        return;
      }

      // Calculate role quotas that would be over-filled
      final overQuotaRoles = <String>{};
      for (final roleType in RoleType.values) {
        final newQuota = event.newRoleRequirements[roleType.key] ?? 0;
        final assignmentCount =
            assignments.where((a) => a.roleType == roleType.key).length;
        if (assignmentCount > newQuota) {
          overQuotaRoles.add(roleType.key);
        }
      }

      // Build assignment info list with conflict details
      final assignmentInfos = <AssignmentDuplicationInfo>[];
      bool hasAnyConflict = false;

      for (final assignment in assignments) {
        bool hasAvailabilityConflict = false;
        String? availabilityReason;

        // Check availability conflict with new dates
        // Skip for members with allowMultipleAssignments
        if (assignment.teamMember != null &&
            !assignment.teamMember!.allowMultipleAssignments) {
          if (!assignment.teamMember!
              .isAvailableForDateRange(event.newStartDate, event.newEndDate)) {
            hasAvailabilityConflict = true;
            availabilityReason = 'חבר הצוות לא זמין בתאריכים החדשים';
          }
        }

        final isInOverQuotaRole = overQuotaRoles.contains(assignment.roleType);

        if (hasAvailabilityConflict || isInOverQuotaRole) {
          hasAnyConflict = true;
        }

        assignmentInfos.add(AssignmentDuplicationInfo(
          assignment: assignment,
          hasAvailabilityConflict: hasAvailabilityConflict,
          availabilityReason: availabilityReason,
          isInOverQuotaRole: isInOverQuotaRole,
        ));
      }

      // If there are ANY conflicts, emit state for user resolution
      // DO NOT create anything yet!
      if (hasAnyConflict) {
        // Role requirements are already Map<String, int>, use them directly
        final roleQuotas = Map<String, int>.from(event.newRoleRequirements);

        emit(DuplicationRequiresConflictResolution(
          originalEvent: originalEvent,
          proposedEvent: proposedEvent,
          assignmentInfos: assignmentInfos,
          roleQuotas: roleQuotas,
        ));
        return; // STOP HERE - wait for user to confirm via ConfirmDuplicationWithExclusions
      }

      // No conflicts - proceed with full duplication
      await _repository.duplicateEvent(
        originalEvent,
        proposedEvent,
        assignments,
      );
      emit(const EventOperationSuccess('האירוע שוכפל בהצלחה עם כל השיבוצים'));
      add(const LoadEvents());
    } catch (e) {
      emit(EventError('שגיאה בשכפול האירוע: $e'));
    }
  }

  /// Handle confirmed duplication after user resolves conflicts
  /// This creates the event and ONLY the assignments the user chose to include
  /// Logic fix: Adjusts quotas in the proposed event to match kept assignments
  Future<void> _onConfirmDuplicationWithExclusions(
    ConfirmDuplicationWithExclusions event,
    Emitter<EventState> emit,
  ) async {
    try {
      // Get the original assignments
      final allAssignments = await _assignmentRepository
          .getAssignmentsByEvent(event.originalEvent.id);

      // Filter out excluded assignments
      final assignmentsToInclude = allAssignments
          .where((a) => !event.assignmentIdsToExclude.contains(a.id))
          .toList();

      // LOGIC FIX: Adjust quotas in the proposed event to match kept assignments
      final adjustedEvent = _adjustQuotasToMatchAssignments(
          event.proposedEvent, assignmentsToInclude);

      // Create the event with adjusted quotas and filtered assignments
      await _repository.duplicateEvent(
        event.originalEvent,
        adjustedEvent,
        assignmentsToInclude,
      );

      // Build success message
      final excludedCount = event.assignmentIdsToExclude.length;
      final includedCount = assignmentsToInclude.length;

      String message;
      if (excludedCount == 0) {
        message = 'האירוע שוכפל בהצלחה עם כל $includedCount השיבוצים';
      } else if (includedCount == 0) {
        message = 'האירוע שוכפל בהצלחה ללא שיבוצים';
      } else {
        message =
            'האירוע שוכפל בהצלחה עם $includedCount שיבוצים ($excludedCount הוסרו)';
      }

      emit(EventOperationSuccess(message));
      add(const LoadEvents());
    } catch (e) {
      emit(EventError('שגיאה בשכפול האירוע: $e'));
    }
  }

  /// Adjust role requirements in the event to match the number of kept assignments
  /// This ensures the event's quotas are consistent with what will be created
  Event _adjustQuotasToMatchAssignments(
      Event proposedEvent, List<Assignment> assignmentsToInclude) {
    // Count assignments by role
    final roleCounts = <String, int>{};
    for (final assignment in assignmentsToInclude) {
      roleCounts[assignment.roleType] =
          (roleCounts[assignment.roleType] ?? 0) + 1;
    }

    // Update the proposed event's role requirements to match the kept assignments
    final updatedRoleRequirements =
        Map<String, int>.from(proposedEvent.roleRequirements);

    // Set each role's quota to match the number of kept assignments
    for (final entry in roleCounts.entries) {
      updatedRoleRequirements[entry.key] = entry.value;
    }

    // Create a new event with adjusted quotas
    return Event(
      id: proposedEvent.id,
      name: proposedEvent.name,
      location: proposedEvent.location,
      comments: proposedEvent.comments,
      startDate: proposedEvent.startDate,
      endDate: proposedEvent.endDate,
      startTime: proposedEvent.startTime,
      endTime: proposedEvent.endTime,
      assemblyTime: proposedEvent.assemblyTime,
      requiresArmed: proposedEvent.requiresArmed,
      roleRequirements: updatedRoleRequirements,
      categoryId: proposedEvent.categoryId,
      createdAt: proposedEvent.createdAt,
      updatedAt:
          DateTime.now(), // Update timestamp since we're modifying quotas
      // Preserve Drive fields from proposedEvent (if any)
      driveFolderId: proposedEvent.driveFolderId,
      driveFolderLink: proposedEvent.driveFolderLink,
      relevantForExtendedTeam: proposedEvent.relevantForExtendedTeam,
    );
  }

  /// Helper method to sync event to Google Calendar
  /// Always syncs to handle both creation/update AND deletion of calendar events.
  /// Deactivated events get their calendar entries removed instead of synced.
  void _syncEventToCalendar(Event event) {
    final calendarSyncBloc = _calendarSyncBloc;
    if (calendarSyncBloc == null) {
      return;
    }

    // Deactivated events have no calendar presence — remove any existing entries.
    if (event.isDeactivated) {
      calendarSyncBloc.add(RemoveAppEventFromCalendar(eventId: event.id));
      return;
    }

    // Extract clean location name (remove coordinates if present)
    String? cleanLocation;
    if (event.location.isNotEmpty) {
      // Location format: "Name||lat,lng" - extract only the name part
      final parts = event.location.split('||');
      cleanLocation = parts[0].trim();
      if (cleanLocation.isEmpty) cleanLocation = null;
    }

    // IMPORTANT: Always dispatch sync event, even if time fields are empty
    // The sync service will handle deletion of calendar events when time fields are removed
    // Dispatch sync event to calendar sync bloc
    calendarSyncBloc.add(SyncAppEventToCalendar(
      eventId: event.id,
      eventName: event.name,
      startDate: event.startDate,
      endDate: event.endDate,
      assemblyTime: event.assemblyTime,
      startTime: event.startTime,
      actualShowStartTime: event.actualShowStartTime,
      endTime: event.endTime,
      location: cleanLocation,
    ));
  }

  /// Deactivate an event:
  /// - Writes isDeactivated=true to Firestore (assignments are preserved)
  /// - Removes the event's Google Calendar entries via _syncEventToCalendar
  Future<void> _onDeactivateEvent(
    DeactivateEventRequested event,
    Emitter<EventState> emit,
  ) async {
    try {
      final current = await _repository.getEventById(event.eventId);
      if (current == null) {
        const message = 'האירוע לא נמצא';
        emit(const EventError(message));
        _completeActionFailure(event.completion, message);
        return;
      }

      final updated = current.copyWith(
        isDeactivated: true,
        updatedAt: DateTime.now(),
      );

      await _repository.updateEvent(updated);
      _syncEventToCalendar(updated);

      emit(const EventOperationSuccess('האירוע הושבת'));
      _completeActionSuccess(event.completion, 'האירוע הושבת');
    } catch (e) {
      final message = 'שגיאה בהשבתת האירוע: $e';
      emit(EventError(message));
      _completeActionFailure(event.completion, message);
    }
  }

  /// Reactivate an event:
  /// - Writes isDeactivated=false to Firestore
  /// - Recreates Google Calendar entries via _syncEventToCalendar and re-syncs attendees
  ///   from the preserved assignments
  Future<void> _onReactivateEvent(
    ReactivateEventRequested event,
    Emitter<EventState> emit,
  ) async {
    try {
      final current = await _repository.getEventById(event.eventId);
      if (current == null) {
        const message = 'האירוע לא נמצא';
        emit(const EventError(message));
        _completeActionFailure(event.completion, message);
        return;
      }

      final updated = current.copyWith(
        isDeactivated: false,
        updatedAt: DateTime.now(),
      );

      await _repository.updateEvent(updated);
      _syncEventToCalendar(updated);
      // Re-sync attendees from the preserved assignments so calendar invites are
      // restored to whoever was on the event before it was deactivated.
      _calendarSyncBloc?.add(SyncAttendeesForAppEvent(eventId: updated.id));

      emit(const EventOperationSuccess('האירוע הופעל מחדש'));
      _completeActionSuccess(event.completion, 'האירוע הופעל מחדש');
    } catch (e) {
      final message = 'שגיאה בהפעלת האירוע: $e';
      emit(EventError(message));
      _completeActionFailure(event.completion, message);
    }
  }

  @override
  Future<void> close() async {
    // Cancel stream subscriptions to prevent memory leaks
    await _eventsSubscription?.cancel();
    await _assignmentsSubscription?.cancel();
    return super.close();
  }

  void _completeActionSuccess(
    CrudActionCompleter? completion, [
    String? message,
  ]) {
    completeCrudAction(completion, CrudActionResult.success(message));
  }

  void _completeActionFailure(
    CrudActionCompleter? completion,
    String message,
  ) {
    completeCrudAction(completion, CrudActionResult.failure(message));
  }
}

/// Internal event: Received events and assignments update from streams
/// This is used to properly manage stream subscriptions and prevent memory leaks
class _EventsDataUpdated extends EventEvent {
  final List<Event> events;
  final Map<String, int> assignmentCounts;
  final Map<String, List<String>> eventBirthdays;
  final bool upcomingOnly;

  const _EventsDataUpdated({
    required this.events,
    required this.assignmentCounts,
    this.eventBirthdays = const {},
    this.upcomingOnly = false,
  });

  @override
  List<Object?> get props =>
      [events, assignmentCounts, eventBirthdays, upcomingOnly];
}
