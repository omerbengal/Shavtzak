import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import '../../../core/constants/role_types.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/assignment/assignment_state.dart';
import 'models/assignment_slot.dart';
import '../../widgets/navigation_menu.dart';

class AssignmentListScreen extends StatefulWidget {
  const AssignmentListScreen({super.key});

  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen> {
  bool _showOnlyUnfilled = false;
  AssignmentSlotsLoaded? _lastSlotsState;
  // Track when dropdowns need to be reset (forces new widget instance)
  final Map<String, int> _dropdownResetCounters = {};

  @override
  void initState() {
    super.initState();
    context.read<AssignmentBloc>().add(const LoadAssignmentSlots());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          leading: const NavigationMenu(),
          title: const Text('שיבוצים'),
          actions: [
            // Toggle for filled/unfilled
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OutlinedButton(
                onPressed: () {
                  setState(() => _showOnlyUnfilled = !_showOnlyUnfilled);
                },
                style: OutlinedButton.styleFrom(
                  backgroundColor: _showOnlyUnfilled ? Colors.green : Colors.white,
                  foregroundColor: _showOnlyUnfilled ? Colors.white : Colors.black,
                  side: BorderSide(
                    color: _showOnlyUnfilled ? Colors.green : Colors.grey,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('הצג רק לא משובצים'),
              ),
            ),
          ],
        ),
        body: BlocConsumer<AssignmentBloc, AssignmentState>(
          listener: (context, state) {
            if (state is AssignmentError) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.red),
                );
            } else if (state is AssignmentOperationSuccess) {
              // BLoC will automatically reload slots without showing loading
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.green),
                );
            } else if (state is AssignmentConflictWarning) {
              // Show conflict warning to user
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Text('שיבוץ לא בוצע: ${state.conflicts.join(", ")}'),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 5),
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
              _lastSlotsState = state; // Store the last successful state
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

            return _buildEmptyState();
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

    // Filter slots based on toggle
    final slots = _showOnlyUnfilled
        ? state.slots.where((s) => !s.isFilled).toList()
        : state.slots;

    if (slots.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () async {
        context.read<AssignmentBloc>().add(const LoadAssignmentSlots());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: Column(
      children: [
        // Statistics bar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                  'סה"כ תפקידים', state.totalSlots.toString(), Colors.blue),
              _buildStatItem(
                  'משובץ', state.filledSlots.toString(), Colors.green),
              _buildStatItem(
                  'פנוי', state.unfilledSlots.toString(), Colors.orange),
            ],
          ),
        ),

        // Header row
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade200,
          child: const Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text('אירוע',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('תפקיד',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 3,
                  child: Text('שיבוץ',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ),

        // Grid rows
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
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
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
        color: slot.isFilled ? null : Colors.orange.shade50,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Event column
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  slot.event.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  textAlign: TextAlign.center,
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
                    slot.event.location,
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
                  child: Text(
                    slot.roleType.hebrewName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
            flex: 4,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _buildAssignmentCell(slot, constraints.maxWidth);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentCell(AssignmentSlot slot, double availableWidth) {
    final isMobile = availableWidth < 300; // Detect mobile/narrow screens
    // Find current assigned member in either list
    final currentMember = slot.availableMembers.firstWhereOrNull(
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
          child: Center(
            child: Text(
              member.name,
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
          child: Center(
            child: Text(
              currentMember.name,
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
          child: DropdownButtonFormField<String>(
            key: ValueKey('${_getSlotKey(slot)}_${_dropdownResetCounters[_getSlotKey(slot)] ?? 0}'),
            value: currentMember?.id,
            hint: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(child: Text('בחר...')),
            ),
            style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.normal),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: hasOptions
                  ? (slot.isFilled ? Colors.green.shade50 : Colors.white)
                  : Colors.grey.shade200, // Gray out when no options
            ),
            icon: const Icon(Icons.arrow_drop_down, size: 20),
            items: items,
            selectedItemBuilder: (context) {
              // Build plain text items for closed dropdown display (no green/bold styling)
              final selectedItems = <Widget>[];

              // Available members (plain style)
              for (var member in slot.availableMembers) {
                selectedItems.add(Directionality(
                  textDirection: TextDirection.rtl,
                  child: Center(child: Text(member.name)),
                ));
              }

              // Current member from already assigned (if exists)
              if (currentMember != null &&
                  !slot.availableMembers.any((m) => m.id == currentMember.id)) {
                selectedItems.insert(0, Directionality(
                  textDirection: TextDirection.rtl,
                  child: Center(child: Text(currentMember.name)),
                ));
              }

              // Divider and "show already assigned" option
              selectedItems.add(const SizedBox.shrink()); // For divider
              selectedItems.add(Directionality(
                textDirection: TextDirection.rtl,
                child: Center(child: Text('שובצו כבר...')),
              ));

              return selectedItems;
            },
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

        const SizedBox(width: 8),

        // "ניקוי" button - only show if slot is filled AND currentMember is valid
        if (slot.isFilled && currentMember != null)
          SizedBox(
            width: isMobile ? 40 : 60,
            child: isMobile
                ? IconButton(
                    onPressed: () => _handleClearAssignment(slot),
                    icon: const Icon(Icons.clear, size: 20),
                    color: Colors.red,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'ניקוי',
                  )
                : ElevatedButton(
                    onPressed: () => _handleClearAssignment(slot),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    child: const Text(
                      'ניקוי',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
          ),

        // Removed: "שובצו כבר" button - now integrated in dropdown
      ],
    );
  }

  void _handleClearAssignment(AssignmentSlot slot) {
    if (slot.currentAssignment != null) {
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
          }
          return s;
        }).toList();

        setState(() {
          _lastSlotsState = AssignmentSlotsLoaded(updatedSlots);
        });
      }

      // Then proceed with actual database deletion
      context.read<AssignmentBloc>().add(
            DeleteAssignment(slot.currentAssignment!.id),
          );
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
    // Optimistic update: update local state immediately
    if (_lastSlotsState != null) {
      final updatedSlots = _lastSlotsState!.slots.map((s) {
        if (s.event.id == slot.event.id &&
            s.roleType == slot.roleType &&
            s.slotIndex == slot.slotIndex) {
          // This is the slot being updated
          if (slot.currentAssignment != null) {
            // Update existing assignment
            final updatedAssignment = slot.currentAssignment!.copyWith(
              teamMemberId: selectedMember.id,
              teamMember: selectedMember,
              updatedAt: DateTime.now(),
            );
            return AssignmentSlot(
              event: s.event,
              roleType: s.roleType,
              slotIndex: s.slotIndex,
              currentAssignment: updatedAssignment,
              availableMembers: s.availableMembers,
              alreadyAssignedMembers: s.alreadyAssignedMembers,
              hasDoubleAssignment: s.hasDoubleAssignment,
              otherRoles: s.otherRoles,
            );
          } else {
            // Create new assignment
            final newAssignment = Assignment(
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
            return AssignmentSlot(
              event: s.event,
              roleType: s.roleType,
              slotIndex: s.slotIndex,
              currentAssignment: newAssignment,
              availableMembers: s.availableMembers,
              alreadyAssignedMembers: s.alreadyAssignedMembers,
              hasDoubleAssignment: s.hasDoubleAssignment,
              otherRoles: s.otherRoles,
            );
          }
        }
        return s;
      }).toList();

      setState(() {
        _lastSlotsState = AssignmentSlotsLoaded(updatedSlots);
      });
    }

    // Then proceed with actual database update
    if (slot.currentAssignment != null) {
      // Update existing
      final updated = slot.currentAssignment!.copyWith(
        teamMemberId: selectedMember.id,
        updatedAt: DateTime.now(),
      );
      context.read<AssignmentBloc>().add(UpdateAssignment(updated));
    } else {
      // Create new
      final assignment = Assignment(
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
      context.read<AssignmentBloc>().add(CreateAssignment(assignment));
    }
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined,
              size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _showOnlyUnfilled
                ? 'כל התפקידים משובצים!'
                : 'אין תפקידים להצגה',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
