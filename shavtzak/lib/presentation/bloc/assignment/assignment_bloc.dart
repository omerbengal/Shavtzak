import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/debug/logger.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/event_sorting.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/role.dart';
import '../../../domain/entities/team_member.dart';
import 'assignment_event.dart';
import 'assignment_state.dart';
import '../../screens/assignment/models/assignment_slot.dart';
import '../calendar_sync/calendar_sync_bloc.dart';
import '../calendar_sync/calendar_sync_event.dart';

/// BLoC for managing assignments
/// This is the KEY BLoC that solves the V1 sync problem
class AssignmentBloc extends Bloc<AssignmentEvent, AssignmentState> {
  final AssignmentRepository _repository;
  final EventRepository _eventRepository;
  final TeamRepository _teamRepository;
  final RoleRepository _roleRepository;
  final CalendarSyncBloc? _calendarSyncBloc;

  // Stream subscriptions for manual control
  StreamSubscription? _assignmentSubscription;
  StreamSubscription? _teamMemberSubscription;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _roleSubscription;

  // Stream subscriptions for user assignments view
  StreamSubscription? _userAssignmentSubscription;
  StreamSubscription? _userEventSubscription;

  // Stream plumbing for the "list" view modes (all / by-event / by-person).
  // These historically used emit.forEach directly, whose future never completes
  // for an infinite Firestore stream — so the subscription lived for the bloc's
  // whole lifetime and could clobber a later view (e.g. /user/assignments) with
  // the full assignments collection. We now feed the source stream through a
  // controller we OWN, so _cancelListSubscriptions() can close it and complete
  // the forEach on demand when switching modes.
  StreamSubscription? _listAssignmentSubscription;
  StreamController<List<Assignment>>? _listAssignmentController;

  // Keep the current event filter independent of state
  Set<String> _currentEventFilter = <String>{};

  // Cached roles for the slots grid. Seeded once at slots-load time and
  // refreshed by the watchRoles listener when roles actually change. The
  // RebuildAssignmentSlotsFromData handler reads this cache instead of
  // re-fetching getAllRoles() on every rebuild (the windowed assignment/team/
  // event/role stream listeners each trigger a rebuild on their initial emit,
  // which previously caused ~5 identical getAllRoles fetches per load).
  // watchRoles() emits the SAME role set as getAllRoles() (both read
  // utilities/Lists 'Roles' with identical mapping + sortOrder sort, no
  // filtering), so the listener can cache its stream payload directly.
  List<Role> _cachedRoles = const [];

  // --- Past-history pagination (load more) ---
  static const int _pastLoadMoreRowChunk = 25; // rows revealed per tap
  static const int _pastEventFetchBatch = 15; // events fetched per round-trip

  // Live 90-day window data, promoted to fields so the load-more handler can
  // trigger a rebuild that merges the extra-past cache on top.
  final Map<String, Event> _windowEventsMap = {};
  final Map<String, TeamMember> _windowMembersMap = {};
  DateTime? _slotsWindowStart; // now - 90d; boundary between window and "extra-past"

  // First-paint gate for the slots view. Each flag flips true when its stream
  // delivers its first emit during a (re)load; _onRebuildAssignmentSlotsFromData
  // suppresses the emit until all three are true, so the spinner clears
  // straight to a fully-populated grid instead of flashing an empty/partial
  // one while the streams arrive out of order. See _onLoadAssignmentSlots.
  bool _slotsRolesReady = false;
  bool _slotsEventsReady = false;
  bool _slotsAssignmentsReady = false;

  // Events/assignments older than the window, loaded on demand.
  final Map<String, Event> _extraPastEventsMap = {};
  final List<Assignment> _extraPastAssignments = [];
  int _extraPastRowsRevealed = 0; // reveal cap for extra-past rows
  DateTime? _oldestLoadedEventStart; // pagination cursor
  bool _pastPagingExhausted = false; // reached the start of history
  bool _loadingMorePast = false; // authoritative in-flight guard (state field can be stomped by concurrent rebuilds)

  // Keep pending operations independent of state (survives error states)
  Map<String, PendingOperation> _pendingOperations = {};

  AssignmentBloc(
    this._repository,
    this._eventRepository,
    this._teamRepository,
    this._roleRepository,
    this._calendarSyncBloc,
  ) : super(const AssignmentInitial()) {
    // Register event handlers
    on<LoadAssignments>(_onLoadAssignments);
    on<LoadAssignmentsByEvent>(_onLoadAssignmentsByEvent);
    on<LoadAssignmentsByPerson>(_onLoadAssignmentsByPerson);
    on<LoadAssignmentsByDateRange>(_onLoadAssignmentsByDateRange);
    on<LoadAssignmentById>(_onLoadAssignmentById);
    on<CreateAssignment>(_onCreateAssignment);
    on<CreateAssignmentWithBypass>(_onCreateAssignmentWithBypass);
    on<UpdateAssignment>(_onUpdateAssignment);
    on<DeleteAssignment>(_onDeleteAssignment);
    on<UpdateAssignmentStatus>(_onUpdateAssignmentStatus);
    on<ConfirmAssignment>(_onConfirmAssignment);
    on<DeclineAssignment>(_onDeclineAssignment);
    on<LoadAssignmentsWithConflicts>(_onLoadAssignmentsWithConflicts);
    on<LoadEventAssignmentStats>(_onLoadEventAssignmentStats);
    on<RefreshAssignments>(_onRefreshAssignments);
    on<LoadAssignmentSlots>(_onLoadAssignmentSlots);
    on<ApplyEventFilter>(_onApplyEventFilter);
    on<ClearEventFilter>(_onClearEventFilter);
    on<RebuildAssignmentSlots>(_onRebuildAssignmentSlots);
    on<RebuildAssignmentSlotsFromData>(_onRebuildAssignmentSlotsFromData);
    on<LoadUserAssignments>(_onLoadUserAssignments);
    on<RebuildUserAssignments>(_onRebuildUserAssignments);
    on<UpdateAssignmentNotes>(_onUpdateAssignmentNotes);
    on<OptimisticCreateAssignment>(_onOptimisticCreateAssignment);
    on<OptimisticUpdateAssignment>(_onOptimisticUpdateAssignment);
    on<OptimisticDeleteAssignment>(_onOptimisticDeleteAssignment);
    on<LoadMorePastAssignmentSlots>(_onLoadMorePastAssignmentSlots);
    on<ExternalExtraPastMutation>(_onExternalExtraPastMutation);
  }

  /// Load all assignments with real-time updates
  Future<void> _onLoadAssignments(
    LoadAssignments event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentLoading());

    try {
      // Stop slot-mode subscriptions to prevent mixed AssignmentSlotsLoaded
      // updates while in "all assignments" mode.
      await _cancelSlotsSubscriptions();
      await _cancelUserAssignmentsSubscriptions();

      await _streamAssignmentsList(
        emit,
        _repository.watchAssignments(),
        (assignments) => assignments.isEmpty
            ? const AssignmentsEmpty('אין שיבוצים במערכת')
            : AssignmentsLoaded.withCounts(assignments, filterType: 'all'),
      );
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Subscribe a "list" view mode (all / by-event / by-person) to [source]
  /// through a controller we own, so the stream can be cancelled when the bloc
  /// switches to another view mode. A raw `emit.forEach` on an infinite
  /// Firestore stream can never be stopped, which previously let a stale
  /// list-mode subscription overwrite the /user/assignments (and slots) state.
  Future<void> _streamAssignmentsList(
    Emitter<AssignmentState> emit,
    Stream<List<Assignment>> source,
    AssignmentState Function(List<Assignment> assignments) onData,
  ) async {
    // Cancel any list-mode stream already running (also covers switching
    // between all/by-event/by-person without leaking the previous one).
    await _cancelListSubscriptions();

    final controller = StreamController<List<Assignment>>();
    _listAssignmentController = controller;
    _listAssignmentSubscription = source.listen(
      controller.add,
      onError: controller.addError,
    );

    // Closing the controller (via _cancelListSubscriptions) completes this
    // forEach cleanly, so the handler returns instead of emitting forever.
    await emit.forEach<List<Assignment>>(
      controller.stream,
      onData: onData,
      onError: (error, stackTrace) =>
          AssignmentError('שגיאה בטעינת שיבוצים: $error'),
    );
  }

  /// Load assignments for a specific event with real-time updates
  Future<void> _onLoadAssignmentsByEvent(
    LoadAssignmentsByEvent event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentLoading());

    try {
      await _cancelSlotsSubscriptions();
      await _cancelUserAssignmentsSubscriptions();

      await _streamAssignmentsList(
        emit,
        _repository.watchAssignmentsByEvent(event.eventId),
        (assignments) => assignments.isEmpty
            ? const AssignmentsEmpty('אין שיבוצים לאירוע זה')
            : AssignmentsLoaded.withCounts(
                assignments,
                filterType: 'event',
                filterId: event.eventId,
              ),
      );
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Load assignments for a specific team member with real-time updates
  Future<void> _onLoadAssignmentsByPerson(
    LoadAssignmentsByPerson event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentLoading());

    try {
      await _cancelSlotsSubscriptions();
      await _cancelUserAssignmentsSubscriptions();

      await _streamAssignmentsList(
        emit,
        _repository.watchAssignmentsByPerson(event.teamMemberId),
        (assignments) => assignments.isEmpty
            ? const AssignmentsEmpty('אין שיבוצים לחבר צוות זה')
            : AssignmentsLoaded.withCounts(
                assignments,
                filterType: 'person',
                filterId: event.teamMemberId,
              ),
      );
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Load assignments by date range
  Future<void> _onLoadAssignmentsByDateRange(
    LoadAssignmentsByDateRange event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentLoading());

    try {
      await _cancelSlotsSubscriptions();
      await _cancelUserAssignmentsSubscriptions();
      await _cancelListSubscriptions();

      final assignments = await _repository.getAssignmentsByDateRange(
        event.start,
        event.end,
      );

      if (assignments.isEmpty) {
        _emitOrLog(emit, const AssignmentsEmpty('אין שיבוצים בטווח תאריכים זה'));
      } else {
        _emitOrLog(emit, AssignmentsLoaded.withCounts(
          assignments,
          filterType: 'dateRange',
        ));
      }
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Load assignment by ID
  Future<void> _onLoadAssignmentById(
    LoadAssignmentById event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentLoading());

    try {
      await _cancelSlotsSubscriptions();
      await _cancelUserAssignmentsSubscriptions();
      await _cancelListSubscriptions();

      final assignment = await _repository.getAssignmentById(event.id);

      if (assignment == null) {
        _emitOrLog(emit, const AssignmentError('שיבוץ לא נמצא'));
      } else {
        _emitOrLog(emit, AssignmentDetailLoaded(assignment));
      }
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת פרטי השיבוץ: $e'));
    }
  }

  /// Create new assignment
  Future<void> _onCreateAssignment(
    CreateAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    // Store previous state BEFORE any emit
    final previousState = state;

    _emitOrLog(emit, const AssignmentOperating('creating'));

    try {
      // Check for conflicts before creating
      final conflicts = await _repository.checkConflicts(event.assignment);

      if (conflicts.isNotEmpty) {
        // Emit conflict warning but don't fail
        _emitOrLog(emit, AssignmentConflictWarning(conflicts, event.assignment));
        _completeActionFailure(event.completion, conflicts.join(', '));
        // Note: Real-time stream will automatically update UI, no manual reload needed
        return;
      }

      await _repository.createAssignment(event.assignment);
      _syncAttendeesForAffectedEvents(nextAssignment: event.assignment);
      await _refreshExtraPastEvent(event.assignment.eventId);
      _emitOrLog(emit, const AssignmentOperationSuccess('השיבוץ נוסף בהצלחה'));
      _completeActionSuccess(event.completion, 'השיבוץ נוסף בהצלחה');

      // Check if we need to reload based on view type
      // For slots view: Real-time stream handles updates automatically
      // For list view: Need to restart the listener
      if (previousState is AssignmentsLoaded) {
        // Restart real-time listener based on current filter
        final currentState = previousState;
        if (currentState.filterType == 'event' &&
            currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' &&
            currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else if (previousState is AssignmentSlotsLoaded) {
        add(RebuildAssignmentSlots(
          preservedFilter: previousState.selectedEventIds,
        ));
      } else {
        // Only reload if not in slots view (real-time stream handles slots view)
        add(const LoadAssignments());
      }
      // If previousState is AssignmentSlotsLoaded, do nothing - real-time stream will handle it
    } catch (e) {
      if (e is AssignmentConflictException) {
        _emitOrLog(emit, AssignmentConflictWarning(e.conflicts, event.assignment));
        _completeActionFailure(event.completion, e.conflicts.join(', '));
      } else {
        final message = 'שגיאה בהוספת שיבוץ: $e';
        _emitOrLog(emit, AssignmentError(message));
        _completeActionFailure(event.completion, message);
      }
    }
  }

  /// Update assignment
  Future<void> _onUpdateAssignment(
    UpdateAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    // Store previous state BEFORE any emit
    final previousState = state;

    _emitOrLog(emit, const AssignmentOperating('updating'));

    try {
      final previousAssignment =
          await _repository.getAssignmentById(event.assignment.id);

      if (!event.bypassAvailability) {
        final conflicts = await _repository.checkConflicts(event.assignment);

        if (conflicts.isNotEmpty) {
          _emitOrLog(emit, AssignmentConflictWarning(conflicts, event.assignment));
          _completeActionFailure(event.completion, conflicts.join(', '));
          // Note: Real-time stream will automatically update UI, no manual reload needed
          return;
        }
      }

      if (event.bypassAvailability) {
        await _repository.updateAssignmentWithBypass(event.assignment);
      } else {
        await _repository.updateAssignment(event.assignment);
      }
      _syncAttendeesForAffectedEvents(
        previousAssignment: previousAssignment,
        nextAssignment: event.assignment,
      );
      await _refreshExtraPastEvent(event.assignment.eventId);
      if (previousAssignment != null &&
          previousAssignment.eventId != event.assignment.eventId) {
        await _refreshExtraPastEvent(previousAssignment.eventId);
      }
      _emitOrLog(emit, const AssignmentOperationSuccess('השיבוץ עודכן בהצלחה'));
      _completeActionSuccess(event.completion, 'השיבוץ עודכן בהצלחה');

      // Check if we need to reload based on view type
      // For slots view: Real-time stream handles updates automatically
      // For list view: Need to restart the listener
      if (previousState is AssignmentsLoaded) {
        // Restart real-time listener based on current filter
        final currentState = previousState;
        if (currentState.filterType == 'event' &&
            currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' &&
            currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else if (previousState is AssignmentSlotsLoaded) {
        add(RebuildAssignmentSlots(
          preservedFilter: previousState.selectedEventIds,
        ));
      } else {
        // Only reload if not in slots view (real-time stream handles slots view)
        add(const LoadAssignments());
      }
      // If previousState is AssignmentSlotsLoaded, do nothing - real-time stream will handle it
    } catch (e) {
      if (e is AssignmentConflictException) {
        _emitOrLog(emit, AssignmentConflictWarning(e.conflicts, event.assignment));
        _completeActionFailure(event.completion, e.conflicts.join(', '));
      } else {
        final message = 'שגיאה בעדכון שיבוץ: $e';
        _emitOrLog(emit, AssignmentError(message));
        _completeActionFailure(event.completion, message);
      }
    }
  }

  /// Delete assignment
  Future<void> _onDeleteAssignment(
    DeleteAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    // Store previous state BEFORE any emit
    final previousState = state;

    _emitOrLog(emit, const AssignmentOperating('deleting'));

    try {
      // IMPORTANT: Get assignment BEFORE deleting to sync calendar attendees
      final assignmentToDelete = await _repository.getAssignmentById(event.id);

      await _repository.deleteAssignment(event.id);

      // Sync attendees for calendar event (will remove the deleted attendee)
      _syncAttendeesForAffectedEvents(previousAssignment: assignmentToDelete);
      if (assignmentToDelete != null) {
        await _refreshExtraPastEvent(assignmentToDelete.eventId);
      }

      _emitOrLog(emit, const AssignmentOperationSuccess('השיבוץ נמחק בהצלחה'));
      _completeActionSuccess(event.completion, 'השיבוץ נמחק בהצלחה');

      // Check if we need to reload based on view type
      // For slots view: Real-time stream handles updates automatically
      // For list view: Need to restart the listener
      if (previousState is AssignmentsLoaded) {
        // Restart real-time listener based on current filter
        final currentState = previousState;
        if (currentState.filterType == 'event' &&
            currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' &&
            currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else if (previousState is AssignmentSlotsLoaded) {
        add(RebuildAssignmentSlots(
          preservedFilter: previousState.selectedEventIds,
        ));
      } else {
        // Only reload if not in slots view (real-time stream handles slots view)
        add(const LoadAssignments());
      }
      // If previousState is AssignmentSlotsLoaded, do nothing - real-time stream will handle it
    } catch (e) {
      final message = 'שגיאה במחיקת שיבוץ: $e';
      _emitOrLog(emit, AssignmentError(message));
      _completeActionFailure(event.completion, message);
    }
  }

  /// Update assignment status
  Future<void> _onUpdateAssignmentStatus(
    UpdateAssignmentStatus event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentOperating('updating'));

    try {
      await _repository.updateAssignmentStatus(event.id, event.status);
      _emitOrLog(emit, const AssignmentOperationSuccess('סטטוס השיבוץ עודכן בהצלחה'));

      // Restart real-time listener based on current filter
      if (state is AssignmentsLoaded) {
        final currentState = state as AssignmentsLoaded;
        if (currentState.filterType == 'event' &&
            currentState.filterId != null) {
          add(LoadAssignmentsByEvent(currentState.filterId!));
        } else if (currentState.filterType == 'person' &&
            currentState.filterId != null) {
          add(LoadAssignmentsByPerson(currentState.filterId!));
        } else {
          add(const LoadAssignments());
        }
      } else {
        add(const LoadAssignments());
      }
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בעדכון סטטוס: $e'));
    }
  }

  /// Confirm assignment
  Future<void> _onConfirmAssignment(
    ConfirmAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    add(UpdateAssignmentStatus(event.id, AssignmentStatus.confirmed));
  }

  /// Decline assignment
  Future<void> _onDeclineAssignment(
    DeclineAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    add(UpdateAssignmentStatus(event.id, AssignmentStatus.declined));
  }

  /// Load assignments with conflicts
  Future<void> _onLoadAssignmentsWithConflicts(
    LoadAssignmentsWithConflicts event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentLoading());

    try {
      await _cancelSlotsSubscriptions();
      await _cancelUserAssignmentsSubscriptions();
      await _cancelListSubscriptions();

      final assignments = await _repository.getAssignmentsWithConflicts();

      if (assignments.isEmpty) {
        _emitOrLog(emit, const AssignmentsEmpty('אין שיבוצים עם קונפליקטים'));
      } else {
        _emitOrLog(emit, AssignmentsLoaded.withCounts(assignments));
      }
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Load event assignment statistics
  Future<void> _onLoadEventAssignmentStats(
    LoadEventAssignmentStats event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentLoading());

    try {
      await _cancelSlotsSubscriptions();
      await _cancelUserAssignmentsSubscriptions();
      await _cancelListSubscriptions();

      final stats = await _repository.getEventAssignmentStats(event.eventId);
      _emitOrLog(emit, EventAssignmentStatsLoaded(event.eventId, stats));
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת סטטיסטיקות: $e'));
    }
  }

  /// Refresh assignments
  Future<void> _onRefreshAssignments(
    RefreshAssignments event,
    Emitter<AssignmentState> emit,
  ) async {
    // Simply reload based on current state
    if (state is AssignmentsLoaded) {
      final currentState = state as AssignmentsLoaded;
      if (currentState.filterType == 'event' && currentState.filterId != null) {
        add(LoadAssignmentsByEvent(currentState.filterId!));
      } else if (currentState.filterType == 'person' &&
          currentState.filterId != null) {
        add(LoadAssignmentsByPerson(currentState.filterId!));
      } else {
        add(const LoadAssignments());
      }
    } else {
      add(const LoadAssignments());
    }
  }

  /// Load assignment slots for grid view with real-time updates
  /// Rebuilds slots whenever assignments, team members, OR events change
  Future<void> _onLoadAssignmentSlots(
    LoadAssignmentSlots event,
    Emitter<AssignmentState> emit,
  ) async {
    // Preserve the current filter from state BEFORE emitting loading
    final currentFilter = state is AssignmentSlotsLoaded
        ? (state as AssignmentSlotsLoaded).selectedEventIds
        : _currentEventFilter; // use remembered value as fallback

    // Keep the internal filter in sync
    _currentEventFilter = currentFilter;

    _emitOrLog(emit, const AssignmentLoading());

    try {
      // Cancel any existing subscriptions
      await _cancelSlotsSubscriptions();
      await _cancelUserAssignmentsSubscriptions();
      await _cancelListSubscriptions();

      // OPTIMIZATION: Use time window instead of loading all events/assignments
      // This reduces initial load from 5000+ assignments to ~500 (90% reduction)
      const pastWindow = Duration(days: 90); // 3 months back
      const futureWindow = Duration(days: 180); // 6 months forward

      final now = DateTime.now();
      final windowStart = now.subtract(pastWindow);
      final windowEnd = now.add(futureWindow);

      // Stream-first load: do NOT seed these with awaited one-shot .get()s.
      // The first `.get()` on a cold Firestore WebChannel parks ~30s (see the
      // assignments note below); the watchX listeners subscribed just below
      // deliver the exact same data in ~100ms. Clear any stale data from a
      // previous load — the streams refill these on their first emit.
      _windowMembersMap.clear();
      _windowEventsMap.clear();
      _cachedRoles = const [];

      // Arm the first-paint gate. Held until the roles, events, AND assignments
      // streams have EACH delivered once, so the first AssignmentSlotsLoaded is
      // fully populated instead of flashing an empty/partial grid. (Members are
      // intentionally excluded — assignments carry populated teamMember
      // relations, so names render without the map; available-member lists fill
      // a beat later and aren't visible until a slot is tapped.) The three
      // stream listeners below flip these true.
      _slotsRolesReady = false;
      _slotsEventsReady = false;
      _slotsAssignmentsReady = false;

      // Reset past-history pagination on every (re)load, incl. toggling past.
      _slotsWindowStart = windowStart;
      _extraPastEventsMap.clear();
      _extraPastAssignments.clear();
      _extraPastRowsRevealed = 0;
      _oldestLoadedEventStart = windowStart; // fetch events strictly older than the window
      _pastPagingExhausted = false;

      // First paint comes from the assignments STREAM's first emit — NOT an
      // awaited one-shot getAssignmentsInTimeWindow(). A one-shot `.get()` can
      // park ~30s on this web setup (WebChannel handshake) while `.snapshots()`
      // returns the same data in ~90ms; gating first paint on the get froze the
      // spinner for the full park. `.snapshots()` fires immediately with current
      // data, and watchAssignmentsInTimeWindow emits on the first chunk (no
      // wait-for-all), so the listener below both paints initially and stays
      // live. See memory: firestore-stream-first-first-paint.
      //
      // Subscribe to real-time updates on assignments within time window
      _assignmentSubscription = _repository
          .watchAssignmentsInTimeWindow(
        windowStart: windowStart,
        windowEnd: windowEnd,
      )
          .listen(
        (assignments) {
          // Cache current assignments for rebuild purposes
          _repository.cacheCurrentAssignments(assignments);
          _slotsAssignmentsReady = true; // first-paint gate: assignments arrived
          // Rebuild slots using cached data - use _currentEventFilter to preserve user's filter
          add(RebuildAssignmentSlotsFromData(assignments, _windowEventsMap,
              _windowMembersMap, _currentEventFilter));
        },
        onError: (e) {
          _emitOrLog(emit, AssignmentError('שגיאה בהאזנה לשיבוצים: $e'));
        },
      );

      // Also listen for team member changes
      _teamMemberSubscription = _teamRepository.watchTeamMembers().listen(
        (updatedMembers) {
          // Update member cache
          _windowMembersMap.clear();
          _windowMembersMap.addAll({for (var tm in updatedMembers) tm.id: tm});
          // Assignments are kept live by the watchAssignmentsInTimeWindow listener
          // (the source of truth); reuse its cache instead of re-querying.
          final currentAssignments = _repository.getCurrentAssignments();
          add(RebuildAssignmentSlotsFromData(currentAssignments,
              _windowEventsMap, _windowMembersMap, _currentEventFilter));
        },
        onError: (e) {
          _emitOrLog(emit, AssignmentError('שגיאה בהאזנה לחברי צוות: $e'));
        },
      );

      // Also listen for event changes within time window
      _eventSubscription = _eventRepository
          .watchEventsByDateRange(
        windowStart,
        windowEnd,
      )
          .listen(
        (updatedEvents) {
          // Update event cache
          _windowEventsMap.clear();
          _windowEventsMap.addAll({for (var e in updatedEvents) e.id: e});
          _slotsEventsReady = true; // first-paint gate: events arrived

          // Assignments are kept live by the watchAssignmentsInTimeWindow listener
          // (the source of truth); reuse its cache instead of re-querying.
          final currentAssignments = _repository.getCurrentAssignments();
          add(RebuildAssignmentSlotsFromData(currentAssignments,
              _windowEventsMap, _windowMembersMap, _currentEventFilter));
        },
        onError: (e) {
          _emitOrLog(emit, AssignmentError('שגיאה בהאזנה לאירועים: $e'));
        },
      );

      // Also listen for role changes
      _roleSubscription = _roleRepository.watchRoles().listen(
        (updatedRoles) {
          // When roles change (rename/reorder/add/archive), refresh the cache
          // from the stream payload so the rebuild reflects the change. This is
          // the ONLY place roles are refreshed after the initial load; the
          // rebuild handler never re-fetches them. watchRoles() emits the same
          // set getAllRoles() returns, so caching the payload directly is safe.
          // Assignments are kept live by the watchAssignmentsInTimeWindow
          // listener (the source of truth); reuse its cache instead of
          // re-querying.
          _cachedRoles = updatedRoles;
          _slotsRolesReady = true; // first-paint gate: roles arrived
          final currentAssignments = _repository.getCurrentAssignments();
          add(RebuildAssignmentSlotsFromData(currentAssignments,
              _windowEventsMap, _windowMembersMap, _currentEventFilter));
        },
        onError: (e) {
          _emitOrLog(emit, AssignmentError('שגיאה בהאזנה לתפקידים: $e'));
        },
      );
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  @override
  Future<void> close() async {
    await _cancelSlotsSubscriptions();
    await _cancelUserAssignmentsSubscriptions();
    await _cancelListSubscriptions();
    return super.close();
  }

  Future<void> _cancelSlotsSubscriptions() async {
    await _assignmentSubscription?.cancel();
    _assignmentSubscription = null;
    await _teamMemberSubscription?.cancel();
    _teamMemberSubscription = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _roleSubscription?.cancel();
    _roleSubscription = null;
  }

  Future<void> _cancelUserAssignmentsSubscriptions() async {
    await _userAssignmentSubscription?.cancel();
    _userAssignmentSubscription = null;
    await _userEventSubscription?.cancel();
    _userEventSubscription = null;
  }

  /// Cancel the list-mode (all / by-event / by-person) stream. Closing the
  /// controller completes the pending emit.forEach in _streamAssignmentsList,
  /// so the corresponding load handler returns instead of emitting into a state
  /// that now belongs to a different view mode.
  Future<void> _cancelListSubscriptions() async {
    await _listAssignmentSubscription?.cancel();
    _listAssignmentSubscription = null;
    await _listAssignmentController?.close();
    _listAssignmentController = null;
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

  /// Emit [next] unless it is Equatable-equal to [state], in which case log
  /// a warning and skip — surfacing the silent-drop that flutter_bloc would
  /// otherwise perform invisibly.
  void _emitOrLog(Emitter<AssignmentState> emit, AssignmentState next) {
    if (next == state) {
      Logger.warning('AssignmentBloc no-emit', const {
        'reason': 'equatable-equal',
      });
      return;
    }
    emit(next);
  }

  /// Resolve a Role for an assignment's roleType key. Uses the roles cache
  /// (which includes archived roles). If the role was PERMANENTLY deleted,
  /// synthesize a display-only Role so the assignment still renders a name.
  Role _resolveRoleForKey(String key) {
    for (final role in _cachedRoles) {
      if (role.key == key) return role;
    }
    String hebrew;
    try {
      hebrew = RoleTypeExtension.fromString(key).hebrewName;
    } catch (_) {
      hebrew = key; // unknown key → show the raw key rather than crash
    }
    // Deterministic per key so two rebuilds produce an EQUAL synthesized Role
    // (Role.props includes createdAt/updatedAt); otherwise _emitOrLog's
    // no-op suppression breaks for any event with a deleted-role assignment.
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return Role(
      id: key,
      key: key,
      hebrewName: hebrew,
      isVisible: false,
      isArchived: true,
      sortOrder: 1 << 20, // sort after all real roles
      createdAt: epoch,
      updatedAt: epoch,
    );
  }

  /// Build "off-quota" rows for every [eventAssignments] entry whose id is NOT
  /// in [placedAssignmentIds] (i.e. it never landed in a normal quota slot).
  List<AssignmentSlot> _buildOffQuotaSlots(
    Event event,
    List<Assignment> eventAssignments,
    Set<String> placedAssignmentIds,
  ) {
    final result = <AssignmentSlot>[];
    for (final assignment in eventAssignments) {
      if (placedAssignmentIds.contains(assignment.id)) continue;
      result.add(AssignmentSlot(
        event: event,
        role: _resolveRoleForKey(assignment.roleType),
        slotIndex: assignment.slotIndex,
        currentAssignment: assignment,
        availableMembers: const [],
        alreadyAssignedMembers: const [],
        isOffQuota: true,
      ));
    }
    return result;
  }

  int _compareAssignmentSlots(AssignmentSlot a, AssignmentSlot b) {
    // Past ON → newest→oldest so "load older" reads downward (like /db);
    // Past OFF (default/upcoming view) → oldest→newest, unchanged.
    final eventCompare = FilterPersistence.showPastEvents
        ? compareEventsChronologicallyDescending(a.event, b.event)
        : compareEventsChronologically(a.event, b.event);
    if (eventCompare != 0) {
      return eventCompare;
    }

    final eventNameCompare = a.event.name.compareTo(b.event.name);
    if (eventNameCompare != 0) {
      return eventNameCompare;
    }

    // Off-quota rows sort AFTER their event's normal rows.
    if (a.isOffQuota != b.isOffQuota) {
      return a.isOffQuota ? 1 : -1;
    }

    final roleOrderCompare = a.role.sortOrder.compareTo(b.role.sortOrder);
    if (roleOrderCompare != 0) {
      return roleOrderCompare;
    }

    final roleKeyCompare = a.role.key.compareTo(b.role.key);
    if (roleKeyCompare != 0) {
      return roleKeyCompare;
    }

    final slotIndexCompare = a.slotIndex.compareTo(b.slotIndex);
    if (slotIndexCompare != 0) {
      return slotIndexCompare;
    }

    final memberNameCompare = (a.currentAssignment?.teamMemberName ?? '')
        .compareTo(b.currentAssignment?.teamMemberName ?? '');
    if (memberNameCompare != 0) {
      return memberNameCompare;
    }

    return (a.currentAssignment?.id ?? '')
        .compareTo(b.currentAssignment?.id ?? '');
  }

  /// Get slot key for AssignmentSlot
  String _getSlotKey(AssignmentSlot slot) {
    return '${slot.event.id}_${slot.role.key}_${slot.slotIndex}';
  }

  /// Apply optimistic update to a specific slot only
  List<AssignmentSlot> _applyOptimisticUpdate(
    List<AssignmentSlot> slots,
    String targetSlotKey,
    Assignment? optimisticAssignment, {
    required bool isDelete,
  }) {
    return slots.map((slot) {
      if (slot.isOffQuota) return slot;
      final slotKey = _getSlotKey(slot);

      if (slotKey == targetSlotKey) {
        // This is the target slot - apply the optimistic change
        return AssignmentSlot(
          event: slot.event,
          role: slot.role,
          slotIndex: slot.slotIndex,
          currentAssignment: isDelete ? null : optimisticAssignment,
          // CRITICAL: Keep database member lists unchanged
          availableMembers: slot.availableMembers,
          alreadyAssignedMembers: slot.alreadyAssignedMembers,
          hasDoubleAssignment: isDelete ? false : slot.hasDoubleAssignment,
          otherRoles: isDelete ? const [] : slot.otherRoles,
        );
      }

      // For all other slots, keep database state as-is
      return slot;
    }).toList();
  }

  /// Merge slots from database with pending optimistic operations
  /// Also recalculates member availability for affected events
  List<AssignmentSlot> _mergeSlotsWithOptimisticUpdates(
    List<AssignmentSlot> databaseSlots,
    Map<String, PendingOperation> pendingOperations,
  ) {
    if (pendingOperations.isEmpty) {
      return databaseSlots;
    }

    // Remove expired operations (older than 5 seconds)
    final activeOperations = Map<String, PendingOperation>.fromEntries(
      pendingOperations.entries.where((entry) => !entry.value.isExpired),
    );

    // CRITICAL FIX: Track slots with delete operations (including expired ones)
    // This ensures deleted slots stay empty even after operations expire
    // IMPORTANT: Only include a slot in deletedSlots if the CURRENT operation is DELETE
    // If a slot has CREATE/UPDATE, it's not deleted even if there was an old DELETE op
    final deletedSlots = <String>{}; // Set of slotKeys that were deleted
    for (final operation in pendingOperations.values) {
      if (operation.type == PendingOperationType.deleteAssignment) {
        deletedSlots.add(operation.slotKey);
      } else if (operation.type == PendingOperationType.createAssignment ||
          operation.type == PendingOperationType.updateAssignment) {
        // Slot has CREATE/UPDATE, so it's NOT deleted (remove from set if present)
        deletedSlots.remove(operation.slotKey);
      }
    }

    // Group pending operations by event ID (only active ones for processing)
    final operationsByEvent = <String, List<PendingOperation>>{};
    for (final operation in activeOperations.values) {
      final eventId = operation.slotKey.split('_')[0];
      operationsByEvent.putIfAbsent(eventId, () => []).add(operation);
    }

    // CRITICAL FIX: Also add events that have deleted slots, even if no active ops
    // This ensures member lists are recalculated even after operations expire
    for (final slotKey in deletedSlots) {
      final eventId = slotKey.split('_')[0];
      operationsByEvent.putIfAbsent(
          eventId, () => []); // Add empty list if not present
    }

    // Build a map of slots by event for efficient updates
    final slotsByEvent = <String, List<AssignmentSlot>>{};
    for (final slot in databaseSlots) {
      slotsByEvent.putIfAbsent(slot.event.id, () => []).add(slot);
    }

    // Process each event that has pending operations
    for (final entry in operationsByEvent.entries) {
      final eventId = entry.key;
      final operations = entry.value;
      final eventSlots = slotsByEvent[eventId] ?? [];

      if (eventSlots.isEmpty) continue;

      // CRITICAL FIX: Rebuild effectiveAssignedMemberIds from scratch to avoid cross-slot interference
      // Instead of modifying a set incrementally (which can remove members from wrong slots),
      // we build a fresh map of which member is assigned to which slot.

      // Map: slotKey -> member ID (null if empty)
      final slotAssignments = <String, String?>{};

      // Start with database assignments
      for (final slot in eventSlots) {
        if (slot.isOffQuota) continue;
        final slotKey = _getSlotKey(slot);
        slotAssignments[slotKey] = slot.currentAssignment?.teamMemberId;
      }

      // Apply pending operations (this overrides DB state for specific slots)
      for (final operation in operations) {
        final slotKey = operation.slotKey;

        if (operation.type == PendingOperationType.deleteAssignment) {
          slotAssignments[slotKey] = null; // Slot is now empty
        } else if (operation.type == PendingOperationType.createAssignment ||
            operation.type == PendingOperationType.updateAssignment) {
          if (operation.optimisticAssignment != null) {
            slotAssignments[slotKey] =
                operation.optimisticAssignment!.teamMemberId;
          }
        }
      }

      // Collect all non-null member IDs
      final effectiveAssignedMemberIds = slotAssignments.values
          .where((id) => id != null)
          .cast<String>()
          .toSet();

      // Recalculate member availability for all slots in this event
      for (final slot in eventSlots) {
        if (slot.isOffQuota) continue;
        final slotKey = _getSlotKey(slot);
        final operation = activeOperations[slotKey];

        // Build new member lists based on effective assigned IDs
        final availableMembersMap = <String, TeamMember>{};
        final alreadyAssignedMembersMap = <String, TeamMember>{};

        // Combine all members from both lists
        final allMembers = [
          ...slot.availableMembers,
          ...slot.alreadyAssignedMembers,
        ];

        for (final member in allMembers) {
          // Check capability
          if (!member.canPerformRole(slot.role.key)) continue;

          // Check availability for entire event duration (including time-based constraints)
          final isAvailable = member.isAvailableForEventWithTime(slot.event);

          if (!member.allowMultipleAssignments && !isAvailable) {
            continue;
          }

          // Separate based on effective assignment status
          if (member.allowMultipleAssignments) {
            availableMembersMap[member.id] = member;
          } else if (effectiveAssignedMemberIds.contains(member.id)) {
            alreadyAssignedMembersMap[member.id] = member;
          } else {
            availableMembersMap[member.id] = member;
          }
        }

        // Update the slot with recalculated member lists
        // Reset double assignment flags - will be recomputed after all updates
        final slotIndex = eventSlots.indexOf(slot);
        eventSlots[slotIndex] = AssignmentSlot(
          event: slot.event,
          role: slot.role,
          slotIndex: slot.slotIndex,
          currentAssignment: slot.currentAssignment,
          availableMembers: availableMembersMap.values.toList(),
          alreadyAssignedMembers: alreadyAssignedMembersMap.values.toList(),
          hasDoubleAssignment: false, // Will be recomputed
          otherRoles: const [], // Will be recomputed
        );
      }
    }

    // Now apply the optimistic currentAssignment changes
    // After this, we need to re-run double assignment detection for affected events
    final resultSlots = databaseSlots.map((dbSlot) {
      if (dbSlot.isOffQuota) return dbSlot;
      final slotKey = _getSlotKey(dbSlot);
      final operation = activeOperations[slotKey];

      // CRITICAL FIX: Check if this slot was deleted (even if operation expired)
      if (deletedSlots.contains(slotKey)) {
        // This slot was deleted - keep it empty even if DB has old data
        final eventSlots = slotsByEvent[dbSlot.event.id];
        final baseSlot = eventSlots != null
            ? eventSlots.firstWhere(
                (s) =>
                    s.role.key == dbSlot.role.key &&
                    s.slotIndex == dbSlot.slotIndex,
                orElse: () => dbSlot,
              )
            : dbSlot;
        return AssignmentSlot(
          event: baseSlot.event,
          role: baseSlot.role,
          slotIndex: baseSlot.slotIndex,
          currentAssignment: null,
          availableMembers: baseSlot.availableMembers,
          alreadyAssignedMembers: baseSlot.alreadyAssignedMembers,
          hasDoubleAssignment: false,
          otherRoles: const [],
        );
      }

      if (operation == null) {
        // No pending operation - use updated slot (if it was recalculated) or original
        final eventSlots = slotsByEvent[dbSlot.event.id];
        if (eventSlots != null) {
          final updatedSlot = eventSlots.firstWhere(
            (s) =>
                s.role.key == dbSlot.role.key &&
                s.slotIndex == dbSlot.slotIndex,
            orElse: () => dbSlot,
          );
          return updatedSlot;
        }
        return dbSlot;
      }

      // Apply optimistic operation to this slot
      if (operation.type == PendingOperationType.deleteAssignment) {
        final eventSlots = slotsByEvent[dbSlot.event.id];
        final baseSlot = eventSlots != null
            ? eventSlots.firstWhere(
                (s) =>
                    s.role.key == dbSlot.role.key &&
                    s.slotIndex == dbSlot.slotIndex,
                orElse: () => dbSlot,
              )
            : dbSlot;
        return AssignmentSlot(
          event: baseSlot.event,
          role: baseSlot.role,
          slotIndex: baseSlot.slotIndex,
          currentAssignment: null,
          availableMembers: baseSlot.availableMembers,
          alreadyAssignedMembers: baseSlot.alreadyAssignedMembers,
          hasDoubleAssignment: false,
          otherRoles: const [],
        );
      } else {
        // Create or Update
        final eventSlots = slotsByEvent[dbSlot.event.id];
        final baseSlot = eventSlots != null
            ? eventSlots.firstWhere(
                (s) =>
                    s.role.key == dbSlot.role.key &&
                    s.slotIndex == dbSlot.slotIndex,
                orElse: () => dbSlot,
              )
            : dbSlot;
        return AssignmentSlot(
          event: baseSlot.event,
          role: baseSlot.role,
          slotIndex: baseSlot.slotIndex,
          currentAssignment: operation.optimisticAssignment,
          availableMembers: baseSlot.availableMembers,
          alreadyAssignedMembers: baseSlot.alreadyAssignedMembers,
          hasDoubleAssignment: baseSlot.hasDoubleAssignment ?? false,
          otherRoles: baseSlot.otherRoles ?? const [],
        );
      }
    }).toList();

    // Re-run double assignment detection for affected events
    // This ensures hasDoubleAssignment and otherRoles are correct after optimistic updates
    for (final eventId in operationsByEvent.keys) {
      final eventResultSlots =
          resultSlots.where((s) => s.event.id == eventId).toList();

      for (final slot in eventResultSlots) {
        if (slot.isOffQuota) continue;
        if (slot.isFilled) {
          // Check if member has allowMultipleAssignments - skip double assignment warning
          final teamMember = slot.currentAssignment!.teamMember;
          final skipDoubleAssignmentWarning =
              teamMember?.allowMultipleAssignments ?? false;

          // Check if this person has other assignments in the same event
          final otherAssignments = eventResultSlots
              .where((s) =>
                  s.event.id == slot.event.id &&
                  s.isFilled &&
                  s.currentAssignment!.teamMemberId ==
                      slot.currentAssignment!.teamMemberId &&
                  s.role.key != slot.role.key)
              .toList();

          if (otherAssignments.isNotEmpty && !skipDoubleAssignmentWarning) {
            // This person has multiple roles in this event
            final otherRoleNames =
                otherAssignments.map((s) => s.role.hebrewName).toList();

            // Find and update this slot in resultSlots
            final slotIndex = resultSlots.indexOf(slot);
            resultSlots[slotIndex] = AssignmentSlot(
              event: slot.event,
              role: slot.role,
              slotIndex: slot.slotIndex,
              currentAssignment: slot.currentAssignment,
              availableMembers: slot.availableMembers,
              alreadyAssignedMembers: slot.alreadyAssignedMembers,
              hasDoubleAssignment: true,
              otherRoles: otherRoleNames,
            );
          }
        }
      }
    }

    return resultSlots;
  }

  /// Optimistic create assignment handler
  Future<void> _onOptimisticCreateAssignment(
    OptimisticCreateAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    if (state is! AssignmentSlotsLoaded) {
      _completeActionFailure(
        event.completion,
        'לא ניתן לעדכן שיבוץ בזמן שהמסך עדיין נטען',
      );
      return;
    }

    final currentState = state as AssignmentSlotsLoaded;

    // Create pending operation
    final operation = PendingOperation(
      id: event.operationId,
      type: PendingOperationType.createAssignment,
      slotKey: event.slotKey,
      optimisticAssignment: event.assignment,
      timestamp: DateTime.now(),
    );

    // Add to BLoC-level pending operations map
    _pendingOperations = Map<String, PendingOperation>.from(_pendingOperations);
    _pendingOperations[event.slotKey] = operation;

    // Apply optimistic update
    final updatedSlots = _applyOptimisticUpdate(
      currentState.slots,
      event.slotKey,
      event.assignment,
      isDelete: false,
    );

    _emitOrLog(emit, AssignmentSlotsLoaded(
      updatedSlots,
      selectedEventIds: currentState.selectedEventIds,
      pendingOperations: _pendingOperations,
    ));

    // Execute database operation
    try {
      if (event.bypassConflicts) {
        await _repository.createAssignmentWithBypass(event.assignment);
      } else {
        await _repository.createAssignment(event.assignment);
      }

      _syncAttendeesForAffectedEvents(nextAssignment: event.assignment);
      await _refreshExtraPastEvent(event.assignment.eventId);

      // CRITICAL FIX: Remove pending operation after successful write
      _pendingOperations.remove(event.slotKey);
      _emitOrLog(emit, AssignmentSlotsLoaded(
        updatedSlots,
        selectedEventIds: currentState.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
      _completeActionSuccess(event.completion, 'השיבוץ נוסף בהצלחה');
      add(RebuildAssignmentSlots(
          preservedFilter: currentState.selectedEventIds));
    } catch (e) {
      // On error: remove operation, revert to database state
      _pendingOperations.remove(event.slotKey);
      _emitOrLog(emit, AssignmentSlotsLoaded(
        currentState.slots,
        selectedEventIds: currentState.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
      final message = e is AssignmentConflictException
          ? e.conflicts.join(', ')
          : 'שגיאה בהוספת שיבוץ: $e';
      _completeActionFailure(event.completion, message);
    }
  }

  /// Optimistic update assignment handler
  Future<void> _onOptimisticUpdateAssignment(
    OptimisticUpdateAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    if (state is! AssignmentSlotsLoaded) {
      _completeActionFailure(
        event.completion,
        'לא ניתן לעדכן שיבוץ בזמן שהמסך עדיין נטען',
      );
      return;
    }

    final currentState = state as AssignmentSlotsLoaded;

    // Create pending operation
    final operation = PendingOperation(
      id: event.operationId,
      type: PendingOperationType.updateAssignment,
      slotKey: event.slotKey,
      optimisticAssignment: event.assignment,
      timestamp: DateTime.now(),
    );

    // Add to BLoC-level pending operations map
    _pendingOperations = Map<String, PendingOperation>.from(_pendingOperations);
    _pendingOperations[event.slotKey] = operation;

    // Apply optimistic update
    final updatedSlots = _applyOptimisticUpdate(
      currentState.slots,
      event.slotKey,
      event.assignment,
      isDelete: false,
    );

    _emitOrLog(emit, AssignmentSlotsLoaded(
      updatedSlots,
      selectedEventIds: currentState.selectedEventIds,
      pendingOperations: _pendingOperations,
    ));

    // Execute database operation
    try {
      final previousAssignment =
          await _repository.getAssignmentById(event.assignment.id);

      await _repository.updateAssignment(event.assignment);
      _syncAttendeesForAffectedEvents(
        previousAssignment: previousAssignment,
        nextAssignment: event.assignment,
      );
      await _refreshExtraPastEvent(event.assignment.eventId);
      if (previousAssignment != null &&
          previousAssignment.eventId != event.assignment.eventId) {
        await _refreshExtraPastEvent(previousAssignment.eventId);
      }
      // CRITICAL FIX: Remove pending operation after successful write
      _pendingOperations.remove(event.slotKey);
      _emitOrLog(emit, AssignmentSlotsLoaded(
        updatedSlots,
        selectedEventIds: currentState.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
      _completeActionSuccess(event.completion, 'השיבוץ עודכן בהצלחה');
      add(RebuildAssignmentSlots(
          preservedFilter: currentState.selectedEventIds));
    } catch (e) {
      // On error: remove operation, revert to database state
      _pendingOperations.remove(event.slotKey);
      _emitOrLog(emit, AssignmentSlotsLoaded(
        currentState.slots,
        selectedEventIds: currentState.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
      final message = e is AssignmentConflictException
          ? e.conflicts.join(', ')
          : 'שגיאה בעדכון שיבוץ: $e';
      _completeActionFailure(event.completion, message);
    }
  }

  /// Optimistic delete assignment handler
  Future<void> _onOptimisticDeleteAssignment(
    OptimisticDeleteAssignment event,
    Emitter<AssignmentState> emit,
  ) async {
    if (state is! AssignmentSlotsLoaded) {
      _completeActionFailure(
        event.completion,
        'לא ניתן למחוק שיבוץ בזמן שהמסך עדיין נטען',
      );
      return;
    }

    final currentState = state as AssignmentSlotsLoaded;

    // Create pending operation
    final operation = PendingOperation(
      id: event.operationId,
      type: PendingOperationType.deleteAssignment,
      slotKey: event.slotKey,
      optimisticAssignment: null,
      timestamp: DateTime.now(),
    );

    // Add to BLoC-level pending operations map
    _pendingOperations = Map<String, PendingOperation>.from(_pendingOperations);
    _pendingOperations[event.slotKey] = operation;

    // Apply optimistic update (clear slot)
    final updatedSlots = _applyOptimisticUpdate(
      currentState.slots,
      event.slotKey,
      null,
      isDelete: true,
    );

    _emitOrLog(emit, AssignmentSlotsLoaded(
      updatedSlots,
      selectedEventIds: currentState.selectedEventIds,
      pendingOperations: _pendingOperations,
    ));

    // Execute database operation
    try {
      // Get assignment info BEFORE deleting for calendar sync
      final assignmentToDelete =
          await _repository.getAssignmentById(event.assignmentId);

      await _repository.deleteAssignment(event.assignmentId);

      // CRITICAL: Clear the cache to prevent stale data (same as swipe-to-delete)
      _repository.clearCache();

      // Sync calendar attendees (will remove the deleted attendee)
      _syncAttendeesForAffectedEvents(previousAssignment: assignmentToDelete);
      if (assignmentToDelete != null) {
        await _refreshExtraPastEvent(assignmentToDelete.eventId);
      }

      // CRITICAL FIX: Remove pending operation after successful delete
      _pendingOperations.remove(event.slotKey);
      _emitOrLog(emit, AssignmentSlotsLoaded(
        updatedSlots,
        selectedEventIds: currentState.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
      _completeActionSuccess(event.completion, 'השיבוץ נמחק בהצלחה');
      add(RebuildAssignmentSlots(
          preservedFilter: currentState.selectedEventIds));
    } catch (e) {
      // On error: remove operation, revert to database state
      _pendingOperations.remove(event.slotKey);
      _emitOrLog(emit, AssignmentSlotsLoaded(
        currentState.slots,
        selectedEventIds: currentState.selectedEventIds,
        pendingOperations: _pendingOperations,
      ));
      _completeActionFailure(event.completion, 'שגיאה במחיקת שיבוץ: $e');
    }
  }

  /// Notify calendar attendees for an assignment change — targeting ONLY the
  /// member who was actually added or removed, not the whole roster.
  ///
  /// Previously this re-pushed the entire attendee list for every affected
  /// event (SyncAttendeesForAppEvent), which made Google email every
  /// already-assigned member on each change. Now it dispatches a delta so the
  /// sync service can invite/cancel just the changed member (falling back to a
  /// full re-sync internally only for the invite-all roster transitions).
  ///
  /// Covers create ([nextAssignment] only), delete ([previousAssignment] only),
  /// role change / reassignment within one event (both, same eventId), and
  /// reassignment across events (both, different eventIds).
  void _syncAttendeesForAffectedEvents({
    Assignment? previousAssignment,
    Assignment? nextAssignment,
  }) {
    final calendarSyncBloc = _calendarSyncBloc;
    if (calendarSyncBloc == null) {
      return;
    }

    // Same event touched on both sides (role change or same-event reassignment)
    // → one delta carrying both the added and removed member.
    if (previousAssignment != null &&
        nextAssignment != null &&
        previousAssignment.eventId == nextAssignment.eventId) {
      calendarSyncBloc.add(SyncAttendeeForAssignmentChange(
        eventId: nextAssignment.eventId,
        addedMemberId: nextAssignment.teamMemberId,
        removedMemberId: previousAssignment.teamMemberId,
      ));
      return;
    }

    // Otherwise each side is its own event: the previous event loses a member,
    // the next event gains one.
    if (previousAssignment != null) {
      calendarSyncBloc.add(SyncAttendeeForAssignmentChange(
        eventId: previousAssignment.eventId,
        removedMemberId: previousAssignment.teamMemberId,
      ));
    }
    if (nextAssignment != null) {
      calendarSyncBloc.add(SyncAttendeeForAssignmentChange(
        eventId: nextAssignment.eventId,
        addedMemberId: nextAssignment.teamMemberId,
      ));
    }
  }

  /// If [eventId] is an event older than the window (its rows come from the
  /// extra-past cache, not the live stream), re-fetch its assignments so an
  /// edit/delete is reflected instead of being reverted by the next rebuild.
  Future<void> _refreshExtraPastEvent(String eventId) async {
    if (!_extraPastEventsMap.containsKey(eventId)) return;
    try {
      final freshEvent = await _eventRepository.getEventById(eventId);
      if (freshEvent == null) {
        _extraPastEventsMap.remove(eventId);
      } else {
        _extraPastEventsMap[eventId] = freshEvent;
      }
      final fresh = await _repository.getAssignmentsByEventIds([eventId]);
      _extraPastAssignments.removeWhere((a) => a.eventId == eventId);
      _extraPastAssignments.addAll(fresh);
    } catch (_) {
      // Best-effort; the next full reload will reconcile.
    }
  }

  /// Screen performed a direct-repository mutation (swipe-delete / quota
  /// reduce) on [event.eventId]. If that event lives in the extra-past cache
  /// (older than the window, loaded via "load more"), the live window stream
  /// can't cover it, so refresh its cache entry and rebuild. No-op for
  /// in-window events — the live stream already handles those.
  Future<void> _onExternalExtraPastMutation(
    ExternalExtraPastMutation event,
    Emitter<AssignmentState> emit,
  ) async {
    if (!_extraPastEventsMap.containsKey(event.eventId)) return;
    await _refreshExtraPastEvent(event.eventId);
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  /// Build complete slots state from assignments
  /// Fetches latest events and team members, then builds slot grid
  Future<AssignmentSlotsLoaded> _buildSlotsFromAssignments(
    List<Assignment> assignments, {
    Set<String>? selectedEventIds,
  }) async {
    // 1. Load all events
    var events = await _eventRepository.getAllEvents();

    // 2a. Deactivated events have no presence in the assignments grid
    events = events.where((event) => !event.isDeactivated).toList();

    // 2b. Filter events based on showPastEvents flag
    if (!FilterPersistence.showPastEvents) {
      final now = DateTime.now();
      // Only include events where end date >= today (start of day)
      final todayStart = DateTime(now.year, now.month, now.day);
      events = events
          .where((event) => event.endDate
              .isAfter(todayStart.subtract(const Duration(days: 1))))
          .toList();
    }

    // 3. Load all active team members
    final allMembers = await _teamRepository.getActiveTeamMembers();

    // 4. Load roles and sort by sortOrder.
    // Roles are global (window-independent) and kept live in _cachedRoles by
    // the watchRoles() subscription; reuse the cache instead of re-fetching on
    // every filter change. Fall back to a one-shot fetch if not yet seeded.
    final allRoles = _cachedRoles.isNotEmpty
        ? _cachedRoles
        : await _roleRepository.getAllRoles();
    // Sort a COPY so the shared _cachedRoles list is never mutated in place.
    final sortedRoles = [...allRoles]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Create a mapping from role key to Role for easy lookup
    final roleKeyToRole = <String, Role>{};
    for (final role in sortedRoles) {
      roleKeyToRole[role.key] = role;
    }

    // 5. Build slots
    final slots = <AssignmentSlot>[];

    for (final event in events) {
      final placedAssignmentIds = <String>{};
      // Iterate through roles in sortOrder (not enum order)
      for (final role in sortedRoles) {
        final requiredCount = event.roleRequirements[role.key] ?? 0;
        if (requiredCount == 0) continue; // Skip roles with 0 requirement

        // Get assignments for this event+role
        final roleAssignments = assignments
            .where((a) => a.eventId == event.id && a.roleType == role.key)
            .toList();

        // Create slots (one per required count)
        for (int i = 0; i < requiredCount; i++) {
          // Find if this slot is filled (match by slotIndex, not array position)
          final assignment = roleAssignments
              .cast<Assignment?>()
              .firstWhere((a) => a?.slotIndex == i, orElse: () => null);

          // CRITICAL: Verify the assignment still exists in the fresh assignment list
          // This prevents showing deleted assignments from stale cache
          if (assignment != null) {
            final stillExists = assignments.any((a) => a.id == assignment.id);
            if (!stillExists) {
              // Assignment was deleted, treat this slot as empty
              continue;
            }
          }

          // Get all assignments for this event to check who's already assigned
          final eventAssignments =
              assignments.where((a) => a.eventId == event.id).toList();
          final assignedMemberIds =
              eventAssignments.map((a) => a.teamMemberId).toSet();

          // Detect same-day assignments (members assigned to OTHER events on same day(s))
          final sameDayAssignedMembersMap = <String, TeamMember>{};
          final sameDayEventInfoMap = <String, List<String>>{};

          for (final otherAssignment in assignments) {
            // Skip assignments to THIS event
            if (otherAssignment.eventId == event.id) continue;

            // Find the other event
            final otherEvent = events.firstWhere(
              (e) => e.id == otherAssignment.eventId,
              orElse: () => event, // Fallback (shouldn't happen)
            );

            // Skip if event not found or is the same event
            if (otherEvent.id == event.id) continue;

            // Check if events share dates
            if (_eventsShareDate(event, otherEvent)) {
              final memberId = otherAssignment.teamMemberId;
              final member = allMembers.firstWhere(
                (m) => m.id == memberId,
                orElse: () => allMembers.first, // Fallback
              );

              // Only add if member has the capability for current role and doesn't allow multiple assignments
              if (member.canPerformRole(role.key) &&
                  !member.allowMultipleAssignments) {
                // Check availability (same logic as normal available members)
                final isAvailable = member.isAvailableForEventWithTime(event);
                if (isAvailable) {
                  sameDayAssignedMembersMap[memberId] = member;
                  sameDayEventInfoMap.putIfAbsent(memberId, () => []);
                  sameDayEventInfoMap[memberId]!.add(otherEvent.name);
                }
              }
            }
          }

          // Separate members into available (not assigned to this event)
          // and already assigned (assigned to this event)
          // Use Maps to prevent duplicates
          final availableMembersMap = <String, TeamMember>{};
          final alreadyAssignedMembersMap = <String, TeamMember>{};

          for (final member in allMembers) {
            // Check capability
            if (!member.canPerformRole(role.key)) continue;

            // Check availability for entire event duration (including time-based constraints)
            // Skip availability check for members with allowMultipleAssignments
            final isAvailable = member.isAvailableForEventWithTime(event);
            if (!member.allowMultipleAssignments && !isAvailable) {
              continue;
            }

            // Separate based on whether already assigned to this event
            // Members with allowMultipleAssignments always go to available list
            if (member.allowMultipleAssignments) {
              availableMembersMap[member.id] = member;
            } else if (assignedMemberIds.contains(member.id)) {
              alreadyAssignedMembersMap[member.id] = member;
            } else if (sameDayAssignedMembersMap.containsKey(member.id)) {
              // Member is assigned to another event on the same day - don't add to available
              continue;
            } else {
              availableMembersMap[member.id] = member;
            }
          }

          final availableMembers = availableMembersMap.values.toList();
          final alreadyAssignedMembers =
              alreadyAssignedMembersMap.values.toList();
          final sameDayAssignedMembers =
              sameDayAssignedMembersMap.values.toList();

          slots.add(AssignmentSlot(
            event: event,
            role: role,
            slotIndex: i,
            currentAssignment: assignment,
            availableMembers: availableMembers,
            alreadyAssignedMembers: alreadyAssignedMembers,
            sameDayAssignedMembers: sameDayAssignedMembers,
            sameDayEventInfo: sameDayEventInfoMap,
          ));
          if (assignment != null) placedAssignmentIds.add(assignment.id);
        }
      }

      final eventAssignmentsAll =
          assignments.where((a) => a.eventId == event.id).toList();
      slots.addAll(
        _buildOffQuotaSlots(event, eventAssignmentsAll, placedAssignmentIds),
      );
    }

    // 6. Detect double assignments (person assigned to multiple roles in same event)
    // Skip for members with allowMultipleAssignments since it's expected behavior
    final slotsWithDoubleAssignmentDetection = <AssignmentSlot>[];
    for (final slot in slots) {
      if (slot.isOffQuota) {
        slotsWithDoubleAssignmentDetection.add(slot);
        continue;
      }
      if (slot.isFilled) {
        // Check if member has allowMultipleAssignments - skip double assignment warning
        final teamMember = slot.currentAssignment!.teamMember;
        final skipDoubleAssignmentWarning =
            teamMember?.allowMultipleAssignments ?? false;

        // Check if this person has other assignments in the same event
        final otherAssignments = slots
            .where((s) =>
                s.event.id == slot.event.id &&
                s.isFilled &&
                s.currentAssignment!.teamMemberId ==
                    slot.currentAssignment!.teamMemberId &&
                s.role.key != slot.role.key)
            .toList();

        if (otherAssignments.isNotEmpty && !skipDoubleAssignmentWarning) {
          // This person has multiple roles in this event
          final otherRoleNames =
              otherAssignments.map((s) => s.role.hebrewName).toList();
          slotsWithDoubleAssignmentDetection.add(AssignmentSlot(
            event: slot.event,
            role: slot.role,
            slotIndex: slot.slotIndex,
            currentAssignment: slot.currentAssignment,
            availableMembers: slot.availableMembers,
            alreadyAssignedMembers: slot.alreadyAssignedMembers,
            hasDoubleAssignment: true,
            otherRoles: otherRoleNames,
          ));
        } else {
          slotsWithDoubleAssignmentDetection.add(slot);
        }
      } else {
        slotsWithDoubleAssignmentDetection.add(slot);
      }
    }

    // 7. Sort slots deterministically so same-role rows do not flip order.
    slotsWithDoubleAssignmentDetection.sort(_compareAssignmentSlots);

    return AssignmentSlotsLoaded(
      slotsWithDoubleAssignmentDetection,
      selectedEventIds: selectedEventIds ?? {},
    );
  }

  /// Apply event filter to current slots
  Future<void> _onApplyEventFilter(
    ApplyEventFilter event,
    Emitter<AssignmentState> emit,
  ) async {
    // Remember the filter
    _currentEventFilter = event.eventIds;

    // Trigger immediate rebuild with new filter
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  /// Clear event filter
  Future<void> _onClearEventFilter(
    ClearEventFilter event,
    Emitter<AssignmentState> emit,
  ) async {
    // Clear in-memory filter
    _currentEventFilter = <String>{};

    // Trigger immediate rebuild with cleared filter
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  /// Internal handler to rebuild slots (triggered by streams or filter changes)
  Future<void> _onRebuildAssignmentSlots(
    RebuildAssignmentSlots event,
    Emitter<AssignmentState> emit,
  ) async {
    try {
      // Determine which filter to use:
      // 1. If the event provides a filter (explicit change), use it
      // 2. Otherwise, use the last known filter stored in _currentEventFilter
      final filterToUse = event.preservedFilter ?? _currentEventFilter;

      // Keep the internal field in sync
      _currentEventFilter = filterToUse;

      // Build slots from database data (base state)
      final databaseSlots = await _buildSlotsFromAssignments(
        await _repository.getAllAssignments(),
        selectedEventIds: filterToUse,
      );

      // Merge optimistic updates on top of database state using BLoC-level pending operations
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        databaseSlots.slots,
        _pendingOperations,
      );

      final capped = _applyPastRevealCap(mergedSlots);

      _emitOrLog(emit, AssignmentSlotsLoaded(
        capped.slots,
        selectedEventIds: filterToUse,
        pendingOperations: _pendingOperations,
        hasMorePast: capped.hasMore,
        isLoadingMorePast: _loadingMorePast,
      ));
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Rebuild slots using pre-loaded data (for real-time updates)
  Future<void> _onRebuildAssignmentSlotsFromData(
    RebuildAssignmentSlotsFromData rebuildEvent,
    Emitter<AssignmentState> emit,
  ) async {
    try {
      // First-paint gate: until the roles, events, and assignments streams have
      // each streamed once (see _onLoadAssignmentSlots), suppress the emit and
      // keep the spinner up rather than flash an empty/partial grid. All three
      // flip true within ~150ms of load; once ready they stay ready, so live
      // updates after first paint are never suppressed.
      if (!_slotsRolesReady || !_slotsEventsReady || !_slotsAssignmentsReady) {
        return;
      }

      // Update the repository's cached assignments
      _repository.cacheCurrentAssignments(rebuildEvent.assignments);

      // Merge the live window data with the extra-past cache (populated by
      // the load-more handler) so history rows beyond the 90-day window can
      // be revealed without disturbing the window's own live stream data.
      final mergedEvents = <String, Event>{
        ...rebuildEvent.events,
        ..._extraPastEventsMap,
      };
      final mergedAssignmentsById = <String, Assignment>{
        for (final a in rebuildEvent.assignments) a.id: a,
        for (final a in _extraPastAssignments) a.id: a,
      };
      final mergedAssignments = mergedAssignmentsById.values.toList();

      // Convert maps to lists for the build method
      final eventsList = mergedEvents.values.toList();
      final teamMembersMap = rebuildEvent.teamMembers;
      final teamMembers = rebuildEvent.teamMembers.values.toList();

      // Read roles from the cache (seeded at load, refreshed by the watchRoles
      // listener) instead of re-fetching on every rebuild. Sort a COPY so the
      // cached list is never mutated in place.
      final sortedRoles = [..._cachedRoles]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      // Create a mapping from role key to Role for easy lookup
      final roleKeyToRole = <String, Role>{};
      for (final role in sortedRoles) {
        roleKeyToRole[role.key] = role;
      }

      // Deactivated events have no presence in the assignments grid
      var filteredEvents =
          eventsList.where((e) => !e.isDeactivated).toList();

      // Filter events based on showPastEvents flag
      if (!FilterPersistence.showPastEvents) {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        filteredEvents = filteredEvents
            .where((e) =>
                e.endDate.isAfter(todayStart.subtract(const Duration(days: 1))))
            .toList();
      }

      // Build slots using the existing method
      final slots = <AssignmentSlot>[];
      for (final eventData in filteredEvents) {
        final placedAssignmentIds = <String>{};
        // Iterate through roles in sortOrder (not enum order)
        for (final role in sortedRoles) {
          final requiredCount = eventData.roleRequirements[role.key] ?? 0;
          if (requiredCount == 0) continue; // Skip roles with 0 requirement

          // Get assignments for this event+role from the assignments list
          final roleAssignments = mergedAssignments
              .where((a) => a.eventId == eventData.id && a.roleType == role.key)
              .map((a) => a.withRelations(
                    event: eventData,
                    teamMember: teamMembersMap[a.teamMemberId] ?? a.teamMember,
                  ))
              .toList();

          // Create slots (one per required count)
          for (int i = 0; i < requiredCount; i++) {
            // Find if this slot is filled (match by slotIndex, not array position)
            final assignment = roleAssignments
                .cast<Assignment?>()
                .firstWhere((a) => a?.slotIndex == i, orElse: () => null);

            // Get all assignments for this event to check who's already assigned
            final eventAssignments = mergedAssignments
                .where((a) => a.eventId == eventData.id)
                .toList();
            final assignedMemberIds =
                eventAssignments.map((a) => a.teamMemberId).toSet();

            // Detect same-day assignments (members assigned to OTHER events on same day(s))
            final sameDayAssignedMembersMap = <String, TeamMember>{};
            final sameDayEventInfoMap = <String, List<String>>{};

            for (final otherAssignment in mergedAssignments) {
              // Skip assignments to THIS event
              if (otherAssignment.eventId == eventData.id) continue;

              // Find the other event
              final otherEvent = mergedEvents[otherAssignment.eventId];

              // Skip if event not found
              if (otherEvent == null) continue;

              // Deactivated events do not generate conflicts —
              // their assignments are preserved but treated as inactive.
              if (otherEvent.isDeactivated) continue;

              // Check if events share dates
              if (_eventsShareDate(eventData, otherEvent)) {
                final memberId = otherAssignment.teamMemberId;
                final member = teamMembersMap[memberId];

                // Skip if member not found
                if (member == null) continue;

                // Only add if member has the capability for current role and doesn't allow multiple assignments
                if (member.canPerformRole(role.key) &&
                    !member.allowMultipleAssignments) {
                  // Check availability (same logic as normal available members)
                  final isAvailable =
                      member.isAvailableForEventWithTime(eventData);
                  if (isAvailable) {
                    sameDayAssignedMembersMap[memberId] = member;
                    sameDayEventInfoMap.putIfAbsent(memberId, () => []);
                    sameDayEventInfoMap[memberId]!.add(otherEvent.name);
                  }
                }
              }
            }

            // Separate members into available (not assigned to this event)
            // and already assigned (assigned to this event)
            // Use Maps to prevent duplicates
            final availableMembersMap = <String, TeamMember>{};
            final alreadyAssignedMembersMap = <String, TeamMember>{};

            for (final member in teamMembers) {
              // Check capability
              if (!member.canPerformRole(role.key)) {
                continue;
              }

              // Check availability for entire event duration (including time-based constraints)
              // Skip availability check for members with allowMultipleAssignments
              final isAvailable = member.isAvailableForEventWithTime(eventData);
              if (!member.allowMultipleAssignments && !isAvailable) {
                continue;
              }

              // Separate based on whether already assigned to this event
              // Members with allowMultipleAssignments always go to available list
              if (member.allowMultipleAssignments) {
                availableMembersMap[member.id] = member;
              } else if (assignedMemberIds.contains(member.id)) {
                alreadyAssignedMembersMap[member.id] = member;
              } else if (sameDayAssignedMembersMap.containsKey(member.id)) {
                // Member is assigned to another event on the same day - don't add to available
                continue;
              } else {
                availableMembersMap[member.id] = member;
              }
            }

            final availableMembers = availableMembersMap.values.toList();
            final alreadyAssignedMembers =
                alreadyAssignedMembersMap.values.toList();
            final sameDayAssignedMembers =
                sameDayAssignedMembersMap.values.toList();

            slots.add(AssignmentSlot(
              event: eventData,
              role: role,
              slotIndex: i,
              currentAssignment: assignment,
              availableMembers: availableMembers,
              alreadyAssignedMembers: alreadyAssignedMembers,
              sameDayAssignedMembers: sameDayAssignedMembers,
              sameDayEventInfo: sameDayEventInfoMap,
            ));
            if (assignment != null) placedAssignmentIds.add(assignment.id);
          }
        }

        final eventAssignmentsAll = mergedAssignments
            .where((a) => a.eventId == eventData.id)
            .map((a) => a.withRelations(
                  event: eventData,
                  teamMember: teamMembersMap[a.teamMemberId] ?? a.teamMember,
                ))
            .toList();
        slots.addAll(
          _buildOffQuotaSlots(eventData, eventAssignmentsAll, placedAssignmentIds),
        );
      }

      // Detect double assignments
      final slotsWithDoubleAssignmentDetection = <AssignmentSlot>[];
      for (final slot in slots) {
        if (slot.isOffQuota) {
          slotsWithDoubleAssignmentDetection.add(slot);
          continue;
        }
        if (slot.isFilled) {
          // Check if member has allowMultipleAssignments - skip double assignment warning
          final teamMember = slot.currentAssignment!.teamMember;
          final skipDoubleAssignmentWarning =
              teamMember?.allowMultipleAssignments ?? false;

          // Check if this person has other assignments in the same event
          final otherAssignments = slots
              .where((s) =>
                  s.event.id == slot.event.id &&
                  s.isFilled &&
                  s.currentAssignment!.teamMemberId ==
                      slot.currentAssignment!.teamMemberId &&
                  s.role.key != slot.role.key)
              .toList();

          if (otherAssignments.isNotEmpty && !skipDoubleAssignmentWarning) {
            // This person has multiple roles in this event
            final otherRoleNames =
                otherAssignments.map((s) => s.role.hebrewName).toList();
            slotsWithDoubleAssignmentDetection.add(AssignmentSlot(
              event: slot.event,
              role: slot.role,
              slotIndex: slot.slotIndex,
              currentAssignment: slot.currentAssignment,
              availableMembers: slot.availableMembers,
              alreadyAssignedMembers: slot.alreadyAssignedMembers,
              hasDoubleAssignment: true,
              otherRoles: otherRoleNames,
            ));
          } else {
            slotsWithDoubleAssignmentDetection.add(slot);
          }
        } else {
          slotsWithDoubleAssignmentDetection.add(slot);
        }
      }

      // Sort slots deterministically so same-role rows do not flip order.
      slotsWithDoubleAssignmentDetection.sort(_compareAssignmentSlots);

      // Apply filter if needed
      final filteredSlots = rebuildEvent.selectedEventIds.isNotEmpty
          ? slotsWithDoubleAssignmentDetection
              .where((slot) =>
                  rebuildEvent.selectedEventIds.contains(slot.event.id))
              .toList()
          : slotsWithDoubleAssignmentDetection;

      // Remember the filter
      _currentEventFilter = rebuildEvent.selectedEventIds;

      // Merge optimistic updates on top of database state using BLoC-level pending operations
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        filteredSlots,
        _pendingOperations,
      );

      final capped = _applyPastRevealCap(mergedSlots);

      _emitOrLog(emit, AssignmentSlotsLoaded(
        capped.slots,
        selectedEventIds: rebuildEvent.selectedEventIds,
        pendingOperations: _pendingOperations,
        hasMorePast: capped.hasMore,
        isLoadingMorePast: _loadingMorePast,
      ));
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בבניית שיבוצים: $e'));
    }
  }

  /// Create new assignment bypassing conflict checks (for manual assignments)
  Future<void> _onCreateAssignmentWithBypass(
    CreateAssignmentWithBypass event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentOperating('creating'));

    try {
      // Skip conflict checks for bypass assignments
      await _repository.createAssignmentWithBypass(event.assignment);

      _syncAttendeesForAffectedEvents(nextAssignment: event.assignment);
      await _refreshExtraPastEvent(event.assignment.eventId);

      _emitOrLog(emit, const AssignmentOperationSuccess('השיבוץ נוסף בהצלחה'));
      _completeActionSuccess(event.completion, 'השיבוץ נוסף בהצלחה');

      // No manual reload: the active Firestore stream subscription
      // (emit.forEach in _onLoadAssignments / _onLoadAssignmentsByEvent /
      // _onLoadAssignmentsByPerson, or _assignmentSubscription for slots view)
      // will emit the updated list automatically once the write propagates.
      // Dispatching another Load* here would re-subscribe and cause a brief
      // AssignmentLoading flash plus a redundant _populateAssignmentRelations.
    } catch (e) {
      if (e is AssignmentConflictException) {
        _emitOrLog(emit, AssignmentConflictWarning(e.conflicts, event.assignment));
        _completeActionFailure(event.completion, e.conflicts.join(', '));
        // Note: Real-time stream will automatically update UI, no manual reload needed
      } else {
        final message = 'שגיאה ביצירת שיבוץ: $e';
        _emitOrLog(emit, AssignmentError(message));
        _completeActionFailure(event.completion, message);
      }
    }
  }

  /// Load user assignments with real-time updates for both assignments AND events
  /// This ensures UI updates when event details change or events are deleted
  Future<void> _onLoadUserAssignments(
    LoadUserAssignments event,
    Emitter<AssignmentState> emit,
  ) async {
    _emitOrLog(emit, const AssignmentLoading());

    try {
      // Cancel any competing subscriptions from other modes. The list-mode
      // cancel is critical here: a lingering all/by-event/by-person forEach left
      // over from a prior load would otherwise keep emitting the full (or a
      // differently-filtered) assignment list into THIS user's state.
      await _cancelSlotsSubscriptions();
      await _cancelUserAssignmentsSubscriptions();
      await _cancelListSubscriptions();

      // Subscribe to assignments stream for this user.
      //
      // watchAssignmentsByPerson already POPULATES relations (event/teamMember)
      // exactly like getAssignmentsByPerson, so we pass its payload straight
      // through to the rebuild instead of re-fetching the same data — this is
      // the redundant round-trip the live log surfaced. On error we fall back
      // to a re-fetch (null payload).
      _userAssignmentSubscription =
          _repository.watchAssignmentsByPerson(event.teamMemberId).listen(
        (assignments) {
          add(RebuildUserAssignments(
            event.teamMemberId,
            assignments: assignments,
          ));
        },
        onError: (e) {
          add(RebuildUserAssignments(event.teamMemberId));
        },
      );

      // Subscribe to events stream to detect changes/deletions.
      //
      // watchAssignmentsByPerson only re-emits on assignment-document changes,
      // NOT on event changes, so an event being deactivated/deleted does not
      // trigger the assignment stream. This listener forces a re-fetch (null
      // payload) so getAssignmentsByPerson re-populates FRESH event relations —
      // a now-deactivated event is then filtered out of the user's list.
      _userEventSubscription = _eventRepository.watchEvents().listen(
        (_) {
          add(RebuildUserAssignments(event.teamMemberId));
        },
        onError: (e) {
          add(RebuildUserAssignments(event.teamMemberId));
        },
      );

      // No explicit initial add: both Firestore snapshot streams emit on
      // subscribe (the assignment stream with a populated payload, the event
      // stream forcing the single initial fetch that populates fresh events),
      // so the load is covered without a third redundant rebuild.
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Internal handler to rebuild user assignments (triggered by streams).
  ///
  /// If [event.assignments] is provided (the populated watchAssignmentsByPerson
  /// payload) we use it directly — no re-fetch. Otherwise (watchEvents path /
  /// error fallback) we re-fetch so fresh event relations are re-populated,
  /// which is what makes a deactivated/deleted event drop from the list.
  Future<void> _onRebuildUserAssignments(
    RebuildUserAssignments event,
    Emitter<AssignmentState> emit,
  ) async {
    try {
      // Use the streamed (already-populated) payload when available; only
      // re-fetch when none was supplied (event-change/error paths).
      final allAssignments = event.assignments ??
          await _repository.getAssignmentsByPerson(event.teamMemberId);

      // Hide assignments whose event is deactivated — preserved in DB but
      // not shown to the user until the event is reactivated.
      final assignments = allAssignments
          .where((a) => a.event == null || !a.event!.isDeactivated)
          .toList();

      if (assignments.isEmpty) {
        _emitOrLog(emit, const AssignmentsEmpty('אין שיבוצים לחבר צוות זה'));
      } else {
        _emitOrLog(emit, AssignmentsLoaded.withCounts(
          assignments,
          filterType: 'person',
          filterId: event.teamMemberId,
        ));
      }
    } catch (e) {
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת שיבוצים: $e'));
    }
  }

  /// Update assignment notes and related admin metadata
  Future<void> _onUpdateAssignmentNotes(
    UpdateAssignmentNotes event,
    Emitter<AssignmentState> emit,
  ) async {
    final previousState = state;

    try {
      await _repository.updateAssignmentNotes(
        event.id,
        event.notes,
        alternativePhoneNumber: event.alternativePhoneNumber,
        semanticLabelId: event.semanticLabelId,
      );
      if (_extraPastEventsMap.isNotEmpty) {
        try {
          final fresh = await _repository
              .getAssignmentsByEventIds(_extraPastEventsMap.keys.toList());
          _extraPastAssignments
            ..clear()
            ..addAll(fresh);
        } catch (_) {
          // best-effort; next reload reconciles
        }
      }
      _emitOrLog(emit, const AssignmentOperationSuccess('פרטי השיבוץ עודכנו בהצלחה'));
      _completeActionSuccess(event.completion, 'פרטי השיבוץ עודכנו בהצלחה');

      // Keep Firestore streams as the single source of truth for note/label/phone
      // updates. A manual rebuild here can race with the stream and re-emit stale
      // slot data, which is exactly the behavior this screen was showing.
      if (previousState is! AssignmentSlotsLoaded &&
          previousState is! AssignmentsLoaded) {
        add(const RefreshAssignments());
      }
    } catch (e) {
      final message = 'שגיאה בעדכון פרטי השיבוץ: $e';
      _emitOrLog(emit, AssignmentError(message));
      _completeActionFailure(event.completion, message);
    }
  }

  /// Helper function to check if two events share at least one day
  bool _eventsShareDate(Event a, Event b) {
    // Normalize dates to day precision (ignore time)
    final aStart =
        DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final aEnd = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    final bStart =
        DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
    final bEnd = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);

    // Check for overlap: events overlap if one starts before the other ends
    return aStart.isBefore(bEnd.add(const Duration(days: 1))) &&
        bStart.isBefore(aEnd.add(const Duration(days: 1)));
  }

  /// Count how many display rows the given events would produce (quota slots +
  /// off-quota rows), for non-deactivated events. Lightweight mirror of the
  /// slot-build loops, used to decide how many older events to fetch per tap.
  int _countDisplayRows(Iterable<Event> events, List<Assignment> assignments) {
    var count = 0;
    for (final event in events) {
      if (event.isDeactivated) continue;
      final placed = <String>{};
      for (final role in _cachedRoles) {
        final required = event.roleRequirements[role.key] ?? 0;
        if (required == 0) continue;
        count += required;
        final roleAssignments = assignments
            .where((a) => a.eventId == event.id && a.roleType == role.key)
            .toList();
        for (int i = 0; i < required; i++) {
          Assignment? match;
          for (final a in roleAssignments) {
            if (a.slotIndex == i) {
              match = a;
              break;
            }
          }
          if (match != null) placed.add(match.id);
        }
      }
      count += assignments
          .where((a) => a.eventId == event.id && !placed.contains(a.id))
          .length;
    }
    return count;
  }

  /// Keep all window rows plus the first [_extraPastRowsRevealed] extra-past
  /// rows (rows for events older than the window). Only applies when past is
  /// shown; otherwise past rows are already removed by the showPastEvents
  /// filter. Returns the capped list and whether more history is available.
  ({List<AssignmentSlot> slots, bool hasMore}) _applyPastRevealCap(
      List<AssignmentSlot> sorted) {
    final windowStart = _slotsWindowStart;
    if (!FilterPersistence.showPastEvents || windowStart == null) {
      return (slots: sorted, hasMore: false);
    }
    final kept = <AssignmentSlot>[];
    var extraShown = 0;
    var extraTotal = 0;
    for (final slot in sorted) {
      final isExtraPast = slot.event.startDate.isBefore(windowStart);
      if (!isExtraPast) {
        kept.add(slot);
      } else {
        extraTotal++;
        if (extraShown < _extraPastRowsRevealed) {
          kept.add(slot);
          extraShown++;
        }
      }
    }
    final hasMore = extraShown < extraTotal || !_pastPagingExhausted;
    return (slots: kept, hasMore: hasMore);
  }

  /// Reveal the next 25 rows of history older than the 90-day window. Fetches
  /// older events (and their assignments) on demand until enough rows exist,
  /// then rebuilds with the extra-past cache merged in.
  Future<void> _onLoadMorePastAssignmentSlots(
    LoadMorePastAssignmentSlots event,
    Emitter<AssignmentState> emit,
  ) async {
    if (state is! AssignmentSlotsLoaded) return;
    final current = state as AssignmentSlotsLoaded;
    // Use the private flag as the authoritative re-entrancy guard: the state's
    // isLoadingMorePast can be stomped false by an unrelated concurrent rebuild.
    if (_loadingMorePast || !current.hasMorePast) return;

    _loadingMorePast = true;
    _emitOrLog(emit, current.copyWith(isLoadingMorePast: true));

    final target = _extraPastRowsRevealed + _pastLoadMoreRowChunk;

    try {
      while (!_pastPagingExhausted &&
          _countDisplayRows(_extraPastEventsMap.values, _extraPastAssignments) <
              target) {
        final cursor = _oldestLoadedEventStart;
        if (cursor == null) {
          _pastPagingExhausted = true;
          break;
        }
        final batch = await _eventRepository.getEventsBeforeDate(
          cursor,
          limit: _pastEventFetchBatch,
        );
        if (batch.isEmpty) {
          _pastPagingExhausted = true;
          break;
        }
        for (final e in batch) {
          _extraPastEventsMap[e.id] = e;
        }
        _oldestLoadedEventStart = batch
            .map((e) => e.startDate)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final freshIds = batch.map((e) => e.id).toList();
        final newAssignments =
            await _repository.getAssignmentsByEventIds(freshIds);
        _extraPastAssignments.addAll(newAssignments);
        if (batch.length < _pastEventFetchBatch) {
          _pastPagingExhausted = true;
        }
      }

      _extraPastRowsRevealed = target;

      // Clear the in-flight flag BEFORE the rebuild so its emit carries
      // isLoadingMorePast: _loadingMorePast == false.
      _loadingMorePast = false;

      // Rebuild from the live window data with the extra-past cache merged in.
      add(RebuildAssignmentSlotsFromData(
        _repository.getCurrentAssignments(),
        _windowEventsMap,
        _windowMembersMap,
        _currentEventFilter,
      ));
    } catch (e) {
      _loadingMorePast = false;
      _emitOrLog(emit, current.copyWith(isLoadingMorePast: false));
      _emitOrLog(emit, AssignmentError('שגיאה בטעינת היסטוריה: $e'));
    }
  }
}
