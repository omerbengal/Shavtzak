import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../core/debug/logger.dart';
import '../../../../core/utils/same_day_assignments.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/checklist_item.dart';
import '../../../../domain/entities/role.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_state.dart';
import '../../../bloc/team/team_bloc.dart';
import '../../../bloc/team/team_state.dart';
import '../../../bloc/assignment/assignment_bloc.dart';
import '../../../bloc/assignment/assignment_event.dart';
import '../../../widgets/map_location_picker.dart';
import '../../event/widgets/event_assignments_dialog.dart';

/// Combined data for a single event's summary
class EventSummaryData {
  final Event event;
  final int filledSlots;
  final int totalSlots;
  final Map<String, int> missingRoles; // role key -> count needed
  final List<ChecklistItem> checklistItems;

  const EventSummaryData({
    required this.event,
    required this.filledSlots,
    required this.totalSlots,
    required this.missingRoles,
    required this.checklistItems,
  });

  bool get isFullyStaffed => totalSlots == 0 || filledSlots >= totalSlots;
  int get unfilledSlots => totalSlots - filledSlots;
  int get totalMissingRoles =>
      missingRoles.values.fold(0, (sum, count) => sum + count);

  int get completedChecklistItems =>
      checklistItems.where((item) => item.status).length;
  int get pendingChecklistItems =>
      checklistItems.where((item) => !item.status).length;
  int get totalChecklistItems => checklistItems.length;

  bool get hasChecklistItems => checklistItems.isNotEmpty;
}

/// Expandable tile for a single event showing staffing and checklist status
class EventSummaryTile extends StatelessWidget {
  final EventSummaryData data;
  final List<Assignment> allAssignments;
  final List<Event> allEvents;

  const EventSummaryTile({
    super.key,
    required this.data,
    required this.allAssignments,
    required this.allEvents,
  });

  @override
  Widget build(BuildContext context) {
    final hasIssues = !data.isFullyStaffed || data.pendingChecklistItems > 0;
    final urgencyColor = _getUrgencyColor(data.event);

    return Card(
      color: hasIssues ? Colors.orange.shade50 : Colors.green.shade50,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: PageStorageKey<String>('summary_event_tile_${data.event.id}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Row(
          children: [
            // Status indicator circle
            _buildStatusIndicator(),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                data.event.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // People icon button to show assignments
            IconButton(
              icon: const Icon(Icons.people_outline),
              tooltip: 'צפה בשיבוצים',
              onPressed: () {
                Logger.action('open:eventAssignmentsDialog', {'eventId': data.event.id});
                // Filter assignments for this event from the already-loaded list
                final eventAssignments = allAssignments
                    .where((a) => a.eventId == data.event.id)
                    .toList();
                showDialog(
                  context: context,
                  builder: (context) => EventAssignmentsDialog.withAssignments(
                    event: data.event,
                    assignments: eventAssignments,
                  ),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            // Default expansion arrow
            const Icon(Icons.expand_more),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              // Date in Hebrew with urgency color
              Text(
                _formatEventDatesHebrew(data.event),
                style: TextStyle(
                  fontSize: 13,
                  color: urgencyColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Time fields
              Text(
                _formatTimeFields(data.event),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              // Location (stripped of coordinates)
              if (data.event.location.isNotEmpty)
                Text(
                  _formatLocationForDisplay(data.event.location),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              // Participant count (hidden when unset)
              if (data.event.participantCount != null)
                Text(
                  'כמות משתתפים: ${data.event.participantCount}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              const SizedBox(height: 6),
              // Status indicators
              _buildStatusRow(),
            ],
          ),
        ),
        children: [
          _buildExpandedContent(),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    if (data.isFullyStaffed) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.green.shade600,
          shape: BoxShape.circle,
        ),
      );
    } else if (data.unfilledSlots > 0 && data.filledSlots > 0) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.orange.shade600,
          shape: BoxShape.circle,
        ),
      );
    } else {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          shape: BoxShape.circle,
        ),
      );
    }
  }

  Color _getUrgencyColor(Event event) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final eventDay = DateTime(
        event.startDate.year, event.startDate.month, event.startDate.day);

    if (eventDay.isAtSameMomentAs(today)) {
      return Colors.red.shade700;
    } else if (eventDay.isAtSameMomentAs(tomorrow)) {
      return Colors.orange.shade700;
    } else if (event.startDate.isBefore(today.add(const Duration(days: 7)))) {
      return Colors.blue.shade700;
    } else {
      return Colors.grey.shade700;
    }
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        // Staffing status
        _buildStatusChip(
          icon: data.isFullyStaffed ? Icons.check_circle : Icons.person_off,
          label: data.isFullyStaffed
              ? 'מאויש במלואו'
              : '${data.unfilledSlots} תפקידים חסרים',
          color: data.isFullyStaffed ? Colors.green : Colors.orange,
        ),
        const SizedBox(width: 12),
        // Checklist status
        if (data.hasChecklistItems)
          _buildStatusChip(
            icon: data.pendingChecklistItems == 0
                ? Icons.check_circle
                : Icons.pending,
            label: data.pendingChecklistItems == 0
                ? 'צ\'קליסט הושלם'
                : '${data.pendingChecklistItems} פריטים ממתינים',
            color:
                data.pendingChecklistItems == 0 ? Colors.green : Colors.orange,
          ),
      ],
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required MaterialColor color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color.shade700),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Staffing details section
          if (!data.isFullyStaffed) ...[
            _buildSectionHeader('תפקידים חסרים', Icons.person_off),
            const SizedBox(height: 8),
            _buildMissingRolesSection(),
            const SizedBox(height: 16),
          ],
          // Checklist details section
          if (data.hasChecklistItems) ...[
            _buildSectionHeader(
              'צ\'קליסט (${data.completedChecklistItems}/${data.totalChecklistItems})',
              Icons.checklist,
            ),
            const SizedBox(height: 8),
            _buildChecklistSection(),
          ],
          // All good message
          if (data.isFullyStaffed && data.pendingChecklistItems == 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.check_circle,
                        size: 48, color: Colors.green.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'הכל מוכן!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  Widget _buildMissingRolesSection() {
    return Builder(
      builder: (outerContext) {
        return BlocBuilder<RoleBloc, RoleState>(
          builder: (context, roleState) {
            // Get role display names from RoleBloc
            List<Role> roles;
            if (roleState is RolesLoaded) {
              roles = roleState.allNonArchivedRoles;
            } else {
              // Fallback to RoleType.values during initial load
              roles = RoleType.values
                  .map((rt) => Role(
                        id: rt.key,
                        key: rt.key,
                        hebrewName: rt.hebrewName,
                        isVisible: true,
                        isArchived: false,
                        sortOrder: RoleType.values.indexOf(rt),
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ))
                  .toList();
            }

            // Build individual slot entries for each missing role
            final missingSlots = <_MissingSlot>[];
            for (final roleObj in roles) {
              final count = data.missingRoles[roleObj.key] ?? 0;
              for (int i = 0; i < count; i++) {
                missingSlots.add(_MissingSlot(
                  roleKey: roleObj.key,
                  roleHebrewName: roleObj.hebrewName,
                  slotIndex: i + 1,
                ));
              }
            }

            if (missingSlots.isEmpty) {
              return const SizedBox.shrink();
            }

            // Sort by role sort order
            missingSlots.sort((a, b) {
              final roleA = roles.firstWhere((r) => r.key == a.roleKey);
              final roleB = roles.firstWhere((r) => r.key == b.roleKey);
              if (roleA.sortOrder != roleB.sortOrder) {
                return roleA.sortOrder.compareTo(roleB.sortOrder);
              }
              return a.slotIndex.compareTo(b.slotIndex);
            });

            return BlocBuilder<TeamBloc, TeamState>(
              builder: (context, teamState) {
                final teamMembers = teamState is TeamLoaded
                    ? teamState.members
                        .where((member) => member.isActive)
                        .toList()
                    : <TeamMember>[];

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: missingSlots.map((slot) {
                    return _buildRoleAssignmentDropdown(
                      outerContext,
                      slot.roleKey,
                      slot.roleHebrewName,
                      data.event,
                      teamMembers,
                    );
                  }).toList(),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRoleAssignmentDropdown(
    BuildContext outerContext,
    String roleKey,
    String hebrewName,
    Event event,
    List<TeamMember> teamMembers,
  ) {
    // Categorize members
    final categorized = _categorizeMembersForRole(
      teamMembers,
      roleKey,
      event,
      allAssignments,
    );
    final constrainedMembers = _buildConstrainedMembers(
      allTeamMembers: teamMembers,
      roleKey: roleKey,
      event: event,
      availableMembers: categorized.available,
      alreadyAssignedMembers: categorized.alreadyAssigned,
      sameDayAssignedMembers: categorized.sameDayAssigned,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, size: 16, color: Colors.red.shade600),
              const SizedBox(width: 4),
              Text(
                hebrewName,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (categorized.available.isNotEmpty ||
              categorized.alreadyAssigned.isNotEmpty ||
              constrainedMembers.isNotEmpty) ...[
            const SizedBox(height: 4),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                hint: const Text(
                  'בחר חבר צוות',
                  style: TextStyle(fontSize: 12),
                ),
                isDense: true,
                iconEnabledColor: Colors.red.shade700,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
                dropdownColor: Colors.white,
                menuWidth: 250,
                items: _buildDropdownItems(
                  categorized,
                  hasConstrainedMembers: constrainedMembers.isNotEmpty,
                ),
                onChanged: (selectedValue) async {
                  Logger.action('select:roleAssignmentMember', {'eventId': event.id, 'roleKey': roleKey, 'selectedValue': selectedValue});
                  if (selectedValue == null) return;

                  if (selectedValue == '__show_already_assigned__') {
                    final selectedMember = await _showAlreadyAssignedDialog(
                      outerContext,
                      event,
                      roleKey,
                      hebrewName,
                      categorized.alreadyAssigned,
                    );
                    if (selectedMember != null) {
                      _showAssignmentConfirmationDialog(
                        outerContext,
                        event,
                        roleKey,
                        hebrewName,
                        selectedMember.id,
                        selectedMember,
                      );
                    }
                  } else if (selectedValue == '__show_constrained__') {
                    final selectedMember = await _showConstrainedMembersDialog(
                      outerContext,
                      event,
                      constrainedMembers,
                      categorized.sameDayEventInfo,
                    );
                    if (selectedMember != null) {
                      _showAssignmentConfirmationDialog(
                        outerContext,
                        event,
                        roleKey,
                        hebrewName,
                        selectedMember.id,
                        selectedMember,
                      );
                    }
                  } else {
                    // Find the selected member
                    final member = categorized.available
                        .firstWhere((m) => m.id == selectedValue);
                    _showAssignmentConfirmationDialog(
                      outerContext,
                      event,
                      roleKey,
                      hebrewName,
                      member.id,
                      member,
                    );
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _buildDropdownItems(
    _CategorizedMembers cat, {
    required bool hasConstrainedMembers,
  }) {
    final items = <DropdownMenuItem<String>>[];

    // Available members
    for (final member in cat.available) {
      items.add(DropdownMenuItem<String>(
        value: member.id,
        child: SizedBox(
          width: 250,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    children: [
                      TextSpan(text: member.name),
                      if (member.isPermanent)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(start: 4),
                            child: Icon(
                              Icons.verified_user,
                              size: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ));
    }

    // "שובצו כבר" option (if there are already assigned members)
    if (cat.alreadyAssigned.isNotEmpty) {
      items.add(DropdownMenuItem<String>(
        value: '__show_already_assigned__',
        child: SizedBox(
          width: 250,
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
                    const Icon(Icons.people, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
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
        ),
      ));
    }

    // "בעלי מגבלות / לא זמינים" option (if there are constrained members)
    if (hasConstrainedMembers) {
      items.add(DropdownMenuItem<String>(
        value: '__show_constrained__',
        child: SizedBox(
          width: 250,
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
                    const Icon(Icons.block, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
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
        ),
      ));
    }

    return items;
  }

  /// Categorize members for a specific role and event
  /// This logic MUST match AssignmentBloc._buildAssignmentSlots to ensure consistency
  _CategorizedMembers _categorizeMembersForRole(
    List<TeamMember> teamMembers,
    String roleKey,
    Event event,
    List<Assignment> allAssignments,
  ) {
    final available = <TeamMember>[];
    final alreadyAssigned = <TeamMember>[];
    final sameDayAssignedMembersMap = <String, TeamMember>{};
    final sameDayEventInfoMap = <String, List<String>>{};

    // Get IDs of members already assigned to THIS event
    final assignedMemberIds = allAssignments
        .where((a) => a.eventId == event.id)
        .map((a) => a.teamMemberId)
        .toSet();

    // Build a map of eventId -> Event for quick lookup
    final eventMap = {for (var e in allEvents) e.id: e};
    final membersById = {for (var member in teamMembers) member.id: member};

    // Find members assigned to OTHER events on the same day(s)
    for (final assignment in allAssignments) {
      if (assignment.eventId == event.id) {
        continue; // Skip this event's assignments
      }

      // Get the other event
      final otherEvent = eventMap[assignment.eventId];
      if (otherEvent == null) continue;

      // Check if events share any day
      if (eventsShareDay(event, otherEvent)) {
        final member = membersById[assignment.teamMemberId];
        if (member == null) continue;

        // Same logic as /admin/assignments:
        // include only members who can do the role, do not allow multiple assignments,
        // and are available for this event.
        if (member.canPerformRole(roleKey) &&
            !member.allowMultipleAssignments) {
          final isAvailable = member.isAvailableForEventWithTime(event);
          if (isAvailable) {
            sameDayAssignedMembersMap[member.id] = member;
            sameDayEventInfoMap.putIfAbsent(member.id, () => []);
            sameDayEventInfoMap[member.id]!.add(otherEvent.name);
          }
        }
      }
    }

    for (final member in teamMembers) {
      // Check capability
      if (!member.canPerformRole(roleKey)) continue;

      // Check availability for entire event duration (including time-based constraints)
      // Skip availability check for members with allowMultipleAssignments
      final isAvailable = member.isAvailableForEventWithTime(event);
      if (!member.allowMultipleAssignments && !isAvailable) {
        continue;
      }

      // Separate based on whether already assigned to this event
      // Members with allowMultipleAssignments always go to available list
      if (member.allowMultipleAssignments) {
        available.add(member);
      } else if (assignedMemberIds.contains(member.id)) {
        alreadyAssigned.add(member);
      } else if (sameDayAssignedMembersMap.containsKey(member.id)) {
        // Member is assigned to another overlapping event.
        // Keep them out of "available", and show them in constrained dialog.
        continue;
      } else {
        available.add(member);
      }
    }

    // Sort each group by name
    available.sort((a, b) => a.name.compareTo(b.name));
    alreadyAssigned.sort((a, b) => a.name.compareTo(b.name));
    final sameDayAssigned = sameDayAssignedMembersMap.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return _CategorizedMembers(
      available: available,
      alreadyAssigned: alreadyAssigned,
      sameDayAssigned: sameDayAssigned,
      sameDayEventInfo: sameDayEventInfoMap,
    );
  }

  /// Build constrained/unavailable members using the same logic as /admin/assignments.
  List<TeamMember> _buildConstrainedMembers({
    required List<TeamMember> allTeamMembers,
    required String roleKey,
    required Event event,
    required List<TeamMember> availableMembers,
    required List<TeamMember> alreadyAssignedMembers,
    required List<TeamMember> sameDayAssignedMembers,
  }) {
    final availableIds = availableMembers.map((m) => m.id).toSet();
    final alreadyAssignedIds = alreadyAssignedMembers.map((m) => m.id).toSet();

    final constrainedMembersMap = <String, TeamMember>{
      for (final member in sameDayAssignedMembers) member.id: member,
    };

    for (final member in allTeamMembers) {
      if (!member.canPerformRole(roleKey)) continue;
      if (availableIds.contains(member.id) ||
          alreadyAssignedIds.contains(member.id)) {
        continue;
      }

      final isAvailable = member.isAvailableForEventWithTime(event);
      if (!isAvailable) {
        constrainedMembersMap[member.id] = member;
      }
    }

    final constrainedMembers = constrainedMembersMap.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return constrainedMembers;
  }

  void _showAssignmentConfirmationDialog(
    BuildContext context,
    Event event,
    String roleKey,
    String roleHebrewName,
    String memberId,
    TeamMember member,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('אישור שיבוץ'),
          content: _buildAssignmentConfirmationContent(
            memberName: member.name,
            roleHebrewName: roleHebrewName,
            eventName: event.name,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:cancel:assignmentConfirmation', {'eventId': event.id, 'roleKey': roleKey, 'memberId': memberId});
                Navigator.of(dialogContext).pop();
              },
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                Logger.action('tap:confirmAssignment', {'eventId': event.id, 'roleKey': roleKey, 'memberId': memberId});
                Navigator.of(dialogContext).pop();
                final now = DateTime.now();
                // Calculate slot index - find first available slot for this role
                final existingAssignments = allAssignments
                    .where(
                        (a) => a.eventId == event.id && a.roleType == roleKey)
                    .toList();
                final slotIndex = existingAssignments.length;

                context.read<AssignmentBloc>().add(
                      CreateAssignment(
                        Assignment(
                          id: const Uuid().v4(),
                          eventId: event.id,
                          teamMemberId: memberId,
                          roleType: roleKey,
                          slotIndex: slotIndex,
                          status: AssignmentStatus.pending,
                          notes: '',
                          createdAt: now,
                          updatedAt: now,
                        ),
                      ),
                    );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('שיבצת את ${member.name} לתפקיד $roleHebrewName'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('שבץ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistSection() {
    // Group items: pending first, then completed
    final pendingItems = data.checklistItems.where((i) => !i.status).toList();
    final completedItems = data.checklistItems.where((i) => i.status).toList();

    return Column(
      children: [
        // Pending items
        ...pendingItems.map((item) => _buildChecklistItemRow(item)),
        // Completed items (collapsible if many)
        if (completedItems.isNotEmpty) ...[
          if (pendingItems.isNotEmpty) const Divider(height: 16),
          ...completedItems.map((item) => _buildChecklistItemRow(item)),
        ],
      ],
    );
  }

  Widget _buildChecklistItemRow(ChecklistItem item) {
    final isCompleted = item.status;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isCompleted ? Icons.check_box : Icons.check_box_outline_blank,
            size: 20,
            color: isCompleted ? Colors.green.shade600 : Colors.orange.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              style: TextStyle(
                fontSize: 13,
                color:
                    isCompleted ? Colors.grey.shade600 : Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<TeamMember?> _showAlreadyAssignedDialog(
    BuildContext context,
    Event event,
    String roleKey,
    String roleHebrewName,
    List<TeamMember> alreadyAssignedMembers,
  ) async {
    // FILTER: Exclude members who already have this exact role
    final filteredSameEventMembers = alreadyAssignedMembers.where((member) {
      // Check if this member is already assigned to this specific role
      final hasThisRole = allAssignments.any((a) =>
          a.eventId == event.id &&
          a.roleType == roleKey &&
          a.teamMemberId == member.id);
      return !hasThisRole;
    }).toList();

    return showDialog<TeamMember?>(
      context: context,
      builder: (dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final dialogWidth =
            screenWidth > 600 ? screenWidth * 0.4 : screenWidth * 0.9;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.people, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'אנשים שכבר שובצו לאירוע "${event.name}"',
                    style: const TextStyle(fontSize: 18),
                    maxLines: 3,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              child: filteredSameEventMembers.isEmpty
                  ? SizedBox(
                      width: dialogWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            alreadyAssignedMembers.isEmpty
                                ? 'אין אנשים שכבר שובצו לאירוע זה'
                                : 'כל חברי הצוות שיכולים להשתבץ לתפקיד $roleHebrewName, ומשובצים לאירוע זה, כבר משובצים בתפקיד זה...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredSameEventMembers.length,
                      itemBuilder: (context, index) {
                        final member = filteredSameEventMembers[index];

                        final memberRoles = allAssignments
                            .where((assignment) =>
                                assignment.eventId == event.id &&
                                assignment.teamMemberId == member.id &&
                                assignment.roleType != roleKey)
                            .map((assignment) => _getRoleDisplayName(
                                  context,
                                  assignment.roleType,
                                ))
                            .toSet()
                            .toList();
                        final subtitle = memberRoles.isNotEmpty
                            ? 'תפקידים: ${memberRoles.join(", ")}'
                            : 'משובץ כבר לאירוע זה';

                        return ListTile(
                          title: Align(
                            alignment: Alignment.centerRight,
                            child: _buildMemberNameWithPermanentShield(member),
                          ),
                          subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                          trailing: ElevatedButton(
                            onPressed: () {
                              Logger.action('tap:assignAlreadyAssigned', {'eventId': event.id, 'roleKey': roleKey, 'memberId': member.id});
                              Navigator.of(dialogContext).pop(member);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('שבץ בכל זאת'),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:close:alreadyAssignedDialog', {'eventId': event.id, 'roleKey': roleKey});
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('סגור'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<TeamMember?> _showConstrainedMembersDialog(
    BuildContext context,
    Event event,
    List<TeamMember> constrainedMembers,
    Map<String, List<String>> sameDayEventInfo,
  ) async {
    return showDialog<TeamMember?>(
      context: context,
      builder: (dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final dialogWidth =
            screenWidth > 600 ? screenWidth * 0.4 : screenWidth * 0.9;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.block, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'בעלי מגבלות / לא זמינים - "${event.name}"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: constrainedMembers.isEmpty
                ? SizedBox(
                    width: dialogWidth,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'אין אנשים עם מגבלות או חוסר זמינות לתפקיד זה באירוע זה',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : SizedBox(
                    width: dialogWidth,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: constrainedMembers.length,
                      itemBuilder: (context, index) {
                        final member = constrainedMembers[index];
                        final sameDayEvents = sameDayEventInfo[member.id] ?? [];
                        final isSameDayAssigned = sameDayEvents.isNotEmpty;
                        final reason = isSameDayAssigned
                            ? 'משובצ/ת ב: ${sameDayEvents.join(", ")}'
                            : (member.isPermanent
                                ? 'מגבלה מאושרת'
                                : 'לא ציין/ה זמינות');

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
                              Logger.action('tap:assignConstrained', {'eventId': event.id, 'memberId': member.id});
                              Navigator.of(dialogContext).pop(member);
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
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:close:constrainedMembersDialog', {'eventId': event.id});
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('סגור'),
              ),
            ],
          ),
        );
      },
    );
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

  /// Format location for display - remove coordinates
  String _formatLocationForDisplay(String location) {
    if (location.contains('||')) {
      final strippedLocation = MapLocationResult.stripCoordinates(location);
      return strippedLocation.isNotEmpty ? strippedLocation : location;
    }
    return location;
  }

  String _getRoleDisplayName(BuildContext context, String roleKey) {
    final roleState = context.read<RoleBloc>().state;
    if (roleState is RolesLoaded) {
      final role = roleState.getRoleByKey(roleKey);
      if (role != null) {
        return role.hebrewName;
      }
    }

    try {
      return RoleTypeExtension.fromString(roleKey).hebrewName;
    } catch (_) {
      return roleKey;
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

  Widget _buildAssignmentConfirmationContent({
    required String memberName,
    required String roleHebrewName,
    required String eventName,
  }) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAssignmentConfirmationLine('חבר צוות:', memberName),
          const SizedBox(height: 8),
          _buildAssignmentConfirmationLine('לתפקיד:', roleHebrewName),
          const SizedBox(height: 8),
          _buildAssignmentConfirmationLine('באירוע:', eventName),
        ],
      ),
    );
  }

  Widget _buildAssignmentConfirmationLine(String label, String value) {
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        _buildHighlightedSentenceToken(value),
      ],
    );
  }

  Widget _buildHighlightedSentenceToken(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Helper class to hold member availability information
class _MissingSlot {
  final String roleKey;
  final String roleHebrewName;
  final int slotIndex;

  _MissingSlot({
    required this.roleKey,
    required this.roleHebrewName,
    required this.slotIndex,
  });
}

/// Helper class to hold categorized members
class _CategorizedMembers {
  final List<TeamMember> available;
  final List<TeamMember> alreadyAssigned;
  final List<TeamMember> sameDayAssigned;
  final Map<String, List<String>> sameDayEventInfo;

  _CategorizedMembers({
    required this.available,
    required this.alreadyAssigned,
    required this.sameDayAssigned,
    this.sameDayEventInfo = const {},
  });
}
