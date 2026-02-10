import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/checklist_item.dart';
import '../../../../domain/entities/role.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_state.dart';
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

  const EventSummaryTile({
    super.key,
    required this.data,
    required this.allAssignments,
  });

  @override
  Widget build(BuildContext context) {
    final hasIssues = !data.isFullyStaffed || data.pendingChecklistItems > 0;

    return Card(
      color: hasIssues ? Colors.orange.shade50 : Colors.green.shade50,
      child: ExpansionTile(
        title: Text(
          data.event.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // People icon button to show assignments
            IconButton(
              icon: const Icon(Icons.people_outline),
              tooltip: 'צפה בשיבוצים',
              onPressed: () {
                // Filter assignments for this event from the already-loaded list
                final eventAssignments = allAssignments
                    .where((a) => a.eventId == data.event.id)
                    .toList();
                showDialog(
                  context: context,
                  builder: (context) => EventAssignmentsDialog.withAssignments(
                    eventId: data.event.id,
                    eventName: data.event.name,
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            // Date in Hebrew
            Text(
              _formatEventDatesHebrew(data.event),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            // Time fields
            Text(
              _formatTimeFields(data.event),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            // Location (stripped of coordinates)
            if (data.event.location.isNotEmpty)
              Text(
                _formatLocationForDisplay(data.event.location),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            const SizedBox(height: 8),
            // Status indicators
            _buildStatusRow(),
          ],
        ),
        children: [
          _buildExpandedContent(),
        ],
      ),
    );
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
            color: data.pendingChecklistItems == 0 ? Colors.green : Colors.orange,
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
                    Icon(Icons.check_circle, size: 48, color: Colors.green.shade400),
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
    return BlocBuilder<RoleBloc, RoleState>(
      builder: (context, roleState) {
        // Get role display names from RoleBloc
        List<Role> roles;
        if (roleState is RolesLoaded) {
          roles = roleState.allNonArchivedRoles;
        } else {
          // Fallback to RoleType.values during initial load
          roles = RoleType.values.map((rt) => Role(
            id: rt.key,
            key: rt.key,
            hebrewName: rt.hebrewName,
            isVisible: true,
            isArchived: false,
            sortOrder: RoleType.values.indexOf(rt),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )).toList();
        }

        // Filter to only show roles that are missing
        final missingRoleEntries = roles.where((roleObj) {
          final count = data.missingRoles[roleObj.key] ?? 0;
          return count > 0;
        }).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        if (missingRoleEntries.isEmpty) {
          return const SizedBox.shrink();
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: missingRoleEntries.map((roleObj) {
            final count = data.missingRoles[roleObj.key] ?? 0;
            return _buildRoleChip(roleObj.hebrewName, count);
          }).toList(),
        );
      },
    );
  }

  Widget _buildRoleChip(String hebrewName, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 16, color: Colors.red.shade600),
          const SizedBox(width: 4),
          Text(
            '$hebrewName ($count)',
            style: TextStyle(
              fontSize: 13,
              color: Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
                color: isCompleted ? Colors.grey.shade600 : Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
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

  /// Format location for display - remove coordinates
  String _formatLocationForDisplay(String location) {
    if (location.contains('||')) {
      final strippedLocation = MapLocationResult.stripCoordinates(location);
      return strippedLocation.isNotEmpty ? strippedLocation : location;
    }
    return location;
  }
}
