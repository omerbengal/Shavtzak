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
import '../../../core/utils/filter_persistence.dart';
import '../../../core/services/environment_service.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/assignment/assignment_state.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import 'models/assignment_slot.dart';
import '../../widgets/interactive_filter_bar.dart';
import 'assignment_filter_modal.dart';
import '../event/widgets/event_form_modal.dart';
import 'manual_assignment_flow_dialog.dart';
import '../../widgets/map_location_picker.dart';

class AssignmentListScreen extends StatefulWidget {
  const AssignmentListScreen({super.key});

  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen> {
  AssignmentSlotsLoaded? _lastSlotsState;
  // Track when dropdowns need to be reset (forces new widget instance)
  final Map<String, int> _dropdownResetCounters = {};
  // Track assignment IDs that are pending deletion to prevent race conditions
  final Set<String> _pendingDeletions = {};
  // Track assignment IDs that are pending creation (not yet in DB)
  final Set<String> _pendingCreates = {};
  // Track pending creates that should be deleted immediately after creation completes
  final Set<String> _pendingCreatesToDelete = {};

  @override
  void initState() {
    super.initState();
    context.read<AssignmentBloc>().add(const LoadAssignmentSlots());
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('שיבוצים'),
          leading: Container(
            width: 180,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  FilterPersistence.showPastEvents = !FilterPersistence.showPastEvents;
                });
                // Reload assignments with new filter setting
                context.read<AssignmentBloc>().add(const LoadAssignmentSlots());
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        ? 'מציג אירועי עבר'
                        : 'לא מציג אירועי עבר',
                    style: TextStyle(
                      fontSize: 14,
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
          leadingWidth: 200,
          actions: [
            IconButton(
              icon: const Icon(Icons.home),
              tooltip: 'בית',
              onPressed: () {
                final envPrefix = EnvironmentService.instance.routePrefix;
                context.go('$envPrefix/admin');
              },
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'התנתק',
              onPressed: () => _logout(context),
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
          ],
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
              // Check if any completed creates need immediate deletion
              if (_pendingCreatesToDelete.isNotEmpty) {
                // Delete all assignments that were cleared during their creation
                for (final id in _pendingCreatesToDelete) {
                  context.read<AssignmentBloc>().add(DeleteAssignment(id));
                }
                setState(() {
                  _pendingCreatesToDelete.clear();
                });
              }

              // Clear pending creates when operation succeeds
              // (operation could be create, update, or delete - clear all tracking)
              setState(() {
                _pendingCreates.clear();
              });

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

              // Filter out slots with assignments pending deletion to prevent race conditions
              final filteredSlots = state.slots.map((slot) {
                // If this slot has an assignment that's pending deletion, clear it
                if (slot.currentAssignment != null &&
                    _pendingDeletions.contains(slot.currentAssignment!.id)) {
                  return AssignmentSlot(
                    event: slot.event,
                    roleType: slot.roleType,
                    slotIndex: slot.slotIndex,
                    currentAssignment: null, // Clear the assignment
                    availableMembers: slot.availableMembers,
                    alreadyAssignedMembers: slot.alreadyAssignedMembers,
                    hasDoubleAssignment: false,
                    otherRoles: const [],
                  );
                }
                return slot;
              }).toList();

              _lastSlotsState = AssignmentSlotsLoaded(
                filteredSlots,
                selectedEventIds: state.selectedEventIds,
              ); // Store the filtered state
                            return _buildSlotGrid(_lastSlotsState!);
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
    return '${slot.event.id}_${slot.roleType.name}_${slot.slotIndex}';
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
    final slots = _filterAssignments(filteredSlots, FilterPersistence.assignmentFilterIndex);

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

        // Header row
        Container(
          height: 56, // Fixed height to accommodate both layers
          color: Colors.grey.shade200,
          child: Stack(
            children: [
              // Bottom layer: Column titles with exact same structure as data rows
              Positioned.fill(
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
              // Top layer: Filter icon positioned on the right (in RTL)
              Positioned(
                right: 12,
                top: 6,
                bottom: 6,
                child: IconButton(
                  icon: Icon(
                    Icons.filter_list,
                    color: state.selectedEventIds.isEmpty
                        ? Colors.grey.shade700
                        : Colors.blue,
                  ),
                  onPressed: () => _showFilterModal(context, state),
                  tooltip: 'סינון',
                  iconSize: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
                ),
              ),
            ],
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
                        // Line 1: Dates (single date if same, or date range)
                        Text(
                          _isSameDay(slot.event.startDate, slot.event.endDate)
                              ? _formatDate(slot.event.startDate)
                              : '${_formatDate(slot.event.startDate)} - ${_formatDate(slot.event.endDate)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Line 2: Times (show if at least one time is filled)
                        if (slot.event.startTime.isNotEmpty || slot.event.endTime.isNotEmpty)
                          Text(
                            '${slot.event.startTime.isNotEmpty ? slot.event.startTime : "?"} - ${slot.event.endTime.isNotEmpty ? slot.event.endTime : "?"}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        // Line 3: Location (only if not empty)
                        if (slot.event.location.isNotEmpty)
                          Text(
                            _formatLocationForDisplay(slot.event.location),
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // Role column
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showEventFormModal(slot.event, selectedRole: slot.roleType),
                            child: Text(
                              slot.roleType.hebrewName,
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
                        ),
                        if (slot.hasDoubleAssignment)
                          Tooltip(
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
                      ],
                    ),
                  ),

                  // Assignment cell with dropdown and buttons
                  Expanded(
                    flex: 3,
                    child: _buildAssignmentCell(slot),
                  ),
                ],
              ),
            ),
          ),

          // Notes section (only shown if there are notes)
          if (hasNotes)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  slot.currentAssignment!.notes,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.purple.shade700,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
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
      key: Key('slot_${slot.event.id}_${slot.roleType.name}_${slot.slotIndex}'),
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
    try {
      final assignmentRepo = context.read<AssignmentRepository>();
      final eventBloc = context.read<EventBloc>();

      // Step 1: Delete the assignment if it exists (filled slot)
      if (slot.currentAssignment != null) {
        await assignmentRepo.deleteAssignment(slot.currentAssignment!.id);
      }

      // Step 2: Get all remaining assignments for this event and role
      final allAssignments = await assignmentRepo.getAssignmentsByEvent(slot.event.id);
      final roleAssignments = allAssignments
          .where((a) => a.roleType == slot.roleType)
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
      final updatedRoleRequirements = Map<RoleType, int>.from(slot.event.roleRequirements);
      final currentQuota = updatedRoleRequirements[slot.roleType] ?? 0;
      if (currentQuota > 0) {
        updatedRoleRequirements[slot.roleType] = currentQuota - 1;
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

    final controller = TextEditingController(text: assignment.notes);

    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => Directionality(
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show assignment info
              Text(
                '${slot.currentAssignment?.teamMember?.name ?? ""} - ${slot.roleType.hebrewName}',
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
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'הכנס הערות...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                textDirection: TextDirection.rtl,
                autofocus: false,
              ),
              // Delete note button (only show if there are existing notes)
              if (assignment.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(''),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text(
                      'מחק הערה',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      // Update notes via BLoC (empty string = delete note)
      context.read<AssignmentBloc>().add(
        UpdateAssignmentNotes(assignment.id, result),
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
        ),
      ));
    }

    // ALWAYS add "שובצו כבר" option at the end (even if no one is assigned)
    items.add(const DropdownMenuItem<String>(
      value: '__divider__',
      enabled: false,
      child: Divider(),
    ));

    items.add(DropdownMenuItem<String>(
      value: '__show_already_assigned__',
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people, size: 16, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Text(
                'שובצו כבר...',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: ValueKey('${_getSlotKey(slot)}_${_dropdownResetCounters[_getSlotKey(slot)] ?? 0}'),
                value: currentMember?.id,
                isExpanded: true,
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
                          child: Text(
                            member.name,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 12, color: Colors.black),
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
                          child: Text(
                            currentMember.name,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 12, color: Colors.black),
                          ),
                        ),
                      ),
                    );
                  }

                  return selectedItems;
                },
                items: items,
                onChanged: hasOptions ? (selectedValue) {
              if (selectedValue == '__show_already_assigned__') {
                // Show dialog for already-assigned members
                _showAlreadyAssignedDialog(slot);
              } else if (selectedValue != null && selectedValue != '__divider__') {
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
      final clearedMemberId = slot.currentAssignment!.teamMemberId;
      final clearedMember = slot.currentAssignment!.teamMember;
      final assignmentId = slot.currentAssignment!.id;

      // Add to pending deletions to prevent race conditions
      _pendingDeletions.add(assignmentId);

      // Remove from pending deletions after 5 seconds (cleanup timeout)
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _pendingDeletions.remove(assignmentId);
          });
        }
      });

      // Optimistic update: clear the assignment in local state immediately
      if (_lastSlotsState != null) {
        final updatedSlots = _lastSlotsState!.slots.map((s) {
          if (s.event.id == slot.event.id &&
              s.roleType == slot.roleType &&
              s.slotIndex == slot.slotIndex) {
            // This is the slot being cleared
            return AssignmentSlot(
              event: s.event,
              roleType: s.roleType,
              slotIndex: s.slotIndex,
              currentAssignment: null, // Clear the assignment
              availableMembers: s.availableMembers,
              alreadyAssignedMembers: s.alreadyAssignedMembers,
              hasDoubleAssignment: false,
              otherRoles: const [],
            );
          } else if (s.event.id == slot.event.id) {
            // For ALL other slots in the same event, check if member is still assigned elsewhere
            // If not, move them back to availableMembers
            final stillAssignedElsewhere = _lastSlotsState!.slots.any((otherSlot) =>
                otherSlot.event.id == slot.event.id &&
                otherSlot.isFilled &&
                otherSlot.currentAssignment!.teamMemberId == clearedMemberId &&
                !(otherSlot.event.id == slot.event.id &&
                  otherSlot.roleType == slot.roleType &&
                  otherSlot.slotIndex == slot.slotIndex)); // Exclude the slot being cleared

            if (!stillAssignedElsewhere && clearedMember != null) {
              // Member is no longer assigned to this event - add back to available
              final updatedAvailable = s.availableMembers.any((m) => m.id == clearedMemberId)
                  ? s.availableMembers
                  : [...s.availableMembers, clearedMember];

              // Remove from alreadyAssigned
              final updatedAlreadyAssigned = s.alreadyAssignedMembers
                  .where((m) => m.id != clearedMemberId)
                  .toList();

              return AssignmentSlot(
                event: s.event,
                roleType: s.roleType,
                slotIndex: s.slotIndex,
                currentAssignment: s.currentAssignment,
                availableMembers: updatedAvailable,
                alreadyAssignedMembers: updatedAlreadyAssigned,
                hasDoubleAssignment: s.hasDoubleAssignment,
                otherRoles: s.otherRoles,
              );
            }
          }
          return s;
        }).toList();

        setState(() {
          _lastSlotsState = AssignmentSlotsLoaded(
            updatedSlots,
            selectedEventIds: _lastSlotsState!.selectedEventIds, // Preserve the filter!
          );
        });
      }

      // Then proceed with actual database deletion
      // BUT: if this assignment is pending creation (not yet in DB), schedule deletion for after creation
      if (_pendingCreates.contains(assignmentId)) {
        // Assignment is still being created - mark it for deletion after creation completes
        _pendingCreatesToDelete.add(assignmentId);
        // Don't dispatch DeleteAssignment yet - the assignment doesn't exist in DB yet
        // It will be deleted immediately after the create completes (see listener)
      } else {
        // Assignment exists in DB - dispatch delete immediately
        context.read<AssignmentBloc>().add(
              DeleteAssignment(slot.currentAssignment!.id),
            );
      }
    }
  }

  Future<void> _showAlreadyAssignedDialog(AssignmentSlot slot) async {
    // FILTER: Exclude members who already have this exact role
    final filteredMembers = slot.alreadyAssignedMembers.where((member) {
      final hasThisRole = _allSlots.any((s) =>
          s.event.id == slot.event.id &&
          s.roleType == slot.roleType &&  // Same role type
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
                if (filteredMembers.isEmpty)
                  // Show message when no members are available
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 16),
                        Text(
                          slot.alreadyAssignedMembers.isEmpty
                              ? 'אין אנשים שכבר שובצו לאירוע זה'
                              : 'כל האנשים שכבר שובצו לאירוע זה כבר משובצים לתפקיד ${slot.roleType.hebrewName}',
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
                    'האנשים הבאים כבר משובצים לאירוע זה בתפקידים אחרים (לא ${slot.roleType.hebrewName}):',
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
                      itemCount: filteredMembers.length,
                      itemBuilder: (context, index) {
                        final member = filteredMembers[index];
                        // Find what OTHER roles this person has in this event (excluding current role)
                        final memberRoles = _allSlots
                            .where((s) =>
                                s.event.id == slot.event.id &&
                                s.isFilled &&
                                s.currentAssignment!.teamMemberId == member.id &&
                                s.roleType != slot.roleType)  // Exclude current role
                            .map((s) => s.roleType.hebrewName)
                            .toList();

                        return ListTile(
                          title: Text(member.name),
                          subtitle: Text('תפקידים: ${memberRoles.join(", ")}'),
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

  Future<void> _handleAssignmentChange(
      AssignmentSlot slot, TeamMember selectedMember) async {
    // Check if the selected member is already assigned to this slot
    if (slot.currentAssignment?.teamMemberId == selectedMember.id) {
      // Already assigned - do nothing, no DB write, no Snackbar
      return;
    }

    // Prepare the assignment for DB operation (create it once with a single UUID)
    final Assignment assignmentForDB;
    if (slot.currentAssignment != null) {
      // Update existing
      assignmentForDB = slot.currentAssignment!.copyWith(
        teamMemberId: selectedMember.id,
        teamMember: selectedMember,
        updatedAt: DateTime.now(),
      );
    } else {
      // Create new - generate UUID ONCE here
      assignmentForDB = Assignment(
        id: const Uuid().v4(),
        eventId: slot.event.id,
        teamMemberId: selectedMember.id,
        roleType: slot.roleType,
        slotIndex: slot.slotIndex,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        event: slot.event,
        teamMember: selectedMember,
      );
    }

    // Optimistic update: update local state immediately using the SAME assignment
    if (_lastSlotsState != null) {
      final updatedSlots = _lastSlotsState!.slots.map((s) {
        if (s.event.id == slot.event.id &&
            s.roleType == slot.roleType &&
            s.slotIndex == slot.slotIndex) {
          // This is the slot being updated - use the assignmentForDB
          return AssignmentSlot(
            event: s.event,
            roleType: s.roleType,
            slotIndex: s.slotIndex,
            currentAssignment: assignmentForDB,
            availableMembers: s.availableMembers,
            alreadyAssignedMembers: s.alreadyAssignedMembers,
            hasDoubleAssignment: s.hasDoubleAssignment,
            otherRoles: s.otherRoles,
          );
        } else if (s.event.id == slot.event.id) {
          // For ALL other slots in the same event, update their available/alreadyAssigned lists
          // Remove selectedMember from availableMembers
          final updatedAvailable = s.availableMembers
              .where((m) => m.id != selectedMember.id)
              .toList();

          // Add selectedMember to alreadyAssignedMembers if not already there
          final updatedAlreadyAssigned = s.alreadyAssignedMembers.any((m) => m.id == selectedMember.id)
              ? s.alreadyAssignedMembers
              : [...s.alreadyAssignedMembers, selectedMember];

          return AssignmentSlot(
            event: s.event,
            roleType: s.roleType,
            slotIndex: s.slotIndex,
            currentAssignment: s.currentAssignment,
            availableMembers: updatedAvailable,
            alreadyAssignedMembers: updatedAlreadyAssigned,
            hasDoubleAssignment: s.hasDoubleAssignment,
            otherRoles: s.otherRoles,
          );
        }
        return s;
      }).toList();

      setState(() {
        _lastSlotsState = AssignmentSlotsLoaded(
          updatedSlots,
          selectedEventIds: _lastSlotsState!.selectedEventIds, // Preserve the filter!
        );
      });
    }

    // Then proceed with actual database update using the SAME assignment
    if (slot.currentAssignment != null) {
      context.read<AssignmentBloc>().add(UpdateAssignment(assignmentForDB));
    } else {
      // Track this as a pending create
      _pendingCreates.add(assignmentForDB.id);
      context.read<AssignmentBloc>().add(CreateAssignment(assignmentForDB));
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
    // Get all events from repository (not just from slots) when showPastEvents is true
    // This ensures past events appear in the filter when the switch is on
    if (FilterPersistence.showPastEvents) {
      final eventRepo = context.read<EventRepository>();
      final allEvents = await eventRepo.getAllEvents();
      final availableEvents = allEvents
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

      final result = await showDialog<Set<String>>(
        context: context,
        builder: (context) => AssignmentFilterModal(
          availableEvents: availableEvents,
          selectedEventIds: state.selectedEventIds,
        ),
      );

      if (result != null) {
        if (!mounted) return;

        if (result.isEmpty) {
          // Clear filter
          context.read<AssignmentBloc>().add(const ClearEventFilter());
        } else {
          // Apply filter
          context.read<AssignmentBloc>().add(ApplyEventFilter(result));
        }
      }
    } else {
      // Original behavior when showPastEvents is false
      // Get unique events from slots that have at least one role with capacity > 0
      final eventsMap = <String, Event>{};
      for (final slot in state.slots) {
        if (!eventsMap.containsKey(slot.event.id)) {
          eventsMap[slot.event.id] = slot.event;
        }
      }
      final availableEvents = eventsMap.values.toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

      final result = await showDialog<Set<String>>(
        context: context,
        builder: (context) => AssignmentFilterModal(
          availableEvents: availableEvents,
          selectedEventIds: state.selectedEventIds,
        ),
      );

      if (result != null) {
        if (!mounted) return;

        if (result.isEmpty) {
          // Clear filter
          context.read<AssignmentBloc>().add(const ClearEventFilter());
        } else {
          // Apply filter
          context.read<AssignmentBloc>().add(ApplyEventFilter(result));
        }
      }
    }
  }

  /// Show event form modal for editing an event
  void _showEventFormModal(Event event, {RoleType? selectedRole}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => EventFormModal(
        event: event,
        selectedRole: selectedRole,
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
      final RoleType roleType = result['roleType'];

      // Create assignment and increase quota
      await _createAssignmentAndQuota(event, teamMember, roleType);
    }
  }

  /// Create assignment and increase event quota for the selected role
  Future<void> _createAssignmentAndQuota(Event event, TeamMember teamMember, RoleType roleType) async {
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
      final updatedRoleRequirements = Map<RoleType, int>.from(event.roleRequirements);
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
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('שיבוץ חדש נוצר בהצלחה: ${teamMember.name} → ${roleType.hebrewName} באירוע "${event.name}"'),
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
}
