import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../../core/constants/role_types.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/assignment_label.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/event.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../data/repositories/assignment_label_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../core/constants/assignment_label_palette.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/services/environment_service.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/assignment/assignment_state.dart';
import '../../bloc/assignment/models/assignment_conflict.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import 'models/assignment_slot.dart';
import '../../widgets/interactive_filter_bar.dart';
import '../../widgets/same_day_assignment_mark.dart';
import '../../../core/debug/logger.dart';
import 'assignment_filter_modal.dart';
import 'widgets/assignment_label_management_dialog.dart';
import 'widgets/assignment_save_bar.dart';
import 'widgets/conflict_resolution_dialog.dart';
import 'widgets/unsaved_changes_dialog.dart';
import '../event/widgets/event_form_modal.dart';
import 'manual_assignment_flow_dialog.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/assignment_label_chip.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/phone_input_formatter.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../core/utils/search_utils.dart';
import '../../../core/debug/search_action_logger.dart';

class AssignmentListScreen extends StatefulWidget {
  const AssignmentListScreen({super.key});

  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentLabelSelectionResult {
  final String? selectedLabelId;
  final AssignmentLabel? createdLabel;

  const _AssignmentLabelSelectionResult({
    required this.selectedLabelId,
    this.createdLabel,
  });
}

class _AssignmentLabelCreationResult {
  final AssignmentLabel createdLabel;
  final bool shouldSelectLabel;

  const _AssignmentLabelCreationResult({
    required this.createdLabel,
    required this.shouldSelectLabel,
  });
}

class _AssignmentListScreenState extends State<AssignmentListScreen> {
  AssignmentSlotsLoaded? _lastSlotsState;
  // Track when dropdowns need to be reset (forces new widget instance)
  final Map<String, int> _dropdownResetCounters = {};
  // Track if initial data load is complete (to show loading until both assignments and team members are loaded)
  bool _isInitialLoadComplete = false;
  // Search functionality
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final SearchActionLogger _searchLog = SearchActionLogger('assignments');
  bool _isMutationInFlight = false;
  String _mutationMessage = '';

  @override
  void initState() {
    super.initState();
    context.read<AssignmentBloc>().add(const LoadAssignmentSlots());
    context.read<AssignmentBloc>().add(const RehydrateStagedChanges());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchLog.dispose();
    super.dispose();
  }

  /// Handle filter change
  void _onFilterChanged(int newIndex) {
    Logger.action('filter:assignmentStatus', {'index': newIndex});
    setState(() {
      FilterPersistence.assignmentFilterIndex = newIndex;
    });
  }

  void _showAssignmentSnackBar(
    String message, {
    required Color backgroundColor,
  }) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(message),
          ),
          backgroundColor: backgroundColor,
        ),
      );
  }

  void _startMutation(String message) {
    setState(() {
      _isMutationInFlight = true;
      _mutationMessage = message;
    });
  }

  void _updateMutationMessage(String message) {
    if (!mounted) return;
    setState(() {
      _mutationMessage = message;
    });
  }

  void _finishMutation() {
    if (!mounted) return;
    setState(() {
      _isMutationInFlight = false;
      _mutationMessage = '';
    });
  }

  void _unfocusDialogInputs(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
  }

  Future<void> _settleDialogFocus(BuildContext context) async {
    _unfocusDialogInputs(context);
    await Future<void>.delayed(Duration.zero);
  }

  Future<CrudActionResult> _dispatchMutation(
    void Function(CrudActionCompleter completion) dispatch, {
    bool showErrorSnackBar = true,
  }) async {
    final completion = Completer<CrudActionResult>();
    dispatch(completion);
    return await completion.future;
  }

  Widget _buildMutationDialogOverlay() {
    if (!_isMutationInFlight) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text(
                  _mutationMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Save every staged assignment change. Classifies staged-vs-DB conflicts
  /// FIRST (baseline captured at staging time vs. the current DB); if any
  /// exist, shows [ConflictResolutionDialog] and waits for the admin's
  /// resolutions before dispatching the save. Cancelling the dialog leaves
  /// staging fully intact — nothing is saved. See
  /// docs/superpowers/specs/2026-07-15-assignments-staged-save-design.md
  /// ("Conflict handling" / "Save flow").
  Future<void> _onSavePressed() async {
    if (_isMutationInFlight) return;
    final bloc = context.read<AssignmentBloc>();
    if (!bloc.hasStagedChanges) return;
    Logger.action('tap:saveStagedChanges');

    final blocState = bloc.state;
    final slots = blocState is AssignmentSlotsLoaded
        ? blocState.slots
        : (_lastSlotsState?.slots ?? const <AssignmentSlot>[]);
    final conflicts = bloc.classifyStagedConflicts(slots);

    Map<String, ConflictResolution> resolutions = const {};
    if (conflicts.isNotEmpty) {
      Logger.action(
          'open:conflictResolutionDialog', {'count': conflicts.length});
      final result = await showDialog<Map<String, ConflictResolution>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ConflictResolutionDialog(conflicts: conflicts),
      );
      if (result == null) {
        Logger.action('tap:cancel:conflictResolutionDialog');
        return; // cancelled — nothing saved, staging intact
      }
      resolutions = result;
    }

    if (!mounted) return;
    _startMutation('שומר שינויים...');
    final saveResult = await _dispatchMutation(
      (completion) => bloc.add(
        SaveStagedChanges(resolutions: resolutions, completion: completion),
      ),
    );
    _finishMutation();
    if (!mounted) return;
    _showAssignmentSnackBar(
      saveResult.isSuccess
          ? (saveResult.message ?? 'נשמר')
          : (saveResult.message ?? 'שמירה נכשלה'),
      backgroundColor: saveResult.isSuccess ? Colors.green : Colors.red,
    );
  }

  /// Leave-guard for in-screen exits (home button, logout) — a courtesy
  /// reminder, not data-protection (staged changes already survive in the
  /// cache). See docs/superpowers/specs/
  /// 2026-07-15-assignments-staged-save-design.md ("Leave-guard").
  ///
  /// Returns whether the caller should proceed with its navigation:
  /// - clean (no staged changes) → `true` immediately, no dialog.
  /// - `leave` → `true` (staged changes stay in cache; still dirty on
  ///   return).
  /// - `save` → runs the full save flow (including the per-conflict
  ///   resolution dialog if needed) and proceeds only if it actually
  ///   cleared staging.
  /// - `cancel` / dismissed → `false` (stay).
  Future<bool> _confirmLeaveIfDirty() async {
    final bloc = context.read<AssignmentBloc>();
    if (!bloc.hasStagedChanges) return true;
    final count = bloc.stagedCount;
    final decision = await showUnsavedChangesDialog(context, count: count);
    if (!mounted) return false;
    if (decision == LeaveDecision.leave) return true;
    if (decision == LeaveDecision.save) {
      await _onSavePressed(); // full flow incl. conflict dialog
      if (!mounted) return false;
      return !bloc.hasStagedChanges; // proceed only if save actually cleared staging
    }
    return false; // cancel / dismissed
  }

  /// Confirm, then discard every staged (unsaved) change. See
  /// docs/superpowers/specs/2026-07-15-assignments-staged-save-design.md
  /// ("Discard" — "All-at-once").
  Future<void> _onDiscardAll() async {
    if (_isMutationInFlight) return;
    final bloc = context.read<AssignmentBloc>();
    final blocState = bloc.state;
    final count = blocState is AssignmentSlotsLoaded
        ? blocState.stagedSlotKeys.length
        : 0;
    Logger.action('open:discardAllStagedDialog', {'count': count});
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ביטול שינויים'),
          content: Text('לבטל את כל $count השינויים שלא נשמרו?'),
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:cancel:discardAllStaged');
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('חזרה'),
            ),
            TextButton(
              onPressed: () {
                Logger.action('tap:confirm:discardAllStaged');
                Navigator.of(dialogContext).pop(true);
              },
              child:
                  const Text('בטל הכל', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      bloc.add(const DiscardAllStagedChanges());
    }
  }

  /// Format location for display based on how it was entered
  /// - Manual location: show as-is
  /// - Map picker from search: show name/address only
  /// - Map picker by pinpoint: show coordinates
  String _formatLocationForDisplay(String location) {
    if (location.isEmpty) return '-';

    // Check if location was picked using map picker (contains || separator)
    if (location.contains('||')) {
      // This is a map-picked location from search
      final strippedLocation = MapLocationResult.stripCoordinates(location);

      if (strippedLocation.isNotEmpty) {
        // Location was picked from search result - show the name/address
        return strippedLocation;
      }
    }

    // Check if this is coordinates-only (pinpointed on map)
    final (lat, lng) = MapLocationResult.parseCoordinates(location);
    if (lat != null && lng != null) {
      // Check if the entire location string is just coordinates
      // This happens when admin pinpoints directly on map
      final coordPattern = RegExp(r'^\s*\d+\.\d+\s*,\s*\d+\.\d+\s*$');
      if (coordPattern.hasMatch(location)) {
        // This is a pinpointed location - format coordinates nicely
        return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
      }
    }

    // This is a manually entered location - show as-is
    return location;
  }

  /// Filter assignments based on selected filter index
  List<AssignmentSlot> _filterAssignments(
      List<AssignmentSlot> slots, int filterIndex) {
    switch (filterIndex) {
      case 0: // All
        return slots;
      case 1: // Filled (משובצים)
        return slots.where((s) => s.isFilled).toList();
      case 2: // Unfilled (לא משובצים)
        return slots.where((s) => !s.isFilled).toList();
      default:
        return slots;
    }
  }

  /// Filter slots by search query (event name, role name, member name, label)
  List<AssignmentSlot> _searchSlots(List<AssignmentSlot> slots) {
    if (_searchQuery.isEmpty) {
      return slots;
    }

    final normalizedQuery = normalizeForSearch(_searchQuery);
    return slots.where((slot) {
      // Search in event name
      if (normalizeForSearch(slot.event.name).contains(normalizedQuery)) {
        return true;
      }
      // Search in role Hebrew name
      if (normalizeForSearch(slot.role.hebrewName).contains(normalizedQuery)) {
        return true;
      }
      // Search in assigned member name (if filled)
      if (slot.isFilled && slot.currentAssignment?.teamMember?.name != null) {
        if (normalizeForSearch(slot.currentAssignment!.teamMember!.name)
            .contains(normalizedQuery)) {
          return true;
        }
      }
      // Search in semantic label name (if filled)
      final semanticLabelName =
          slot.currentAssignment?.semanticLabel?.hebrewName;
      if (semanticLabelName != null &&
          normalizeForSearch(semanticLabelName).contains(normalizedQuery)) {
        return true;
      }
      return false;
    }).toList();
  }

  List<AssignmentSlot> _sortSlotsForDisplay(List<AssignmentSlot> slots) {
    final sorted = List<AssignmentSlot>.from(slots);
    final originalIndexes = <String, int>{
      for (int index = 0; index < slots.length; index++)
        _getSlotKey(slots[index]): index,
    };

    sorted.sort((a, b) {
      final originalCompare = (originalIndexes[_getSlotKey(a)] ?? 0)
          .compareTo(originalIndexes[_getSlotKey(b)] ?? 0);

      final sameEvent = a.event.id == b.event.id;
      if (!sameEvent) {
        return originalCompare;
      }

      // Off-quota rows always sort below their in-quota siblings, mirroring the
      // BLoC's _compareAssignmentSlots (a duplicate-slotIndex off-quota row
      // shares its sibling's slot-key and could otherwise render above it).
      if (a.isOffQuota != b.isOffQuota) {
        return a.isOffQuota ? 1 : -1;
      }

      final aLabel = a.currentAssignment?.semanticLabel;
      final bLabel = b.currentAssignment?.semanticLabel;

      int compareLabels() {
        if (aLabel == null && bLabel == null) {
          return 0;
        }
        if (aLabel == null) return 1;
        if (bLabel == null) return -1;

        final bySortOrder = aLabel.sortOrder.compareTo(bLabel.sortOrder);
        if (bySortOrder != 0) return bySortOrder;

        return aLabel.hebrewName.compareTo(bLabel.hebrewName);
      }

      final byRoleOrder = a.role.sortOrder.compareTo(b.role.sortOrder);
      final byRoleKey = a.role.key.compareTo(b.role.key);

      if (FilterPersistence.assignmentSortBySemanticLabel) {
        final byLabel = compareLabels();
        if (byLabel != 0) return byLabel;

        if (byRoleOrder != 0) return byRoleOrder;
        if (byRoleKey != 0) return byRoleKey;
        return originalCompare;
      }

      if (byRoleOrder != 0) return byRoleOrder;
      if (byRoleKey != 0) return byRoleKey;

      final byLabel = compareLabels();
      if (byLabel != 0) return byLabel;

      return originalCompare;
    });

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              // Leading: past-events toggle chip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: GestureDetector(
                  onTap: () {
                    Logger.action('toggle:showPastEvents', {
                      'on': !FilterPersistence.showPastEvents,
                    });
                    setState(() {
                      FilterPersistence.showPastEvents =
                          !FilterPersistence.showPastEvents;
                    });
                    // Reload assignments with new filter setting
                    context
                        .read<AssignmentBloc>()
                        .add(const LoadAssignmentSlots());
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: FilterPersistence.showPastEvents
                          ? Colors.green.shade50
                          : Colors.grey.shade100,
                      border: Border.all(
                        color: FilterPersistence.showPastEvents
                            ? Colors.green
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        FilterPersistence.showPastEvents
                            ? 'אירועי עבר'
                            : 'ללא עבר',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: FilterPersistence.showPastEvents
                              ? Colors.green.shade700
                              : Colors.grey.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
              // Centered title
              const Expanded(
                child: Center(
                    child: Text('שיבוצים', style: TextStyle(fontSize: 20))),
              ),
              // Trailing icons
              IconButton(
                icon: const Icon(Icons.label_outline),
                tooltip: 'ניהול לייבלים',
                onPressed: () {
                  Logger.action('open:assignmentLabelManagementDialog');
                  showDialog(
                    context: context,
                    builder: (context) =>
                        const AssignmentLabelManagementDialog(),
                  );
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              IconButton(
                icon: const Icon(Icons.home),
                tooltip: 'בית',
                onPressed: () async {
                  Logger.action('tap:home');
                  if (await _confirmLeaveIfDirty()) {
                    if (!context.mounted) return;
                    final envPrefix = EnvironmentService.instance.routePrefix;
                    context.go('$envPrefix/admin');
                  }
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'התנתק',
                onPressed: () async {
                  Logger.action('tap:logout');
                  if (await _confirmLeaveIfDirty()) {
                    if (!context.mounted) return;
                    _logout(context);
                  }
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
            ],
          ),
        ),
        floatingActionButton: BlocBuilder<AssignmentBloc, AssignmentState>(
          builder: (context, state) {
            final stagedCount = state is AssignmentSlotsLoaded
                ? state.stagedSlotKeys.length
                : (_lastSlotsState?.stagedSlotKeys.length ?? 0);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AssignmentSaveBar(
                  stagedCount: stagedCount,
                  onSave: _onSavePressed,
                  onDiscardAll: _onDiscardAll,
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  heroTag: 'assignment-list-fab',
                  backgroundColor: Colors.blue,
                  tooltip: 'שיבוץ ידני',
                  onPressed: _isMutationInFlight
                      ? null
                      : () => _showManualAssignmentFlow(),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ],
            );
          },
        ),
        body: BlocListener<EventBloc, EventState>(
          listener: (context, state) {
            if (state is EventError) {
              _showAssignmentSnackBar(
                state.message,
                backgroundColor: Colors.red,
              );
            }
          },
          child: Stack(
            children: [
              BlocConsumer<AssignmentBloc, AssignmentState>(
                listener: (context, state) {
                  if (state is AssignmentError) {
                    _showAssignmentSnackBar(
                      state.message,
                      backgroundColor: Colors.red,
                    );
                  } else if (state is AssignmentOperationSuccess) {
                    _showAssignmentSnackBar(
                      state.message,
                      backgroundColor: Colors.green,
                    );
                  } else if (state is AssignmentConflictWarning) {
                    _showAssignmentSnackBar(
                      'שיבוץ לא בוצע: ${state.conflicts.join(", ")}',
                      backgroundColor: Colors.orange,
                    );
                  }
                },
                builder: (context, state) {
                  // Always show last known state if available, unless explicitly loading
                  if (state is AssignmentLoading && _lastSlotsState == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is AssignmentSlotsLoaded) {
                    // If slots are empty, the load is complete (no events in time window)
                    // Only check for team members if there are actual slots
                    if (!_isInitialLoadComplete && state.slots.isNotEmpty) {
                      final hasTeamMembers = state.slots
                          .any((slot) => slot.availableMembers.isNotEmpty);
                      if (!hasTeamMembers) {
                        return const Center(child: CircularProgressIndicator());
                      }
                    }

                    // Mark initial load as complete
                    if (!_isInitialLoadComplete) {
                      _isInitialLoadComplete = true;
                    }

                    // Update _lastSlotsState with current state
                    _lastSlotsState = state;
                    return _buildSlotGrid(state);
                  }

                  // For any other state (Operating, Success, Error), keep showing last state if available
                  if (_lastSlotsState != null) {
                    return _buildSlotGrid(_lastSlotsState!);
                  }

                  // Only show error UI if we have no cached state
                  if (state is AssignmentError) {
                    return _buildErrorState(state.message);
                  }

                  return _buildEmptyState(0, 0, 0);
                },
              ),
              _buildMutationDialogOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // Store all slots for double-assignment checking
  List<AssignmentSlot> _allSlots = [];

  // Get unique key for a slot's dropdown
  String _getSlotKey(AssignmentSlot slot) {
    return '${slot.event.id}_${slot.role.key}_${slot.slotIndex}';
  }

  // Reset a dropdown by incrementing its counter (forces new widget with fresh state)
  void _resetDropdown(AssignmentSlot slot) {
    final key = _getSlotKey(slot);
    setState(() {
      _dropdownResetCounters[key] = (_dropdownResetCounters[key] ?? 0) + 1;
    });
  }

  Widget _buildSlotGrid(AssignmentSlotsLoaded state) {
    return StreamBuilder<List<AssignmentLabel>>(
      stream: context.read<AssignmentLabelRepository>().watchAssignmentLabels(),
      builder: (context, labelSnapshot) {
        final liveSlots = _applyAssignmentLabelsToSlots(
          state.slots,
          labelSnapshot.data ?? const <AssignmentLabel>[],
        );

        // Store all slots for checking
        _allSlots = liveSlots;

        // Apply event filter first
        var filteredSlots = liveSlots;
        if (state.selectedEventIds.isNotEmpty) {
          filteredSlots = filteredSlots
              .where((s) => state.selectedEventIds.contains(s.event.id))
              .toList();
        }

        // Calculate statistics based on all slots (before assignment filter)
        final totalSlots = filteredSlots.length;
        final filledSlots = filteredSlots.where((s) => s.isFilled).length;
        final unfilledSlots = filteredSlots.where((s) => !s.isFilled).length;

        // Apply assignment filter
        final filteredByStatus = _filterAssignments(
            filteredSlots, FilterPersistence.assignmentFilterIndex);

        // Apply semantic label filter
        var filteredByLabel = filteredByStatus;
        if (FilterPersistence.selectedAssignmentLabelIds.isNotEmpty) {
          filteredByLabel = filteredByStatus.where((slot) {
            final semanticLabelId = slot.currentAssignment?.semanticLabelId;
            return semanticLabelId != null &&
                FilterPersistence.selectedAssignmentLabelIds.contains(
                  semanticLabelId,
                );
          }).toList();
        }

        // Apply search filter
        final slots = _sortSlotsForDisplay(_searchSlots(filteredByLabel));
        final hasVisibleSlots = slots.isNotEmpty;
        final activeFilterCount = state.selectedEventIds.length +
            FilterPersistence.selectedAssignmentCategoryIds.length +
            FilterPersistence.selectedAssignmentLabelIds.length;

        return RefreshIndicator(
          onRefresh: () async {
            Logger.action('tap:refreshSlots');
            context.read<AssignmentBloc>().add(const LoadAssignmentSlots());
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: Column(
            children: [
              // Interactive filter bar
              InteractiveFilterBar(
                options: [
                  FilterOption(label: 'סה״כ', count: totalSlots.toString()),
                  FilterOption(label: 'משובצים', count: filledSlots.toString()),
                  FilterOption(
                      label: 'לא משובצים', count: unfilledSlots.toString()),
                ],
                selectedIndex: FilterPersistence.assignmentFilterIndex,
                onFilterChanged: _onFilterChanged,
              ),

              // Search bar with filter button inside
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'חיפוש באירוע, תפקיד, שם או לייבל...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Clear button (only when there's text)
                          if (_searchQuery.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                Logger.action('tap:clearSearch');
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            ),
                          // Filter button (always visible)
                          IconButton(
                            icon: Badge(
                              isLabelVisible: activeFilterCount > 0,
                              label: Text(activeFilterCount.toString()),
                              child: Icon(
                                Icons.filter_list,
                                color: activeFilterCount > 0
                                    ? Colors.blue.shade700
                                    : null,
                              ),
                            ),
                            onPressed: () {
                              Logger.action('open:filterModal');
                              _showFilterModal(context, state);
                            },
                            tooltip: activeFilterCount == 0
                                ? 'סינון לפי אירוע ולייבל'
                                : 'קיימים $activeFilterCount מסננים פעילים',
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      _searchLog.onQueryChanged(value);
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ),

              if (hasVisibleSlots)
                // Header row
                Container(
                  height: 48,
                  color: Colors.grey.shade200,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // Event column (matches data row flex: 3)
                        Expanded(
                            flex: 3,
                            child: Text('אירוע',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        // Role column (matches data row flex: 2)
                        Expanded(
                            flex: 2,
                            child: Text('תפקיד',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        // Assignment column (matches data row flex: 3)
                        Expanded(
                            flex: 3,
                            child: Text('שיבוץ',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                ),

              // Grid rows
              Expanded(
                child: hasVisibleSlots
                    ? Builder(
                        builder: (context) {
                          final showLoadMore =
                              FilterPersistence.showPastEvents && state.hasMorePast;
                          return ListView.builder(
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: slots.length + (showLoadMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (showLoadMore && index == slots.length) {
                                return _buildLoadMorePastButton(state);
                              }
                              final row = _buildSlotRow(slots[index],
                                  state.stagedSlotKeys, state.stagedGoneSlotKeys);
                              // A dirty row whose DB assignment was deleted
                              // upstream is kept visible but marked with the
                              // red diagonal-stripe overlay (see
                              // stagedGoneSlotKeys / _withDeletedRemotelyOverlay).
                              return state.stagedGoneSlotKeys
                                      .contains(_getSlotKey(slots[index]))
                                  ? _withDeletedRemotelyOverlay(row)
                                  : row;
                            },
                          );
                        },
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.assignment_outlined,
                                size: 80, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'לא נמצאו תוצאות לחיפוש'
                                  : FilterPersistence.assignmentFilterIndex == 1
                                      ? 'אין תפקידים משובצים'
                                      : FilterPersistence
                                                  .assignmentFilterIndex ==
                                              2
                                          ? 'אין תפקידים פנויים'
                                          : 'אין תפקידים להצגה',
                              style: TextStyle(
                                  fontSize: 18, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadMorePastButton(AssignmentSlotsLoaded state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Align(
        alignment: Alignment.center,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: state.isLoadingMorePast
              ? null
              : () {
                  Logger.action('tap:loadMorePast');
                  context
                      .read<AssignmentBloc>()
                      .add(const LoadMorePastAssignmentSlots());
                },
          icon: state.isLoadingMorePast
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more),
          label: const Text('טען עוד'),
        ),
      ),
    );
  }

  List<AssignmentSlot> _applyAssignmentLabelsToSlots(
    List<AssignmentSlot> slots,
    List<AssignmentLabel> labels,
  ) {
    if (slots.isEmpty) {
      return slots;
    }

    final labelsById = {
      for (final label in labels) label.id: label,
    };

    return slots.map((slot) {
      final assignment = slot.currentAssignment;
      if (assignment == null) {
        return slot;
      }

      final updatedAssignment = assignment.copyWith(
        semanticLabel: () => assignment.semanticLabelId == null
            ? null
            : labelsById[assignment.semanticLabelId!],
      );

      return slot.copyWith(currentAssignment: updatedAssignment);
    }).toList();
  }

  /// Wraps a rendered slot [row] with the "deleted upstream, kept because
  /// dirty" marker: a translucent bright-red diagonal-stripe wash plus a small
  /// badge. Applied to rows in [AssignmentSlotsLoaded.stagedGoneSlotKeys] — a
  /// dirty row whose backing DB assignment was deleted remotely. The overlay is
  /// non-interactive (IgnorePointer), so the row underneath stays swipe- and
  /// tap-able for discard / Save-resolution.
  Widget _withDeletedRemotelyOverlay(Widget row) {
    return Stack(
      children: [
        row,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: const _DiagonalStripesPainter(),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(6)),
                  ),
                  child: const Text(
                    'שורה זו נמחקה מהשרת, אבל קיים שינוי שמור מקומית',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The optional "extra info" block shown beneath an assignment row — the
  /// semantic-label chip, the notes card, and the alternative-phone card.
  /// Shared by in-quota rows ([_buildSlotRow]) and off-quota rows
  /// ([_buildOffQuotaRow]) so a note / label / phone still shows when a row
  /// falls OUTSIDE its quota (e.g. after the role's quota was reduced). Returns
  /// null when the assignment has nothing extra to show.
  Widget? _buildAssignmentExtraInfo(Assignment? assignment) {
    if (assignment == null) return null;
    final hasNotes = assignment.notes.isNotEmpty;
    final hasSemanticLabel = assignment.semanticLabel != null;
    final hasAltPhone = assignment.alternativePhoneNumber != null &&
        assignment.alternativePhoneNumber!.isNotEmpty;
    if (!hasNotes && !hasSemanticLabel && !hasAltPhone) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            if (hasSemanticLabel) ...[
              Align(
                alignment: Alignment.center,
                child: AssignmentLabelChip(
                  label: assignment.semanticLabel!,
                  fontSize: 10,
                  maxLines: 3,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
              if (hasNotes || hasAltPhone) const SizedBox(height: 4),
            ],
            // Notes card
            if (hasNotes)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.note_alt_outlined,
                      size: 14,
                      color: Colors.purple.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'הערות לשיבוץ: ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.purple.shade800,
                              ),
                            ),
                            TextSpan(
                              text: assignment.notes,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.purple.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Alternative phone card
            if (hasAltPhone) ...[
              if (hasNotes) const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.phone_android,
                      size: 14,
                      color: Colors.teal.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'טלפון חד פעמי לשיבוץ: ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.teal.shade800,
                              ),
                            ),
                            TextSpan(
                              text: assignment.alternativePhoneNumber!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.teal.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSlotRow(AssignmentSlot slot, Set<String> stagedSlotKeys,
      Set<String> stagedGoneSlotKeys) {
    if (slot.isOffQuota) {
      return _buildOffQuotaRow(slot, stagedSlotKeys, stagedGoneSlotKeys);
    }

    // Dirty marker: a slot with an unsaved staged change gets a bright,
    // thick yellow border (not a conflict marker — conflicts are only
    // surfaced at Save time). See "Dirty marker (the yellow border)" in
    // docs/superpowers/specs/2026-07-15-assignments-staged-save-design.md.
    final isDirty = stagedSlotKeys.contains(_getSlotKey(slot));

    final extraInfo = _buildAssignmentExtraInfo(slot.currentAssignment);

    final rowContent = Container(
      decoration: BoxDecoration(
        border: isDirty
            ? Border.all(color: Colors.amber, width: 3)
            : Border(
                bottom: BorderSide(color: Colors.grey.shade400, width: 1.5)),
        color: slot.isFilled ? null : Colors.orange.shade50,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main row content
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Event column
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Logger.action('open:eventFormModal', {
                              'eventId': slot.event.id,
                            });
                            _showEventFormModal(slot.event);
                          },
                          child: Text(
                            slot.event.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.blue,
                              decoration: TextDecoration.none,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        // Line 1: Dates formatted in Hebrew
                        Text(
                          _formatEventDatesHebrew(slot.event),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Line 2: Times formatted with labels - responsive layout
                        Builder(
                          builder: (context) {
                            // Check if screen is narrow (phone) using actual screen width
                            final screenWidth =
                                MediaQuery.of(context).size.width;
                            final isNarrow = screenWidth < 880;

                            if (isNarrow) {
                              // Narrow screen: each time field on a separate row
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (slot.event.assemblyTime.isNotEmpty)
                                    Text(
                                      'התייצבות: ${slot.event.assemblyTime}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (slot.event.startTime.isNotEmpty)
                                    Text(
                                      'התכנסות: ${slot.event.startTime}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (slot.event.actualShowStartTime.isNotEmpty)
                                    Text(
                                      'תחילת מופע: ${slot.event.actualShowStartTime}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (slot.event.endTime.isNotEmpty)
                                    Text(
                                      'סיום מופע משוער: ${slot.event.endTime}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (slot.event.teamEndTime.isNotEmpty)
                                    Text(
                                      'סיום צוות משוער: ${slot.event.teamEndTime}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                ],
                              );
                            } else {
                              // Wide screen: single line with all times
                              return Text(
                                _formatTimeFields(slot.event),
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              );
                            }
                          },
                        ),
                        // Line 3: Location (only if not empty)
                        if (slot.event.location.isNotEmpty)
                          Text(
                            _formatLocationForDisplay(slot.event.location),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade500),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // Role column
                  Expanded(
                    flex: 2,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Role name text (always centered)
                        GestureDetector(
                          onTap: () {
                            Logger.action('open:eventFormModal', {
                              'eventId': slot.event.id,
                              'role': slot.role.key,
                            });
                            _showEventFormModal(slot.event,
                                selectedRoleKey: slot.role.key);
                          },
                          child: Text(
                            slot.role.hebrewName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              decoration: TextDecoration.none,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Warning icon overlaid on the left edge (doesn't push text)
                        if (slot.hasDoubleAssignment)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: Tooltip(
                              message:
                                  'משובץ גם ל: ${slot.otherRoles.join(", ")}',
                              child: InkWell(
                                onTap: () {
                                  Logger.action('open:doubleAssignmentDialog', {
                                    'eventId': slot.event.id,
                                    'role': slot.role.key,
                                  });
                                  showDialog(
                                    context: context,
                                    builder: (dialogContext) => Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: AlertDialog(
                                        title: Row(
                                          children: const [
                                            Icon(Icons.warning,
                                                color: Colors.orange),
                                            SizedBox(width: 8),
                                            Text('שיבוץ כפול'),
                                          ],
                                        ),
                                        content: Text(
                                          'משובץ גם לתפקידים: ${slot.otherRoles.join(", ")}',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Logger.action(
                                                  'tap:close:doubleAssignmentDialog');
                                              Navigator.of(dialogContext).pop();
                                            },
                                            child: const Text('סגור'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                child: const Icon(
                                  Icons.warning,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Assignment cell with dropdown and buttons
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8.0),
                      child: _buildAssignmentCell(slot, isDirty: isDirty),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Notes / label / alt-phone section (shared with off-quota rows).
          if (extraInfo != null) extraInfo,
        ],
      ),
    );

    // Return the assignment row with swipe gestures:
    // - Swipe left (endToStart): Delete slot
    // - Swipe right (startToEnd): Edit notes (only for filled slots)
    return Dismissible(
      key: Key('slot_${slot.event.id}_${slot.role.key}_${slot.slotIndex}'),
      direction: slot.isFilled
          ? DismissDirection.horizontal // Both directions for filled slots
          : DismissDirection.endToStart, // Only delete for empty slots
      // Right-to-left swipe (delete) - red background
      secondaryBackground: Container(
        alignment: Alignment.centerLeft, // RTL: left side is the visible side
        padding: const EdgeInsets.only(left: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      // Left-to-right swipe (notes) - blue background
      background: Container(
        alignment: Alignment.centerRight, // RTL: right side is the visible side
        padding: const EdgeInsets.only(right: 20),
        color: Colors.blue,
        child: const Icon(Icons.edit_note, color: Colors.white, size: 32),
      ),
      dismissThresholds: const {
        DismissDirection.endToStart: 0.5,
        DismissDirection.startToEnd: 0.5,
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Notes swipe - show notes dialog
          if (slot.isFilled && slot.currentAssignment != null) {
            Logger.action('swipeEdit:notesDialog', {
              'assignmentId': slot.currentAssignment?.id,
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showNotesDialog(slot);
              }
            });
          }
          return false; // Never actually dismiss
        } else {
          // Delete swipe - show delete confirmation dialog
          final isSlotFilled = slot.isFilled;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('מחיקת משרה'),
                content: Text(
                  isSlotFilled
                      ? 'האם אתה בטוח שברצונך למחוק משרה זו?\nפעולה זו תמחק את השיבוץ ותקטין את מספר המשרות הנדרשות לתפקיד זה.'
                      : 'האם אתה בטוח שברצונך למחוק משרה פנויה זו?\nפעולה זו תקטין את מספר המשרות הנדרשות לתפקיד זה.',
                ),
                actions: [
                  TextButton(
                    child: const Text('ביטול'),
                    onPressed: () {
                      Logger.action('tap:cancel:deleteSlot');
                      Navigator.of(dialogContext).pop(false);
                    },
                  ),
                  TextButton(
                    child:
                        const Text('מחק', style: TextStyle(color: Colors.red)),
                    onPressed: () {
                      Logger.action('tap:confirm:deleteSlot', {
                        'eventId': slot.event.id,
                        'role': slot.role.key,
                      });
                      Navigator.of(dialogContext).pop(true);
                    },
                  ),
                ],
              ),
            ),
          );

          if (confirmed == true) {
            Logger.action('swipeDelete:assignment', {
              'assignmentId': slot.currentAssignment?.id,
            });
            await _handleSlotDismiss(slot);
          }
          return false;
        }
      },
      child: rowContent,
    );
  }

  /// A row for an assignment that has no matching quota slot. Display + delete
  /// only: no dropdown, no notes-edit swipe. Swipe-left deletes just the
  /// assignment document (no quota change — it is already outside the quota).
  Widget _buildOffQuotaRow(AssignmentSlot slot, Set<String> stagedSlotKeys,
      Set<String> stagedGoneSlotKeys) {
    final assignment = slot.currentAssignment!;
    final memberName = assignment.teamMember?.name ?? 'לא ידוע';
    // Off-quota rows are display + immediate-delete only today (no dropdown, so
    // a REAL off-quota row can't be staged). The exception is a re-materialized
    // "deleted upstream" staged row (isGone): a staged edit whose slot vanished,
    // injected here by _materializeGoneStagedRows so it stays visible under the
    // red-stripe overlay; its swipe discards the local edit instead of deleting
    // from the DB (there is nothing left in the DB to delete).
    final isDirty = stagedSlotKeys.contains(_getSlotKey(slot));
    final isGone = stagedGoneSlotKeys.contains(_getSlotKey(slot));
    // A note / label / phone must still show when the row is out of quota.
    final extraInfo = _buildAssignmentExtraInfo(assignment);

    return Dismissible(
      key: Key(
          isGone ? 'gone_${_getSlotKey(slot)}' : 'offquota_${assignment.id}'),
      direction: DismissDirection.endToStart,
      secondaryBackground: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white, size: 32),
      ),
      background: const SizedBox.shrink(),
      dismissThresholds: const {DismissDirection.endToStart: 0.5},
      confirmDismiss: (direction) async {
        if (isGone) {
          // Re-materialized "deleted upstream" staged row: its DB assignment is
          // gone, so swiping discards the LOCAL staged edit (nothing to delete
          // in the DB; Save would otherwise re-create it).
          final assignmentBloc = context.read<AssignmentBloc>();
          final discard = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('ביטול שינוי מקומי'),
                content: const Text(
                  'השיבוץ הזה נמחק בשרת. לבטל את השינוי המקומי? '
                  '(לחלופין, שמירה תיצור אותו מחדש.)',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('חזרה'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('בטל שינוי',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          );
          if (discard == true) {
            Logger.action(
                'tap:discardGoneStagedRow', {'slot': _getSlotKey(slot)});
            assignmentBloc.add(DiscardStagedSlot(_getSlotKey(slot)));
          }
          return false;
        }
        final assignmentRepo = context.read<AssignmentRepository>();
        final assignmentBloc = context.read<AssignmentBloc>();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('מחיקת שיבוץ מחוץ למכסה'),
              content: const Text(
                'שיבוץ זה נמצא מחוץ למכסת האירוע. האם למחוק אותו?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('ביטול'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('מחק', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        );
        if (confirmed == true) {
          Logger.action('delete:offQuotaAssignment', {
            'assignmentId': assignment.id,
          });
          try {
            await assignmentRepo.deleteAssignment(assignment.id);
            // Refresh extra-past cache if this row is from an event older than
            // the live window (no-op for in-window events).
            assignmentBloc.add(ExternalExtraPastMutation(assignment.eventId));
            if (mounted) {
              _showAssignmentSnackBar('השיבוץ נמחק בהצלחה',
                  backgroundColor: Colors.green);
            }
          } catch (e) {
            if (mounted) {
              _showAssignmentSnackBar('שגיאה במחיקת השיבוץ: $e',
                  backgroundColor: Colors.red);
            }
          }
        }
        return false; // real-time stream removes the row after delete
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          border: isDirty
              ? Border.all(color: Colors.amber, width: 3)
              : Border(
                  bottom:
                      BorderSide(color: Colors.grey.shade400, width: 1.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(slot.event.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(_formatEventDatesHebrew(slot.event),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(slot.role.hebrewName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Mark first, so in RTL it sits to the RIGHT of the
                          // name — matching the quota row's placement.
                          if (slot.sameDayOtherEvents.isNotEmpty) ...[
                            SameDayAssignmentMark(
                              otherEvents: slot.sameDayOtherEvents,
                              memberName: memberName,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(memberName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('מחוץ למכסה',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (extraInfo != null) extraInfo,
          ],
        ),
      ),
    );
  }

  /// Handle dismissing a slot - removes role slot from event (reduces capacity)
  /// If the slot is filled, also deletes the assignment
  Future<void> _handleSlotDismiss(AssignmentSlot slot) async {
    if (_isMutationInFlight) {
      return;
    }

    // Drop any staged edit for this slot first so a pending stage can't
    // resurrect it after the immediate delete below removes the underlying
    // assignment/quota.
    context.read<AssignmentBloc>().add(
          DiscardStagedSlot(
            '${slot.event.id}_${slot.role.key}_${slot.slotIndex}',
          ),
        );

    _startMutation('מוחק משרה...');
    try {
      final assignmentRepo = context.read<AssignmentRepository>();
      final eventBloc = context.read<EventBloc>();
      final assignmentBloc = context.read<AssignmentBloc>();

      // Step 1: Delete the assignment if it exists (filled slot)
      if (slot.currentAssignment != null) {
        _updateMutationMessage('מוחק שיבוץ...');
        await assignmentRepo.deleteAssignment(slot.currentAssignment!.id);

        // CRITICAL: Clear the cache to prevent stale data
        assignmentRepo.clearCache();
      }

      // Step 2: Get all remaining assignments for this event and role
      final allAssignments =
          await assignmentRepo.getAssignmentsByEvent(slot.event.id);
      final roleAssignments = allAssignments
          .where((a) => a.roleType == slot.role.key)
          .toList()
        ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

      // Step 3: Reorder remaining assignments to fill gaps
      _updateMutationMessage('מעדכן סדר משרות...');
      for (int i = 0; i < roleAssignments.length; i++) {
        if (roleAssignments[i].slotIndex != i) {
          final updated = roleAssignments[i].copyWith(
            slotIndex: i,
            updatedAt: DateTime.now(),
          );
          await assignmentRepo.updateAssignmentUnchecked(updated);
        }
      }

      // Step 4: Reduce the event's quota for this role by 1
      final updatedRoleRequirements =
          Map<String, int>.from(slot.event.roleRequirements);
      final currentQuota = updatedRoleRequirements[slot.role.key] ?? 0;
      if (currentQuota > 0) {
        updatedRoleRequirements[slot.role.key] = currentQuota - 1;
      }

      final updatedEvent = slot.event.copyWith(
        roleRequirements: updatedRoleRequirements,
        updatedAt: DateTime.now(),
      );

      // Step 5: Update the event
      _updateMutationMessage('מעדכן מכסת אירוע...');
      final updateResult = await _dispatchMutation(
        (completion) => eventBloc.add(
          UpdateEvent(updatedEvent, completion: completion),
        ),
        showErrorSnackBar: false,
      );

      if (updateResult.isFailure) {
        _finishMutation();
        return;
      }

      _finishMutation();

      // Refresh extra-past cache if this event is older than the live window
      // (no-op for in-window events; dispatch via captured bloc, not context).
      assignmentBloc.add(ExternalExtraPastMutation(slot.event.id));

      // Show success message
      if (mounted) {
        _showAssignmentSnackBar(
          'המשרה נמחקה בהצלחה',
          backgroundColor: Colors.green,
        );
      }

      // Real-time streams will automatically reload assignment slots to reflect changes
    } catch (e) {
      _finishMutation();
      // Show error message
      if (mounted) {
        _showAssignmentSnackBar(
          'שגיאה במחיקת המשרה: $e',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  /// Show notes dialog for editing assignment notes
  Future<void> _showNotesDialog(AssignmentSlot slot) async {
    final assignment = slot.currentAssignment;
    if (assignment == null) return;

    final notesController = TextEditingController(text: assignment.notes);
    final notesFocusNode = createRtlCursorFixedFocusNode(notesController);
    final phoneController =
        TextEditingController(text: assignment.alternativePhoneNumber ?? '');
    final labelRepository = context.read<AssignmentLabelRepository>();
    final formKey = GlobalKey<FormState>();
    String? selectedSemanticLabelId = assignment.semanticLabelId;
    final inlineCreatedLabels = <AssignmentLabel>[];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final isWide = screenWidth > 600;
        final dialogWidth = isWide ? screenWidth * 0.45 : screenWidth * 0.9;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                actionsAlignment: MainAxisAlignment.center,
                title: Row(
                  children: [
                    const Icon(Icons.edit_note, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'הערות לשיבוץ',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: dialogWidth,
                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${slot.currentAssignment?.teamMember?.name ?? ""} - ${slot.role.hebrewName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            slot.event.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          StreamBuilder<List<AssignmentLabel>>(
                            stream: labelRepository.watchAssignmentLabels(),
                            builder: (context, snapshot) {
                              final allLabels =
                                  snapshot.data ?? const <AssignmentLabel>[];
                              final availableLabels =
                                  _buildNotesDialogAvailableLabels(
                                allLabels,
                                inlineCreatedLabels,
                                selectedLabelId: selectedSemanticLabelId,
                              );
                              final selectedLabel =
                                  availableLabels.firstWhereOrNull(
                                (label) => label.id == selectedSemanticLabelId,
                              );

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap: () async {
                                      Logger.action(
                                          'open:assignmentLabelPicker', {
                                        'assignmentId': assignment.id,
                                      });
                                      await _settleDialogFocus(
                                        dialogContext,
                                      );
                                      if (!dialogContext.mounted) {
                                        return;
                                      }

                                      final result =
                                          await _showAssignmentLabelPickerDialog(
                                        dialogContext,
                                        allLabels: allLabels,
                                        availableLabels: availableLabels,
                                        selectedLabelId:
                                            selectedSemanticLabelId,
                                      );
                                      if (result == null ||
                                          !dialogContext.mounted) {
                                        return;
                                      }

                                      setDialogState(() {
                                        if (result.createdLabel != null) {
                                          inlineCreatedLabels.removeWhere(
                                            (label) =>
                                                label.id ==
                                                result.createdLabel!.id,
                                          );
                                          inlineCreatedLabels.add(
                                            result.createdLabel!,
                                          );
                                        }
                                        selectedSemanticLabelId =
                                            result.selectedLabelId;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'לייבל',
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        prefixIcon: const Icon(
                                          Icons.label_outline,
                                        ),
                                        suffixIcon: const Icon(
                                          Icons.arrow_drop_down,
                                        ),
                                      ),
                                      child: selectedLabel == null
                                          ? Text(
                                              'ללא לייבל',
                                              style: TextStyle(
                                                color: Colors.grey.shade700,
                                              ),
                                            )
                                          : Align(
                                              alignment: Alignment.centerRight,
                                              child: AssignmentLabelChip(
                                                label: selectedLabel,
                                                fontSize: 10,
                                                maxLines: 2,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: notesController,
                            focusNode: notesFocusNode,
                            minLines: 4,
                            maxLines: 10,
                            decoration: InputDecoration(
                              hintText: 'הכנס הערות...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            autofocus: false,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.center,
                            inputFormatters: [PhoneNumberTextInputFormatter()],
                            validator: Validators.validatePhoneNumber,
                            decoration: InputDecoration(
                              labelText: 'טלפון חד פעמי לשיבוץ',
                              hintText: '05X-XXXXXXX',
                              hintTextDirection: TextDirection.ltr,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              prefixIcon: const Icon(Icons.phone),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      Logger.action('tap:cancel:notesDialog');
                      await _settleDialogFocus(dialogContext);
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('ביטול'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Logger.action('tap:saveNotes', {
                        'assignmentId': assignment.id,
                      });
                      final assignmentBloc = context.read<AssignmentBloc>();
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      final phone = phoneController.text.trim();
                      assignmentBloc.add(
                        StageNotesChange(
                          slot: slot,
                          notes: notesController.text.trim(),
                          semanticLabelId: selectedSemanticLabelId,
                          alternativePhoneNumber:
                              phone.isEmpty ? null : phone,
                        ),
                      );

                      await _settleDialogFocus(dialogContext);
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('שמור'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Intentionally do not dispose these immediately after showDialog returns.
    // On Flutter Web, the editable subtree can still be unwinding for a frame
    // after pop, and eager disposal here causes use-after-dispose assertions.
  }

  Future<_AssignmentLabelSelectionResult?> _showAssignmentLabelPickerDialog(
    BuildContext context, {
    required List<AssignmentLabel> allLabels,
    required List<AssignmentLabel> availableLabels,
    required String? selectedLabelId,
  }) async {
    final searchController = TextEditingController();
    final pickerInlineCreatedLabels = <AssignmentLabel>[];
    String searchQuery = '';

    final result = await showDialog<_AssignmentLabelSelectionResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final mergedLabels = _mergeAssignmentLabels(
              availableLabels,
              pickerInlineCreatedLabels,
            );
            final allKnownLabels = _mergeAssignmentLabels(
              allLabels,
              pickerInlineCreatedLabels,
            );
            final normalizedQuery = normalizeForSearch(searchQuery);
            final filteredLabels = normalizedQuery.isEmpty
                ? mergedLabels
                : mergedLabels.where((label) {
                    return normalizeForSearch(label.hebrewName)
                        .contains(normalizedQuery);
                  }).toList();
            final isCreateFromSearchContext =
                filteredLabels.isEmpty && normalizedQuery.isNotEmpty;
            const compactTileDensity = VisualDensity(vertical: -3);

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('בחירת לייבל'),
                content: SizedBox(
                  width: 420,
                  height: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: searchController,
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'חיפוש לייבל...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            searchQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                visualDensity: compactTileDensity,
                                leading: const Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.blue,
                                ),
                                title: const Text('צור לייבל חדש'),
                                subtitle: isCreateFromSearchContext
                                    ? Text(searchQuery.trim())
                                    : null,
                                onTap: () async {
                                  Logger.action(
                                      'open:createAssignmentLabelDialog');
                                  await _settleDialogFocus(dialogContext);
                                  if (!dialogContext.mounted) {
                                    return;
                                  }

                                  final creationResult =
                                      await _showCreateAssignmentLabelDialog(
                                    dialogContext,
                                    existingLabels: allKnownLabels,
                                    initialName: searchQuery.trim(),
                                  );
                                  if (creationResult == null ||
                                      !dialogContext.mounted) {
                                    return;
                                  }

                                  final createdLabel =
                                      creationResult.createdLabel;

                                  if (isCreateFromSearchContext ||
                                      creationResult.shouldSelectLabel) {
                                    Navigator.of(dialogContext).pop(
                                      _AssignmentLabelSelectionResult(
                                        selectedLabelId: createdLabel.id,
                                        createdLabel: createdLabel,
                                      ),
                                    );
                                    return;
                                  }

                                  setDialogState(() {
                                    pickerInlineCreatedLabels.removeWhere(
                                      (label) => label.id == createdLabel.id,
                                    );
                                    pickerInlineCreatedLabels.add(createdLabel);
                                  });
                                },
                              ),
                              if (normalizedQuery.isEmpty)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  visualDensity: compactTileDensity,
                                  leading: const Icon(Icons.clear),
                                  title: const Text('ללא לייבל'),
                                  selected: selectedLabelId == null,
                                  onTap: () {
                                    Logger.action('select:label', {
                                      'labelId': null,
                                    });
                                    Navigator.of(dialogContext).pop(
                                      const _AssignmentLabelSelectionResult(
                                        selectedLabelId: null,
                                      ),
                                    );
                                  },
                                ),
                              if (filteredLabels.isNotEmpty)
                                ...filteredLabels.map((label) {
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    visualDensity: compactTileDensity,
                                    leading: Icon(
                                      Icons.label,
                                      color: _colorFromHex(label.color),
                                    ),
                                    title: Text(
                                      _labelDisplayName(label),
                                    ),
                                    selected: selectedLabelId == label.id,
                                    onTap: () {
                                      Logger.action('select:label', {
                                        'labelId': label.id,
                                      });
                                      Navigator.of(dialogContext).pop(
                                        _AssignmentLabelSelectionResult(
                                          selectedLabelId: label.id,
                                        ),
                                      );
                                    },
                                  );
                                }),
                              if (filteredLabels.isEmpty &&
                                  normalizedQuery.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'הקלד כדי לחפש לייבל או ליצור חדש',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      Logger.action('tap:cancel:assignmentLabelPicker');
                      await _settleDialogFocus(dialogContext);
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('ביטול'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    return result;
  }

  Future<_AssignmentLabelCreationResult?> _showCreateAssignmentLabelDialog(
    BuildContext context, {
    required List<AssignmentLabel> existingLabels,
    String initialName = '',
  }) async {
    final nameController = TextEditingController(text: initialName);
    String selectedColor = AssignmentLabelPalette.defaultColor;
    bool isSaving = false;
    String? errorText;

    final result = await showDialog<_AssignmentLabelCreationResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final trimmedName = nameController.text.trim();
            final duplicateNameError = _duplicateLabelError(
              trimmedName,
              existingLabels,
            );

            Future<void> saveLabel({
              required bool shouldSelectLabel,
            }) async {
              final assignmentLabelRepository =
                  context.read<AssignmentLabelRepository>();
              if (trimmedName.isEmpty) {
                setDialogState(() {
                  errorText = 'יש להזין שם ללייבל';
                });
                return;
              }
              if (duplicateNameError != null) {
                setDialogState(() {
                  errorText = null;
                });
                return;
              }

              setDialogState(() {
                isSaving = true;
                errorText = null;
              });

              await _settleDialogFocus(dialogContext);
              try {
                final createdLabel =
                    await assignmentLabelRepository.createAssignmentLabel(
                  hebrewName: trimmedName,
                  color: selectedColor,
                );

                if (!dialogContext.mounted) {
                  return;
                }

                await _settleDialogFocus(dialogContext);
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop(
                  _AssignmentLabelCreationResult(
                    createdLabel: createdLabel,
                    shouldSelectLabel: shouldSelectLabel,
                  ),
                );
              } catch (e) {
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  isSaving = false;
                  errorText = _extractErrorMessage(e);
                });
              }
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                actionsAlignment: MainAxisAlignment.center,
                actionsOverflowAlignment: OverflowBarAlignment.center,
                actionsOverflowButtonSpacing: 12,
                title: const Text('יצירת לייבל חדש'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameController,
                          enabled: !isSaving,
                          autofocus: false,
                          onChanged: (_) {
                            setDialogState(() {
                              errorText = null;
                            });
                          },
                          decoration: InputDecoration(
                            labelText: 'שם לייבל',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            errorText: duplicateNameError ?? errorText,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'צבע',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              AssignmentLabelPalette.colors.map((colorHex) {
                            final isSelected = colorHex == selectedColor;
                            return InkWell(
                              onTap: isSaving
                                  ? null
                                  : () {
                                      Logger.action('select:labelColor', {
                                        'color': colorHex,
                                      });
                                      setDialogState(() {
                                        selectedColor = colorHex;
                                      });
                                    },
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _colorFromHex(colorHex),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.black87
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 18,
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            Logger.action('tap:cancel:createLabelDialog');
                            await _settleDialogFocus(dialogContext);
                            if (!dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                          },
                    child: const Text('ביטול'),
                  ),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () {
                            Logger.action('tap:createLabel', {
                              'shouldSelectLabel': false,
                            });
                            saveLabel(shouldSelectLabel: false);
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('יצירה'),
                  ),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () {
                            Logger.action('tap:createLabel', {
                              'shouldSelectLabel': true,
                            });
                            saveLabel(shouldSelectLabel: true);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('יצירה ובחירת לייבל'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Intentionally do not dispose immediately after showDialog returns for the
    // same Flutter Web teardown reason as the notes dialog above.
    return result;
  }

  List<AssignmentLabel> _mergeAssignmentLabels(
    List<AssignmentLabel> streamLabels,
    List<AssignmentLabel> inlineCreatedLabels,
  ) {
    final labelsById = <String, AssignmentLabel>{
      for (final label in streamLabels) label.id: label,
      for (final label in inlineCreatedLabels) label.id: label,
    };

    final labels = labelsById.values.toList()
      ..sort((a, b) {
        final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
        if (bySortOrder != 0) {
          return bySortOrder;
        }
        return a.hebrewName.compareTo(b.hebrewName);
      });
    return labels;
  }

  List<AssignmentLabel> _buildNotesDialogAvailableLabels(
    List<AssignmentLabel> allLabels,
    List<AssignmentLabel> inlineCreatedLabels, {
    required String? selectedLabelId,
  }) {
    final visibleLabels = allLabels.where((label) {
      return label.isActive || label.id == selectedLabelId;
    }).toList();

    return _mergeAssignmentLabels(visibleLabels, inlineCreatedLabels);
  }

  String? _duplicateLabelError(
    String trimmedName,
    List<AssignmentLabel> existingLabels, {
    String? excludeId,
  }) {
    if (trimmedName.isEmpty) {
      return null;
    }

    final duplicateLabel = existingLabels.firstWhereOrNull(
      (label) =>
          label.id != excludeId &&
          label.hebrewName.trim().toLowerCase() == trimmedName.toLowerCase(),
    );

    if (duplicateLabel == null) {
      return null;
    }

    return duplicateLabel.isActive
        ? 'כבר קיים לייבל בשם הזה'
        : 'כבר קיים לייבל בשם הזה (בארכיון)';
  }

  String _labelDisplayName(AssignmentLabel label) {
    return label.isActive ? label.hebrewName : '${label.hebrewName} (בארכיון)';
  }

  String _extractErrorMessage(Object error) {
    final message = error.toString();
    const exceptionPrefix = 'Exception: ';
    if (message.startsWith(exceptionPrefix)) {
      return message.substring(exceptionPrefix.length);
    }
    return message;
  }

  Color _colorFromHex(String hex) {
    final normalized = hex.replaceAll('#', '').trim();
    final buffer = StringBuffer();
    if (normalized.length == 6) {
      buffer.write('FF');
    }
    buffer.write(normalized);
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  Widget _buildAssignmentCell(AssignmentSlot slot, {required bool isDirty}) {
    // Get current assigned member:
    // - First try from assignment object itself (handles deactivated members)
    // - Then try from available/alreadyAssigned lists (handles active members)
    final currentMember = slot.currentAssignment?.teamMember ??
        slot.availableMembers.firstWhereOrNull(
          (m) => m.id == slot.currentAssignment?.teamMemberId,
        ) ??
        slot.alreadyAssignedMembers.firstWhereOrNull(
          (m) => m.id == slot.currentAssignment?.teamMemberId,
        );

    // Build items list using String values (member IDs)
    final items = <DropdownMenuItem<String>>[];

    // Add all available members with RTL and centered text
    items.addAll(slot.availableMembers.map((member) {
      final isCurrentlyAssigned = member.id == currentMember?.id;
      return DropdownMenuItem<String>(
        value: member.id,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    member.name,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 4,
                    style: isCurrentlyAssigned
                        ? const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          )
                        : null,
                  ),
                ),
                if (member.isPermanent) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.verified_user,
                    size: 12,
                    color: Colors.blue.shade700,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }));

    // If current member is from alreadyAssigned list, add them too so they can be displayed
    if (currentMember != null &&
        !slot.availableMembers.any((m) => m.id == currentMember.id)) {
      items.insert(
          0,
          DropdownMenuItem<String>(
            value: currentMember.id,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        currentMember.name,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 4,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (currentMember.isPermanent) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified_user,
                        size: 12,
                        color: Colors.blue.shade700,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ));
    }

    // ALWAYS add "שובצו כבר" option (with top border as divider)
    items.add(DropdownMenuItem<String>(
      value: '__show_already_assigned__',
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'שובצו כבר',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));

    // Add "constrained/unavailable members" option (with top border as divider)
    items.add(DropdownMenuItem<String>(
      value: '__show_constrained__',
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 16, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'בעלי מגבלות / לא זמינים',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));

    // Determine if dropdown should be enabled
    // Enable if: there are available members, OR there's a current assignment, OR there are already assigned members
    final bool hasOptions = slot.availableMembers.isNotEmpty ||
        currentMember != null ||
        slot.alreadyAssignedMembers.isNotEmpty;

    return Row(
      children: [
        // Same-day double-booking mark. First child, so in RTL it renders to the
        // RIGHT of the dropdown — the same side as the role column's ⚠ double-role
        // mark, so the two read as a pair instead of bracketing the dropdown.
        if (slot.isFilled && slot.sameDayOtherEvents.isNotEmpty) ...[
          SameDayAssignmentMark(
            otherEvents: slot.sameDayOtherEvents,
            memberName: currentMember?.name ??
                slot.currentAssignment?.teamMemberName ??
                '',
          ),
          const SizedBox(width: 4),
        ],

        // Main dropdown with string values
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
              color: hasOptions
                  ? (slot.isFilled ? Colors.green.shade50 : Colors.white)
                  : Colors.grey.shade200,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = MediaQuery.of(context).size.width;
                // On small screens, make menu wider (expand towards screen center).
                // Use the full container width (constraints + padding) * 1.5
                final double? menuWidth = screenWidth < 600
                    ? (constraints.maxWidth + 24) *
                        2 // 24 = horizontal padding (12*2)
                    : null;
                return DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: ValueKey(
                        '${_getSlotKey(slot)}_${_dropdownResetCounters[_getSlotKey(slot)] ?? 0}'),
                    value: currentMember?.id,
                    isExpanded: true,
                    menuWidth: menuWidth,
                    hint: const Text(
                      'בחר...',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    alignment: AlignmentDirectional.center,
                    selectedItemBuilder: (context) {
                      final selectedItems = <Widget>[];

                      // Build custom selected item display with proper wrapping
                      for (var member in slot.availableMembers) {
                        selectedItems.add(
                          DropdownMenuItem<String>(
                            value: member.id,
                            enabled: false,
                            child: Container(
                              constraints: const BoxConstraints(
                                  minWidth: double.infinity),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      member.name,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 4,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.black),
                                    ),
                                  ),
                                  if (member.isPermanent) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.verified_user,
                                      size: 12,
                                      color: Colors.blue.shade700,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // Current member from already assigned (if exists)
                      if (currentMember != null &&
                          !slot.availableMembers
                              .any((m) => m.id == currentMember.id)) {
                        selectedItems.insert(
                          0,
                          DropdownMenuItem<String>(
                            value: currentMember.id,
                            enabled: false,
                            child: Container(
                              constraints: const BoxConstraints(
                                  minWidth: double.infinity),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      currentMember.name,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 4,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.black),
                                    ),
                                  ),
                                  if (currentMember.isPermanent) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.verified_user,
                                      size: 12,
                                      color: Colors.blue.shade700,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // Add placeholders for button items to match items count
                      // __show_already_assigned__, __show_constrained__
                      for (var i = 0; i < 2; i++) {
                        selectedItems.add(const SizedBox.shrink());
                      }

                      return selectedItems;
                    },
                    items: items,
                    onChanged: hasOptions
                        ? (selectedValue) {
                            Logger.action('select:assignmentMember', {
                              'eventId': slot.event.id,
                              'role': slot.role.key,
                              'value': selectedValue,
                            });
                            if (selectedValue == '__show_already_assigned__') {
                              // Show dialog for already-assigned members
                              _showAlreadyAssignedDialog(slot);
                            } else if (selectedValue ==
                                '__show_constrained__') {
                              // Show dialog for constrained/unavailable members
                              _showConstrainedMembersDialog(slot);
                            } else if (selectedValue != null) {
                              // Find the selected member by ID
                              final member = slot.availableMembers
                                      .firstWhereOrNull(
                                    (m) => m.id == selectedValue,
                                  ) ??
                                  slot.alreadyAssignedMembers.firstWhereOrNull(
                                    (m) => m.id == selectedValue,
                                  );

                              if (member != null) {
                                _handleAssignmentChange(slot, member);
                              }
                            }
                          }
                        : null, // Disable dropdown when no options available
                  ),
                );
              },
            ),
          ),
        ),

        const SizedBox(width: 4),

        // "ניקוי" button - only show if slot is filled AND currentMember is valid
        if (slot.isFilled && currentMember != null)
          IconButton(
            onPressed: () {
              Logger.action('tap:clearAssignment', {
                'assignmentId': slot.currentAssignment?.id,
              });
              _handleClearAssignment(slot);
            },
            icon: const Icon(Icons.clear, size: 20),
            color: Colors.red,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'ניקוי',
            splashRadius: 16,
          ),

        // Inline "↩" undo for a staged (unsaved) change on this slot —
        // reverts just this slot to its DB baseline. Same operation as the
        // per-row "קח מה-DB" resolution at Save. See "Discard" (per-slot) in
        // docs/superpowers/specs/2026-07-15-assignments-staged-save-design.md.
        if (isDirty)
          IconButton(
            onPressed: () {
              final slotKey = _getSlotKey(slot);
              Logger.action('tap:discardStagedSlot', {
                'eventId': slot.event.id,
                'role': slot.role.key,
                'slotIndex': slot.slotIndex,
              });
              context.read<AssignmentBloc>().add(DiscardStagedSlot(slotKey));
            },
            icon: const Icon(Icons.undo, size: 20),
            color: Colors.amber.shade800,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'בטל שינוי',
            splashRadius: 16,
          ),

        // Removed: "שובצו כבר" button - now integrated in dropdown
      ],
    );
  }

  Future<void> _handleClearAssignment(AssignmentSlot slot) async {
    if (slot.currentAssignment != null) {
      context.read<AssignmentBloc>().add(
            StageMemberChange(slot: slot, member: null),
          );
    }
  }

  Future<void> _showAlreadyAssignedDialog(AssignmentSlot slot) async {
    // FILTER: Exclude members who already have this exact role
    final filteredSameEventMembers =
        slot.alreadyAssignedMembers.where((member) {
      final hasThisRole = _allSlots.any((s) =>
          s.event.id == slot.event.id &&
          s.role.key == slot.role.key && // Same role type
          s.isFilled &&
          s.currentAssignment!.teamMemberId == member.id);
      return !hasThisRole;
    }).toList();

    final selectedMember = await showDialog<TeamMember>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'אנשים שכבר שובצו לאירוע "${slot.event.name}"',
                  maxLines: 3,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (filteredSameEventMembers.isEmpty)
                  // Show message when no members are available
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline,
                            size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 16),
                        Text(
                          slot.alreadyAssignedMembers.isEmpty
                              ? 'אין אנשים שכבר שובצו לאירוע זה'
                              : 'כל חברי הצוות שיכולים להשתבץ לתפקיד ${slot.role.hebrewName}, ומשובצים לאירוע זה, כבר משובצים בתפקיד זה...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  // Show list of members
                  Text(
                    'האנשים הבאים כבר משובצים לאירוע זה:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  // Make the list scrollable with constrained height
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height *
                          0.5, // Max 50% of screen height
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredSameEventMembers.length,
                      itemBuilder: (context, index) {
                        final member = filteredSameEventMembers[index];
                        // Find what OTHER roles this person has in this event (excluding current role)
                        final memberRoles = _allSlots
                            .where((s) =>
                                s.event.id == slot.event.id &&
                                s.isFilled &&
                                s.currentAssignment!.teamMemberId ==
                                    member.id &&
                                s.role.key !=
                                    slot.role.key) // Exclude current role
                            .map((s) => s.role.hebrewName)
                            .toList();
                        final subtitle = 'תפקידים: ${memberRoles.join(", ")}';

                        return ListTile(
                          title: Align(
                            alignment: Alignment.centerRight,
                            child: _buildMemberNameWithPermanentShield(member),
                          ),
                          subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                          trailing: ElevatedButton(
                            onPressed: () {
                              Logger.action('tap:assignAnyway', {
                                'eventId': slot.event.id,
                                'role': slot.role.key,
                                'memberId': member.id,
                              });
                              Navigator.of(context).pop(member);
                            },
                            child: const Text('שבץ בכל זאת'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:close:alreadyAssignedDialog');
                Navigator.of(context).pop();
              },
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );

    if (selectedMember != null) {
      _handleAssignmentChange(slot, selectedMember);
    } else {
      // User closed dialog without selecting - force dropdown reset
      _resetDropdown(slot);
    }
  }

  /// Show dialog with constrained/unavailable team members for the event
  /// Allows admin to force-assign them despite constraints
  Future<void> _showConstrainedMembersDialog(AssignmentSlot slot) async {
    // Get all active team members
    final teamRepo = context.read<TeamRepository>();
    final allMembers = await teamRepo.getActiveTeamMembers();

    // IDs of members already in available and alreadyAssigned lists
    final availableIds = slot.availableMembers.map((m) => m.id).toSet();
    final alreadyAssignedIds =
        slot.alreadyAssignedMembers.map((m) => m.id).toSet();

    // Members assigned to another overlapping event should also appear here.
    final sameDayAssignedMembers = slot.sameDayAssignedMembers.where((member) {
      if (availableIds.contains(member.id) ||
          alreadyAssignedIds.contains(member.id)) {
        return false;
      }
      return true;
    }).toList();

    // Find constrained/unavailable members:
    // - Must have the required role capability
    // - Must NOT be in available or alreadyAssigned lists (those are already shown)
    // - Must be active and not archived
    final constrainedMembersMap = <String, TeamMember>{
      for (final member in sameDayAssignedMembers) member.id: member,
    };

    for (final member in allMembers) {
      // Must have role capability
      if (!member.canPerformRole(slot.role.key)) {
        continue;
      }

      // Must not already be in available or alreadyAssigned lists
      if (availableIds.contains(member.id) ||
          alreadyAssignedIds.contains(member.id)) {
        continue;
      }

      // Must be unavailable for the event (including time-based constraints)
      final isAvailable = member.isAvailableForEventWithTime(slot.event);
      if (!isAvailable) {
        constrainedMembersMap[member.id] = member;
      }
    }

    final constrainedMembers = constrainedMembersMap.values.toList();

    // Sort alphabetically
    constrainedMembers.sort((a, b) => a.name.compareTo(b.name));

    if (!mounted) return;

    final selectedMember = await showDialog<TeamMember>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.block, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'בעלי מגבלות / לא זמינים - "${slot.event.name}"',
                  maxLines: 3,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (constrainedMembers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline,
                            size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 16),
                        Text(
                          'אין אנשים עם מגבלות או חוסר זמינות לתפקיד ${slot.role.hebrewName} באירוע זה',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    'האנשים הבאים לא זמינים או משובצים לאירועים אחרים באותם תאריכים:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: constrainedMembers.length,
                      itemBuilder: (context, index) {
                        final member = constrainedMembers[index];
                        final sameDayEvents =
                            slot.sameDayEventInfo[member.id] ?? [];
                        final isSameDayAssigned = sameDayEvents.isNotEmpty;

                        // Determine the reason for unavailability/constraint
                        String reason;
                        if (isSameDayAssigned) {
                          reason = 'משובצ/ת ב: ${sameDayEvents.join(", ")}';
                        } else if (member.isPermanent) {
                          reason = 'מגבלה מאושרת';
                        } else {
                          reason = 'לא ציין/ה זמינות';
                        }

                        return ListTile(
                          leading: Icon(
                            isSameDayAssigned
                                ? Icons.event
                                : member.isPermanent
                                    ? Icons.event_busy
                                    : Icons.schedule,
                            color: Colors.red.shade400,
                          ),
                          title: Align(
                            alignment: Alignment.centerRight,
                            child: _buildMemberNameWithPermanentShield(member),
                          ),
                          subtitle: Text(
                            reason,
                            style: TextStyle(
                                color: Colors.red.shade600, fontSize: 12),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Logger.action('tap:assignConstrainedAnyway', {
                                'eventId': slot.event.id,
                                'role': slot.role.key,
                                'memberId': member.id,
                              });
                              Navigator.of(context).pop(member);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('שבץ בכל זאת'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:close:constrainedMembersDialog');
                Navigator.of(context).pop();
              },
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );

    if (selectedMember != null) {
      _handleAssignmentChangeWithBypass(slot, selectedMember);
    } else {
      // User closed dialog without selecting - force dropdown reset
      _resetDropdown(slot);
    }
  }

  Widget _buildMemberNameWithPermanentShield(TeamMember member) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(member.name),
          if (member.isPermanent) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified_user, size: 16, color: Colors.blue.shade700),
          ],
        ],
      ),
    );
  }

  /// Handle assignment change bypassing conflict checks (for constrained members)
  Future<void> _handleAssignmentChangeWithBypass(
      AssignmentSlot slot, TeamMember selectedMember) async {
    if (_isMutationInFlight) {
      return;
    }

    // Check if already assigned (no-op)
    if (slot.currentAssignment?.teamMemberId == selectedMember.id) {
      return;
    }

    // Stage the change instantly (no write yet). Conflict handling (bypass
    // or not) now happens at Save time, so the bypass distinction is moot
    // here — both handlers stage the same way.
    context.read<AssignmentBloc>().add(
          StageMemberChange(slot: slot, member: selectedMember),
        );
  }

  Future<void> _handleAssignmentChange(
      AssignmentSlot slot, TeamMember selectedMember) async {
    if (_isMutationInFlight) {
      return;
    }

    // Check if already assigned (no-op)
    if (slot.currentAssignment?.teamMemberId == selectedMember.id) {
      return;
    }

    // Stage the change instantly (no write yet); the actual write happens
    // later when the admin saves all staged changes.
    context.read<AssignmentBloc>().add(
          StageMemberChange(slot: slot, member: selectedMember),
        );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 80, color: Colors.red),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(fontSize: 18, color: Colors.red)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Logger.action('tap:retryLoadSlots');
              context.read<AssignmentBloc>().add(const LoadAssignmentSlots());
            },
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(int totalSlots, int filledSlots, int unfilledSlots) {
    return Column(
      children: [
        // Interactive filter bar
        InteractiveFilterBar(
          options: [
            FilterOption(label: 'סה״כ', count: totalSlots.toString()),
            FilterOption(label: 'משובצים', count: filledSlots.toString()),
            FilterOption(label: 'לא משובצים', count: unfilledSlots.toString()),
          ],
          selectedIndex: FilterPersistence.assignmentFilterIndex,
          onFilterChanged: _onFilterChanged,
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_outlined,
                    size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  FilterPersistence.assignmentFilterIndex == 1
                      ? 'אין תפקידים משובצים'
                      : FilterPersistence.assignmentFilterIndex == 2
                          ? 'אין תפקידים פנויים'
                          : 'אין תפקידים להצגה',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showFilterModal(
      BuildContext context, AssignmentSlotsLoaded state) async {
    void applyFilter(Set<String> selectedEventIds) {
      Logger.action('filter:events', {'count': selectedEventIds.length});
      if (!mounted) return;
      setState(() {});
      if (selectedEventIds.isEmpty) {
        context.read<AssignmentBloc>().add(const ClearEventFilter());
      } else {
        context.read<AssignmentBloc>().add(ApplyEventFilter(selectedEventIds));
      }
    }

    List<Event> availableEvents;

    // Get all events from repository (not just from slots) when showPastEvents is true
    // This ensures past events appear in the filter when the switch is on
    if (FilterPersistence.showPastEvents) {
      final eventRepo = context.read<EventRepository>();
      final allEvents = await eventRepo.getAllEvents();
      availableEvents = allEvents
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
    } else {
      // Original behavior when showPastEvents is false
      // Get unique events from slots that have at least one role with capacity > 0
      final eventsMap = <String, Event>{};
      for (final slot in state.slots) {
        if (!eventsMap.containsKey(slot.event.id)) {
          eventsMap[slot.event.id] = slot.event;
        }
      }
      availableEvents = eventsMap.values.toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AssignmentFilterModal(
        availableEvents: availableEvents,
        selectedEventIds: state.selectedEventIds,
        onFilterChanged: applyFilter,
      ),
    );
  }

  /// Show event form modal for editing an event
  void _showEventFormModal(Event event, {String? selectedRoleKey}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => EventFormModal(
        event: event,
        selectedRoleKey: selectedRoleKey,
        filterIndex: 1, // Default to future for assignments screen
        onSuccess: () {
          Navigator.of(modalContext).pop();
          // Real-time streams will automatically reload assignment slots to reflect changes
        },
      ),
    );
  }

  /// Show manual assignment flow (3-step process)
  Future<void> _showManualAssignmentFlow() async {
    Logger.action('open:manualAssignmentFlow');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: ManualAssignmentFlowDialog(),
      ),
    );

    if (result != null) {
      // Extract data from the flow
      final Event event = result['event'];
      final TeamMember teamMember = result['teamMember'];
      final String roleType = result['roleType'];

      // Create assignment and increase quota
      await _createAssignmentAndQuota(event, teamMember, roleType);
    }
  }

  /// Create assignment and increase event quota for the selected role
  Future<void> _createAssignmentAndQuota(
      Event event, TeamMember teamMember, String roleType) async {
    if (_isMutationInFlight) {
      return;
    }

    try {
      final eventBloc = context.read<EventBloc>();
      final assignmentBloc = context.read<AssignmentBloc>();

      // Step 1: Find slot indices already used for this event+role from the
      // bloc's in-memory state (avoids a Firestore round-trip + relation
      // population, since the bloc's real-time stream already has this data).
      // Falls back to a Firestore read if the bloc hasn't loaded yet.
      final assignmentState = assignmentBloc.state;
      List<int> usedSlotIndices;
      if (assignmentState is AssignmentsLoaded) {
        usedSlotIndices = assignmentState.assignments
            .where((a) => a.eventId == event.id && a.roleType == roleType)
            .map((a) => a.slotIndex)
            .toList();
      } else if (assignmentState is AssignmentSlotsLoaded) {
        usedSlotIndices = assignmentState.slots
            .where((s) =>
                s.event.id == event.id &&
                s.role.key == roleType &&
                s.currentAssignment != null)
            .map((s) => s.currentAssignment!.slotIndex)
            .toList();
      } else {
        final existingAssignments = await context
            .read<AssignmentRepository>()
            .getAssignmentsByEvent(event.id);
        usedSlotIndices = existingAssignments
            .where((a) => a.roleType == roleType)
            .map((a) => a.slotIndex)
            .toList();
      }
      usedSlotIndices.sort();

      // Step 2: Find the next available slot index (first gap, or end of list)
      int nextSlotIndex = 0;
      for (final slotIndex in usedSlotIndices) {
        if (slotIndex == nextSlotIndex) {
          nextSlotIndex++;
        } else {
          break; // Found a gap
        }
      }

      // Step 3: Create the new assignment
      final newAssignment = Assignment(
        id: const Uuid().v4(),
        eventId: event.id,
        teamMemberId: teamMember.id,
        roleType: roleType,
        slotIndex: nextSlotIndex,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        event: event,
        teamMember: teamMember,
      );

      // Step 4: Update event's role requirements (increase quota by 1)
      final updatedRoleRequirements =
          Map<String, int>.from(event.roleRequirements);
      final currentQuota = updatedRoleRequirements[roleType] ?? 0;
      updatedRoleRequirements[roleType] = currentQuota + 1;

      final updatedEvent = event.copyWith(
        roleRequirements: updatedRoleRequirements,
        updatedAt: DateTime.now(),
      );

      _startMutation('מעדכן מכסת אירוע...');

      final quotaUpdateResult = await _dispatchMutation(
        (completion) => eventBloc.add(
          UpdateEvent(updatedEvent, completion: completion),
        ),
        showErrorSnackBar: false,
      );

      if (quotaUpdateResult.isFailure) {
        _finishMutation();
        return;
      }

      _updateMutationMessage('יוצר שיבוץ...');

      final assignmentResult = await _dispatchMutation(
        (completion) => context.read<AssignmentBloc>().add(
              CreateAssignmentWithBypass(
                newAssignment,
                completion: completion,
              ),
            ),
        showErrorSnackBar: false,
      );

      if (assignmentResult.isFailure) {
        _updateMutationMessage('משחזר מכסת אירוע...');
        final rollbackResult = await _dispatchMutation(
          (completion) => eventBloc.add(
            UpdateEvent(event, completion: completion),
          ),
          showErrorSnackBar: false,
        );
        _finishMutation();
        if (rollbackResult.isFailure && mounted) {
          _showAssignmentSnackBar(
            'השיבוץ נכשל וגם שחזור המכסה לא הושלם. יש לבדוק את האירוע ידנית.',
            backgroundColor: Colors.red,
          );
        }
        return;
      }

      _finishMutation();
    } catch (e) {
      // Show error message
      _finishMutation();
      if (mounted) {
        _showAssignmentSnackBar(
          'שגיאה ביצירת שיבוץ: $e',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    // Sign out first
    context.read<UserSelectionBloc>().add(const SignOut());

    // Listen for the state change and then navigate once
    bool handled = false;
    StreamSubscription? subscription;
    subscription = context.read<UserSelectionBloc>().stream.listen((state) {
      if (!handled && state is UserSignedOut && context.mounted) {
        handled = true;
        subscription?.cancel();
        final envPrefix = EnvironmentService.instance.routePrefix;
        context.go('$envPrefix/whoami');
      }
    });
  }

  /// Format event dates in Hebrew (like user/assignments screen)
  String _formatEventDatesHebrew(Event event) {
    final isSameDay = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    if (isSameDay) {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)}';
    } else {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)} - יום ${_getFullHebrewDayName(event.endDate.weekday)} ${event.endDate.day} ב${_getHebrewMonthName(event.endDate.month)}';
    }
  }

  /// Format time fields with labels: "התייצבות - <HH:mm> | התכנסות - <HH:mm> | תחילת מופע - <HH:mm> | סיום - <HH:mm>"
  String _formatTimeFields(Event event) {
    final parts = <String>[];

    if (event.assemblyTime.isNotEmpty) {
      parts.add('התייצבות - ${event.assemblyTime}');
    }
    if (event.startTime.isNotEmpty) {
      parts.add('התכנסות - ${event.startTime}');
    }
    if (event.actualShowStartTime.isNotEmpty) {
      parts.add('תחילת מופע - ${event.actualShowStartTime}');
    }
    if (event.endTime.isNotEmpty) {
      parts.add('סיום מופע משוער - ${event.endTime}');
    }
    if (event.teamEndTime.isNotEmpty) {
      parts.add('סיום צוות משוער - ${event.teamEndTime}');
    }

    return parts.join(' | ');
  }

  /// Get full Hebrew day name (e.g., "ראשון", "שני")
  String _getFullHebrewDayName(int weekday) {
    const days = ['', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
    return days[weekday];
  }

  /// Get Hebrew month name (e.g., "פברואר")
  String _getHebrewMonthName(int month) {
    const months = [
      '',
      'ינואר',
      'פברואר',
      'מרץ',
      'אפריל',
      'מאי',
      'יוני',
      'יולי',
      'אוגוסט',
      'ספטמבר',
      'אוקטובר',
      'נובמבר',
      'דצמבר'
    ];
    return months[month];
  }

}

/// Bright-red diagonal hazard stripes over a light red wash, painted across a
/// slot row to mark it "deleted upstream but kept locally because dirty" (see
/// [_AssignmentListScreenState._withDeletedRemotelyOverlay]). Semi-transparent
/// so the row content stays readable underneath.
class _DiagonalStripesPainter extends CustomPainter {
  const _DiagonalStripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Light red wash so the row content still reads through.
    final wash = Paint()..color = Colors.red.withValues(alpha: 0.10);
    canvas.drawRect(Offset.zero & size, wash);

    // Bright-red 45° hazard stripes.
    final stripe = Paint()
      ..color = Colors.red.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    const spacing = 20.0;
    // Start x back by size.height so the slanted lines still cover the left
    // edge over the full row height (each line drops by size.height in x).
    for (double x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(
          Offset(x, 0), Offset(x + size.height, size.height), stripe);
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalStripesPainter oldDelegate) => false;
}
