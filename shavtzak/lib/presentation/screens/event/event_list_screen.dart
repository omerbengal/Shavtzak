import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/event_assignment_status.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/search_utils.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/services/google_calendar_service.dart';
import '../../../core/constants/calendar_constants.dart';
import '../../../domain/entities/event.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/category/category_bloc.dart';
import '../../bloc/category/category_state.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/interactive_filter_bar.dart';
import '../../../core/debug/logger.dart';
import '../../widgets/map_location_picker.dart';
import 'widgets/category_filter_modal.dart';
import 'widgets/category_management_dialog.dart';
import 'widgets/event_form_modal.dart';
import 'widgets/event_drive_files_section.dart';
import 'widgets/role_management_dialog.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../core/debug/search_action_logger.dart';

// Filter enum for events (0=all, 1=future, 2=past)
enum EventFilter { all, future, past }

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SearchActionLogger _searchLog = SearchActionLogger('events');
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';
  EventsLoaded? _lastLoadedState;
  Set<String> _selectedCategoryIds = {};

  /// Live per-event Google Calendar sync status, used to badge events whose
  /// calendar entry is missing/failed. Cached once so rebuilds don't
  /// re-subscribe to the underlying Firestore stream.
  late final Stream<Map<String, CalendarSyncStatus>> _calendarSyncStates;

  /// Build a compact icon button for the leading AppBar section
  Widget _buildCompactIcon(
      {required IconData icon,
      required VoidCallback onPressed,
      Widget? badge}) {
    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: badge != null
            ? Badge(
                label: badge,
                // Nudge the badge further up and toward the end (visually left
                // in RTL) so it sits at the icon's corner instead of covering
                // most of it.
                alignment: AlignmentDirectional.topEnd,
                offset: const Offset(8, -8),
                child: Icon(icon, size: 22),
              )
            : Icon(icon, size: 22),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchFocusNode = createRtlCursorFixedFocusNode(_searchController);
    _calendarSyncStates =
        context.read<EventBloc>().watchCalendarSyncStates().asBroadcastStream();
    // Always load ALL events - filtering happens in UI
    context.read<EventBloc>().add(const LoadEvents());
  }

  @override
  void dispose() {
    _searchLog.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchLog.onQueryChanged(query);
    setState(() {
      _searchQuery = query;
    });
  }

  /// Handle filter change
  void _onFilterChanged(int newIndex) {
    Logger.action('filter:eventScope', {'index': newIndex});
    setState(() {
      FilterPersistence.eventFilterIndex = newIndex;
    });
  }

  /// Show category filter modal
  void _showCategoryFilterModal() {
    Logger.action('open:categoryFilterModal');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CategoryFilterModal(
        selectedCategoryIds: _selectedCategoryIds,
        onFilterChanged: (selectedIds) {
          Logger.action('filter:categories', {'count': selectedIds.length});
          setState(() {
            _selectedCategoryIds = selectedIds;
            FilterPersistence.selectedEventCategoryIds = selectedIds;
          });
        },
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              // Leading: Deactivated events button (mirrors the car icon in /admin/team-members)
              BlocSelector<EventBloc, EventState, int>(
                selector: (state) {
                  if (state is EventsLoaded) {
                    return state.events.where((e) => e.isDeactivated).length;
                  }
                  if (_lastLoadedState != null) {
                    return _lastLoadedState!.events
                        .where((e) => e.isDeactivated)
                        .length;
                  }
                  return 0;
                },
                builder: (context, deactivatedCount) {
                  return Tooltip(
                    message: 'אירועים מושבתים',
                    child: _buildCompactIcon(
                      icon: Icons.power_settings_new,
                      onPressed: _showDeactivatedEventsDialog,
                      badge: deactivatedCount > 0
                          ? Text(deactivatedCount.toString())
                          : null,
                    ),
                  );
                },
              ),
              // Centered title
              const Expanded(
                child: Center(
                    child: Text('אירועים', style: TextStyle(fontSize: 20))),
              ),
              // Trailing icons
              IconButton(
                icon: const Icon(Icons.work),
                tooltip: 'ניהול תפקידים',
                onPressed: () {
                  Logger.action('open:roleManagementDialog');
                  showDialog(
                    context: context,
                    builder: (context) => const RoleManagementDialog(),
                  );
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              IconButton(
                icon: const Icon(Icons.category),
                tooltip: 'ניהול קטגוריות',
                onPressed: () {
                  Logger.action('open:categoryManagementDialog');
                  showDialog(
                    context: context,
                    builder: (context) => const CategoryManagementDialog(),
                  );
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              IconButton(
                icon: const Icon(Icons.home),
                tooltip: 'בית',
                onPressed: () {
                  Logger.action('tap:home');
                  final envPrefix = EnvironmentService.instance.routePrefix;
                  context.go('$envPrefix/admin');
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'התנתק',
                onPressed: () {
                  Logger.action('tap:logout');
                  _logout(context);
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
            ],
          ),
        ),
        body: BlocConsumer<EventBloc, EventState>(
          listener: (context, state) {
            if (state is EventError) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(state.message),
                    ),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 2),
                  ),
                );
            } else if (state is EventOperationSuccess) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(state.message),
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
            }
          },
          builder: (context, state) {
            // Always show last known state if available, unless explicitly loading
            if (state is EventLoading && _lastLoadedState == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is EventsEmpty) {
              return _buildEmptyState(state);
            }
            if (state is EventsLoaded) {
              _lastLoadedState = state;
              return _buildEventList(state);
            }
            // For any other state (Success, Error), keep showing last state if available
            if (_lastLoadedState != null) {
              return _buildEventList(_lastLoadedState!);
            }
            if (state is EventError) {
              return _buildErrorState(state.message);
            }
            return _buildEmptyState(const EventsEmpty('טוען...'));
          },
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'event-list-fab',
          onPressed: () {
            Logger.action('tap:addEvent');
            _showEventFormModal(null);
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildEventList(EventsLoaded state) {
    // Exclude deactivated events from the main list and from all counts.
    // Deactivated events are surfaced through a dedicated dialog instead.
    final activeEvents =
        state.events.where((event) => !event.isDeactivated).toList();

    // Calculate counts from active events only
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final totalCount = activeEvents.length;
    final upcomingCount = activeEvents.where((event) {
      return event.endDate.isAfter(todayDate) ||
          event.endDate.isAtSameMomentAs(todayDate);
    }).length;
    final pastCount = activeEvents.where((event) {
      return event.endDate.isBefore(todayDate);
    }).length;

    // Filter events based on selected filter (operating on active-only set)
    final filteredEvents =
        _filterEvents(activeEvents, FilterPersistence.eventFilterIndex);

    return RefreshIndicator(
      onRefresh: () async {
        Logger.action('tap:refreshEvents');
        context.read<EventBloc>().add(const RefreshEvents());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: Column(
        children: [
          // Interactive filter bar
          InteractiveFilterBar(
            options: [
              FilterOption(label: 'סה״כ', count: totalCount.toString()),
              FilterOption(
                  label: 'עתידיים', count: upcomingCount.toString()),
              FilterOption(label: 'עברו', count: pastCount.toString()),
            ],
            selectedIndex: FilterPersistence.eventFilterIndex,
            onFilterChanged: _onFilterChanged,
          ),
          // Search bar with filter button inside
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'חיפוש אירוע...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Clear button (only when there's text)
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            Logger.action('tap:clearSearch');
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        ),
                      // Filter button (always visible)
                      IconButton(
                        icon: Badge(
                          isLabelVisible: _selectedCategoryIds.isNotEmpty,
                          label: Text(_selectedCategoryIds.length.toString()),
                          child: Icon(
                            Icons.filter_list,
                            color: _selectedCategoryIds.isNotEmpty
                                ? Colors.blue.shade700
                                : null,
                          ),
                        ),
                        onPressed: _showCategoryFilterModal,
                        tooltip: _selectedCategoryIds.isEmpty
                            ? 'סינון לפי קטגוריה'
                            : 'סינון: ${_selectedCategoryIds.length} קטגוריות',
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<Map<String, CalendarSyncStatus>>(
              stream: _calendarSyncStates,
              builder: (context, snapshot) {
                final syncStates =
                    snapshot.data ?? const <String, CalendarSyncStatus>{};
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: filteredEvents.length,
                  itemBuilder: (context, index) {
                    return _buildEventCard(
                      filteredEvents[index],
                      state.assignmentCounts,
                      state.eventBirthdays,
                      calendarSyncStates: syncStates,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Filter events based on selected filter index
  List<Event> _filterEvents(List<Event> events, int filterIndex) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    List<Event> result;
    switch (filterIndex) {
      case 0: // All
        result = events;
        break;
      case 1: // Future (עתידיים) - endDate >= today
        result = events.where((event) {
          return event.endDate.isAfter(todayDate) ||
              event.endDate.isAtSameMomentAs(todayDate);
        }).toList();
        break;
      case 2: // Past (עברו) - endDate < today
        result = events.where((event) {
          return event.endDate.isBefore(todayDate);
        }).toList();
        break;
      default:
        result = events;
    }

    // Apply category filter if any categories are selected
    if (_selectedCategoryIds.isNotEmpty) {
      result = result.where((event) {
        return event.categoryId != null &&
            _selectedCategoryIds.contains(event.categoryId);
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final normalizedQuery = normalizeForSearch(_searchQuery);
      result = result.where((event) {
        final normalizedName = normalizeForSearch(event.name);
        final normalizedLocation = normalizeForSearch(event.location);
        return normalizedName.contains(normalizedQuery) ||
            normalizedLocation.contains(normalizedQuery);
      }).toList();
    }

    // Sort by startDate ascending, then by name ascending
    result.sort((a, b) {
      final dateCompare = a.startDate.compareTo(b.startDate);
      if (dateCompare != 0) return dateCompare;
      return a.name.compareTo(b.name);
    });

    return result;
  }

  /// Get background color for event card based on assignment status.
  /// Deactivated events always render gray, overriding the status color.
  Color? _getEventCardColor(Event event, Map<String, int> assignmentCounts) {
    if (event.isDeactivated) {
      return Colors.grey.shade500;
    }

    final assignmentCount = assignmentCounts[event.id] ?? 0;
    final totalRequired = event.totalPeopleRequired;

    // Determine status based on counts
    final EventAssignmentStatus status;
    if (totalRequired == 0) {
      status = EventAssignmentStatus.noQuotas;
    } else if (assignmentCount == 0) {
      status = EventAssignmentStatus.none;
    } else if (assignmentCount < totalRequired) {
      status = EventAssignmentStatus.partial;
    } else {
      status = EventAssignmentStatus.complete;
    }

    switch (status) {
      case EventAssignmentStatus.none:
        return Colors.red.shade50;
      case EventAssignmentStatus.partial:
        return Colors.orange.shade50;
      case EventAssignmentStatus.complete:
        return Colors.green.shade50;
      case EventAssignmentStatus.noQuotas:
        return null; // Default color
    }
  }

  /// Resolve category name from categoryId using the CategoryBloc state
  /// Uses context.watch for real-time updates when category names change
  String? _getCategoryName(String? categoryId) {
    if (categoryId == null) return null;
    final categoryState = context.watch<CategoryBloc>().state;
    if (categoryState is CategoriesLoaded) {
      for (final category in categoryState.activeCategories) {
        if (category.id == categoryId) return category.name;
      }
      // Also check archived categories in case an event references one
      for (final category in categoryState.archivedCategories) {
        if (category.id == categoryId) return category.name;
      }
    }
    return null;
  }

  /// Whether [event] should have a Google Calendar entry but currently does
  /// not have a healthy one — used to show the "not synced" badge. True only
  /// when the calendar integration is connected, the event is active, in the
  /// future (in scope), and its sync status is anything other than `synced`
  /// (missing state, pending, failed, or removed).
  bool _needsCalendarSync(
    Event event,
    Map<String, CalendarSyncStatus> states,
  ) {
    // Without a connected calendar, every event would look unsynced.
    if (!GoogleCalendarService.instance.isAuthenticated) return false;
    // Deactivated events intentionally have no calendar entry.
    if (event.isDeactivated) return false;
    // Past events are out of the calendar sync scope.
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final endDate =
        DateTime(event.endDate.year, event.endDate.month, event.endDate.day);
    if (endDate.isBefore(todayDate)) return false;

    return states[event.id] != CalendarSyncStatus.synced;
  }

  /// Retry the Google Calendar sync for a single event from the badge.
  void _resyncEventToCalendar(Event event) {
    Logger.action('tap:resyncEventCalendar', {'eventId': event.id});
    context.read<EventBloc>().resyncEventToCalendar(event);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('מסנכרן את האירוע ליומן גוגל...'),
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildEventCard(
    Event event,
    Map<String, int> assignmentCounts,
    Map<String, List<String>> eventBirthdays, {
    Map<String, CalendarSyncStatus> calendarSyncStates =
        const <String, CalendarSyncStatus>{},
  }) {
    // Check if start and end dates are the same
    final isSameDate = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    final cardColor = _getEventCardColor(event, assignmentCounts);
    final categoryName = _getCategoryName(event.categoryId);

    return Card(
      color: cardColor,
      child: InkWell(
        onTap: () {
          Logger.action('tap:eventCard', {'eventId': event.id});
          _showEventFormModal(event);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with avatar and name
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Text(event.name.isNotEmpty ? event.name[0] : '?',
                        style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: event.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                          if (categoryName != null) ...[
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: '($categoryName)',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                          if (event.isDeactivated)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    start: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade700,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'מושבת',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (_needsCalendarSync(event, calendarSyncStates))
                    IconButton(
                      tooltip: 'האירוע לא סונכרן ליומן גוגל — הקש/י לסנכרון',
                      onPressed: () => _resyncEventToCalendar(event),
                      icon: Icon(
                        Icons.event_busy,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  IconButton(
                    tooltip: 'קבצים בגוגל דרייב',
                    onPressed: () => _showDriveFilesDialog(context, event),
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Event details - aligned to visual right with padding
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Line 1: Date(s) with old styling
                    if (isSameDate)
                      _buildFieldItem('תאריך', _formatDate(event.startDate),
                          isDeactivated: event.isDeactivated)
                    else
                      // Multi-day: both dates on same row
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFieldItem(
                              'תאריך התחלה', _formatDate(event.startDate),
                              isDeactivated: event.isDeactivated),
                          const SizedBox(width: 16),
                          _buildFieldItem(
                              'תאריך סיום', _formatDate(event.endDate),
                              isDeactivated: event.isDeactivated),
                        ],
                      ),
                    // Line 2: Location with old styling (only if not empty)
                    if (event.location.isNotEmpty)
                      _buildFieldItem(
                          'מיקום', _formatLocationForDisplay(event.location),
                          isDeactivated: event.isDeactivated),
                    // Line 3: Time fields with old styling and responsive font size
                    if (event.assemblyTime.isNotEmpty ||
                        event.startTime.isNotEmpty ||
                        event.actualShowStartTime.isNotEmpty ||
                        event.endTime.isNotEmpty)
                      _buildFieldItemWithResponsiveFont(
                          'שעות', _formatTimeFields(event),
                          isDeactivated: event.isDeactivated),
                  ],
                ),
              ),
              // Comments (if not empty)
              if (event.comments.isNotEmpty) ...[
                const SizedBox(height: 4),
                _buildFieldItem('הערות', event.comments,
                    isDeactivated: event.isDeactivated),
              ],
              // Birthday indicators (if any team member has birthday during event)
              if (eventBirthdays[event.id] != null &&
                  eventBirthdays[event.id]!.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...eventBirthdays[event.id]!.map((name) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '🎂 ',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF6A1B9A), // Dark purple
                              ),
                            ),
                            TextSpan(
                              text: name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6A1B9A), // Dark purple
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showEventFormModal(Event? event, {bool isDuplication = false}) async {
    Logger.action('open:eventFormModal', {
      'eventId': event?.id,
      'mode': event == null ? 'create' : (isDuplication ? 'duplicate' : 'edit'),
    });
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => EventFormModal(
        event: event,
        filterIndex: FilterPersistence.eventFilterIndex,
        isDuplication: isDuplication,
        onSuccess: () {
          Navigator.of(modalContext).pop();
        },
      ),
    );

    // Check if the modal was closed with a duplication intent
    if (result is Map &&
        result['action'] == 'duplicate' &&
        result['event'] != null) {
      // Open the duplication modal after the original modal is fully closed
      if (mounted) {
        _showEventFormModal(result['event'] as Event, isDuplication: true);
      }
    }
  }

  /// Show a dialog listing only deactivated events. The list reactively updates
  /// as events get deactivated/reactivated. Tapping an event opens the edit
  /// modal (where it can be reactivated).
  void _showDeactivatedEventsDialog() {
    Logger.action('open:deactivatedEventsDialog');
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogHeight = (screenHeight * 0.8).clamp(420.0, 760.0);

    showDialog(
      context: context,
      // Use the same navigator that the event form modal uses
      // (showModalBottomSheet defaults to useRootNavigator: false). This keeps
      // the dialog and any subsequently opened modal in the same Navigator
      // stack, so the modal layers above the dialog and the dialog remains
      // intact when the modal closes.
      useRootNavigator: false,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: SizedBox(
            width: 560,
            height: dialogHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.power_settings_new,
                          color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'אירועים מושבתים',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        tooltip: 'סגור',
                        onPressed: () {
                          Logger.action('tap:close:deactivatedEventsDialog');
                          Navigator.of(dialogContext).pop();
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Expanded(
                    child: BlocBuilder<EventBloc, EventState>(
                      builder: (context, state) {
                        // Resolve a stable EventsLoaded snapshot
                        EventsLoaded? loaded;
                        if (state is EventsLoaded) {
                          loaded = state;
                        } else if (_lastLoadedState != null) {
                          loaded = _lastLoadedState;
                        }

                        if (loaded == null) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        final deactivatedEvents = loaded.events
                            .where((e) => e.isDeactivated)
                            .toList()
                          ..sort((a, b) {
                            final dateCompare =
                                a.startDate.compareTo(b.startDate);
                            if (dateCompare != 0) return dateCompare;
                            return a.name.compareTo(b.name);
                          });

                        if (deactivatedEvents.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.power_settings_new,
                                    size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  'אין אירועים מושבתים',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: deactivatedEvents.length,
                          itemBuilder: (context, index) {
                            return _buildEventCard(
                              deactivatedEvents[index],
                              loaded!.assignmentCounts,
                              loaded.eventBirthdays,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Event event) {
    bool isDeleting = false;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('מחיקת אירוע'),
              content: Text(
                'האם אתה בטוח שברצונך למחוק את ${event.name}?\nפעולה זו תמחק גם את כל השיבוצים.',
              ),
              actions: [
                TextButton(
                  child: const Text('ביטול'),
                  onPressed: isDeleting
                      ? null
                      : () {
                          Logger.action('tap:cancel:deleteEvent',
                              {'eventId': event.id});
                          Navigator.pop(dialogContext);
                        },
                ),
                TextButton(
                  child: isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'מחק',
                          style: TextStyle(color: Colors.red),
                        ),
                  onPressed: isDeleting
                      ? null
                      : () async {
                          Logger.action('tap:deleteEvent', {'eventId': event.id});
                          setDialogState(() {
                            isDeleting = true;
                          });
                          final completion = Completer<CrudActionResult>();
                          this
                              .context
                              .read<EventBloc>()
                              .add(DeleteEvent(event.id, completion: completion));
                          final result = await completion.future;
                          if (!dialogContext.mounted) {
                            return;
                          }
                          if (result.isFailure) {
                            setDialogState(() {
                              isDeleting = false;
                            });
                            return;
                          }
                          Navigator.pop(dialogContext);
                        },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDriveFilesDialog(BuildContext context, Event event) {
    Logger.action('open:driveFilesDialog', {'eventId': event.id});
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogHeight = (screenHeight * 0.72).clamp(420.0, 760.0);
    final filesListHeight = (dialogHeight - 170).clamp(200.0, 580.0);

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SizedBox(
            width: 560,
            height: dialogHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_open, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'קבצים בגוגל דרייב - ${event.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'סגור',
                        onPressed: () {
                          Logger.action('tap:close:driveFilesDialog',
                              {'eventId': event.id});
                          Navigator.of(dialogContext).pop();
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  EventDriveFilesSection(
                    eventId: event.id,
                    driveFolderId: event.driveFolderId,
                    driveFolderLink: event.driveFolderLink,
                    eventName: event.name,
                    showHeader: false,
                    scrollableFilesOnly: true,
                    filesListHeight: filesListHeight,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTimeFields(Event event) {
    final parts = <String>[];

    if (event.assemblyTime.isNotEmpty) {
      parts.add('התייצבות: ${event.assemblyTime}');
    }
    if (event.startTime.isNotEmpty) {
      parts.add('התכנסות: ${event.startTime}');
    }
    if (event.actualShowStartTime.isNotEmpty) {
      parts.add('תחילת מופע: ${event.actualShowStartTime}');
    }
    if (event.endTime.isNotEmpty) {
      parts.add('סיום: ${event.endTime}');
    }

    return parts.join(' | ');
  }

  Widget _buildFieldItem(String label, String value,
      {bool isDeactivated = false}) {
    // On deactivated cards (gray.shade500 background), the default Colors.grey
    // label is invisible. Use a near-black label for contrast there.
    final labelColor = isDeactivated ? Colors.grey.shade900 : Colors.grey;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: labelColor,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  /// Build field item with responsive font size for the value
  /// Uses FittedBox to automatically scale down font size when text would wrap
  Widget _buildFieldItemWithResponsiveFont(String label, String value,
      {bool isDeactivated = false}) {
    final labelColor = isDeactivated ? Colors.grey.shade900 : Colors.grey;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: labelColor,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(EventsEmpty state) {
    return Column(
      children: [
        // Show interactive filter bar if this is a filtered empty state
        if (state.isFiltered)
          InteractiveFilterBar(
            options: const [
              FilterOption(label: 'סה״כ', count: '0'),
              FilterOption(label: 'עתידיים', count: '0'),
              FilterOption(label: 'עברו', count: '0'),
            ],
            selectedIndex: FilterPersistence.eventFilterIndex,
            onFilterChanged: _onFilterChanged,
          ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_outlined,
                    size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(state.message,
                    style:
                        TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                const SizedBox(height: 24),
                // Only show "add first" button if database is truly empty (not filtered)
                if (!state.isFiltered)
                  ElevatedButton.icon(
                    onPressed: () {
                      Logger.action('tap:addFirstEvent');
                      _showEventFormModal(null);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('הוסף אירוע ראשון'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 80, color: Colors.red),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(fontSize: 18, color: Colors.red),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Logger.action('tap:retryLoadEvents');
              context.read<EventBloc>().add(const LoadEvents());
            },
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
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
