import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/debug/logger.dart';
import '../../../core/services/user_cache_service.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/event_sorting.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../core/utils/same_day_assignments.dart';
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
import 'models/assignment_conflict.dart';
import 'models/staged_assignment_change.dart';
import '../../screens/assignment/models/assignment_slot.dart';
import '../../screens/assignment/models/assignment_slot_annotations.dart';
import '../calendar_sync/calendar_sync_bloc.dart';

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
  DateTime?
      _slotsWindowStart; // now - 90d; boundary between window and "extra-past"

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
  bool _loadingMorePast =
      false; // authoritative in-flight guard (state field can be stomped by concurrent rebuilds)

  // Keep pending operations independent of state (survives error states)
  Map<String, PendingOperation> _pendingOperations = {};

  // --- Staged Save --------------------------------------------------------
  // Source of truth for unsaved slot edits, keyed by slotKey
  // ("${eventId}_${roleType}_${slotIndex}"). Mirrored to _userCache on every
  // change for crash recovery. Derived PendingOperations (tagged
  // `persistent: true`) are layered into _pendingOperations at the two
  // slots-view merge sites so the existing optimistic-merge machinery
  // renders them with no changes to the merge function itself.
  final Map<String, StagedAssignmentChange> _stagedChanges = {};

  // Baseline DB quota per "eventId_roleType", captured the first time a role
  // gets a staged quota-changing action. Conflict detection ONLY (type-G).
  final Map<String, int> _baselineQuota = {};

  final UserCacheService _userCache;

  /// True when there is at least one unsaved staged change.
  bool get hasStagedChanges => _stagedChanges.isNotEmpty;

  /// Number of unsaved staged changes. Unlike reading
  /// `state.stagedSlotKeys.length`, this is correct regardless of the
  /// bloc's currently emitted state (e.g. during `AssignmentOperating`
  /// while a save is in flight, when state is no longer
  /// `AssignmentSlotsLoaded`) — leave-guards must use this, not a
  /// state-type branch, to get an accurate count.
  int get stagedCount => _stagedChanges.length;

  /// True while a SaveStagedChanges write is in flight. Guards against a
  /// second concurrent SaveStagedChanges dispatch (flutter_bloc runs
  /// same-type events concurrently by default) double-submitting the same
  /// staged changes as two separate batch writes.
  bool _saveInFlight = false;

  AssignmentBloc(
    this._repository,
    this._eventRepository,
    this._teamRepository,
    this._roleRepository,
    this._calendarSyncBloc, {
    UserCacheService? userCacheService,
  })  : _userCache = userCacheService ?? UserCacheService(),
        super(const AssignmentInitial()) {
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
    on<StageMemberChange>(_onStageMemberChange);
    on<StageNotesChange>(_onStageNotesChange);
    on<StageSlotDeletion>(_onStageSlotDeletion);
    on<StageManualAdd>(_onStageManualAdd);
    on<DiscardStagedSlot>(_onDiscardStagedSlot);
    on<DiscardAllStagedChanges>(_onDiscardAllStagedChanges);
    on<RehydrateStagedChanges>(_onRehydrateStagedChanges);
    on<SaveStagedChanges>(_onSaveStagedChanges);
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
        _emitOrLog(
            emit, const AssignmentsEmpty('אין שיבוצים בטווח תאריכים זה'));
      } else {
        _emitOrLog(
            emit,
            AssignmentsLoaded.withCounts(
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
        _emitOrLog(
            emit, AssignmentConflictWarning(conflicts, event.assignment));
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
        _emitOrLog(
            emit, AssignmentConflictWarning(e.conflicts, event.assignment));
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
          _emitOrLog(
              emit, AssignmentConflictWarning(conflicts, event.assignment));
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
        _emitOrLog(
            emit, AssignmentConflictWarning(e.conflicts, event.assignment));
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
      // Read before deletion so the extra-past event cache can be refreshed.
      final assignmentToDelete = await _repository.getAssignmentById(event.id);

      await _repository.deleteAssignment(event.id);

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
      _emitOrLog(
          emit, const AssignmentOperationSuccess('סטטוס השיבוץ עודכן בהצלחה'));

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
      _oldestLoadedEventStart =
          windowStart; // fetch events strictly older than the window
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
          _slotsAssignmentsReady =
              true; // first-paint gate: assignments arrived
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

      // For all other slots, keep database state as-is
      if (_getSlotKey(slot) != targetSlotKey) return slot;

      // This is the target slot - apply the optimistic change.
      if (isDelete) return _emptied(slot);

      // The database member lists are deliberately carried over untouched.
      // sameDayOtherEvents is deliberately NOT: an update swaps the occupant,
      // and the mark on this slot belongs to the person on their way out —
      // carrying it over would pin their events on the incoming person. Cleared
      // here, then recomputed from the database on the next stream emit, exactly
      // as in _mergeSlotsWithOptimisticUpdates.
      return slot.copyWith(
        currentAssignment: optimisticAssignment,
        clearCurrentAssignment: optimisticAssignment == null,
        sameDayOtherEvents: const [],
      );
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

      // Recalculate member availability for all slots in this event.
      // Indexed, not indexOf: AssignmentSlot is Equatable, so indexOf matches by
      // VALUE and would rewrite the wrong row the moment two slots compared
      // equal.
      for (var i = 0; i < eventSlots.length; i++) {
        final slot = eventSlots[i];
        if (slot.isOffQuota) continue;

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

        // Update the slot with recalculated member lists.
        // Reset the double-assignment flags — annotateDoubleAssignments below
        // recomputes them (it only ever SETS the flag, never clears it, so the
        // reset here is what lets a no-longer-double assignment go back to
        // false).
        //
        // copyWith, never the raw constructor: a hand-rebuilt slot silently
        // drops every field the call forgets. This loop runs over EVERY slot of
        // any event with a pending operation, and the `operation == null` branch
        // below hands these rebuilt slots straight back — so a raw rebuild here
        // erased sameDayOtherEvents from every row of an event the moment
        // anyone in it was assigned.
        eventSlots[i] = slot.copyWith(
          availableMembers: availableMembersMap.values.toList(),
          alreadyAssignedMembers: alreadyAssignedMembersMap.values.toList(),
          hasDoubleAssignment: false,
          otherRoles: const [],
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
        return _emptied(baseSlot);
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
        return _emptied(baseSlot);
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
        final optimistic = operation.optimisticAssignment;
        // sameDayOtherEvents is cleared, not inherited: an UPDATE swaps the
        // occupant, and baseSlot's mark describes the person on their way OUT.
        // This function cannot recompute the incoming person's mark (it has no
        // access to the full event/assignment window), and inheriting the old
        // one would pin the wrong events on the wrong person. Empty is the
        // honest answer until the stream re-emits — see the note below.
        // hasDoubleAssignment/otherRoles need no such care: they are recomputed
        // wholesale by annotateDoubleAssignments below.
        return baseSlot.copyWith(
          currentAssignment: optimistic,
          clearCurrentAssignment: optimistic == null,
          sameDayOtherEvents: const [],
        );
      }
    }).toList();

    // Re-run double-assignment detection over the merged result, using the very
    // same pass the two slot-build paths run, so the grid cannot disagree with
    // itself about who is double-booked.
    //
    // Deliberately NOT recomputed here: sameDayOtherEvents. Deriving it needs
    // the full event + assignment window, which the merge does not have; all it
    // can do is carry through what the database slot already worked out (hence
    // the copyWith calls above — a raw rebuild drops it). The practical effect
    // is that a newly-assigned person's OWN mark appears one stream emit later,
    // while every already-marked row keeps its mark throughout. The same lag
    // has a symmetric half in the other direction: when M is instead REMOVED
    // from E (a delete, or an update that swaps M out), M's row in the OTHER
    // event O still names E until the stream re-emits — a stale mark, not a
    // missing one, and mildly worse. Both directions are bounded by the same
    // Firestore round-trip and the feature is advisory, so this is fine to
    // ship: the admin was already warned at assign time by the
    // "בעלי מגבלות / שבץ בכל זאת" dialog. Do not "fix" this by hand-rebuilding
    // slots here — that is exactly what dropped the field in the first place.
    return annotateDoubleAssignments(resultSlots);
  }

  /// A slot with its assignment removed, keeping everything the row still needs
  /// (member lists, same-day candidate info). The double-assignment flags and
  /// sameDayOtherEvents go with the person who left: both describe the occupant,
  /// and AssignmentSlot documents sameDayOtherEvents as empty on an unfilled
  /// slot, so keeping it would paint a mark on an empty row.
  AssignmentSlot _emptied(AssignmentSlot slot) => slot.copyWith(
        clearCurrentAssignment: true,
        hasDoubleAssignment: false,
        otherRoles: const [],
        sameDayOtherEvents: const [],
      );

  // ===========================================================================
  // Staged Save
  //
  // Edits are staged in _stagedChanges (not written through to the database)
  // until an explicit Save. Each staged change is keyed by slotKey and mirrored
  // to UserCacheService so an unsaved edit survives a crash/reload.
  // _stagedAsPendingOperations() converts the map to persistent PendingOperations
  // that are layered into _pendingOperations at the two slots-view merge sites
  // (see _syncPendingOperationsWithStaged), so the existing
  // _mergeSlotsWithOptimisticUpdates renders staged edits with no changes to
  // the merge function itself.
  // ===========================================================================

  String _slotKey(AssignmentSlot slot) => StagedAssignmentChange.slotKeyFor(
      slot.event.id, slot.role.key, slot.slotIndex);

  /// Seed a fresh staged change from the slot's current DB occupant, which
  /// becomes the baseline (null occupant => the slot started empty).
  StagedAssignmentChange _seedStaged(AssignmentSlot slot) {
    final db = slot.currentAssignment;
    return StagedAssignmentChange(
      slotKey: _slotKey(slot),
      eventId: slot.event.id,
      roleType: slot.role.key,
      slotIndex: slot.slotIndex,
      desiredMemberId: db?.teamMemberId,
      desiredNotes: db?.notes ?? '',
      desiredSemanticLabelId: db?.semanticLabelId,
      desiredAltPhone: db?.alternativePhoneNumber,
      baselineAssignmentId: db?.id,
      baselineMemberId: db?.teamMemberId,
      baselineNotes: db?.notes ?? '',
      baselineSemanticLabelId: db?.semanticLabelId,
      baselineAltPhone: db?.alternativePhoneNumber,
      desiredAssignmentId: db?.id ?? const Uuid().v4(),
      stagedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Store [change] under [key], or drop it if it reverts to baseline; then
  /// mirror to cache. Awaited by callers (never left fire-and-forget) so the
  /// cache reliably reflects the latest state for crash-recovery.
  ///
  /// Task 12 (carry): when a revert-to-baseline empties out the LAST staged
  /// change for [change]'s (event, role), also drop that role's captured
  /// `_baselineQuota` entry — mirroring the per-role clear
  /// [_onDiscardStagedSlot] already does. Without this, a stale baseline
  /// from this reverted session would leak into the next staging session on
  /// the same role (mis-deriving its quota / a phantom type-G conflict).
  Future<void> _commitStaged(String key, StagedAssignmentChange change) async {
    if (change.matchesBaseline) {
      _stagedChanges.remove(key);
      final roleStillStaged = _stagedChanges.values.any((c) =>
          c.eventId == change.eventId && c.roleType == change.roleType);
      if (!roleStillStaged) {
        _baselineQuota.remove(_eventRoleKey(change.eventId, change.roleType));
      }
    } else {
      _stagedChanges[key] = change;
    }
    await _persistStaged();
  }

  /// Stage a member fill/swap/clear (memberId == null => clear).
  Future<void> _upsertStagedMember(
      AssignmentSlot slot, String? memberId) async {
    final key = _slotKey(slot);
    final base = _stagedChanges[key] ?? _seedStaged(slot);
    await _commitStaged(key, base.copyWith(desiredMemberId: () => memberId));
  }

  /// Stage a notes/label/alt-phone edit (member left unchanged).
  Future<void> _upsertStagedNotes(AssignmentSlot slot, String notes,
      String? labelId, String? altPhone) async {
    final key = _slotKey(slot);
    final base = _stagedChanges[key] ?? _seedStaged(slot);
    await _commitStaged(
      key,
      base.copyWith(
        desiredNotes: notes,
        desiredSemanticLabelId: () => labelId,
        desiredAltPhone: () => altPhone,
      ),
    );
  }

  /// Task 12: persists BOTH the staged-change list and the derived-quota
  /// `_baselineQuota` snapshot, wrapped in one JSON object, so a reload can
  /// restore the REAL baseline captured at first quota-touch instead of
  /// re-deriving one from whatever the live DB quota happens to be later.
  Future<void> _persistStaged() async {
    final payload = jsonEncode({
      'changes': _stagedChanges.values.map((c) => c.toJson()).toList(),
      'baselineQuota': _baselineQuota,
    });
    await _userCache.savePendingAssignmentChanges(payload);
  }

  String _eventRoleKey(String eventId, String roleType) =>
      '${eventId}_$roleType';

  int _liveQuota(String eventId, String roleType) {
    final ev = _windowEventsMap[eventId] ?? _extraPastEventsMap[eventId];
    return ev?.roleRequirements[roleType] ?? 0;
  }

  int _baselineQuotaFor(String eventId, String roleType) {
    final key = _eventRoleKey(eventId, roleType);
    return _baselineQuota.putIfAbsent(key, () => _liveQuota(eventId, roleType));
  }

  /// The captured baseline quota if one was seeded, else the live DB quota.
  /// Read-only: unlike [_baselineQuotaFor] this does NOT seed the map, so the
  /// per-role derived-quota reads (called on every grid rebuild by Task 7)
  /// stay side-effect-free.
  int _resolvedBaseline(String eventId, String roleType) =>
      _baselineQuota[_eventRoleKey(eventId, roleType)] ??
      _liveQuota(eventId, roleType);

  /// Staged fills beyond the baseline quota (manual adds) — used by Task 7
  /// rendering to know how many extra rows to draw for a role.
  ///
  /// Returns 0 when `_baselineQuota` was never explicitly seeded for this
  /// (event, role) — i.e. neither `StageManualAdd` nor `StageSlotDeletion`
  /// has ever touched it. This guard matters because a plain
  /// `StageMemberChange` fill of an ordinary (then in-quota) empty slot does
  /// NOT seed `_baselineQuota`. Without the guard, `_resolvedBaseline` would
  /// fall back to the LIVE quota, and a later CONCURRENT/unrelated DB quota
  /// reduction could drop that live quota to/below the fill's slotIndex,
  /// making the ordinary fill look like ">= baseline" and get misclassified
  /// as a manual add — silently re-growing the grid to keep the row
  /// in-quota instead of surfacing the real conflict via
  /// classifyStagedConflicts's slotVanished path (see
  /// assignment_conflict_test.dart, "classifies a staged fill whose slot no
  /// longer exists as slotVanished").
  int _stagedAddCount(String eventId, String roleType) {
    final key = _eventRoleKey(eventId, roleType);
    final baseline = _baselineQuota[key];
    if (baseline == null) return 0;
    return _stagedChanges.values
        .where((c) =>
            c.eventId == eventId &&
            c.roleType == roleType &&
            !c.markedForDeletion &&
            c.baselineMemberId == null &&
            c.slotIndex >= baseline)
        .length;
  }

  int _inQuotaDeletionCount(String eventId, String roleType) {
    final baseline = _resolvedBaseline(eventId, roleType);
    return _stagedChanges.values
        .where((c) =>
            c.eventId == eventId &&
            c.roleType == roleType &&
            c.markedForDeletion &&
            c.slotIndex < baseline)
        .length;
  }

  /// The admin's intended quota for a role = baseline + adds − in-quota
  /// deletions, clamped to a sane [0, 999] range. `.toInt()` is required
  /// because `num.clamp()` (inherited by `int`) returns `num`, not `int` —
  /// see the same pattern in CalendarSyncBloc's poll-backoff clamp.
  int derivedQuota(String eventId, String roleType) {
    final baseline = _resolvedBaseline(eventId, roleType);
    return (baseline +
            _stagedAddCount(eventId, roleType) -
            _inQuotaDeletionCount(eventId, roleType))
        .clamp(0, 999)
        .toInt();
  }

  /// Convert staged changes to persistent PendingOperations for the merge.
  /// Pure function of _stagedChanges — no side effects on _pendingOperations
  /// (see _syncPendingOperationsWithStaged for how the two are reconciled).
  Map<String, PendingOperation> _stagedAsPendingOperations() {
    final ops = <String, PendingOperation>{};
    _stagedChanges.forEach((key, c) {
      final PendingOperationType type;
      Assignment? optimistic;
      if (c.isClear) {
        type = PendingOperationType.deleteAssignment;
      } else {
        type = c.baselineMemberId == null
            ? PendingOperationType.createAssignment
            : PendingOperationType.updateAssignment;
        optimistic = Assignment(
          id: c.desiredAssignmentId,
          eventId: c.eventId,
          teamMemberId: c.desiredMemberId!,
          roleType: c.roleType,
          slotIndex: c.slotIndex,
          status: AssignmentStatus.confirmed,
          notes: c.desiredNotes,
          semanticLabelId: c.desiredSemanticLabelId,
          alternativePhoneNumber: c.desiredAltPhone,
          createdAt: DateTime.fromMillisecondsSinceEpoch(c.stagedAtMillis),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(c.stagedAtMillis),
          teamMember: _windowMembersMap[c.desiredMemberId],
        );
      }
      ops[key] = PendingOperation(
        id: key,
        type: type,
        slotKey: key,
        optimisticAssignment: optimistic,
        timestamp: DateTime.fromMillisecondsSinceEpoch(c.stagedAtMillis),
        persistent: true,
      );
    });
    return ops;
  }

  /// The DB assignments with the in-memory staged changes applied, so cross-event
  /// availability (same-day booking) reflects the admin's unsaved edits. Used ONLY
  /// for the same-day availability computation in slot-building — NOT for save/
  /// conflict logic, which compares staged desired vs the RAW DB.
  List<Assignment> _stagedEffectiveAssignments(List<Assignment> dbAssignments) {
    if (_stagedChanges.isEmpty) return dbAssignments;
    final stagedKeys = _stagedChanges.keys.toSet();
    final result = <Assignment>[
      // keep every DB assignment whose slot the admin did NOT stage
      for (final a in dbAssignments)
        if (!stagedKeys.contains(
            StagedAssignmentChange.slotKeyFor(a.eventId, a.roleType, a.slotIndex)))
          a,
    ];
    // add the desired assignment for every staged fill/swap (staged CLEARs and
    // staged DELETIONS add nothing — a staged deletion frees the member for
    // same-day availability, since the assignment will be gone at Save, even
    // though its desiredMemberId is still set (kept only for rendering the
    // red-stripe row) so isClear alone does not catch it).
    for (final c in _stagedChanges.values) {
      if (c.isClear || c.markedForDeletion) continue;
      result.add(Assignment(
        id: c.desiredAssignmentId,
        eventId: c.eventId,
        teamMemberId: c.desiredMemberId!,
        roleType: c.roleType,
        slotIndex: c.slotIndex,
        status: AssignmentStatus.confirmed,
        notes: c.desiredNotes,
        semanticLabelId: c.desiredSemanticLabelId,
        alternativePhoneNumber: c.desiredAltPhone,
        createdAt: DateTime.fromMillisecondsSinceEpoch(c.stagedAtMillis),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(c.stagedAtMillis),
        teamMember: _windowMembersMap[c.desiredMemberId],
      ));
    }
    return result;
  }

  /// Reconcile `_pendingOperations` with the current staged-changes snapshot,
  /// called immediately before each slots-view merge call.
  ///
  /// This is NOT a blind `_pendingOperations = _stagedAsPendingOperations()`
  /// replace: the (dormant in production, but still exercised by
  /// assignment_bloc_slots_refetch_test.dart) Optimistic* handlers also live
  /// in `_pendingOperations`, tagged `persistent: false`. A blind replace
  /// would wipe their in-flight entries the moment any stream event triggers
  /// a rebuild while a write is in flight. Staged entries are tagged
  /// `persistent: true` (see _stagedAsPendingOperations), so reconciliation
  /// strips only previously-staged entries (preventing a discarded/changed
  /// staged slot from lingering) before overlaying the fresh snapshot —
  /// non-persistent (Optimistic*-owned) entries are left untouched. The two
  /// mechanisms coexist in the same map.
  void _syncPendingOperationsWithStaged() {
    _pendingOperations = Map<String, PendingOperation>.from(_pendingOperations)
      ..removeWhere((_, op) => op.persistent)
      ..addAll(_stagedAsPendingOperations());
  }

  Future<void> _onStageMemberChange(
      StageMemberChange event, Emitter<AssignmentState> emit) async {
    await _upsertStagedMember(event.slot, event.member?.id);
    Logger.action('stage:member', {
      'slot': _slotKey(event.slot),
      'from': event.slot.currentAssignment?.teamMemberId ?? 'empty',
      'to': event.member?.id ?? 'CLEARED',
      'stagedCount': _stagedChanges.length,
    });
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onStageNotesChange(
      StageNotesChange event, Emitter<AssignmentState> emit) async {
    await _upsertStagedNotes(event.slot, event.notes, event.semanticLabelId,
        event.alternativePhoneNumber);
    Logger.action('stage:notes', {
      'slot': _slotKey(event.slot),
      'stagedCount': _stagedChanges.length,
    });
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onStageSlotDeletion(
      StageSlotDeletion event, Emitter<AssignmentState> emit) async {
    final slot = event.slot;
    // MINOR #4: only an IN-quota deletion changes the derived quota. Seeding the
    // baseline for an OFF-quota-only deletion would make the role type-G-eligible
    // and surface a phantom quota conflict on any concurrent DB quota change
    // (which, per the override default, would then 409). The off-quota delete
    // still applies at Save — the main loop deletes markedForDeletion entries
    // regardless of whether a baseline was seeded — and correctly makes no quota
    // change (derivedQuota falls back to the live quota).
    if (slot.slotIndex < _liveQuota(slot.event.id, slot.role.key)) {
      _baselineQuotaFor(slot.event.id, slot.role.key); // seed baseline (in-quota)
    }
    final key = _slotKey(slot);
    final base = _stagedChanges[key] ?? _seedStaged(slot);
    _stagedChanges[key] = base.copyWith(markedForDeletion: true);
    await _persistStaged();
    Logger.action('stage:delete', {'slot': key, 'stagedCount': _stagedChanges.length});
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onStageManualAdd(
      StageManualAdd event, Emitter<AssignmentState> emit) async {
    final eventId = event.event.id;
    final role = event.roleType;
    _baselineQuotaFor(eventId, role); // seed baseline
    // Append at the first free index >= liveQuota. Every staged slotIndex for
    // this (event, role) is "used" — INCLUDING markedForDeletion rows: reusing
    // a marked row's index would overwrite its staged entry (losing the delete
    // and leaving two docs at the same event+role+slotIndex on Save), so the
    // deletion flag must NOT be filtered out here.
    final base = _liveQuota(eventId, role);
    final used = _stagedChanges.values
        .where((c) => c.eventId == eventId && c.roleType == role)
        .map((c) => c.slotIndex)
        .toSet();
    var slotIndex = base;
    while (used.contains(slotIndex)) {
      slotIndex++;
    }
    final key = StagedAssignmentChange.slotKeyFor(eventId, role, slotIndex);
    _stagedChanges[key] = StagedAssignmentChange(
      slotKey: key, eventId: eventId, roleType: role, slotIndex: slotIndex,
      desiredMemberId: event.member.id, desiredNotes: '',
      desiredSemanticLabelId: null, desiredAltPhone: null,
      baselineAssignmentId: null, baselineMemberId: null, baselineNotes: '',
      baselineSemanticLabelId: null, baselineAltPhone: null,
      desiredAssignmentId: const Uuid().v4(),
      stagedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistStaged();
    Logger.action('stage:manualAdd', {'slot': key, 'stagedCount': _stagedChanges.length});
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onDiscardStagedSlot(
      DiscardStagedSlot event, Emitter<AssignmentState> emit) async {
    // A discard must not race an in-flight Save: SaveStagedChanges already
    // captured its own snapshot of creates/updates/deletes before this event
    // is handled, so clearing _stagedChanges here would be silently
    // overridden the moment that write lands — the discard would appear to
    // succeed in the UI but the save writes anyway.
    if (_saveInFlight) return;
    final removed = _stagedChanges.remove(event.slotKey);
    // carry (a): once a role has no staged changes left, drop its captured
    // derived-quota baseline so a discarded session can't leak a stale baseline
    // into the next one (mis-deriving that role's quota). Derive the role from
    // the removed entry's real fields, not by splitting the slot key.
    if (removed != null) {
      final roleStillStaged = _stagedChanges.values.any((c) =>
          c.eventId == removed.eventId && c.roleType == removed.roleType);
      if (!roleStillStaged) {
        _baselineQuota.remove(_eventRoleKey(removed.eventId, removed.roleType));
      }
    }
    await _persistStaged();
    Logger.action('stage:discardSlot', {
      'slot': event.slotKey,
      'stagedCount': _stagedChanges.length,
    });
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onDiscardAllStagedChanges(
      DiscardAllStagedChanges event, Emitter<AssignmentState> emit) async {
    // See _onDiscardStagedSlot: guard against discarding while a Save is
    // already converging its own captured snapshot to the DB.
    if (_saveInFlight) return;
    Logger.action('stage:discardAll', {'had': _stagedChanges.length});
    _stagedChanges.clear();
    // carry (a): a full discard also clears every captured derived-quota
    // baseline, so the next staging session re-seeds from the live DB quota.
    _baselineQuota.clear();
    await _userCache.clearPendingAssignmentChanges();
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  /// Task 12: decodes the persisted payload and restores BOTH the staged
  /// list and the real `_baselineQuota` snapshot captured at stage time — so
  /// a persisted manual-add/deletion survives a reload with the correct
  /// derived quota, without re-deriving a baseline from whatever the LIVE
  /// quota happens to be at reload time (that used to be Task 7's stopgap
  /// reseed loop; it is gone now that the real baseline round-trips).
  ///
  /// Tolerates the OLD format (a bare JSON list, no baseline ever
  /// persisted) for a smooth upgrade: `_baselineQuota` is simply left empty
  /// in that case — any quota-touching staged change in an old cache
  /// re-seeds its baseline from the current live quota the next time it's
  /// touched (StageSlotDeletion/StageManualAdd), same as a brand-new
  /// staging session would. There is nothing better to restore: the old
  /// format never captured a baseline to begin with.
  Future<void> _onRehydrateStagedChanges(
      RehydrateStagedChanges event, Emitter<AssignmentState> emit) async {
    final raw = await _userCache.getPendingAssignmentChanges();
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    final List list;
    if (decoded is List) {
      list = decoded; // legacy format (bare list)
    } else {
      list = (decoded['changes'] as List?) ?? const [];
      _baselineQuota
        ..clear()
        ..addAll(Map<String, int>.from(
            (decoded['baselineQuota'] as Map?)?.cast<String, int>() ??
                const {}));
    }
    _stagedChanges
      ..clear()
      ..addEntries(list
          .map((e) =>
              StagedAssignmentChange.fromJson(e as Map<String, dynamic>))
          .map((c) => MapEntry(c.slotKey, c)));
    Logger.action('stage:rehydrate', {'loaded': _stagedChanges.length});
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  /// Slot keys of dirty rows that would otherwise vanish from the grid
  /// because their underlying slot is gone. Two cases qualify (both require
  /// `desiredMemberId != null` — there is a visible row to keep; a staged
  /// CLEAR's intent IS to remove the row, so that case is always excluded):
  ///
  ///  1. DB-backed: the row WAS anchored to a real DB assignment at stage
  ///     time (`baselineMemberId != null`), but no assignment for that slot
  ///     exists in the current raw DB snapshot (`getCurrentAssignments()` +
  ///     paged extra-past, the same source `classifyStagedConflicts`/Save
  ///     read) — i.e. it was deleted remotely while the row stayed dirty.
  ///  2. Fresh-fill-vanished: the slot started empty (`baselineMemberId ==
  ///     null` — there was never a DB row to lose), but its slot key is no
  ///     longer present in [builtSlots] — e.g. a co-admin shrank the role's
  ///     quota below this slotIndex. A fresh fill whose slot still renders is
  ///     NOT gone — including a manual-add, which renders because the grid
  ///     grows via `_stagedAddCount` for that role; only a fresh fill whose
  ///     slot no longer renders at all qualifies.
  ///
  /// Either way, qualifying rows are kept visible (their staged state) and
  /// marked with the red diagonal-stripe "deleted upstream, kept because
  /// dirty" overlay instead of vanishing (see `_materializeGoneStagedRows`,
  /// which [builtSlots] must also be passed to).
  ///
  /// [builtSlots] must be the SAME built-but-not-yet-materialized slot list
  /// the caller is about to pass to `_materializeGoneStagedRows`, so case 2's
  /// "does it still render" check reflects the actual grid just built, not a
  /// stale or unrelated one.
  Set<String> _computeStagedGoneKeys(List<AssignmentSlot> builtSlots) {
    if (_stagedChanges.isEmpty) return const {};
    final dbKeys = <String>{
      for (final a in [
        ..._repository.getCurrentAssignments(),
        ..._extraPastAssignments,
      ])
        StagedAssignmentChange.slotKeyFor(a.eventId, a.roleType, a.slotIndex),
    };
    final presentKeys = builtSlots.map(_getSlotKey).toSet();
    final gone = <String>{};
    _stagedChanges.forEach((key, c) {
      if (c.desiredMemberId == null) return;
      final dbBackedAndDeleted =
          c.baselineMemberId != null && !dbKeys.contains(key);
      final freshFillVanished =
          c.baselineMemberId == null && !presentKeys.contains(key);
      if (dbBackedAndDeleted || freshFillVanished) {
        gone.add(key);
      }
    });
    return gone;
  }

  /// Slot keys of staged entries currently marked for deletion
  /// (`StageSlotDeletion`) — drives `AssignmentSlotsLoaded.stagedDeletionSlotKeys`.
  /// Pure function of `_stagedChanges`, mirroring `_computeStagedGoneKeys`.
  Set<String> _computeStagedDeletionKeys() {
    if (_stagedChanges.isEmpty) return const {};
    return _stagedChanges.entries
        .where((e) => e.value.markedForDeletion)
        .map((e) => e.key)
        .toSet();
  }

  /// Re-materialize dirty rows whose slot vanished (quota shrank / role removed
  /// under the staged edit) so a remotely-deleted staged change stays VISIBLE —
  /// with the red diagonal-stripe overlay — instead of silently dropping out of
  /// the grid. For each key in [goneKeys] not already represented in [slots],
  /// synthesize an off-quota row from the staged desired state, then re-sort.
  ///
  /// Off-quota (isOffQuota: true) keeps the phantom row OUT of the quota /
  /// double-assignment / availability math, exactly like real off-quota rows.
  /// It is added regardless of the event filter: an unresolved staged edit must
  /// stay reachable to discard or Save. Keys already present in [slots] (the
  /// in-quota case, where the empty quota slot survived + the overlay refilled
  /// it) are skipped — they already render.
  List<AssignmentSlot> _materializeGoneStagedRows(
      List<AssignmentSlot> slots, Set<String> goneKeys) {
    if (goneKeys.isEmpty) return slots;
    final presentKeys = slots.map(_getSlotKey).toSet();
    final synthesized = <AssignmentSlot>[];
    for (final key in goneKeys) {
      if (presentKeys.contains(key)) continue; // already rendered (in-quota)
      final c = _stagedChanges[key];
      if (c == null) continue;
      final event =
          _windowEventsMap[c.eventId] ?? _extraPastEventsMap[c.eventId];
      if (event == null) continue; // cannot render without the event
      final member = c.desiredMemberId == null
          ? null
          : _windowMembersMap[c.desiredMemberId];
      // Deterministic timestamps (the stage-time millis) so two rebuilds of an
      // unchanged staged edit produce an EQUAL synthesized slot — otherwise the
      // Equatable state differs every rebuild and _emitOrLog re-emits endlessly.
      final stagedTs = DateTime.fromMillisecondsSinceEpoch(c.stagedAtMillis);
      final assignment = _assignmentFromStaged(c,
              id: c.desiredAssignmentId,
              createdAt: stagedTs,
              updatedAt: stagedTs)
          .withRelations(event: event, teamMember: member);
      synthesized.add(AssignmentSlot(
        event: event,
        role: _resolveRoleForKey(c.roleType),
        slotIndex: c.slotIndex,
        currentAssignment: assignment,
        availableMembers: const [],
        alreadyAssignedMembers: const [],
        isOffQuota: true,
      ));
    }
    if (synthesized.isEmpty) return slots;
    return [...slots, ...synthesized]..sort(_compareAssignmentSlots);
  }

  /// (eventId, roleType) pairs whose `_baselineQuota` was seeded THIS session
  /// (i.e. touched by StageSlotDeletion/StageManualAdd) — the set of roles a
  /// per-role quota divergence (type-G, in [classifyStagedConflicts]) or a
  /// Save `eventQuotaSet` (in [_onSaveStagedChanges]) applies to. The real
  /// (eventId, roleType) pair for each candidate erk is read from
  /// `_stagedChanges.values`' own fields rather than by splitting the
  /// composite erk string — a role key CAN contain '_', which would make
  /// `erk.split('_')` ambiguous about where eventId ends and roleType
  /// begins. Shared by both call sites so they can never desync on which
  /// erks are "in play" for quota purposes.
  Map<String, ({String eventId, String roleType})> _quotaTouchedRoles() {
    final roles = <String, ({String eventId, String roleType})>{};
    for (final c in _stagedChanges.values) {
      final erk = _eventRoleKey(c.eventId, c.roleType);
      if (_baselineQuota.containsKey(erk)) {
        roles[erk] = (eventId: c.eventId, roleType: c.roleType);
      }
    }
    return roles;
  }

  /// Compare each staged change's baseline to the current DB slots and
  /// return the conflicts to resolve at Save. A slot conflicts when its
  /// current DB occupant/notes differ from the baseline captured at first
  /// touch.
  ///
  /// [currentSlots] (typically `AssignmentSlotsLoaded.slots`) is used ONLY to
  /// check whether the slot still exists in the grid (quota shrink -> D). It
  /// is deliberately NOT used to read the current DB member/notes: every
  /// staged slot renders its OPTIMISTIC (desired) value in `currentSlots`
  /// (see `_mergeSlotsWithOptimisticUpdates`/`_emptied`), which would mask
  /// genuine concurrent DB changes — a staged clear always shows an empty
  /// `currentAssignment` there regardless of what the DB actually holds. The
  /// real current-DB occupant is read from `_repository.getCurrentAssignments()`,
  /// the raw, un-staged snapshot the bloc already keeps live from the
  /// assignments stream.
  List<AssignmentConflict> classifyStagedConflicts(
      List<AssignmentSlot> currentSlots) {
    final slotKeysPresent = currentSlots.map(_getSlotKey).toSet();
    // Union of the live 90-day window cache AND the extra-past cache (rows
    // loaded via "load more history"). The window cache alone misses any
    // paginated-in past row, which would otherwise misclassify a staged edit
    // on that row as targetRemoved (B) and, on override, route it to
    // `creates` with the row's REAL existing id -> backend batch.create on an
    // existing doc -> ALREADY_EXISTS. _extraPastAssignments is strictly older
    // than the window, so no id collisions with getCurrentAssignments.
    final dbByKey = <String, Assignment>{
      for (final a in [
        ..._repository.getCurrentAssignments(),
        ..._extraPastAssignments,
      ])
        StagedAssignmentChange.slotKeyFor(a.eventId, a.roleType, a.slotIndex):
            a,
    };

    final conflicts = <AssignmentConflict>[];

    _stagedChanges.forEach((key, c) {
      // Context header for the conflict row: "<event name> · <role>" so the
      // admin can tell WHICH assignment each conflict is about (several
      // conflicts can otherwise read identically). The event may be out of the
      // live window if it was paged in, so fall back to the extra-past map.
      final conflictEvent =
          _windowEventsMap[c.eventId] ?? _extraPastEventsMap[c.eventId];
      final conflictRoleName = _resolveRoleForKey(c.roleType).hebrewName;
      final conflictTitle = conflictEvent != null
          ? '${conflictEvent.name} · $conflictRoleName'
          : conflictRoleName;

      // D: slot no longer exists (quota shrank / role removed). Two-button:
      // override = create off-quota (handled at Save), takeDb = discard.
      if (!slotKeysPresent.contains(key)) {
        conflicts.add(AssignmentConflict(
          slotKey: key,
          type: AssignmentConflictType.slotVanished,
          title: conflictTitle,
          description:
              'המכסה של "$conflictRoleName" באירוע קטנה, והמשרה ששיבצת אליה כבר לא קיימת.',
          discardOnly: false,
        ));
        return;
      }

      final dbAssignment = dbByKey[key];
      final dbMemberId = dbAssignment?.teamMemberId;
      final dbNotes = dbAssignment?.notes ?? '';
      final dbLabel = dbAssignment?.semanticLabelId;
      final dbAltPhone = dbAssignment?.alternativePhoneNumber;
      final baselineMember = c.baselineMemberId;

      // No divergence from baseline (member + notes + label + altPhone) =>
      // no conflict. Label/altPhone must be included: a concurrent DB change
      // to only one of those (notes/member unchanged) is a real divergence
      // that would otherwise be classified no-conflict and silently
      // overwritten at Save.
      final memberDiverged = dbMemberId != baselineMember;
      final notesDiverged = dbNotes != c.baselineNotes;
      final labelDiverged = dbLabel != c.baselineSemanticLabelId;
      final altPhoneDiverged = dbAltPhone != c.baselineAltPhone;
      if (!memberDiverged &&
          !notesDiverged &&
          !labelDiverged &&
          !altPhoneDiverged) {
        return;
      }

      if (c.isClear) {
        // C: you cleared baseline B, DB now holds a different member.
        if (dbMemberId != null && dbMemberId != baselineMember) {
          conflicts.add(AssignmentConflict(
            slotKey: key,
            type: AssignmentConflictType.clearCollision,
            title: conflictTitle,
            description: 'ניקית שיבוץ שקיים, אך בינתיים שובץ שם אדם אחר ב-DB.',
          ));
        }
        return; // clear + already-empty is satisfied, not a conflict
      }

      if (dbMemberId == null && baselineMember != null) {
        // B: your swap/notes target was deleted.
        conflicts.add(AssignmentConflict(
          slotKey: key,
          type: AssignmentConflictType.targetRemoved,
          title: conflictTitle,
          description: 'השיבוץ ששינית נמחק בינתיים ב-DB.',
        ));
        return;
      }

      if (memberDiverged) {
        // A: slot taken by a different member than your baseline.
        conflicts.add(AssignmentConflict(
          slotKey: key,
          type: AssignmentConflictType.slotTaken,
          title: conflictTitle,
          description: 'המשרה נתפסה: בינתיים שובץ שם אדם אחר ב-DB.',
        ));
        return;
      }

      // F: notes, label, or alt-phone changed underneath a non-member edit
      // (member unchanged from baseline, so A/B/C above did not fire).
      conflicts.add(AssignmentConflict(
        slotKey: key,
        type: AssignmentConflictType.notesChanged,
        title: conflictTitle,
        description: 'ההערות/הלייבל של השיבוץ שונו בינתיים ב-DB.',
      ));
    });

    // G: per-role quota divergence — a DIFFERENT axis from the per-slot A-F
    // checks above (those compare a slot's assignee/notes; this compares a
    // role's QUOTA). For every (event, role) that has a captured
    // `_baselineQuota` entry (i.e. StageSlotDeletion/StageManualAdd touched
    // it this session), fire one conflict when the live DB quota moved off
    // that baseline AND still differs from the admin's derived intent — if
    // `derivedQuota == live`, the admin's staged edits already reconcile with
    // the new DB quota on their own, so there is nothing to ask about.
    //
    // The real (eventId, roleType) pair for each candidate erk is read via
    // [_quotaTouchedRoles] — shared with `_onSaveStagedChanges` (same
    // underlying data, same hazard splitting the composite erk string would
    // hit), so classify-time and save-time agree on exactly which erks are
    // "in play" for type-G.
    final quotaConflictRoles = _quotaTouchedRoles();
    quotaConflictRoles.forEach((erk, role) {
      final baseline = _baselineQuota[erk]!;
      final live = _liveQuota(role.eventId, role.roleType);
      final desired = derivedQuota(role.eventId, role.roleType);
      if (live != baseline && desired != live) {
        final ev = _windowEventsMap[role.eventId] ??
            _extraPastEventsMap[role.eventId];
        final roleName = _resolveRoleForKey(role.roleType).hebrewName;
        conflicts.add(AssignmentConflict(
          // MUST be the eventRoleKey (erk), NOT a per-slot key: Task 10's
          // Save reads `resolutions[erk]` at exactly this key to decide
          // whether to skip (takeDb) or emit (overrideDb) this role's
          // eventQuotaSet.
          slotKey: erk,
          type: AssignmentConflictType.quotaChanged,
          title: ev != null ? '${ev.name} · $roleName' : roleName,
          description:
              'המכסה של "$roleName" השתנתה: התחלת מ-$baseline, וכעת ב-DB יש $live.',
        ));
      }
    });

    return conflicts;
  }

  /// Repack a role's post-save rows contiguous from 0 (Save-time only), after a
  /// staged deletion freed a slot. The rows that will exist for the role =
  /// DB survivors (not in [deletes]) + this role's [creates] (manual-adds,
  /// override-restores, fresh fills). Renumbering the UNION keeps in-quota rows
  /// packed AND lets a same-role manual-add fill the freed in-quota slot instead
  /// of being stranded off-quota (IMPORTANT #2). DB survivors write back to
  /// [updates] (merging into any staged member/notes edit already queued for
  /// them); creates are mutated in place in [creates]. Reads the raw DB snapshot
  /// (getCurrentAssignments + paged extra-past), the same source the rest of
  /// Save converges against.
  void _reindexRoleAfterDeletion(String eventId, String roleType,
      List<String> deletes, List<Assignment> updates, List<Assignment> creates) {
    final deletedIds = deletes.toSet(); // O(1) survivor filtering
    // Sortable union tagged by source: a DB survivor (write back to `updates`)
    // or an index into `creates` (mutate in place).
    final items = <({int slotIndex, Assignment? survivor, int? createIdx})>[];
    for (final a in [
      ..._repository.getCurrentAssignments(),
      ..._extraPastAssignments,
    ]) {
      if (a.eventId == eventId &&
          a.roleType == roleType &&
          !deletedIds.contains(a.id)) {
        items.add((slotIndex: a.slotIndex, survivor: a, createIdx: null));
      }
    }
    for (var i = 0; i < creates.length; i++) {
      if (creates[i].eventId == eventId && creates[i].roleType == roleType) {
        items.add(
            (slotIndex: creates[i].slotIndex, survivor: null, createIdx: i));
      }
    }
    items.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.slotIndex == i) continue; // already contiguous at this index
      if (it.survivor != null) {
        final a = it.survivor!;
        final existing = updates.indexWhere((u) => u.id == a.id);
        if (existing >= 0) {
          updates[existing] = updates[existing].copyWith(slotIndex: i);
        } else {
          updates.add(a.copyWith(slotIndex: i, updatedAt: DateTime.now()));
        }
      } else {
        final ci = it.createIdx!;
        creates[ci] = creates[ci].copyWith(slotIndex: i);
      }
    }
  }

  /// Atomically persist every staged change (see [SaveStagedChanges]).
  ///
  /// Converges each applied staged slot to its desired state against the
  /// CURRENT DB — read from `_repository.getCurrentAssignments()`, the raw
  /// pre-merge cache, exactly as [classifyStagedConflicts] does. This is
  /// deliberate and MUST NOT be read from `state.slots`/`AssignmentSlotsLoaded`:
  /// those slots already have staging overlaid on top
  /// (`_mergeSlotsWithOptimisticUpdates`), so `slot.currentAssignment` is the
  /// MERGED/desired value, not the raw DB doc. Sourcing the DB occupant from
  /// there would mis-route a staged fill into `updates` (updating a document
  /// id that was never written -> batch fails) and would silently drop a
  /// staged clear (the merged slot already reads as empty).
  ///
  /// Fail-loud guarantee: a missing DB row is only ever a legitimate no-op
  /// when the staged change's `baselineMemberId == null` (the slot started
  /// empty — nothing to lose). When `baselineMemberId != null` — the change
  /// is anchored to a member that WAS on the slot — a missing DB row means
  /// the row was deleted from under the edit (e.g. a concurrent co-admin
  /// delete); that case is counted as a skip and surfaced in the completion
  /// message instead of silently vanishing behind `'נשמרו 0 שינויים'`.
  Future<void> _onSaveStagedChanges(
      SaveStagedChanges event, Emitter<AssignmentState> emit) async {
    if (_stagedChanges.isEmpty) {
      _completeActionSuccess(event.completion, 'אין שינויים לשמירה');
      return;
    }
    if (_saveInFlight) {
      _completeActionFailure(event.completion, 'שמירה כבר מתבצעת');
      return;
    }
    _saveInFlight = true;

    final resolutions = event.resolutions ?? const {};
    // Union of the live 90-day window cache AND the extra-past cache (rows
    // loaded via "load more history"). The window cache alone misses any
    // paginated-in past row, which would otherwise misclassify a staged edit
    // on that row as targetRemoved (B) and, on override, route it to
    // `creates` with the row's REAL existing id -> backend batch.create on an
    // existing doc -> ALREADY_EXISTS. _extraPastAssignments is strictly older
    // than the window, so no id collisions with getCurrentAssignments.
    final dbByKey = <String, Assignment>{
      for (final a in [
        ..._repository.getCurrentAssignments(),
        ..._extraPastAssignments,
      ])
        StagedAssignmentChange.slotKeyFor(a.eventId, a.roleType, a.slotIndex):
            a,
    };

    Logger.action('save:start', {
      'staged': _stagedChanges.length,
      'dbTruth': dbByKey.length,
      'resolutions': resolutions.map((k, v) => MapEntry(k, v.name)),
    });

    final creates = <Assignment>[];
    final updates = <Assignment>[];
    final deletes = <String>[];
    final appliedKeys = <String>[];
    // Distinct eventIds this batch writes to (creates/updates/deletes). Used
    // after a successful write to refresh the extra-past cache for any touched
    // event that lives OUTSIDE the live window (paginated in via "load more
    // history") — the live-window stream can't cover those, so without this
    // the grid would revert the edit on the next rebuild (carry b).
    final touchedEventIds = <String>{};
    // Counts staged changes anchored to a real DB member (baselineMemberId
    // != null) whose expected DB row is gone at save time — see the
    // baseline-vs-db branch below. Surfaced in the success message so a real
    // staged edit never disappears behind a silent 'נשמרו 0 שינויים'.
    var skippedNotFound = 0;

    for (final entry in _stagedChanges.entries) {
      final key = entry.key;
      final c = entry.value;

      // takeDb => the admin chose to keep the DB state; drop this staged
      // change entirely (no write), but still remove it from staging.
      if (resolutions[key] == ConflictResolution.takeDb) {
        appliedKeys.add(key);
        Logger.action('save:slot', {
          'slot': key,
          'isClear': c.isClear,
          'dbFound': dbByKey[key] != null,
          'decision': 'takeDb-skip',
        });
        continue;
      }

      final dbAssignment = dbByKey[key];
      // The admin explicitly chose "my change wins" (דרוס DB / צור מחוץ למכסה)
      // for this conflict — a deliberate instruction to re-create/keep the
      // change, so it must NOT be intercepted by the skip-not-found safety net.
      final isOverride = resolutions[key] == ConflictResolution.overrideDb;

      // Task 10: a staged swipe-deletion (StageSlotDeletion). Delete its DB row
      // (if still present) and let the post-loop quota/reindex pass renumber the
      // role's survivors + emit the exact quota. A gone DB row is a benign no-op
      // here (the delete already happened, e.g. a concurrent co-admin delete),
      // NOT a skip-not-found loss — so this MUST precede the skip-not-found net
      // (a deletion always has baselineMemberId != null). Placed after the
      // per-slot takeDb check above, so a per-slot takeDb still discards it.
      if (c.markedForDeletion) {
        if (dbAssignment != null) {
          deletes.add(dbAssignment.id);
          touchedEventIds.add(dbAssignment.eventId);
        }
        appliedKeys.add(key);
        Logger.action('save:slot', {
          'slot': key,
          'isClear': c.isClear,
          'dbFound': dbAssignment != null,
          'decision': 'staged-delete',
        });
        continue; // quota + survivor reindex handled in the post-pass below
      }

      String decision;
      if (dbAssignment == null && c.baselineMemberId != null && !isOverride) {
        // LOSSY case (UNRESOLVED): this change is anchored to a member that WAS
        // on the slot (baselineMemberId != null — a clear, a swap, or a
        // notes/label/alt-phone edit), the expected DB row is gone (a concurrent
        // delete by another admin), AND the admin did NOT explicitly override
        // it. Silently creating a fresh row would fabricate an assignment the
        // admin never asked to (re)create. Queue no write, drop the now-
        // meaningless staged entry, and count it so the caller reports the skip
        // instead of a false 'נשמרו 0 שינויים' success. (An explicit override
        // falls through to the create branch below and RE-creates the row —
        // exactly what the admin asked for.)
        skippedNotFound++;
        decision = 'skip-not-found';
      } else if (c.isClear) {
        if (dbAssignment != null) {
          deletes.add(dbAssignment.id);
          touchedEventIds.add(dbAssignment.eventId);
          decision = 'clear-delete';
        } else {
          // baselineMemberId == null here (the branch above already caught
          // the != null case) -> the slot started empty, so a staged clear
          // over an already-empty DB slot is a legitimate no-op, not a loss.
          decision = 'clear-noop';
        }
      } else if (dbAssignment == null) {
        // No DB row: a fresh fill (baseline empty), OR an explicit override of a
        // since-deleted / vanished-slot conflict — RE-create the assignment
        // (in-quota, or off-quota if the slot's quota is gone) from the staged
        // desired member/notes, keeping its original id.
        creates.add(_assignmentFromStaged(c, id: c.desiredAssignmentId));
        touchedEventIds.add(c.eventId);
        decision = 'create';
      } else {
        // Converge the EXISTING DB doc to the desired state, preserving its
        // id and createdAt (the backend `batch.update` writes the full doc,
        // so a fresh createdAt here would silently overwrite the original).
        updates.add(_assignmentFromStaged(
          c,
          id: dbAssignment.id,
          createdAt: dbAssignment.createdAt,
        ));
        touchedEventIds.add(c.eventId);
        decision = 'update';
      }
      appliedKeys.add(key);
      Logger.action('save:slot', {
        'slot': key,
        'isClear': c.isClear,
        'dbFound': dbByKey[key] != null,
        'decision': decision,
      });
    }

    // Task 10: roles touched by a staged quota change — a manual-add or an
    // in-quota deletion, the two actions that SEED _baselineQuota. For each,
    // emit an EXACT derived quota target with the captured baseline as the
    // backend concurrency guard's `expected`, and renumber that role's DB
    // survivors contiguous from 0. The (eventId, roleType) pair comes from
    // [_quotaTouchedRoles] — shared with `classifyStagedConflicts` so the two
    // never desync on which erks are "in play". The set record is
    // structurally the repository's EventQuotaSet (no import needed).
    final quotaSets =
        <({String eventId, String roleType, int target, int expected})>[];
    final rolesWithSet = <String>{}; // erk keys that produced a set (carry c)
    final quotaChangedRoles = _quotaTouchedRoles();
    quotaChangedRoles.forEach((erk, role) {
      // MINOR #3: a role with an APPLIED staged deletion ALWAYS repacks its
      // survivors + creates, regardless of the quota-set / type-G decision below
      // ("your deletions still apply and survivors still reindex"). A per-SLOT
      // takeDb (resolutions[slotKey]) cancels that specific deletion so it's
      // excluded; a role-level (erk) takeDb does NOT stop the reindex.
      final hadDeletion = _stagedChanges.entries.any((e) =>
          e.value.eventId == role.eventId &&
          e.value.roleType == role.roleType &&
          e.value.markedForDeletion &&
          resolutions[e.key] != ConflictResolution.takeDb);
      if (hadDeletion) {
        // Fix #3: the reindex mutates `updates`/`creates` directly and can be
        // the ONLY write for this event (every markedForDeletion row was
        // already gone, so no delete was queued, yet a survivor still
        // reindexed). Mark the event touched so carry (b) reconciles its stale
        // extra-past cache (no-op for in-window events).
        touchedEventIds.add(role.eventId);
        // IMPORTANT #2: repack survivors AND this role's creates contiguous, so
        // a same-role manual-add fills the freed IN-quota slot instead of being
        // stranded off-quota. Runs BEFORE maxCreateBound below so a pure
        // delete+add lands on derivedTarget, not baseline+adds.
        _reindexRoleAfterDeletion(
            role.eventId, role.roleType, deletes, updates, creates);
      }

      // A role-level (type-G) takeDb keeps the DB quota: skip the SET. The
      // deletions + survivor reindex above already applied.
      if (resolutions[erk] == ConflictResolution.takeDb) return;
      final baseline = _baselineQuota[erk]!;

      // Resolution-aware add / in-quota-deletion counts (Fix #2): a per-slot
      // takeDb cancels that staged entry, so a cancelled deletion must NOT
      // lower the target and a cancelled add must NOT raise it. Mirrors
      // _stagedAddCount / _inQuotaDeletionCount but skips takeDb'd entries —
      // hence NOT the resolution-blind public derivedQuota.
      var adds = 0;
      var inQuotaDeletions = 0;
      for (final e in _stagedChanges.entries) {
        final c = e.value;
        if (c.eventId != role.eventId || c.roleType != role.roleType) continue;
        if (resolutions[e.key] == ConflictResolution.takeDb) continue;
        if (c.markedForDeletion) {
          if (c.slotIndex < baseline) inQuotaDeletions++;
        } else if (c.baselineMemberId == null && c.slotIndex >= baseline) {
          adds++;
        }
      }
      final derivedTarget =
          (baseline + adds - inQuotaDeletions).clamp(0, 999).toInt();

      // The target must ALSO fit every create the admin wants in-quota for this
      // role — an override-restore create (baselineMemberId != null) that the
      // derived counts are blind to (Fix #1), and any manual-add create (which
      // the reindex above already repacked into a freed slot, so this reads its
      // NEW low index — IMPORTANT #2). Taking the max keeps the SET the single
      // source of truth for the role's quota, so dropping the bump below (carry
      // c) stays safe (target >= max(slotIndex+1) over the role's creates).
      var maxCreateBound = 0;
      for (final a in creates) {
        if (a.eventId == role.eventId && a.roleType == role.roleType) {
          final bound = a.slotIndex + 1;
          if (bound > maxCreateBound) maxCreateBound = bound;
        }
      }
      final target =
          derivedTarget > maxCreateBound ? derivedTarget : maxCreateBound;

      // CRITICAL #1: on an override (the dialog DEFAULT for a type-G conflict),
      // `expected` MUST be the LIVE DB quota — the backend's
      // planEventQuotaSetWrites rejects (409) a set whose expected != live &&
      // target != live, so a baseline `expected` makes override fail every time.
      // With no override, baseline is the correct optimistic-concurrency guard.
      final expected = resolutions[erk] == ConflictResolution.overrideDb
          ? _liveQuota(role.eventId, role.roleType)
          : baseline;

      quotaSets.add((
        eventId: role.eventId,
        roleType: role.roleType,
        target: target,
        expected: expected,
      ));
      rolesWithSet.add(erk);
    });

    // Restore-to-quota: any create that would land OFF-quota — its slotIndex is
    // at/above the event's CURRENT quota for that role, i.e. an override that
    // re-creates a row whose slot had vanished — asks the backend to raise that
    // role's quota just enough to fit it, ATOMICALLY with the write (one batch),
    // so the row comes back IN-quota instead of off-quota. Keyed per
    // (event, role) to the highest slotIndex+1 needed. The record type is
    // structurally the repository's EventQuotaBump (no import needed).
    final quotaBumpByKey =
        <String, ({String eventId, String roleType, int count})>{};
    for (final a in creates) {
      final ev = _windowEventsMap[a.eventId] ?? _extraPastEventsMap[a.eventId];
      if (ev == null) continue;
      final currentQuota = ev.roleRequirements[a.roleType] ?? 0;
      if (a.slotIndex >= currentQuota) {
        final key = '${a.eventId}_${a.roleType}';
        final needed = a.slotIndex + 1;
        final existing = quotaBumpByKey[key];
        if (existing == null || needed > existing.count) {
          quotaBumpByKey[key] =
              (eventId: a.eventId, roleType: a.roleType, count: needed);
        }
      }
    }
    // carry (c): a role with an exact eventQuotaSet must NOT also get a
    // max-merge bump — the SET already sets that role's quota and wins the
    // batch, and a redundant bump makes the backend read+write the same event
    // twice. quotaBumpByKey is keyed identically to rolesWithSet (erk).
    quotaBumpByKey.removeWhere((k, _) => rolesWithSet.contains(k));
    final eventQuotaBumps = quotaBumpByKey.values.toList();

    _emitOrLog(emit, const AssignmentOperating('saving'));
    try {
      Logger.action('save:batch', {
        'creates': creates
            .map((a) => '${a.roleType}#${a.slotIndex}=${a.teamMemberId}')
            .toList(),
        'updates': updates.map((a) => '${a.id}=>${a.teamMemberId}').toList(),
        'deletes': deletes,
        'quotaBumps': eventQuotaBumps
            .map((b) => '${b.roleType}@${b.eventId}->${b.count}')
            .toList(),
        'quotaSets': quotaSets
            .map((s) => '${s.roleType}@${s.eventId}->${s.target}(exp ${s.expected})')
            .toList(),
      });
      await _repository.saveAssignmentsBatch(
        creates: creates,
        updates: updates,
        deletes: deletes,
        eventQuotaBumps: eventQuotaBumps,
        eventQuotaSets: quotaSets,
      );
      Logger.action('save:done', {
        'written': creates.length + updates.length + deletes.length,
        'skippedNotFound': skippedNotFound,
      });
      // carry (b): out-of-window (paginated-in) past events aren't covered by
      // the live-window stream, so their _extraPastEventsMap/_extraPastAssignments
      // entries would stay stale after this write and the next rebuild would
      // revert the edit. Refresh every touched event (no-op for in-window ones).
      for (final id in touchedEventIds) {
        await _refreshExtraPastEvent(id);
      }
      // MINOR #5: capture the (eventId, roleType) of every applied entry BEFORE
      // removing them, so the per-role baseline clear below can see their fields.
      final appliedRoleErks = <String>{
        for (final k in appliedKeys)
          if (_stagedChanges[k] != null)
            _eventRoleKey(
                _stagedChanges[k]!.eventId, _stagedChanges[k]!.roleType),
      };
      for (final k in appliedKeys) {
        _stagedChanges.remove(k);
      }
      // carry (a) + MINOR #5: drop the captured derived-quota baseline for each
      // FULLY-applied role (all its staged entries applied, none remaining) —
      // NOT only when _stagedChanges emptied entirely. The overlay-less
      // leave-guard Save keeps the grid interactive during the await, so an
      // edit staged mid-Save leaves a survivor that would otherwise strand the
      // applied roles' stale baselines (reused via putIfAbsent on the next
      // stage, mis-deriving quota / a phantom type-G conflict).
      for (final erk in appliedRoleErks) {
        final stillStaged = _stagedChanges.values
            .any((c) => _eventRoleKey(c.eventId, c.roleType) == erk);
        if (!stillStaged) _baselineQuota.remove(erk);
      }
      // Re-persist the SURVIVING staged changes rather than blanket-clearing
      // the cache. The screen's leave-guard Save runs without a blocking
      // overlay, so the grid stays interactive during this await — a new
      // edit may have been staged (added to _stagedChanges) after
      // appliedKeys was captured above, in which case it correctly survives
      // the removal loop but is NOT in appliedKeys. A blanket
      // clearPendingAssignmentChanges() here would still wipe that survivor
      // from crash-recovery even though it correctly remains in memory.
      // _persistStaged() writes whatever is left in _stagedChanges — `[]`
      // when none remain (equivalent to a clear), or the survivor's entry
      // when one was staged mid-save.
      await _persistStaged();
      final written = creates.length + updates.length + deletes.length;
      // Never a bare 'נשמרו 0 שינויים' while a baseline-anchored change was
      // dropped for lack of a DB row: report the skip alongside the write
      // count instead of pretending nothing happened.
      final successMessage = skippedNotFound == 0
          ? 'נשמרו $written שינויים'
          : 'נשמרו $written שינויים · $skippedNotFound דולגו (השיבוץ כבר לא קיים)';
      _completeActionSuccess(event.completion, successMessage);
      add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
    } catch (e) {
      Logger.action('save:fail', {'error': e.toString()});
      _completeActionFailure(event.completion, 'שמירה נכשלה: $e');
      add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
    } finally {
      _saveInFlight = false;
    }
  }

  /// Build the Assignment doc to write for a staged change. [id] is the
  /// target document id (the existing DB doc's id for an update, or the
  /// staged change's stable [StagedAssignmentChange.desiredAssignmentId] for
  /// a create). [createdAt] should be the existing DB doc's createdAt for an
  /// update (preserved, not reset); omitted (defaults to now) for a create.
  Assignment _assignmentFromStaged(
    StagedAssignmentChange c, {
    required String id,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now();
    return Assignment(
      id: id,
      eventId: c.eventId,
      teamMemberId: c.desiredMemberId!,
      roleType: c.roleType,
      slotIndex: c.slotIndex,
      status: AssignmentStatus.confirmed,
      notes: c.desiredNotes,
      semanticLabelId: c.desiredSemanticLabelId,
      alternativePhoneNumber: c.desiredAltPhone,
      createdAt: createdAt ?? now,
      // updatedAt defaults to now for the Save path (a real write), but callers
      // that render a synthesized row MUST pass a STABLE timestamp: an
      // Equatable Assignment stamped with DateTime.now() on every rebuild would
      // make the slot differ each time and defeat the no-op emit suppression.
      updatedAt: updatedAt ?? now,
    );
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

    _emitOrLog(
        emit,
        AssignmentSlotsLoaded(
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
      _emitOrLog(
          emit,
          AssignmentSlotsLoaded(
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
      _emitOrLog(
          emit,
          AssignmentSlotsLoaded(
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

    _emitOrLog(
        emit,
        AssignmentSlotsLoaded(
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
      _emitOrLog(
          emit,
          AssignmentSlotsLoaded(
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
      _emitOrLog(
          emit,
          AssignmentSlotsLoaded(
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

    _emitOrLog(
        emit,
        AssignmentSlotsLoaded(
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

      _syncAttendeesForAffectedEvents(previousAssignment: assignmentToDelete);
      if (assignmentToDelete != null) {
        await _refreshExtraPastEvent(assignmentToDelete.eventId);
      }

      // CRITICAL FIX: Remove pending operation after successful delete
      _pendingOperations.remove(event.slotKey);
      _emitOrLog(
          emit,
          AssignmentSlotsLoaded(
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
      _emitOrLog(
          emit,
          AssignmentSlotsLoaded(
            currentState.slots,
            selectedEventIds: currentState.selectedEventIds,
            pendingOperations: _pendingOperations,
          ));
      _completeActionFailure(event.completion, 'שגיאה במחיקת שיבוץ: $e');
    }
  }

  /// Retired hook. Assignments no longer change Google Calendar guests; app
  /// event Calendar synchronization is owned entirely by the backend.
  void _syncAttendeesForAffectedEvents({
    Assignment? previousAssignment,
    Assignment? nextAssignment,
  }) {
    // Intentionally a no-op; see the doc comment above. The field read keeps
    // the dependency wired without re-introducing client-side Calendar writes.
    if (_calendarSyncBloc == null) {
      return;
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
  /// Takes already-scoped events/activeMembers/roles from the CALLER instead
  /// of fetching them internally. _onRebuildAssignmentSlots (the only caller)
  /// feeds this from the SAME windowed in-memory caches the live-stream path
  /// (_onRebuildAssignmentSlotsFromData) uses —
  /// _repository.getCurrentAssignments() + _extraPastAssignments,
  /// _windowEventsMap + _extraPastEventsMap (then showPastEvents-filtered by
  /// the caller), _windowMembersMap filtered to active, _cachedRoles —
  /// instead of the unbounded getAllAssignments()/getAllEvents()/
  /// getActiveTeamMembers()/getAllRoles() this method used to fetch itself.
  /// This keeps the stage/filter/rehydrate/save rebuild path scoped to the
  /// exact same 90-day-back/180-day-forward (+ paged extras) data window as
  /// the live-stream path — see docs/superpowers/plans/
  /// 2026-07-16-assignments-slot-build-unification.md ("Bug #3 root cause").
  Future<AssignmentSlotsLoaded> _buildSlotsFromAssignments(
    List<Assignment> assignments,
    List<Event> events,
    List<TeamMember> activeMembers,
    List<Role> roles, {
    Set<String>? selectedEventIds,
  }) async {
    // Deactivated events have no presence in the assignments grid. Unlike
    // showPastEvents (a caller-owned display toggle), this is unconditional,
    // so it stays here rather than moving to the caller.
    events = events.where((event) => !event.isDeactivated).toList();

    // Sort a COPY so the shared _cachedRoles list is never mutated in place.
    final sortedRoles = [...roles]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Create a mapping from role key to Role for easy lookup
    final roleKeyToRole = <String, Role>{};
    for (final role in sortedRoles) {
      roleKeyToRole[role.key] = role;
    }

    // 5. Build slots
    final slots = <AssignmentSlot>[];

    // Staged-aware view of the DB assignments, used ONLY below for the
    // cross-event same-day exclusion so an unsaved stage-clear/fill/swap is
    // reflected in other events' availability immediately (see
    // _stagedEffectiveAssignments doc comment). Every other use of
    // `assignments` in this method (currentAssignment, assignedMemberIds,
    // off-quota rows, annotations) intentionally stays on the raw DB list —
    // the optimistic overlay in _mergeSlotsWithOptimisticUpdates already
    // handles those.
    final effectiveAssignments = _stagedEffectiveAssignments(assignments);

    for (final event in events) {
      final placedAssignmentIds = <String>{};
      // Iterate through roles in sortOrder (not enum order)
      for (final role in sortedRoles) {
        final requiredCount = event.roleRequirements[role.key] ?? 0;
        if (requiredCount == 0 && _stagedAddCount(event.id, role.key) == 0) {
          continue; // Skip roles with 0 requirement and no staged adds
        }

        // Get assignments for this event+role
        final roleAssignments = assignments
            .where((a) => a.eventId == event.id && a.roleType == role.key)
            .toList();

        final renderCount =
            requiredCount + _stagedAddCount(event.id, role.key);
        // Create slots (one per required count, grown by staged manual-adds)
        for (int i = 0; i < renderCount; i++) {
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
          // Iterates effectiveAssignments (DB + staged overlay), NOT the raw
          // `assignments` param — see _stagedEffectiveAssignments.
          final sameDayAssignedMembersMap = <String, TeamMember>{};
          final sameDayEventInfoMap = <String, List<String>>{};

          for (final otherAssignment in effectiveAssignments) {
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
            if (eventsShareDay(event, otherEvent)) {
              final memberId = otherAssignment.teamMemberId;
              // Null-safe: skip if the owner isn't in the active-member set
              // (deactivated, or members not yet streamed in) rather than
              // mis-attributing the same-day conflict to an arbitrary member,
              // or throwing `.first` on an empty list. Mirrors the live-stream
              // path's null-skip (divergence #4).
              final memberMatches =
                  activeMembers.where((m) => m.id == memberId);
              if (memberMatches.isEmpty) continue;
              final member = memberMatches.first;

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

          for (final member in activeMembers) {
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

    // 6. Annotate the built slots. Same-day runs LAST so that no later pass can
    //    drop it (see annotateDoubleAssignments' copyWith note). Both passes see
    //    the full loaded window — the event filter is applied downstream, in the
    //    widget, so narrowing the grid never erases an event's own marks.
    var annotatedSlots = annotateDoubleAssignments(slots);
    annotatedSlots = annotateSameDayOtherEvents(
      annotatedSlots,
      allEvents: events,
      allAssignments: assignments,
    );

    // 7. Sort slots deterministically so same-role rows do not flip order.
    annotatedSlots.sort(_compareAssignmentSlots);

    final goneKeys = _computeStagedGoneKeys(annotatedSlots);
    return AssignmentSlotsLoaded(
      _materializeGoneStagedRows(annotatedSlots, goneKeys),
      selectedEventIds: selectedEventIds ?? {},
      stagedSlotKeys: _stagedChanges.keys.toSet(),
      stagedGoneSlotKeys: goneKeys,
      stagedDeletionSlotKeys: _computeStagedDeletionKeys(),
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
      // First-paint gate: identical to the live-stream path
      // (_onRebuildAssignmentSlotsFromData). Until the roles, events, AND
      // assignments streams have each delivered at least once, the windowed
      // in-memory caches below are not populated yet — suppress the rebuild
      // rather than build against an empty/partial window.
      if (!_slotsRolesReady || !_slotsEventsReady || !_slotsAssignmentsReady) {
        return;
      }

      // Determine which filter to use:
      // 1. If the event provides a filter (explicit change), use it
      // 2. Otherwise, use the last known filter stored in _currentEventFilter
      final filterToUse = event.preservedFilter ?? _currentEventFilter;

      // Keep the internal field in sync
      _currentEventFilter = filterToUse;

      // Build from the SAME windowed in-memory caches the live-stream path
      // (_onRebuildAssignmentSlotsFromData) uses — NOT an unbounded one-shot
      // fetch. This is what keeps the stage/filter/rehydrate/save rebuild
      // path scoped to the exact same 90-day-back/180-day-forward (+ paged
      // extras) data window as the stream path, so a staged clear can never
      // target an assignment the windowed Save path can't see (the
      // "נשמרו 0 שינויים" / member-reappears bug).
      // Id-keyed dedup (matches windowedEvents below and the stream path's
      // mergedAssignmentsById) so a pagination-boundary duplicate can't render
      // as two identical off-quota ghost rows.
      final windowedAssignments = <String, Assignment>{
        for (final a in _repository.getCurrentAssignments()) a.id: a,
        for (final a in _extraPastAssignments) a.id: a,
      }.values.toList();
      var windowedEvents = <String, Event>{
        ..._windowEventsMap,
        ..._extraPastEventsMap,
      }.values.toList();
      // Filter events based on showPastEvents flag — mirrors the
      // filteredEvents step in _onRebuildAssignmentSlotsFromData. (Deactivated
      // events are filtered inside _buildSlotsFromAssignments itself.)
      if (!FilterPersistence.showPastEvents) {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        windowedEvents = windowedEvents
            .where((e) => e.endDate
                .isAfter(todayStart.subtract(const Duration(days: 1))))
            .toList();
      }
      // Active-only — matches the previous getActiveTeamMembers() source, and
      // fixes divergence #3 vs. the live-stream path's unfiltered member map
      // (_windowMembersMap itself stays unfiltered for Path B in this task).
      final windowedActiveMembers =
          _windowMembersMap.values.where((m) => m.isActive).toList();

      // Build slots from the windowed data (base state)
      final databaseSlots = await _buildSlotsFromAssignments(
        windowedAssignments,
        windowedEvents,
        windowedActiveMembers,
        _cachedRoles,
        selectedEventIds: filterToUse,
      );

      // Merge optimistic updates on top of database state using BLoC-level pending operations
      _syncPendingOperationsWithStaged();
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        databaseSlots.slots,
        _pendingOperations,
      );

      final capped = _applyPastRevealCap(mergedSlots);
      final goneKeys = _computeStagedGoneKeys(capped.slots);

      _emitOrLog(
          emit,
          AssignmentSlotsLoaded(
            _materializeGoneStagedRows(capped.slots, goneKeys),
            selectedEventIds: filterToUse,
            pendingOperations: _pendingOperations,
            hasMorePast: capped.hasMore,
            isLoadingMorePast: _loadingMorePast,
            stagedSlotKeys: _stagedChanges.keys.toSet(),
            stagedGoneSlotKeys: goneKeys,
            stagedDeletionSlotKeys: _computeStagedDeletionKeys(),
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
    Logger.action('stream:rebuild', {
      'assignments': rebuildEvent.assignments.length,
      'stagedCount': _stagedChanges.length,
    });
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
      // Staged-effective view (DB + in-memory staged changes) used ONLY for the
      // cross-event same-day availability loop below, so a live Firestore emit
      // arriving mid-stage cannot transiently re-hide a member the admin just
      // freed up by a staged clear on another same-day event. Every other use of
      // mergedAssignments stays raw-DB; the overlay merge applies staging to the
      // within-event state. Mirrors _buildSlotsFromAssignments. See
      // _stagedEffectiveAssignments.
      final effectiveMergedAssignments =
          _stagedEffectiveAssignments(mergedAssignments);

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
      var filteredEvents = eventsList.where((e) => !e.isDeactivated).toList();

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
          if (requiredCount == 0 &&
              _stagedAddCount(eventData.id, role.key) == 0) {
            continue; // Skip roles with 0 requirement and no staged adds
          }

          // Get assignments for this event+role from the assignments list
          final roleAssignments = mergedAssignments
              .where((a) => a.eventId == eventData.id && a.roleType == role.key)
              .map((a) => a.withRelations(
                    event: eventData,
                    teamMember: teamMembersMap[a.teamMemberId] ?? a.teamMember,
                  ))
              .toList();

          final renderCount =
              requiredCount + _stagedAddCount(eventData.id, role.key);
          // Create slots (one per required count, grown by staged manual-adds)
          for (int i = 0; i < renderCount; i++) {
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

            for (final otherAssignment in effectiveMergedAssignments) {
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
              if (eventsShareDay(eventData, otherEvent)) {
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
          _buildOffQuotaSlots(
              eventData, eventAssignmentsAll, placedAssignmentIds),
        );
      }

      // Annotate the built slots — same passes, same order as
      // _buildSlotsFromAssignments. Runs BEFORE the event filter below, so
      // filtering the grid to one event keeps that event's own marks.
      var annotatedSlots = annotateDoubleAssignments(slots);
      annotatedSlots = annotateSameDayOtherEvents(
        annotatedSlots,
        allEvents: filteredEvents,
        allAssignments: mergedAssignments,
      );

      // Sort slots deterministically so same-role rows do not flip order.
      annotatedSlots.sort(_compareAssignmentSlots);

      // Apply filter if needed
      final filteredSlots = rebuildEvent.selectedEventIds.isNotEmpty
          ? annotatedSlots
              .where((slot) =>
                  rebuildEvent.selectedEventIds.contains(slot.event.id))
              .toList()
          : annotatedSlots;

      // Remember the filter
      _currentEventFilter = rebuildEvent.selectedEventIds;

      // Merge optimistic updates on top of database state using BLoC-level pending operations
      _syncPendingOperationsWithStaged();
      final mergedSlots = _mergeSlotsWithOptimisticUpdates(
        filteredSlots,
        _pendingOperations,
      );

      final capped = _applyPastRevealCap(mergedSlots);
      final goneKeys = _computeStagedGoneKeys(capped.slots);

      _emitOrLog(
          emit,
          AssignmentSlotsLoaded(
            _materializeGoneStagedRows(capped.slots, goneKeys),
            selectedEventIds: rebuildEvent.selectedEventIds,
            pendingOperations: _pendingOperations,
            hasMorePast: capped.hasMore,
            isLoadingMorePast: _loadingMorePast,
            stagedSlotKeys: _stagedChanges.keys.toSet(),
            stagedGoneSlotKeys: goneKeys,
            stagedDeletionSlotKeys: _computeStagedDeletionKeys(),
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
        _emitOrLog(
            emit, AssignmentConflictWarning(e.conflicts, event.assignment));
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
        _emitOrLog(
            emit,
            AssignmentsLoaded.withCounts(
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
      _emitOrLog(
          emit, const AssignmentOperationSuccess('פרטי השיבוץ עודכנו בהצלחה'));
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
