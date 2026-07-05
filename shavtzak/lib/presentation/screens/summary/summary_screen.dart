import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/debug/logger.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/utils/event_assignment_status.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/assignment_label.dart';
import '../../bloc/category/category_bloc.dart';
import '../../bloc/category/category_event.dart';
import '../../bloc/category/category_state.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/assignment/assignment_state.dart';
import '../../bloc/checklist/checklist_bloc.dart';
import '../../../data/repositories/assignment_label_repository.dart';
import '../../../data/repositories/event_repository.dart';
import 'widgets/calendar_share/calendar_share_flow_dialog.dart';
import 'widgets/summary_header_cards.dart';
import 'widgets/events_overview_chart.dart';
import 'widgets/staffing_status_chart.dart';
import 'widgets/checklist_compliance_chart.dart';
import 'widgets/event_summary_tile.dart';
import 'widgets/category_summary_card.dart';

/// Summary screen - dashboard for managers
/// Accessible directly via /summary route (not part of main navigation)
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  List<Assignment> _lastKnownAssignments = const [];
  bool _isPreparingCalendarShare = false;

  @override
  void initState() {
    super.initState();
    // Load data when screen initializes
    _loadData();
  }

  void _loadData() {
    final eventBloc = context.read<EventBloc>();
    final assignmentBloc = context.read<AssignmentBloc>();
    final checklistBloc = context.read<ChecklistBloc>();
    final categoryBloc = context.read<CategoryBloc>();

    if (_shouldLoadEvents(eventBloc.state)) {
      eventBloc.add(const LoadEvents());
    }
    if (_shouldLoadAssignments(assignmentBloc.state)) {
      assignmentBloc.add(const LoadAssignments());
    }
    if (_shouldLoadChecklistItems(checklistBloc.state)) {
      checklistBloc.add(LoadChecklistItems());
    }
    if (_shouldLoadCategories(categoryBloc.state)) {
      categoryBloc.add(const LoadCategories());
    }
  }

  bool _shouldLoadEvents(EventState state) {
    if (state is EventLoading) return false;
    if (state is EventsLoaded) return state.searchQuery != null;
    if (state is EventsEmpty) return state.isFiltered;
    return true;
  }

  bool _shouldLoadAssignments(AssignmentState state) {
    if (state is AssignmentLoading) return false;
    if (state is AssignmentsLoaded) return state.filterType != 'all';
    if (state is AssignmentsEmpty) return state.message != 'אין שיבוצים במערכת';
    return true;
  }

  bool _shouldLoadChecklistItems(ChecklistState state) {
    if (state is ChecklistLoading) return false;
    return state is! ChecklistLoaded;
  }

  bool _shouldLoadCategories(CategoryState state) {
    if (state is CategoryLoading) return false;
    return state is! CategoriesLoaded;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מסך מנהלים'),
          centerTitle: true,
          automaticallyImplyLeading: false,
          actions: [
            // Events calendar image export (spec: summary calendar share)
            IconButton(
              icon: _isPreparingCalendarShare
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calendar_month),
              tooltip: 'לוח אירועים',
              onPressed: _isPreparingCalendarShare
                  ? null
                  : () {
                      Logger.action('open:calendarShareFlow');
                      _openCalendarShareFlow();
                    },
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
            // Home button (appears closest to title in RTL)
            BlocBuilder<UserSelectionBloc, UserSelectionState>(
              builder: (context, state) {
                return IconButton(
                  icon: const Icon(Icons.home),
                  tooltip: 'בית',
                  onPressed: () {
                    Logger.action('tap:home', {'isAdmin': state is UserAuthenticated && state.isAdmin});
                    final envPrefix = EnvironmentService.instance.routePrefix;
                    if (state is UserAuthenticated && state.isAdmin) {
                      // Admin goes back to /admin
                      context.go('$envPrefix/admin');
                    } else {
                      // Non-admin with summary access goes back to /choice
                      context.go('$envPrefix/choice');
                    }
                  },
                  iconSize: 24,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints:
                      const BoxConstraints(minWidth: 56, minHeight: 44),
                );
              },
            ),
            // Logout button (appears farthest left in RTL)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'התנתק',
              onPressed: () { Logger.action('open:logoutDialog'); _showLogoutDialog(context); },
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
          ],
        ),
        body: SafeArea(
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return BlocBuilder<CategoryBloc, CategoryState>(
      builder: (context, categoryState) {
        final categories = categoryState is CategoriesLoaded
            ? categoryState.activeCategories
            : <Category>[];
        return BlocBuilder<EventBloc, EventState>(
          builder: (context, eventState) {
            return BlocBuilder<AssignmentBloc, AssignmentState>(
              builder: (context, assignmentState) {
                return BlocBuilder<ChecklistBloc, ChecklistState>(
                  builder: (context, checklistState) {
                    return StreamBuilder<List<AssignmentLabel>>(
                      stream: context
                          .read<AssignmentLabelRepository>()
                          .watchAssignmentLabels(),
                      builder: (context, labelSnapshot) {
                        final isEventBlocking = eventState is EventLoading ||
                            eventState is EventInitial;
                        final isChecklistBlocking =
                            checklistState is ChecklistLoading ||
                                checklistState is ChecklistInitial;
                        final hasAssignmentData =
                            assignmentState is AssignmentsLoaded ||
                                assignmentState is AssignmentSlotsLoaded ||
                                _lastKnownAssignments.isNotEmpty;
                        final isAssignmentBlocking =
                            (assignmentState is AssignmentLoading ||
                                    assignmentState is AssignmentInitial) &&
                                !hasAssignmentData;

                        if (isEventBlocking ||
                            isChecklistBlocking ||
                            isAssignmentBlocking) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        // Deactivated events have no presence in the summary —
                        // exclude them up front so every downstream metric
                        // (counts, staffing %, category breakdown, checklist
                        // compliance) ignores them.
                        final events = eventState is EventsLoaded
                            ? eventState.events
                                .where((e) => !e.isDeactivated)
                                .toList()
                            : <Event>[];
                        List<Assignment> assignments;
                        if (assignmentState is AssignmentsLoaded) {
                          assignments = assignmentState.assignments;
                        } else if (assignmentState is AssignmentSlotsLoaded) {
                          assignments = assignmentState.slots
                              .where((slot) => slot.currentAssignment != null)
                              .map((slot) => slot.currentAssignment!)
                              .toList();
                        } else {
                          assignments = _lastKnownAssignments;
                        }

                        assignments = _applyAssignmentLabels(
                          assignments,
                          labelSnapshot.data ?? const <AssignmentLabel>[],
                        );
                        _lastKnownAssignments = assignments;

                        final checklistItems = checklistState is ChecklistLoaded
                            ? checklistState.items
                            : <ChecklistItem>[];

                        final now = DateTime.now();
                        final today =
                            DateTime(now.year, now.month, now.day);
                        final upcomingEvents = events
                            .where((event) {
                              final eventEndDate = DateTime(
                                event.endDate.year,
                                event.endDate.month,
                                event.endDate.day,
                              );
                              return !eventEndDate.isBefore(today);
                            })
                            .toList()
                          ..sort((a, b) => a.startDate.compareTo(b.startDate));

                        if (upcomingEvents.isEmpty) {
                          return const Center(
                            child: Text(
                              'אין אירועים קרובים',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }

                        final metrics = _computeMetrics(
                          upcomingEvents,
                          assignments,
                          checklistItems,
                        );

                        final summaryCardsData = computeSummaryCardsData(
                          events,
                          assignments,
                          checklistItems,
                        );

                        return _buildContent(metrics, assignments,
                            upcomingEvents, categories, summaryCardsData);
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  List<Assignment> _applyAssignmentLabels(
    List<Assignment> assignments,
    List<AssignmentLabel> labels,
  ) {
    if (assignments.isEmpty || labels.isEmpty) {
      return assignments;
    }

    final labelsById = {
      for (final label in labels) label.id: label,
    };

    return assignments.map((assignment) {
      return assignment.copyWith(
        semanticLabel: () => assignment.semanticLabelId == null
            ? null
            : labelsById[assignment.semanticLabelId!],
      );
    }).toList();
  }

  Widget _buildContent(
      _SummaryMetrics metrics,
      List<Assignment> assignments,
      List<Event> events,
      List<Category> categories,
      SummaryCardsData summaryCardsData) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 600;

    return CustomScrollView(
      slivers: [
        // Section 0: Summary Cards (NEW - before charts)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SummaryHeaderCards(data: summaryCardsData),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 8),
        ),
        // Section 1: Charts
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: isWideScreen ? 220 : 580,
              child: isWideScreen
                  ? _buildHorizontalCharts(metrics)
                  : _buildVerticalCharts(metrics),
            ),
          ),
        ),
        // Section 2: Event Tiles grouped by category
        ..._buildGroupedEventTiles(
            metrics.eventSummaries, assignments, events, categories),
        // Bottom padding
        const SliverToBoxAdapter(
          child: SizedBox(height: 16),
        ),
      ],
    );
  }

  /// Build event tiles grouped by category cards.
  /// Returns a list of sliver widgets.
  List<Widget> _buildGroupedEventTiles(
    List<EventSummaryData> eventSummaries,
    List<Assignment> assignments,
    List<Event> events,
    List<Category> categories,
  ) {
    // Group event summaries by category
    final Map<String?, List<EventSummaryData>> groupedSummaries = {};
    for (final summary in eventSummaries) {
      final categoryId = summary.event.categoryId;
      groupedSummaries.putIfAbsent(categoryId, () => []);
      groupedSummaries[categoryId]!.add(summary);
    }

    final activeCategoryIds = categories.map((c) => c.id).toSet();
    final List<Widget> slivers = [];

    // Categories sorted by sortOrder — only those with events
    final sortedCategories = categories
        .where((c) => groupedSummaries.containsKey(c.id))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    for (final category in sortedCategories) {
      final summaries = groupedSummaries[category.id]!;
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: CategorySummaryCard(
            key: ValueKey('summary_category_${category.id}'),
            categoryId: category.id,
            categoryName: category.name,
            eventSummaries: summaries,
            allAssignments: assignments,
            allEvents: events,
          ),
        ),
      ));
    }

    // Uncategorized events section (always last)
    if (groupedSummaries.containsKey(null) ||
        groupedSummaries.keys
            .any((id) => id != null && !activeCategoryIds.contains(id))) {
      final uncategorizedSummaries = <EventSummaryData>[
        ...groupedSummaries[null] ?? [],
        ...groupedSummaries.entries
            .where((e) => e.key != null && !activeCategoryIds.contains(e.key))
            .expand((e) => e.value),
      ];
      if (uncategorizedSummaries.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: CategorySummaryCard(
              key: const ValueKey('summary_category___uncategorized__'),
              categoryId: '__uncategorized__',
              categoryName: 'אירועים ללא קטגוריה',
              eventSummaries: uncategorizedSummaries,
              allAssignments: assignments,
              allEvents: events,
            ),
          ),
        ));
      }
    }

    return slivers;
  }

  Widget _buildHorizontalCharts(_SummaryMetrics metrics) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: EventsOverviewChart(
            data: metrics.eventsOverviewData,
            isVerticalLayout: false,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: StaffingStatusChart(
            data: metrics.staffingData,
            isVerticalLayout: false,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ChecklistComplianceChart(
            data: metrics.checklistData,
            isVerticalLayout: false,
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalCharts(_SummaryMetrics metrics) {
    return Column(
      children: [
        Expanded(
          child: EventsOverviewChart(
            data: metrics.eventsOverviewData,
            isVerticalLayout: true,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: StaffingStatusChart(
            data: metrics.staffingData,
            isVerticalLayout: true,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ChecklistComplianceChart(
            data: metrics.checklistData,
            isVerticalLayout: true,
          ),
        ),
      ],
    );
  }

  _SummaryMetrics _computeMetrics(
    List<Event> upcomingEvents,
    List<Assignment> allAssignments,
    List<ChecklistItem> allChecklistItems,
  ) {
    // Get event IDs for filtering
    final upcomingEventIds = upcomingEvents.map((e) => e.id).toSet();

    // Filter assignments to upcoming events only
    final upcomingAssignments = allAssignments
        .where((a) => upcomingEventIds.contains(a.eventId))
        .toList();

    // Filter checklist items to upcoming events only
    final upcomingChecklistItems = allChecklistItems
        .where((c) => upcomingEventIds.contains(c.eventId))
        .toList();

    // Create assignment lookup by event
    final assignmentsByEvent = <String, List<Assignment>>{};
    for (final assignment in upcomingAssignments) {
      assignmentsByEvent.putIfAbsent(assignment.eventId, () => []);
      assignmentsByEvent[assignment.eventId]!.add(assignment);
    }

    // Create checklist lookup by event
    final checklistByEvent = <String, List<ChecklistItem>>{};
    for (final item in upcomingChecklistItems) {
      checklistByEvent.putIfAbsent(item.eventId, () => []);
      checklistByEvent[item.eventId]!.add(item);
    }

    // Compute events overview data
    int fullyStaffed = 0;
    int notFullyStaffed = 0;
    int noQuotas = 0;

    // Compute staffing totals
    int totalSlots = 0;
    int filledSlots = 0;

    // Compute checklist totals
    int totalChecklistCompleted = 0;
    int totalChecklistPending = 0;

    // Build event summaries
    final eventSummaries = <EventSummaryData>[];

    for (final event in upcomingEvents) {
      final eventAssignments = assignmentsByEvent[event.id] ?? [];
      final eventChecklistItems = checklistByEvent[event.id] ?? [];
      final status = EventAssignmentStatusHelper.calculateStatus(
        event,
        eventAssignments,
      );

      final eventTotalSlots = event.totalPeopleRequired;
      final eventFilledSlots = eventAssignments.length;

      totalSlots += eventTotalSlots;
      filledSlots += eventFilledSlots;

      // Categorize event status
      switch (status) {
        case EventAssignmentStatus.complete:
          fullyStaffed++;
          break;
        case EventAssignmentStatus.partial:
        case EventAssignmentStatus.none:
          notFullyStaffed++;
          break;
        case EventAssignmentStatus.noQuotas:
          noQuotas++;
          break;
      }

      // Calculate missing roles
      final missingRoles = <String, int>{};
      if (status == EventAssignmentStatus.partial ||
          status == EventAssignmentStatus.none) {
        // Count assignments by role
        final filledByRole = <String, int>{};
        for (final assignment in eventAssignments) {
          filledByRole[assignment.roleType] =
              (filledByRole[assignment.roleType] ?? 0) + 1;
        }

        // Calculate missing for each role
        for (final entry in event.roleRequirements.entries) {
          final required = entry.value;
          final filled = filledByRole[entry.key] ?? 0;
          final missing = required - filled;
          if (missing > 0) {
            // Use role key directly (string) instead of RoleType enum
            missingRoles[entry.key] = missing;
          }
        }
      }

      // Compute checklist stats for this event
      final eventChecklistCompleted =
          eventChecklistItems.where((i) => i.status).length;
      final eventChecklistPending =
          eventChecklistItems.where((i) => !i.status).length;

      totalChecklistCompleted += eventChecklistCompleted;
      totalChecklistPending += eventChecklistPending;

      // Create event summary
      eventSummaries.add(EventSummaryData(
        event: event,
        filledSlots: eventFilledSlots,
        totalSlots: eventTotalSlots,
        missingRoles: missingRoles,
        checklistItems: eventChecklistItems,
      ));
    }

    return _SummaryMetrics(
      eventsOverviewData: EventsOverviewData(
        fullyStaffed: fullyStaffed,
        notFullyStaffed: notFullyStaffed,
        noQuotas: noQuotas,
      ),
      staffingData: StaffingStatusData(
        filledSlots: filledSlots,
        unfilledSlots: totalSlots - filledSlots,
      ),
      checklistData: ChecklistComplianceData(
        completedItems: totalChecklistCompleted,
        pendingItems: totalChecklistPending,
      ),
      eventSummaries: eventSummaries,
    );
  }

  Future<void> _openCalendarShareFlow() async {
    setState(() => _isPreparingCalendarShare = true);
    try {
      List<Event> events;
      final eventState = context.read<EventBloc>().state;
      if (eventState is EventsLoaded) {
        events = eventState.events;
      } else {
        events = await context.read<EventRepository>().getAllEvents();
      }
      if (!mounted) {
        return;
      }
      await startCalendarShareFlow(context, events);
    } catch (e) {
      Logger.action('error:calendarShareFlow', {'error': e.toString()});
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא ניתן להכין לוח אירועים')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparingCalendarShare = false);
      }
    }
  }

  /// Show logout confirmation dialog
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('אישור התנתקות'),
            content: const Text('האם את/ה בטוח/ה שברצונך להתנתק?'),
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:cancel:logoutDialog');
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  Logger.action('tap:logout');
                  Navigator.of(dialogContext).pop();
                  context.read<UserSelectionBloc>().add(const SignOut());
                },
                child: const Text(
                  'התנתקות',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Internal class to hold computed metrics
class _SummaryMetrics {
  final EventsOverviewData eventsOverviewData;
  final StaffingStatusData staffingData;
  final ChecklistComplianceData checklistData;
  final List<EventSummaryData> eventSummaries;

  const _SummaryMetrics({
    required this.eventsOverviewData,
    required this.staffingData,
    required this.checklistData,
    required this.eventSummaries,
  });
}
