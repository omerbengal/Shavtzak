import 'package:flutter/material.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/checklist_item.dart';
import '../../../../core/utils/event_assignment_status.dart';

/// Data class for summary cards metrics
class SummaryCardsData {
  final int criticalEventsCount;
  final int thisWeekEventsCount;
  final int fullyStaffedEventsCount;
  final int totalFutureEventsCount;
  final int pendingChecklistItemsCount;

  const SummaryCardsData({
    required this.criticalEventsCount,
    required this.thisWeekEventsCount,
    required this.fullyStaffedEventsCount,
    required this.totalFutureEventsCount,
    required this.pendingChecklistItemsCount,
  });
}

/// Widget displaying 3 actionable summary cards in a responsive grid
class SummaryHeaderCards extends StatelessWidget {
  final SummaryCardsData data;

  const SummaryHeaderCards({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 600;

    return isWideScreen ? _buildHorizontalGrid() : _buildVerticalList();
  }

  Widget _buildHorizontalGrid() {
    return Row(
      children: [
        Expanded(
          child: _CriticalThisWeekCard(
            criticalCount: data.criticalEventsCount,
            thisWeekCount: data.thisWeekEventsCount,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _FullyStaffedCard(
            count: data.fullyStaffedEventsCount,
            totalFutureEventsCount: data.totalFutureEventsCount,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ChecklistStatusCard(count: data.pendingChecklistItemsCount),
        ),
      ],
    );
  }

  Widget _buildVerticalList() {
    return Column(
      children: [
        _CriticalThisWeekCard(
          criticalCount: data.criticalEventsCount,
          thisWeekCount: data.thisWeekEventsCount,
        ),
        const SizedBox(height: 8),
        _FullyStaffedCard(
          count: data.fullyStaffedEventsCount,
          totalFutureEventsCount: data.totalFutureEventsCount,
        ),
        const SizedBox(height: 8),
        _ChecklistStatusCard(count: data.pendingChecklistItemsCount),
      ],
    );
  }
}

/// Merged Critical/This Week Card - Red/Blue accent
class _CriticalThisWeekCard extends StatelessWidget {
  final int criticalCount;
  final int thisWeekCount;

  const _CriticalThisWeekCard({
    required this.criticalCount,
    required this.thisWeekCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.red.shade700, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$criticalCount ${criticalCount == 1 ? "אירועים דחופים לטיפול" : "אירועים דחופים לטיפול"}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'מתוך $thisWeekCount ${thisWeekCount == 1 ? "אירועים בשבוע הקרוב" : "אירועים בשבוע הקרוב"}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fully Staffed Card - Green accent
class _FullyStaffedCard extends StatelessWidget {
  final int count;
  final int totalFutureEventsCount;

  const _FullyStaffedCard({
    required this.count,
    required this.totalFutureEventsCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              color: Colors.green.shade700, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count ${count == 1 ? "אירוע מאויש במלואו" : "אירועים מאוישים במלואם"}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'מתוך כל $totalFutureEventsCount האירועים העתידיים',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Checklist Status Card - Orange accent
class _ChecklistStatusCard extends StatelessWidget {
  final int count;

  const _ChecklistStatusCard({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_rounded,
              color: Colors.orange.shade700, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count ${count == 1 ? "פריט צ'קליסט ממתין" : count == 2 ? "פריטי צ'קליסט ממתינים" : "פריטי צ'קליסט ממתינים"}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'בכל האירועים',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compute summary cards data from events, assignments, and checklist items
SummaryCardsData computeSummaryCardsData(
  List<Event> events,
  List<Assignment> assignments,
  List<ChecklistItem> checklistItems,
) {
  DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  final now = DateTime.now();
  final today = dateOnly(now);
  final fortyEightHoursLater = now.add(const Duration(hours: 48));
  final sevenDaysLater = now.add(const Duration(days: 7));
  final futureEvents = events
      .where((event) => !dateOnly(event.endDate).isBefore(today))
      .toList();

  // Create assignment lookup by event
  final assignmentsByEvent = <String, List<Assignment>>{};
  for (final assignment in assignments) {
    assignmentsByEvent.putIfAbsent(assignment.eventId, () => []);
    assignmentsByEvent[assignment.eventId]!.add(assignment);
  }

  int criticalEventsCount = 0;
  int thisWeekEventsCount = 0;
  int fullyStaffedEventsCount = 0;

  for (final event in futureEvents) {
    final eventAssignments = assignmentsByEvent[event.id] ?? [];
    final status = EventAssignmentStatusHelper.calculateStatus(
      event,
      eventAssignments,
    );

    // Check if event is within 48 hours and not fully staffed
    if (event.startDate.isBefore(fortyEightHoursLater) &&
        status != EventAssignmentStatus.complete) {
      criticalEventsCount++;
    }

    // Check if event is within 7 days
    if (event.startDate.isBefore(sevenDaysLater)) {
      thisWeekEventsCount++;
    }

    // Count fully staffed events
    if (status == EventAssignmentStatus.complete) {
      fullyStaffedEventsCount++;
    }
  }

  // Count pending checklist items
  final pendingChecklistItemsCount =
      checklistItems.where((i) => !i.status).length;

  return SummaryCardsData(
    criticalEventsCount: criticalEventsCount,
    thisWeekEventsCount: thisWeekEventsCount,
    fullyStaffedEventsCount: fullyStaffedEventsCount,
    totalFutureEventsCount: futureEvents.length,
    pendingChecklistItemsCount: pendingChecklistItemsCount,
  );
}
