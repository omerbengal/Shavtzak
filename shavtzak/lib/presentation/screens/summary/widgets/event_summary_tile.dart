import 'package:flutter/material.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/checklist_item.dart';

/// Combined data for a single event's summary
class EventSummaryData {
  final Event event;
  final int filledSlots;
  final int totalSlots;
  final Map<RoleType, int> missingRoles; // role -> count needed
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

  const EventSummaryTile({
    super.key,
    required this.data,
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            // Date and location row
            Text(
              '${_formatDateRange(data.event)} | ${data.event.location}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            // Show actual show start time if available
            if (data.event.actualShowStartTime.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'תחילת המופע: ${data.event.actualShowStartTime}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
    // Iterate over RoleType.values to maintain consistent order (same as event form)
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: RoleType.values
          .where((role) => (data.missingRoles[role] ?? 0) > 0)
          .map((role) => _buildRoleChip(role, data.missingRoles[role]!))
          .toList(),
    );
  }

  Widget _buildRoleChip(RoleType role, int count) {
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
            '${role.hebrewName} ($count)',
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

  /// Format date range - shows single date if same day, range otherwise
  /// Uses 2-digit padding for days and months
  String _formatDateRange(Event event) {
    final start = event.startDate;
    final end = event.endDate;

    // Helper for 2-digit padding
    String pad(int n) => n.toString().padLeft(2, '0');

    // Check if same day
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return '${pad(start.day)}/${pad(start.month)}/${start.year}';
    }

    // Different days - show range
    if (start.year == end.year) {
      // Same year
      if (start.month == end.month) {
        // Same month: "15-17/01/2025"
        return '${pad(start.day)}-${pad(end.day)}/${pad(start.month)}/${start.year}';
      }
      // Different months, same year: "30/01/2025 - 04/02/2025"
      return '${pad(start.day)}/${pad(start.month)}/${start.year} - ${pad(end.day)}/${pad(end.month)}/${end.year}';
    }

    // Different years: "30/12/2024 - 02/01/2025"
    return '${pad(start.day)}/${pad(start.month)}/${start.year} - ${pad(end.day)}/${pad(end.month)}/${end.year}';
  }
}
