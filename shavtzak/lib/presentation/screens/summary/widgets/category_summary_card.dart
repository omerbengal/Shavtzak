import 'package:flutter/material.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/event.dart';
import 'event_summary_tile.dart';

/// Card widget showing a category with aggregated status data.
/// Header is always colored (orange/green), expanded content is white.
/// Uses implicit animations (AnimatedSize/AnimatedRotation) to avoid
/// disposal issues with manual AnimationController during route transitions.
class CategorySummaryCard extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final List<EventSummaryData> eventSummaries;
  final List<Assignment> allAssignments;
  final List<Event> allEvents;

  const CategorySummaryCard({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.eventSummaries,
    required this.allAssignments,
    required this.allEvents,
  });

  @override
  State<CategorySummaryCard> createState() => _CategorySummaryCardState();
}

class _CategorySummaryCardState extends State<CategorySummaryCard> {
  bool _isExpanded = false;

  int get _totalUnfilledSlots =>
      widget.eventSummaries.fold(0, (sum, s) => sum + s.unfilledSlots);
  int get _eventsWithMissingRolesCount =>
      widget.eventSummaries.where((s) => s.unfilledSlots > 0).length;
  int get _totalPendingChecklist =>
      widget.eventSummaries.fold(0, (sum, s) => sum + s.pendingChecklistItems);
  int get _totalChecklistItems =>
      widget.eventSummaries.fold(0, (sum, s) => sum + s.totalChecklistItems);
  bool get _hasIssues => widget.eventSummaries
      .any((s) => !s.isFullyStaffed || s.pendingChecklistItems > 0);
  bool get _allFullyStaffed =>
      widget.eventSummaries.every((s) => s.isFullyStaffed);
  bool get _hasChecklistItems => _totalChecklistItems > 0;

  // Progress calculation
  int get _totalSlots =>
      widget.eventSummaries.fold(0, (sum, s) => sum + s.totalSlots);
  int get _totalFilledSlots =>
      widget.eventSummaries.fold(0, (sum, s) => sum + s.filledSlots);
  double get _staffingPercentage {
    if (_totalSlots == 0) return 100.0; // No quotas = 100%
    return (_totalFilledSlots / _totalSlots) * 100;
  }

  int get _readyEventsCount =>
      widget.eventSummaries.where((s) => s.isFullyStaffed).length;

  @override
  Widget build(BuildContext context) {
    final headerColor =
        _hasIssues ? Colors.orange.shade50 : Colors.green.shade50;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header - always colored
          Material(
            color: headerColor,
            child: InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Icon(Icons.folder,
                            size: 20, color: Colors.grey.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.categoryName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          '${widget.eventSummaries.length} ${widget.eventSummaries.length == 1 ? "אירוע" : "אירועים"}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700),
                        ),
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: _isExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.expand_more,
                              color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Status row
                    _buildStatusRow(),
                  ],
                ),
              ),
            ),
          ),
          // Expandable content - white background
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Column(
                    children: [
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Column(
                          children: widget.eventSummaries
                              .map((summary) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: EventSummaryTile(
                                      key: ValueKey(
                                          'summary_event_${summary.event.id}'),
                                      data: summary,
                                      allAssignments: widget.allAssignments,
                                      allEvents: widget.allEvents,
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status chips row
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            // Staffing status
            _buildStatusChip(
              icon: _allFullyStaffed ? Icons.check_circle : Icons.person_off,
              label: _allFullyStaffed
                  ? 'כל האירועים מאוישים'
                  : _eventsWithMissingRolesCount == 1
                      ? '$_totalUnfilledSlots תפקידים חסרים באירוע אחד'
                      : '$_totalUnfilledSlots תפקידים חסרים ב-$_eventsWithMissingRolesCount אירועים',
              color: _allFullyStaffed ? Colors.green : Colors.orange,
            ),
            // Checklist status
            if (_hasChecklistItems)
              _buildStatusChip(
                icon: _totalPendingChecklist == 0
                    ? Icons.check_circle
                    : Icons.pending,
                label: _totalPendingChecklist == 0
                    ? 'צ\'קליסט הושלם'
                    : '$_totalPendingChecklist/$_totalChecklistItems פריטים ממתינים',
                color:
                    _totalPendingChecklist == 0 ? Colors.green : Colors.orange,
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Progress bar
        _buildProgressBar(),
        const SizedBox(height: 4),
        // Quick stats
        _buildQuickStats(),
      ],
    );
  }

  Widget _buildProgressBar() {
    final percentage = _staffingPercentage;
    final color = percentage >= 100
        ? Colors.green
        : percentage > 0
            ? Colors.orange
            : Colors.red;

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: percentage / 100,
        backgroundColor: Colors.grey.shade200,
        valueColor: AlwaysStoppedAnimation<Color>(color),
        minHeight: 4,
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '$_readyEventsCount מתוך ${widget.eventSummaries.length} אירועים מוכנים',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
          ),
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
}
