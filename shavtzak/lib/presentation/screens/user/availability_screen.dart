import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/debug/logger.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../../core/utils/event_filter_utils.dart';
import '../../widgets/date_picker_dialog.dart';
import '../../widgets/event_search_filter_bar.dart';
import '../../widgets/loading_overlay.dart';

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
  bool _isMutationInFlight = false;
  String _mutationMessage = '';

  // Feature 2: ephemeral search + category filter over the events list.
  String _searchQuery = '';
  Set<String> _selectedCategoryIds = <String>{};

  @override
  void initState() {
    super.initState();
    // Real-time events via the shared EventBloc (now self-healing) + team data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
        body: Stack(
          children: [
            SafeArea(
              child: BlocSelector<UserSelectionBloc, UserSelectionState,
                  _UserAvailabilityContext>(
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
                      if (teamState is TeamLoading && _lastKnownUser == null) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      if (teamState is TeamLoaded) {
                        if (teamState.members.isEmpty) {
                          if (_lastKnownUser != null) {
                            return _buildAvailabilityContent(
                                context, _lastKnownUser!);
                          }
                          return const Center(child: CircularProgressIndicator());
                        }
                        final currentUser = teamState.members.firstWhere(
                          (member) => member.id == userContext.userId,
                          orElse: () => _lastKnownUser ?? teamState.members.first,
                        );
                        _lastKnownUser = currentUser;
                        return _buildAvailabilityContent(context, currentUser);
                      }

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
            LoadingOverlay(
              isLoading: _isMutationInFlight,
              message: _mutationMessage,
            ),
          ],
        ),
      ),
    );
  }

  void _startMutation(String message) {
    setState(() {
      _isMutationInFlight = true;
      _mutationMessage = message;
    });
  }

  void _finishMutation() {
    if (!mounted) return;
    setState(() {
      _isMutationInFlight = false;
      _mutationMessage = '';
    });
  }

  Future<CrudActionResult> _runBlockingMutation({
    required String message,
    required void Function(CrudActionCompleter completion) dispatch,
  }) async {
    if (_isMutationInFlight) {
      return const CrudActionResult.failure('פעולה אחרת עדיין מתבצעת');
    }

    _startMutation(message);
    try {
      final completion = Completer<CrudActionResult>();
      dispatch(completion);
      return await completion.future;
    } finally {
      _finishMutation();
    }
  }

  Widget _buildAvailabilityContent(BuildContext context, TeamMember user) {
    return BlocBuilder<EventBloc, EventState>(
      builder: (context, eventState) {
        // Derive the events list from EventBloc's (now self-healing) state.
        final List<Event> allEvents;
        if (eventState is EventsLoaded) {
          allEvents = eventState.events;
        } else if (eventState is EventsEmpty) {
          allEvents = const [];
        } else if (eventState is EventError) {
          return _buildEventsErrorState(context);
        } else {
          // EventInitial / EventLoading — still loading.
          return const Center(child: CircularProgressIndicator());
        }

        _futureEvents = allEvents
            .where((event) {
              // Show ALL future events relevant to the extended team — full or
              // not, marked or not. (Previously also hid events with no free
              // slots; per product decision, full events now appear too.)
              if (_isPastEvent(event)) return false;
              if (event.isDeactivated) return false; // on-hold events are hidden
              if (!event.relevantForExtendedTeam) return false;
              return true;
            })
            .toList()
          ..sort((a, b) {
            // Sort by date first, then by name
            final dateComparison = a.startDate.compareTo(b.startDate);
            if (dateComparison != 0) return dateComparison;
            return a.name.compareTo(b.name);
          });

        final filteredEvents = filterEventsBySearchAndCategory(
          _futureEvents,
          query: _searchQuery,
          categoryIds: _selectedCategoryIds,
        );
        final hasAnyEvents = _futureEvents.isNotEmpty;

        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                        onPressed: () {
                          Logger.action('open:pastEventsModal');
                          _showPastEventsModal(context, user);
                        },
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

            // Feature 1: bulk-mark availability across a date range.
            if (hasAnyEvents) _buildDateRangeButton(context, user),

            // Feature 2: search + category filter over the events.
            if (hasAnyEvents)
              EventSearchFilterBar(
                logField: 'availabilityEvents',
                searchQuery: _searchQuery,
                onSearchChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                selectedCategoryIds: _selectedCategoryIds,
                onCategoryFilterChanged: (ids) {
                  setState(() => _selectedCategoryIds = ids);
                },
              ),

            // Feature 2: "select all filtered" toggle + count.
            if (hasAnyEvents)
              _buildSelectAllRow(context, user, filteredEvents),

            // Events list
            Expanded(
              child: !hasAnyEvents
                  ? _buildEmptyState(context)
                  : (filteredEvents.isEmpty
                      ? _buildNoResultsState(context)
                      : _buildEventsList(context, user, filteredEvents)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEventsErrorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'שגיאה בטעינת אירועים',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[700],
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Logger.action('tap:retryLoadAvailabilityEvents');
                context.read<EventBloc>().add(const LoadUpcomingEvents());
              },
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('נסה שוב'),
            ),
          ],
        ),
      ),
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

  /// Feature 1: button that opens the date-range picker to bulk-mark availability.
  Widget _buildDateRangeButton(BuildContext context, TeamMember user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: () {
            Logger.action('open:availabilityDateRangePicker');
            _pickDateRangeForAvailability(context, user);
          },
          icon: const Icon(Icons.date_range, size: 20),
          label: const Text('בחירה לפי טווח תאריכים'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.green[700]),
        ),
      ),
    );
  }

  /// Feature 2: "select all filtered" ⇄ "clear filtered" toggle + count.
  Widget _buildSelectAllRow(
    BuildContext context,
    TeamMember user,
    List<Event> filteredEvents,
  ) {
    final filteredIds = filteredEvents.map((e) => e.id).toSet();
    final selectedCount =
        filteredIds.where((id) => user.availableEventIds.contains(id)).length;
    final allSelected =
        filteredIds.isNotEmpty && selectedCount == filteredIds.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: filteredEvents.isEmpty
                ? null
                : () {
                    Logger.action('tap:selectAllFilteredAvailability', {
                      'allSelected': allSelected,
                      'count': filteredIds.length,
                    });
                    _toggleSelectAllFiltered(context, user, filteredEvents);
                  },
            icon: Icon(
              allSelected ? Icons.remove_done : Icons.done_all,
              size: 20,
            ),
            label: Text(allSelected ? 'בטל בחירה' : 'בחר הכל'),
          ),
          Text(
            'נבחרו $selectedCount מתוך ${filteredIds.length}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'אין אירועים התואמים לסינון',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsList(
    BuildContext context,
    TeamMember user,
    List<Event> events,
  ) {
    // Group events by month
    final groupedEvents = _groupEventsByMonth(events);

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
            Logger.action('toggle:eventAvailability', {'eventId': event.id, 'on': value});
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

  Future<void> _toggleEventAvailability(
    BuildContext context,
    Event event,
    TeamMember user,
    bool isAvailable,
  ) async {
    final userState = context.read<UserSelectionBloc>().state;
    final teamState = context.read<TeamBloc>().state;

    if (userState is UserAuthenticated && teamState is TeamLoaded) {
      final currentUser = teamState.members.firstWhere(
        (member) => member.id == userState.user.id,
        orElse: () => userState.user,
      );

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

      final result = await _runBlockingMutation(
        message: isAvailable ? 'מוסיף זמינות...' : 'מסיר זמינות...',
        dispatch: (completion) => context.read<TeamBloc>().add(
              UpdateTeamMember(updatedUser, completion: completion),
            ),
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                result.message ??
                    (result.isSuccess
                        ? (isAvailable
                            ? 'נוספה זמינות לאירוע'
                            : 'הוסרה זמינות מהאירוע')
                        : 'שגיאה בעדכון הזמינות'),
              ),
            ),
            backgroundColor: result.isSuccess
                ? (isAvailable ? Colors.green : Colors.orange)
                : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  /// Resolve the freshest copy of the current user from live BLoC state,
  /// falling back to [fallback] when state is unavailable.
  TeamMember _resolveCurrentUser(BuildContext context, TeamMember fallback) {
    final teamState = context.read<TeamBloc>().state;
    final userState = context.read<UserSelectionBloc>().state;
    if (teamState is TeamLoaded && userState is UserAuthenticated) {
      return teamState.members.firstWhere(
        (member) => member.id == userState.user.id,
        orElse: () => fallback,
      );
    }
    return fallback;
  }

  /// Feature 1: pick a date range and union every event in that range into the
  /// user's availability with a single batched write.
  Future<void> _pickDateRangeForAvailability(
    BuildContext context,
    TeamMember user,
  ) async {
    final eligible = _futureEvents;
    if (eligible.isEmpty) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (_) => DualCalendarDatePicker(
        isSingleDate: false,
        title: 'בחירת זמינות לפי טווח תאריכים',
        minDate: today,
        highlightedDates: eventCoverageDays(eligible),
      ),
    );
    if (result == null || result['startDate'] == null) return;

    final start = result['startDate']!;
    final end = result['endDate'] ?? start;
    final idsInRange = eventIdsInDateRange(eligible, start, end);

    if (!context.mounted) return;
    final currentUser = _resolveCurrentUser(context, user);
    final currentIds = currentUser.availableEventIds;
    final merged = <String>{...currentIds, ...idsInRange};
    final addedCount = merged.length - currentIds.length;

    if (addedCount == 0) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text('לא נמצאו אירועים חדשים בטווח שנבחר'),
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    await _persistAvailabilityIds(
      context,
      baseUser: currentUser,
      newIds: merged.toList(),
      progressMessage: 'מסמן זמינות לטווח...',
      successText: 'נוספה זמינות ל-$addedCount אירועים',
    );
  }

  /// Feature 2: toggle availability for every currently-filtered event with a
  /// single batched write (select-all when not all are marked, else clear).
  Future<void> _toggleSelectAllFiltered(
    BuildContext context,
    TeamMember user,
    List<Event> filteredEvents,
  ) async {
    if (filteredEvents.isEmpty) return;

    final currentUser = _resolveCurrentUser(context, user);
    final currentIds = currentUser.availableEventIds;
    final filteredIds = filteredEvents.map((e) => e.id).toSet();
    final allSelected = filteredIds.every((id) => currentIds.contains(id));

    final List<String> newIds;
    final String successText;
    final Color successColor;
    if (allSelected) {
      newIds =
          currentIds.where((id) => !filteredIds.contains(id)).toList();
      successText = 'הוסרה זמינות מ-${filteredIds.length} אירועים';
      successColor = Colors.orange;
    } else {
      final merged = <String>{...currentIds, ...filteredIds};
      final addedCount = merged.length - currentIds.length;
      newIds = merged.toList();
      successText = 'נוספה זמינות ל-$addedCount אירועים';
      successColor = Colors.green;
    }

    await _persistAvailabilityIds(
      context,
      baseUser: currentUser,
      newIds: newIds,
      progressMessage: allSelected ? 'מסיר זמינות...' : 'מוסיף זמינות...',
      successText: successText,
      successColor: successColor,
    );
  }

  /// Shared batched persist for bulk availability changes (date range + select
  /// all). One [UpdateTeamMember]; the real-time stream refreshes the checkboxes.
  Future<void> _persistAvailabilityIds(
    BuildContext context, {
    required TeamMember baseUser,
    required List<String> newIds,
    required String progressMessage,
    required String successText,
    Color successColor = Colors.green,
  }) async {
    final updatedUser = baseUser.copyWith(availableEventIds: newIds);

    final result = await _runBlockingMutation(
      message: progressMessage,
      dispatch: (completion) => context.read<TeamBloc>().add(
            UpdateTeamMember(updatedUser, completion: completion),
          ),
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              result.isSuccess
                  ? successText
                  : (result.message ?? 'שגיאה בעדכון הזמינות'),
            ),
          ),
          backgroundColor: result.isSuccess ? successColor : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
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
              onPressed: () {
                Logger.action('tap:close:pastEventsModal');
                Navigator.of(context).pop();
              },
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
