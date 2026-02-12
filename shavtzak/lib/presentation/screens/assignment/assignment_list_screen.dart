import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../../core/constants/role_types.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/event.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../core/services/environment_service.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/assignment/assignment_state.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/role/role_bloc.dart';
import '../../bloc/role/role_state.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import 'models/assignment_slot.dart';
import '../../widgets/interactive_filter_bar.dart';
import 'assignment_filter_modal.dart';
import '../event/widgets/event_form_modal.dart';
import 'manual_assignment_flow_dialog.dart';
import '../../widgets/map_location_picker.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/phone_input_formatter.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../core/utils/search_utils.dart';

class AssignmentListScreen extends StatefulWidget {
  const AssignmentListScreen({super.key});

  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
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

  @override
  void initState() {
    super.initState();
    context.read<AssignmentBloc>().add(const LoadAssignmentSlots());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Handle filter change
  void _onFilterChanged(int newIndex) {
    setState(() {
      FilterPersistence.assignmentFilterIndex = newIndex;
    });
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
  List<AssignmentSlot> _filterAssignments(List<AssignmentSlot> slots, int filterIndex) {
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

  /// Filter slots by search query (event name, role name, member name)
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
        if (normalizeForSearch(slot.currentAssignment!.teamMember!.name).contains(normalizedQuery)) {
          return true;
        }
      }
      return false;
    }).toList();
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
                    setState(() {
                      FilterPersistence.showPastEvents = !FilterPersistence.showPastEvents;
                    });
                    // Reload assignments with new filter setting
                    context.read<AssignmentBloc>().add(const LoadAssignmentSlots());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                child: Center(child: Text('שיבוצים', style: TextStyle(fontSize: 20))),
              ),
              // Trailing icons
              IconButton(
                icon: const Icon(Icons.home),
                tooltip: 'בית',
                onPressed: () {
                  final envPrefix = EnvironmentService.instance.routePrefix;
                  context.go('$envPrefix/admin');
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'התנתק',
                onPressed: () => _logout(context),
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'assignment_fab',
          onPressed: () => _showManualAssignmentFlow(),
          backgroundColor: Colors.blue,
          child: const Icon(Icons.add, color: Colors.white),
          tooltip: 'שיבוץ ידני',
        ),
        body: BlocConsumer<AssignmentBloc, AssignmentState>(
          listener: (context, state) {
            if (state is AssignmentError) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                      content: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text(state.message),
                      ),
                      backgroundColor: Colors.red),
                );
            } else if (state is AssignmentOperationSuccess) {
              // BLoC will automatically reload slots without showing loading
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                      content: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text(state.message),
                      ),
                      backgroundColor: Colors.green),
                );
            } else if (state is AssignmentConflictWarning) {
              // Show conflict warning to user
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text('שיבוץ לא בוצע: ${state.conflicts.join(", ")}'),
                    ),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 2),
                  ),
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
                final hasTeamMembers = state.slots.any((slot) => slot.availableMembers.isNotEmpty);
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
    // Store all slots for checking
    _allSlots = state.slots;

    // Apply event filter first
    var filteredSlots = state.slots;
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
    final filteredByStatus = _filterAssignments(filteredSlots, FilterPersistence.assignmentFilterIndex);

    // Apply search filter
    final slots = _searchSlots(filteredByStatus);

    if (slots.isEmpty) {
      return _buildEmptyState(totalSlots, filledSlots, unfilledSlots);
    }

    return RefreshIndicator(
      onRefresh: () async {
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
            FilterOption(label: 'לא משובצים', count: unfilledSlots.toString()),
          ],
          selectedIndex: FilterPersistence.assignmentFilterIndex,
          onFilterChanged: _onFilterChanged,
        ),

        // Search bar with filter button inside
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'חיפוש באירוע, תפקיד או שם...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Clear button (only when there's text)
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      ),
                    // Filter button (always visible)
                    IconButton(
                      icon: Badge(
                        isLabelVisible: state.selectedEventIds.isNotEmpty,
                        label: Text(state.selectedEventIds.length.toString()),
                        child: Icon(
                          Icons.filter_list,
                          color: state.selectedEventIds.isNotEmpty
                              ? Colors.blue.shade700
                              : null,
                        ),
                      ),
                      onPressed: () => _showFilterModal(context, state),
                      tooltip: state.selectedEventIds.isEmpty
                          ? 'סינון לפי אירוע'
                          : 'סינון: ${state.selectedEventIds.length} אירועים',
                    ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        ),

        // Header row
        Container(
          height: 48,
          color: Colors.grey.shade200,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: slots.length,
            itemBuilder: (context, index) {
              return _buildSlotRow(slots[index]);
            },
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildSlotRow(AssignmentSlot slot) {
    final hasNotes = slot.isFilled &&
                     slot.currentAssignment != null &&
                     slot.currentAssignment!.notes.isNotEmpty;
    final hasAltPhone = slot.isFilled &&
                        slot.currentAssignment != null &&
                        slot.currentAssignment!.alternativePhoneNumber != null &&
                        slot.currentAssignment!.alternativePhoneNumber!.isNotEmpty;
    final hasExtraInfo = hasNotes || hasAltPhone;

    final rowContent = Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade400, width: 1.5)),
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
                          onTap: () => _showEventFormModal(slot.event),
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
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Line 2: Times formatted with labels - responsive layout
                        Builder(
                          builder: (context) {
                            // Check if screen is narrow (phone) using actual screen width
                            final screenWidth = MediaQuery.of(context).size.width;
                            final isNarrow = screenWidth < 880;

                            if (isNarrow) {
                              // Narrow screen: each time field on a separate row
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (slot.event.assemblyTime.isNotEmpty)
                                    Text(
                                      'התייצבות: ${slot.event.assemblyTime}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (slot.event.startTime.isNotEmpty)
                                    Text(
                                      'התכנסות: ${slot.event.startTime}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (slot.event.actualShowStartTime.isNotEmpty)
                                    Text(
                                      'תחילת מופע: ${slot.event.actualShowStartTime}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                  if (slot.event.endTime.isNotEmpty)
                                    Text(
                                      'סיום: ${slot.event.endTime}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                ],
                              );
                            } else {
                              // Wide screen: single line with all times
                              return Text(
                                _formatTimeFields(slot.event),
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
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
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
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
                          onTap: () => _showEventFormModal(slot.event, selectedRoleKey: slot.role.key),
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
                              message: 'משובץ גם ל: ${slot.otherRoles.join(", ")}',
                              child: InkWell(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (dialogContext) => Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: AlertDialog(
                                        title: Row(
                                          children: const [
                                            Icon(Icons.warning, color: Colors.orange),
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
                                            onPressed: () => Navigator.of(dialogContext).pop(),
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
                      child: _buildAssignmentCell(slot),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Notes and alternative phone section
          if (hasExtraInfo)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  children: [
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
                                      text: slot.currentAssignment!.notes,
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
                                      text: slot.currentAssignment!.alternativePhoneNumber!,
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
            ),
        ],
      ),
    );

    // Return the assignment row with swipe gestures:
    // - Swipe left (endToStart): Delete slot
    // - Swipe right (startToEnd): Edit notes (only for filled slots)
    return Dismissible(
      key: Key('slot_${slot.event.id}_${slot.role.key}_${slot.slotIndex}'),
      direction: slot.isFilled
          ? DismissDirection.horizontal  // Both directions for filled slots
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
              await _showNotesDialog(slot);
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
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                    TextButton(
                      child: const Text('מחק', style: TextStyle(color: Colors.red)),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ],
                ),
              ),
            );

            if (confirmed == true) {
              await _handleSlotDismiss(slot);
            }
            return false;
          }
          },
          child: rowContent,
        );
  }

  /// Handle dismissing a slot - removes role slot from event (reduces capacity)
  /// If the slot is filled, also deletes the assignment
  Future<void> _handleSlotDismiss(AssignmentSlot slot) async {
    print('🗑️ [DELETE_DEBUG] _handleSlotDismiss START');
    print('  Event: ${slot.event.name}');
    print('  Role: ${slot.role.hebrewName}');
    print('  Slot Index: ${slot.slotIndex}');
    print('  Is Filled: ${slot.isFilled}');
    print('  Assignment ID: ${slot.currentAssignment?.id ?? "none"}');

    try {
      final assignmentRepo = context.read<AssignmentRepository>();
      final eventBloc = context.read<EventBloc>();

      // Step 1: Delete the assignment if it exists (filled slot)
      if (slot.currentAssignment != null) {
        print('  💾 Deleting assignment from DB...');
        await assignmentRepo.deleteAssignment(slot.currentAssignment!.id);

        // CRITICAL: Clear the cache to prevent stale data
        print('  🧹 Clearing repository cache...');
        assignmentRepo.clearCache();
        print('  ✅ Assignment deleted and cache cleared');
        print('  🔄 Real-time stream should trigger automatically...');
      }

      // Step 2: Get all remaining assignments for this event and role
      final allAssignments = await assignmentRepo.getAssignmentsByEvent(slot.event.id);
      final roleAssignments = allAssignments
          .where((a) => a.roleType == slot.role.key)
          .toList()
        ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

      // Step 3: Reorder remaining assignments to fill gaps
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
      final updatedRoleRequirements = Map<String, int>.from(slot.event.roleRequirements);
      final currentQuota = updatedRoleRequirements[slot.role.key] ?? 0;
      if (currentQuota > 0) {
        updatedRoleRequirements[slot.role.key] = currentQuota - 1;
      }

      final updatedEvent = slot.event.copyWith(
        roleRequirements: updatedRoleRequirements,
        updatedAt: DateTime.now(),
      );

      // Step 5: Update the event
      eventBloc.add(UpdateEvent(updatedEvent));

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('המשרה נמחקה בהצלחה'),
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
      }

      // Real-time streams will automatically reload assignment slots to reflect changes
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('שגיאה במחיקת המשרה: $e'),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
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
    final phoneController = TextEditingController(text: assignment.alternativePhoneNumber ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final isWide = screenWidth > 600;
        final dialogWidth = isWide ? screenWidth * 0.45 : screenWidth * 0.9;

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
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show assignment info
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
                  // Alternative phone number field
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
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop({
                    'notes': notesController.text,
                    'phone': phoneController.text,
                  });
                }
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

    // Dispose local focus node and controllers after dialog closes
    notesFocusNode.dispose();
    notesController.dispose();
    phoneController.dispose();

    if (result != null && mounted) {
      final phone = result['phone'];
      // Update notes and phone via BLoC
      context.read<AssignmentBloc>().add(
        UpdateAssignmentNotes(
          assignment.id,
          result['notes']!,
          alternativePhoneNumber: phone != null && phone.isNotEmpty ? phone : null,
        ),
      );
    }
  }

  Widget _buildAssignmentCell(AssignmentSlot slot) {
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
      items.insert(0, DropdownMenuItem<String>(
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
                    ? (constraints.maxWidth + 24) * 2 // 24 = horizontal padding (12*2)
                    : null;
                return DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: ValueKey('${_getSlotKey(slot)}_${_dropdownResetCounters[_getSlotKey(slot)] ?? 0}'),
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
                          constraints: const BoxConstraints(minWidth: double.infinity),
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
                                  style: const TextStyle(fontSize: 12, color: Colors.black),
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
                      !slot.availableMembers.any((m) => m.id == currentMember.id)) {
                    selectedItems.insert(0,
                      DropdownMenuItem<String>(
                        value: currentMember.id,
                        enabled: false,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: double.infinity),
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
                                  style: const TextStyle(fontSize: 12, color: Colors.black),
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
                onChanged: hasOptions ? (selectedValue) {
              if (selectedValue == '__show_already_assigned__') {
                // Show dialog for already-assigned members
                _showAlreadyAssignedDialog(slot);
              } else if (selectedValue == '__show_constrained__') {
                // Show dialog for constrained/unavailable members
                _showConstrainedMembersDialog(slot);
              } else if (selectedValue != null) {
                // Find the selected member by ID
                final member = slot.availableMembers.firstWhereOrNull(
                      (m) => m.id == selectedValue,
                    ) ??
                    slot.alreadyAssignedMembers.firstWhereOrNull(
                      (m) => m.id == selectedValue,
                    );

                if (member != null) {
                  _handleAssignmentChange(slot, member);
                }
              }
            } : null, // Disable dropdown when no options available
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
            onPressed: () => _handleClearAssignment(slot),
            icon: const Icon(Icons.clear, size: 20),
            color: Colors.red,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'ניקוי',
            splashRadius: 16,
          ),

        // Removed: "שובצו כבר" button - now integrated in dropdown
      ],
    );
  }

  void _handleClearAssignment(AssignmentSlot slot) {
    if (slot.currentAssignment != null) {
      final slotKey = _getSlotKey(slot);

      // Dispatch to BLoC - no local state manipulation!
      context.read<AssignmentBloc>().add(
        OptimisticDeleteAssignment(
          assignmentId: slot.currentAssignment!.id,
          slotKey: slotKey,
        ),
      );
    }
  }

  Future<void> _showAlreadyAssignedDialog(AssignmentSlot slot) async {
    // FILTER: Exclude members who already have this exact role
    final filteredSameEventMembers = slot.alreadyAssignedMembers.where((member) {
      final hasThisRole = _allSlots.any((s) =>
          s.event.id == slot.event.id &&
          s.role.key == slot.role.key &&  // Same role type
          s.isFilled &&
          s.currentAssignment!.teamMemberId == member.id);
      return !hasThisRole;
    }).toList();

    // Combine with same-day assigned members
    final allMembers = [...filteredSameEventMembers, ...slot.sameDayAssignedMembers];

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
                if (allMembers.isEmpty)
                  // Show message when no members are available
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 16),
                        Text(
                          slot.alreadyAssignedMembers.isEmpty && slot.sameDayAssignedMembers.isEmpty
                              ? 'אין אנשים שכבר שובצו לאירוע זה'
                              : 'כל האנשים שכבר שובצו לאירוע זה כבר משובצים לתפקיד ${slot.role.hebrewName}',
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
                    'האנשים הבאים כבר משובצים לאירוע זה או לאירועים אחרים באותם תאריכים:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  // Make the list scrollable with constrained height
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5, // Max 50% of screen height
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: allMembers.length,
                      itemBuilder: (context, index) {
                        final member = allMembers[index];

                        // Determine if this is a same-event or same-day member
                        final isSameEvent = filteredSameEventMembers.contains(member);
                        final isSameDay = slot.sameDayAssignedMembers.contains(member);

                        String subtitle;
                        if (isSameEvent) {
                          // Find what OTHER roles this person has in this event (excluding current role)
                          final memberRoles = _allSlots
                              .where((s) =>
                                  s.event.id == slot.event.id &&
                                  s.isFilled &&
                                  s.currentAssignment!.teamMemberId == member.id &&
                                  s.role.key != slot.role.key)  // Exclude current role
                              .map((s) => s.role.hebrewName)
                              .toList();
                          subtitle = 'תפקידים: ${memberRoles.join(", ")}';
                        } else if (isSameDay) {
                          // Show the other events this person is assigned to on the same day
                          final otherEvents = slot.sameDayEventInfo[member.id] ?? [];
                          subtitle = 'משובצ/ת ב: ${otherEvents.join(", ")}';
                        } else {
                          subtitle = '';
                        }

                        return ListTile(
                          title: Text(member.name),
                          subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                          trailing: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(member),
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
              onPressed: () => Navigator.of(context).pop(),
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
    final alreadyAssignedIds = slot.alreadyAssignedMembers.map((m) => m.id).toSet();

    // Find constrained/unavailable members:
    // - Must have the required role capability
    // - Must NOT be in available or alreadyAssigned lists (those are already shown)
    // - Must be active and not archived
    final constrainedMembers = allMembers.where((member) {
      // Must have role capability
      if (!member.canPerformRole(slot.role.key)) return false;

      // Must not already be in available or alreadyAssigned lists
      if (availableIds.contains(member.id) || alreadyAssignedIds.contains(member.id)) return false;

      // Must be unavailable for the event (including time-based constraints)
      final isAvailable = member.isAvailableForEventWithTime(slot.event);
      return !isAvailable;
    }).toList();

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
                        Icon(Icons.info_outline, size: 48, color: Colors.grey.shade600),
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
                    'האנשים הבאים לא זמינים לתאריכי האירוע:',
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
                        // Determine the reason for unavailability
                        String reason;
                        if (member.isPermanent) {
                          reason = 'מגבלה מאושרת';
                        } else {
                          reason = 'לא ציין/ה זמינות';
                        }

                        return ListTile(
                          leading: Icon(
                            member.isPermanent ? Icons.event_busy : Icons.schedule,
                            color: Colors.red.shade400,
                          ),
                          title: Text(member.name),
                          subtitle: Text(
                            reason,
                            style: TextStyle(color: Colors.red.shade600, fontSize: 12),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(member),
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
              onPressed: () => Navigator.of(context).pop(),
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

  /// Handle assignment change bypassing conflict checks (for constrained members)
  Future<void> _handleAssignmentChangeWithBypass(
      AssignmentSlot slot, TeamMember selectedMember) async {
    // Check if already assigned (no-op)
    if (slot.currentAssignment?.teamMemberId == selectedMember.id) {
      return;
    }

    // Create assignment object
    final assignment = slot.currentAssignment != null
        ? slot.currentAssignment!.copyWith(
            teamMemberId: selectedMember.id,
            teamMember: selectedMember,
            updatedAt: DateTime.now(),
          )
        : Assignment(
            id: const Uuid().v4(),
            eventId: slot.event.id,
            teamMemberId: selectedMember.id,
            roleType: slot.role.key,
            slotIndex: slot.slotIndex,
            status: AssignmentStatus.confirmed,
            notes: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            event: slot.event,
            teamMember: selectedMember,
          );

    // Use optimistic path with bypass flag to skip conflict checks
    if (slot.currentAssignment != null) {
      context.read<AssignmentBloc>().add(
        OptimisticUpdateAssignment(assignment),
      );
    } else {
      context.read<AssignmentBloc>().add(
        OptimisticCreateAssignment(assignment, bypassConflicts: true),
      );
    }
  }

  Future<void> _handleAssignmentChange(
      AssignmentSlot slot, TeamMember selectedMember) async {
    // Check if already assigned (no-op)
    if (slot.currentAssignment?.teamMemberId == selectedMember.id) {
      return;
    }

    // Create assignment object
    final assignment = slot.currentAssignment != null
        ? slot.currentAssignment!.copyWith(
            teamMemberId: selectedMember.id,
            teamMember: selectedMember,
            updatedAt: DateTime.now(),
          )
        : Assignment(
            id: const Uuid().v4(),
            eventId: slot.event.id,
            teamMemberId: selectedMember.id,
            roleType: slot.role.key,
            slotIndex: slot.slotIndex,
            status: AssignmentStatus.confirmed,
            notes: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            event: slot.event,
            teamMember: selectedMember,
          );

    // Dispatch to BLoC - no local state manipulation!
    if (slot.currentAssignment != null) {
      context.read<AssignmentBloc>().add(
        OptimisticUpdateAssignment(assignment),
      );
    } else {
      context.read<AssignmentBloc>().add(
        OptimisticCreateAssignment(assignment),
      );
    }
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
          Text(message, style: const TextStyle(fontSize: 18, color: Colors.red)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context
                .read<AssignmentBloc>()
                .add(const LoadAssignmentSlots()),
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
      if (!mounted) return;
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

    if (!mounted) return;

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
  Future<void> _createAssignmentAndQuota(Event event, TeamMember teamMember, String roleType) async {
    try {
      final assignmentRepo = context.read<AssignmentRepository>();
      final eventBloc = context.read<EventBloc>();

      // Step 1: Get all existing assignments for this event and role
      final existingAssignments = await assignmentRepo.getAssignmentsByEvent(event.id);
      final roleAssignments = existingAssignments
          .where((a) => a.roleType == roleType)
          .toList()
        ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

      // Step 2: Find the next available slot index
      int nextSlotIndex = 0;
      for (final assignment in roleAssignments) {
        if (assignment.slotIndex == nextSlotIndex) {
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
      final updatedRoleRequirements = Map<String, int>.from(event.roleRequirements);
      final currentQuota = updatedRoleRequirements[roleType] ?? 0;
      updatedRoleRequirements[roleType] = currentQuota + 1;

      final updatedEvent = event.copyWith(
        roleRequirements: updatedRoleRequirements,
        updatedAt: DateTime.now(),
      );

      // Step 5: Execute both operations
      // First update the event quota
      eventBloc.add(UpdateEvent(updatedEvent));

      // Then create the assignment (bypass conflict checks since admin was warned)
      context.read<AssignmentBloc>().add(CreateAssignmentWithBypass(newAssignment));

      // Show success message
      if (mounted) {
        final roleState = context.read<RoleBloc>().state;
        final roleHebrewName = roleState is RolesLoaded
            ? roleState.getRoleHebrewName(roleType)
            : roleType;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('שיבוץ חדש נוצר בהצלחה: ${teamMember.name} → $roleHebrewName באירוע "${event.name}"'),
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
      }

      // Real-time streams will automatically reload assignment slots to reflect changes
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('שגיאה ביצירת שיבוץ: $e'),
              ),
              backgroundColor: Colors.red,
            ),
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
      parts.add('סיום - ${event.endTime}');
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
      '', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
    ];
    return months[month];
  }
}
