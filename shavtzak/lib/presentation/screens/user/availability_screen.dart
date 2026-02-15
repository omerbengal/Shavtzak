import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';

class _UserAvailabilityContext {
  final String? userId;
  final bool isAuthenticated;

  const _UserAvailabilityContext({
    required this.userId,
    required this.isAuthenticated,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _UserAvailabilityContext &&
        other.userId == userId &&
        other.isAuthenticated == isAuthenticated;
  }

  @override
  int get hashCode => Object.hash(userId, isAuthenticated);
}

/// Screen for non-permanent users to manage their event-based availability
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  TeamMember? _lastKnownUser;
  List<Event> _futureEvents = [];

  @override
  void initState() {
    super.initState();
    // Load future events and team members for real-time updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventBloc>().add(const LoadUpcomingEvents());
      context.read<TeamBloc>().add(const LoadTeamMembers());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: BlocSelector<UserSelectionBloc, UserSelectionState, _UserAvailabilityContext>(
            selector: (state) {
              if (state is UserAuthenticated) {
                return _UserAvailabilityContext(
                  userId: state.user.id,
                  isAuthenticated: true,
                );
              }
              return const _UserAvailabilityContext(
                userId: null,
                isAuthenticated: false,
              );
            },
            builder: (context, userContext) {
              if (!userContext.isAuthenticated || userContext.userId == null) {
                return const Center(
                  child: Text('אין משתמש מחובר'),
                );
              }

              return BlocConsumer<TeamBloc, TeamState>(
                listener: (context, teamState) {
                  if (teamState is TeamError) {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Text(teamState.message),
                          ),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                  }
                },
                builder: (context, teamState) {
                  // Show loading only if we don't have any data yet
                  if (teamState is TeamLoading && _lastKnownUser == null) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (teamState is TeamLoaded) {
                    if (teamState.members.isEmpty) {
                      if (_lastKnownUser != null) {
                        return _buildAvailabilityContent(context, _lastKnownUser!);
                      }
                      return const Center(child: CircularProgressIndicator());
                    }
                    // Find the current user in the team list
                    final currentUser = teamState.members.firstWhere(
                      (member) => member.id == userContext.userId,
                      orElse: () => _lastKnownUser ?? teamState.members.first,
                    );
                    _lastKnownUser = currentUser;
                    return _buildAvailabilityContent(context, currentUser);
                  }

                  // For any other state (Success, Error, etc.), keep showing last known state
                  if (_lastKnownUser != null) {
                    return _buildAvailabilityContent(context, _lastKnownUser!);
                  }

                  if (teamState is TeamError) {
                    return Center(
                      child: Text('שגיאה: ${teamState.message}'),
                    );
                  }

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

  Widget _buildAvailabilityContent(BuildContext context, TeamMember user) {
    return BlocBuilder<EventBloc, EventState>(
      builder: (context, eventState) {
        if (eventState is EventLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (eventState is EventsLoaded) {
          final assignmentCounts = eventState.assignmentCounts;

          _futureEvents = eventState.events
              .where((event) {
                // Check 1: Not past
                if (_isPastEvent(event)) return false;

                // Check 2: Relevant for extended team
                if (!event.relevantForExtendedTeam) return false;

                // Check 3: User has marked as available OR event has available slots
                final userHasMarkedAvailable = user.availableEventIds.contains(event.id);
                if (userHasMarkedAvailable) return true; // Show even if fully occupied

                // If user hasn't marked as available, check if event has available slots
                final totalRequired = event.totalPeopleRequired;
                if (totalRequired == 0) return false; // Hide events with no quotas

                final assignmentCount = assignmentCounts[event.id] ?? 0;
                return assignmentCount < totalRequired; // Has available slots
              })
              .toList()
            ..sort((a, b) {
              // Sort by date first, then by name
              final dateComparison = a.startDate.compareTo(b.startDate);
              if (dateComparison != 0) return dateComparison;
              return a.name.compareTo(b.name);
            });
        }

        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'הזמינות שלי',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.green[700],
                        ),
                      ),
                      // History button for past events
                      TextButton.icon(
                        onPressed: () => _showPastEventsModal(context, user),
                        icon: const Icon(
                          Icons.history,
                          size: 20,
                        ),
                        label: const Text(
                          'אירועים שעברו',
                          style: TextStyle(fontSize: 14),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'כאן תוכל/י לסמן באילו אירועים את/ה זמין/ה להתנדב. הזמינות תשפיע מיד על האפשרות לשבץ אותך לאירועים.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Events list
            Expanded(
              child: _futureEvents.isEmpty
                  ? _buildEmptyState(context)
                  : _buildEventsList(context, user),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_available,
            size: 64,
            color: Colors.green[300],
          ),
          const SizedBox(height: 16),
          Text(
            'אין אירועים עתידיים',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'כשיווצרו אירועים חדשים, תוכל/י לסמן את הזמינות שלך',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEventsList(BuildContext context, TeamMember user) {
    // Group events by month
    final groupedEvents = _groupEventsByMonth(_futureEvents);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: groupedEvents.length,
      itemBuilder: (context, index) {
        final monthYear = groupedEvents.keys.elementAt(index);
        final events = groupedEvents[monthYear]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                monthYear,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Events for this month
            ...events.map((event) => _buildEventCard(context, event, user)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildEventCard(BuildContext context, Event event, TeamMember user) {
    final isAvailable = user.availableEventIds.contains(event.id);
    final formattedLocation = event.location.isNotEmpty
        ? _formatLocationForDisplay(event.location)
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isAvailable ? Colors.green[50] : Colors.white,
      child: CheckboxListTile(
        value: isAvailable,
        onChanged: (bool? value) {
          if (value != null) {
            _toggleEventAvailability(context, event, user, value);
          }
        },
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          event.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: isAvailable ? Colors.green[700] : Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatEventDates(event),
              style: TextStyle(
                fontWeight: isAvailable ? FontWeight.bold : FontWeight.normal,
                color: Colors.black,
              ),
            ),
            Text(
              _formatEventTimes(event),
              style: TextStyle(
                fontWeight: isAvailable ? FontWeight.bold : FontWeight.normal,
                color: Colors.black,
              ),
            ),
            if (formattedLocation.isNotEmpty)
              Text(
                'מיקום: $formattedLocation',
                style: TextStyle(
                  fontWeight: isAvailable ? FontWeight.bold : FontWeight.normal,
                  color: Colors.black,
                ),
              ),
          ],
        ),
        activeColor: Colors.green,
        checkColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  void _toggleEventAvailability(BuildContext context, Event event, TeamMember user, bool isAvailable) {
    final userState = context.read<UserSelectionBloc>().state;
    final teamState = context.read<TeamBloc>().state;

    if (userState is UserAuthenticated && teamState is TeamLoaded) {
      // Find the current user from the fresh team data
      final currentUser = teamState.members.firstWhere(
        (member) => member.id == userState.user.id,
        orElse: () => userState.user,
      );

      // Toggle event availability
      final updatedEventIds = List<String>.from(currentUser.availableEventIds);
      if (isAvailable) {
        if (!updatedEventIds.contains(event.id)) {
          updatedEventIds.add(event.id);
        }
      } else {
        updatedEventIds.remove(event.id);
      }

      final updatedUser = currentUser.copyWith(
        availableEventIds: updatedEventIds,
      );

      context.read<TeamBloc>().add(UpdateTeamMember(updatedUser));

      // Show success message
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text(isAvailable ? 'נוספה זמינות לאירוע' : 'הוסרה זמינות מהאירוע'),
            ),
            backgroundColor: isAvailable ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  void _showPastEventsModal(BuildContext context, TeamMember user) {
    // Since we only have future events loaded, show a message explaining that
    // In a real scenario, you might want to load past events or store history separately
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('אירועים שעברו'),
          content: const Text(
            'הזמינות לאירועים עתידיים מוצגת במסך הראשי. '
            'אירועים שעברו מוסרים אוטומטית מרשימת הזמינות.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('הבנתי'),
            ),
          ],
        ),
      ),
    );
  }

  /// Group events by month for easier navigation
  Map<String, List<Event>> _groupEventsByMonth(List<Event> events) {
    final grouped = <String, List<Event>>{};

    for (final event in events) {
      final monthKey = _getHebrewMonthYear(event.startDate);
      grouped.putIfAbsent(monthKey, () => []).add(event);
    }

    return grouped;
  }

  /// Get Hebrew month and year for grouping
  String _getHebrewMonthYear(DateTime date) {
    const months = [
      '', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
    ];
    return '${months[date.month]} ${date.year}';
  }

  /// Format event dates in Hebrew
  String _formatEventDates(Event event) {
    final isSameDay = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    if (isSameDay) {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)}';
    } else {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)} - יום ${_getFullHebrewDayName(event.endDate.weekday)} ${event.endDate.day} ב${_getHebrewMonthName(event.endDate.month)}';
    }
  }

  /// Format event times
  String _formatEventTimes(Event event) {
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

  /// Check if event is past (before today)
  bool _isPastEvent(Event event) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventEndDate = DateTime(event.endDate.year, event.endDate.month, event.endDate.day);
    return eventEndDate.isBefore(today);
  }

  /// Format location for display - remove coordinates
  String _formatLocationForDisplay(String location) {
    if (location.contains('||')) {
      // Extract the part before the "||" separator
      final parts = location.split('||');
      final strippedLocation = parts[0].trim();
      return strippedLocation.isNotEmpty ? strippedLocation : location;
    }
    return location;
  }
}
