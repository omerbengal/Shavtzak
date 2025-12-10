import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/event.dart';
import '../../../core/constants/role_types.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/assignment/assignment_state.dart';

/// Screen for non-admin users to view their event assignments
class UserAssignmentsScreen extends StatefulWidget {
  const UserAssignmentsScreen({super.key});

  @override
  State<UserAssignmentsScreen> createState() => _UserAssignmentsScreenState();
}

class _UserAssignmentsScreenState extends State<UserAssignmentsScreen> {
  @override
  void initState() {
    super.initState();
    // Load assignments for the current user
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserAssignments();
    });
  }

  void _loadUserAssignments() {
    final userState = context.read<UserSelectionBloc>().state;
    if (userState is UserAuthenticated) {
      // Use LoadUserAssignments which watches both assignments AND events
      // This ensures real-time updates when event details change or events are deleted
      context.read<AssignmentBloc>().add(
        LoadUserAssignments(userState.user.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
            builder: (context, userState) {
              if (userState is! UserAuthenticated) {
                return const Center(
                  child: Text('אין משתמש מחובר'),
                );
              }

              return BlocConsumer<AssignmentBloc, AssignmentState>(
                listener: (context, state) {
                  if (state is AssignmentError) {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(state.message),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                  }
                },
                builder: (context, state) {
                  if (state is AssignmentLoading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (state is AssignmentsEmpty) {
                    return _buildEmptyState();
                  }

                  if (state is AssignmentsLoaded) {
                    return _buildAssignmentsContent(context, state.assignments);
                  }

                  if (state is AssignmentError) {
                    return _buildErrorState(state.message);
                  }

                  // Initial state or other states - show loading
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAssignmentsContent(BuildContext context, List<Assignment> assignments) {
    // Group assignments by event ID to consolidate multiple roles per event
    final Map<String, List<Assignment>> assignmentsByEvent = {};
    for (final assignment in assignments) {
      if (assignment.event == null) continue;
      final eventId = assignment.eventId;
      assignmentsByEvent.putIfAbsent(eventId, () => []);
      assignmentsByEvent[eventId]!.add(assignment);
    }

    // Convert to list of grouped assignments (using first assignment as representative)
    final groupedAssignments = assignmentsByEvent.entries.map((entry) {
      final eventAssignments = entry.value;
      // Sort roles by enum order for consistent display
      eventAssignments.sort((a, b) => a.roleType.index.compareTo(b.roleType.index));
      return eventAssignments;
    }).toList();

    // Separate upcoming and past
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final upcomingGroups = groupedAssignments.where((group) {
      final event = group.first.event!;
      final eventEndDate = DateTime(
        event.endDate.year,
        event.endDate.month,
        event.endDate.day,
      );
      return !eventEndDate.isBefore(today);
    }).toList();

    final pastGroups = groupedAssignments.where((group) {
      final event = group.first.event!;
      final eventEndDate = DateTime(
        event.endDate.year,
        event.endDate.month,
        event.endDate.day,
      );
      return eventEndDate.isBefore(today);
    }).toList();

    // Sort upcoming by start date (soonest first)
    upcomingGroups.sort((a, b) {
      return a.first.event!.startDate.compareTo(b.first.event!.startDate);
    });

    // Sort past by start date (most recent first)
    pastGroups.sort((a, b) {
      return b.first.event!.startDate.compareTo(a.first.event!.startDate);
    });

    return RefreshIndicator(
      onRefresh: () async {
        _loadUserAssignments();
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'המשימות שלי',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'כאן מופיעים כל האירועים שאליהם שובצת',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // Upcoming assignments section
          _buildSectionHeader(
            context,
            'אירועים קרובים',
            upcomingGroups.length,
            Colors.blue.shade700,
          ),

          if (upcomingGroups.isEmpty)
            _buildEmptySectionMessage('אין אירועים קרובים כרגע')
          else
            ...upcomingGroups.map((assignmentGroup) =>
              _buildAssignmentCard(context, assignmentGroup, isUpcoming: true),
            ),

          const SizedBox(height: 16),

          // Past assignments section
          _buildSectionHeader(
            context,
            'אירועים שעברו',
            pastGroups.length,
            Colors.grey.shade600,
          ),

          if (pastGroups.isEmpty)
            _buildEmptySectionMessage('אין אירועים קודמים')
          else
            ...pastGroups.map((assignmentGroup) =>
              _buildAssignmentCard(context, assignmentGroup, isUpcoming: false),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha((255 * 0.15).round()),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySectionMessage(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[500],
          ),
        ),
      ),
    );
  }

  /// Builds a card for an event with all assigned roles
  /// [assignmentGroup] contains all assignments for the same event (multiple roles)
  Widget _buildAssignmentCard(BuildContext context, List<Assignment> assignmentGroup, {required bool isUpcoming}) {
    if (assignmentGroup.isEmpty) return const SizedBox.shrink();

    // Use the first assignment to get event details (all share the same event)
    final event = assignmentGroup.first.event;
    if (event == null) {
      return const SizedBox.shrink();
    }

    // Get all role types for this event
    final roles = assignmentGroup.map((a) => a.roleType).toList();

    final backgroundColor = isUpcoming
        ? Colors.blue.shade50
        : Colors.grey.shade100;
    final borderColor = isUpcoming
        ? Colors.blue.shade200
        : Colors.grey.shade300;
    final iconColor = isUpcoming
        ? Colors.blue.shade700
        : Colors.grey.shade500;
    final textColor = isUpcoming
        ? Colors.grey.shade900
        : Colors.grey.shade600;
    final secondaryTextColor = isUpcoming
        ? Colors.grey.shade700
        : Colors.grey.shade500;

    // Check if event is today or tomorrow for special highlighting
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final eventStart = DateTime(event.startDate.year, event.startDate.month, event.startDate.day);
    final isToday = eventStart.isAtSameMomentAs(today);
    final isTomorrow = eventStart.isAtSameMomentAs(tomorrow);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: isUpcoming ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isToday ? Colors.orange.shade400 : borderColor,
          width: isToday ? 2 : 1,
        ),
      ),
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event name - now first
            Text(
              event.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 8),

            // Role badges row (can have multiple roles)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: roles.map((role) => _buildRoleBadge(role, isUpcoming)).toList(),
            ),

            const SizedBox(height: 12),

            // Assembly time & Location (most important info!)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUpcoming
                    ? Colors.blue.shade100.withAlpha((255 * 0.5).round())
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isUpcoming ? Colors.blue.shade300 : Colors.grey.shade400,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date row (always at top)
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 22,
                        color: isUpcoming ? Colors.blue.shade800 : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isSameDay(event.startDate, event.endDate) ? 'תאריך:' : 'תאריכים:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RichText(
                          text: _formatDateWithHighlight(
                            _formatDateDisplay(event, isToday, isTomorrow),
                            isUpcoming,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Location row (if exists) - now first
                  if (event.location.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 22,
                          color: isUpcoming ? Colors.blue.shade800 : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'מיקום:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            event.location,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isUpcoming ? Colors.blue.shade900 : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  // Assembly time row
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_filled,
                        size: 22,
                        color: isUpcoming ? Colors.blue.shade800 : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'שעת התייצבות:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        event.assemblyTime.isNotEmpty ? event.assemblyTime : 'טרם נקבעה',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isUpcoming ? Colors.blue.shade900 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Event time range
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 18,
                  color: iconColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'שעות האירוע:',
                  style: TextStyle(
                    fontSize: 13,
                    color: secondaryTextColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatEventTimes(event.startTime, event.endTime),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ],
            ),

            // Comments (if any)
            if (event.comments.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Colors.amber.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        event.comments,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Colors.amber.shade900,
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

  Widget _buildRoleBadge(RoleType roleType, bool isUpcoming) {
    final backgroundColor = isUpcoming
        ? _getRoleColor(roleType)
        : Colors.grey.shade400;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        roleType.hebrewName,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isUpcoming ? Colors.white : Colors.grey.shade800,
        ),
      ),
    );
  }

  Color _getRoleColor(RoleType roleType) {
    // All roles use green color for consistency
    return Colors.green.shade700;
  }

  String _formatDateDisplay(Event event, bool isToday, bool isTomorrow) {
    final startDate = event.startDate;
    final endDate = event.endDate;

    // Check if same day
    if (_isSameDay(startDate, endDate)) {
      final dateStr = 'יום ${_getFullHebrewDayName(startDate.weekday)} ${startDate.day} ב${_getHebrewMonthName(startDate.month)}';

      if (isToday) {
        return '$dateStr (היום)';
      }
      if (isTomorrow) {
        return '$dateStr (מחר)';
      }
      return dateStr;
    }

    // Multi-day event
    final startDateStr = 'יום ${_getFullHebrewDayName(startDate.weekday)} ${startDate.day} ב${_getHebrewMonthName(startDate.month)}';
    final endDateStr = 'יום ${_getFullHebrewDayName(endDate.weekday)} ${endDate.day} ב${_getHebrewMonthName(endDate.month)}';

    if (isToday) {
      return '$startDateStr (היום) - $endDateStr';
    }
    if (isTomorrow) {
      return '$startDateStr (מחר) - $endDateStr';
    }
    return '$startDateStr - $endDateStr';
  }

  String _formatDayMonth(DateTime date) {
    final day = date.day;
    final month = _getHebrewMonthName(date.month);
    return '$day $month';
  }

  String _getHebrewDayName(int weekday) {
    const days = ['', 'יום ב\'', 'יום ג\'', 'יום ד\'', 'יום ה\'', 'יום ו\'', 'שבת', 'יום א\''];
    return days[weekday == 7 ? 7 : weekday];
  }

  String _getFullHebrewDayName(int weekday) {
    const days = ['', 'ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    return days[weekday == 7 ? 7 : weekday];
  }

  TextSpan _formatDateWithHighlight(String dateText, bool isUpcoming) {
    final color = isUpcoming ? Colors.blue.shade900 : Colors.grey.shade700;

    if (dateText.contains('(היום)')) {
      final parts = dateText.split('(היום)');
      return TextSpan(
        children: [
          TextSpan(
            text: parts[0],
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          TextSpan(
            text: '(היום)',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          if (parts.length > 1)
            TextSpan(
              text: parts[1],
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
        ],
      );
    }

    if (dateText.contains('(מחר)')) {
      final parts = dateText.split('(מחר)');
      return TextSpan(
        children: [
          TextSpan(
            text: parts[0],
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          TextSpan(
            text: '(מחר)',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          if (parts.length > 1)
            TextSpan(
              text: parts[1],
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
        ],
      );
    }

    // No special indicators
    return TextSpan(
      text: dateText,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );
  }

  String _getHebrewMonthName(int month) {
    const months = [
      '', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
    ];
    return months[month];
  }

  String _formatEventTimes(String startTime, String endTime) {
    // Check if both times are empty
    if (startTime.isEmpty && endTime.isEmpty) {
      return 'טרם נקבעו';
    }

    // Check if only start time is empty
    if (startTime.isEmpty && endTime.isNotEmpty) {
      return 'טרם נקבעה -> $endTime';
    }

    // Check if only end time is empty
    if (startTime.isNotEmpty && endTime.isEmpty) {
      return '$startTime -> טרם נקבעה';
    }

    // Both times are available
    return '$startTime -> $endTime';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'אין לך שיבוצים כרגע',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'כשתשובץ/י לאירוע, הוא יופיע כאן',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red[400],
          ),
          const SizedBox(height: 16),
          Text(
            'שגיאה בטעינת שיבוצים',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadUserAssignments,
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }
}
