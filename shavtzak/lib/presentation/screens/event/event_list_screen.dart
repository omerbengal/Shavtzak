import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/event_assignment_status.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../../core/services/environment_service.dart';
import '../../../domain/entities/event.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/interactive_filter_bar.dart';
import '../../widgets/map_location_picker.dart';
import 'widgets/event_form_modal.dart';
import 'widgets/role_management_dialog.dart';
import 'dart:async';

// Filter enum for events (0=all, 1=future, 2=past)
enum EventFilter { all, future, past }

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  EventsLoaded? _lastLoadedState;

  @override
  void initState() {
    super.initState();
    // Always load ALL events - filtering happens in UI
    context.read<EventBloc>().add(const LoadEvents());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      context.read<EventBloc>().add(const LoadEvents());
    } else {
      context.read<EventBloc>().add(SearchEvents(query));
    }
  }

  /// Handle filter change
  void _onFilterChanged(int newIndex) {
    setState(() {
      FilterPersistence.eventFilterIndex = newIndex;
    });
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
          title: _showSearch
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'חיפוש אירוע...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.black54),
                  ),
                  style: const TextStyle(color: Colors.black),
                  onChanged: _onSearchChanged,
                )
              : const Text('אירועים'),
          leading: IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  context.read<EventBloc>().add(const LoadEvents());
                }
              });
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'ניהול תפקידים',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const RoleManagementDialog(),
                );
              },
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
            IconButton(
              icon: const Icon(Icons.home),
              tooltip: 'בית',
              onPressed: () {
                final envPrefix = EnvironmentService.instance.routePrefix;
                context.go('$envPrefix/admin');
              },
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'התנתק',
              onPressed: () => _logout(context),
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
          ],
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
          heroTag: 'event_fab',
          onPressed: () => _showEventFormModal(null),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildEventList(EventsLoaded state) {
    // Calculate past events count
    final today = DateTime.now();
    final pastCount = state.events.where((event) {
      return event.endDate.isBefore(DateTime(today.year, today.month, today.day));
    }).length;

    // Filter events based on selected filter
    final filteredEvents = _filterEvents(state.events, FilterPersistence.eventFilterIndex);

    return RefreshIndicator(
      onRefresh: () async {
        context.read<EventBloc>().add(const RefreshEvents());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: Column(
        children: [
          // Interactive filter bar
          InteractiveFilterBar(
            options: [
              FilterOption(label: 'סה״כ', count: state.totalCount.toString()),
              FilterOption(label: 'עתידיים', count: state.upcomingCount.toString()),
              FilterOption(label: 'עברו', count: pastCount.toString()),
            ],
            selectedIndex: FilterPersistence.eventFilterIndex,
            onFilterChanged: _onFilterChanged,
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: filteredEvents.length,
              itemBuilder: (context, index) {
                return _buildEventCard(
                  filteredEvents[index],
                  state.assignmentCounts,
                  state.eventBirthdays,
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

    switch (filterIndex) {
      case 0: // All
        return events;
      case 1: // Future (עתידיים) - endDate >= today
        return events.where((event) {
          return event.endDate.isAfter(todayDate) ||
                 event.endDate.isAtSameMomentAs(todayDate);
        }).toList();
      case 2: // Past (עברו) - endDate < today
        return events.where((event) {
          return event.endDate.isBefore(todayDate);
        }).toList();
      default:
        return events;
    }
  }

  /// Get background color for event card based on assignment status
  Color? _getEventCardColor(Event event, Map<String, int> assignmentCounts) {
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

  Widget _buildEventCard(
    Event event,
    Map<String, int> assignmentCounts,
    Map<String, List<String>> eventBirthdays,
  ) {
    // Check if start and end dates are the same
    final isSameDate = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    final cardColor = _getEventCardColor(event, assignmentCounts);

    return Card(
      color: cardColor,
      child: InkWell(
        onTap: () => _showEventFormModal(event),
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
                    child: Text(event.name.isNotEmpty ? event.name[0] : '?', style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(event.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // All fields in a single Wrap for horizontal flow
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  // Date field(s) - smart logic
                  if (isSameDate)
                    _buildFieldItem('תאריך', _formatDate(event.startDate))
                  else ...[
                    _buildFieldItem('תאריך התחלה', _formatDate(event.startDate)),
                    _buildFieldItem('תאריך סיום', _formatDate(event.endDate)),
                  ],
                  _buildFieldItem('מיקום', _formatLocationForDisplay(event.location)),
                  // Time fields
                  _buildFieldItem('שעת התייצבות', event.assemblyTime.isEmpty ? '-' : event.assemblyTime),
                  _buildFieldItem('שעת התכנסות קהל', event.startTime.isEmpty ? '-' : event.startTime),
                  _buildFieldItem('שעת תחילת המופע', event.actualShowStartTime.isEmpty ? '-' : event.actualShowStartTime),
                  _buildFieldItem('שעת סיום', event.endTime.isEmpty ? '-' : event.endTime),
                ],
              ),
              // Comments (if not empty)
              if (event.comments.isNotEmpty) ...[
                const SizedBox(height: 4),
                _buildFieldItem('הערות', event.comments),
              ],
              // Birthday indicators (if any team member has birthday during event)
              if (eventBirthdays[event.id] != null && eventBirthdays[event.id]!.isNotEmpty) ...[
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

  void _showEventFormModal(Event? event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => EventFormModal(
        event: event,
        filterIndex: FilterPersistence.eventFilterIndex,
        onSuccess: () {
          Navigator.of(modalContext).pop();
        },
      ),
    );
  }

  void _showDeleteConfirmation(Event event) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת אירוע'),
          content: Text(
            'האם אתה בטוח שברצונך למחוק את ${event.name}?\nפעולה זו תמחק גם את כל השיבוצים.',
          ),
          actions: [
            TextButton(
              child: const Text('ביטול'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('מחק', style: TextStyle(color: Colors.red)),
              onPressed: () {
                context.read<EventBloc>().add(DeleteEvent(event.id));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildFieldItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
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
                Icon(Icons.event_outlined, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(state.message, style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                const SizedBox(height: 24),
                // Only show "add first" button if database is truly empty (not filtered)
                if (!state.isFiltered)
                  ElevatedButton.icon(
                    onPressed: () {
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
          Text(message, style: const TextStyle(fontSize: 18, color: Colors.red), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.read<EventBloc>().add(const LoadEvents()),
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
