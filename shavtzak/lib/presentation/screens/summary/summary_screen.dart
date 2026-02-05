import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/utils/event_assignment_status.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/event.dart';
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
import 'widgets/events_overview_chart.dart';
import 'widgets/staffing_status_chart.dart';
import 'widgets/checklist_compliance_chart.dart';
import 'widgets/event_summary_tile.dart';

/// Summary screen - dashboard for managers
/// Accessible directly via /summary route (not part of main navigation)
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final Map<String, bool> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    // Load data when screen initializes
    _loadData();
  }

  void _loadData() {
    context.read<EventBloc>().add(const LoadEvents());
    context.read<AssignmentBloc>().add(const LoadAssignments());
    context.read<ChecklistBloc>().add(LoadChecklistItems());
    context.read<CategoryBloc>().add(const LoadCategories());
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
            // Home button (appears closest to title in RTL)
            BlocBuilder<UserSelectionBloc, UserSelectionState>(
              builder: (context, state) {
                return IconButton(
                  icon: const Icon(Icons.home),
                  tooltip: 'בית',
                  onPressed: () {
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
                );
              },
            ),
            // Logout button (appears farthest left in RTL)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'התנתק',
              onPressed: () => _showLogoutDialog(context),
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
                    // Check if data is still loading
                    if (eventState is EventLoading ||
                        eventState is EventInitial ||
                        assignmentState is AssignmentLoading ||
                        assignmentState is AssignmentInitial ||
                        checklistState is ChecklistLoading ||
                        checklistState is ChecklistInitial) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    // Extract data from states
                    final events = eventState is EventsLoaded
                        ? eventState.events
                        : <Event>[];
                    final assignments = assignmentState is AssignmentsLoaded
                        ? assignmentState.assignments
                        : <Assignment>[];
                    final checklistItems = checklistState is ChecklistLoaded
                        ? checklistState.items
                        : <ChecklistItem>[];

                    // Filter to upcoming events only
                    final upcomingEvents = events
                        .where((e) => e.isUpcoming || e.isActive)
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

                    // Compute metrics
                    final metrics = _computeMetrics(
                      upcomingEvents,
                      assignments,
                      checklistItems,
                    );

                    return _buildContent(metrics, assignments, categories);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildContent(_SummaryMetrics metrics, List<Assignment> assignments, List<Category> categories) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 600;

    return CustomScrollView(
      slivers: [
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
        ..._buildGroupedEventTiles(metrics.eventSummaries, assignments, categories),
        // Bottom padding
        const SliverToBoxAdapter(
          child: SizedBox(height: 16),
        ),
      ],
    );
  }

  /// Build event tiles grouped by category headers.
  /// Returns a list of sliver widgets.
  List<Widget> _buildGroupedEventTiles(
    List<EventSummaryData> eventSummaries,
    List<Assignment> assignments,
    List<Category> categories,
  ) {
    // No categories in system → flat list, no category headers
    if (categories.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: EventSummaryTile(
                    data: eventSummaries[index],
                    allAssignments: assignments,
                  ),
                );
              },
              childCount: eventSummaries.length,
            ),
          ),
        ),
      ];
    }

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
      slivers.add(_buildCategoryHeaderSliver(
        category.id,
        category.name,
        summaries,
      ));
      if (_expandedCategories[category.id] ?? false) {
        slivers.add(_buildEventTilesSliver(summaries, assignments));
      }
    }

    // Uncategorized events section (always last)
    if (groupedSummaries.containsKey(null) ||
        groupedSummaries.keys.any((id) => id != null && !activeCategoryIds.contains(id))) {
      final uncategorizedSummaries = <EventSummaryData>[
        ...groupedSummaries[null] ?? [],
        ...groupedSummaries.entries
            .where((e) => e.key != null && !activeCategoryIds.contains(e.key))
            .expand((e) => e.value),
      ];
      if (uncategorizedSummaries.isNotEmpty) {
        slivers.add(_buildCategoryHeaderSliver(
          '__uncategorized__',
          'אירועים ללא קטגוריה',
          uncategorizedSummaries,
        ));
        if (_expandedCategories['__uncategorized__'] ?? false) {
          slivers.add(_buildEventTilesSliver(uncategorizedSummaries, assignments));
        }
      }
    }

    return slivers;
  }

  /// Build a category header sliver with aggregate status color and statistics.
  Widget _buildCategoryHeaderSliver(String categoryId, String categoryName, List<EventSummaryData> summaries) {
    // Calculate aggregate statistics
    final totalUnfilledSlots = summaries.fold<int>(0, (sum, s) => sum + s.unfilledSlots);
    final totalPendingChecklist = summaries.fold<int>(0, (sum, s) => sum + s.pendingChecklistItems);
    final totalChecklistItems = summaries.fold<int>(0, (sum, s) => sum + s.totalChecklistItems);

    // Determine color: orange if any event has issues, green otherwise
    final hasIssues = summaries.any((s) => !s.isFullyStaffed || s.pendingChecklistItems > 0);
    final headerColor = hasIssues ? Colors.orange.shade50 : Colors.green.shade50;

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.only(top: 16, left: 4, right: 4, bottom: 4),
        child: Material(
          color: headerColor,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => setState(() {
              _expandedCategories[categoryId] = !(_expandedCategories[categoryId] ?? false);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: folder icon, name, event count, expand icon
                  Row(
                    children: [
                      Icon(Icons.folder, size: 20, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          categoryName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        '${summaries.length} ${summaries.length == 1 ? "אירוע" : "אירועים"}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _expandedCategories[categoryId] ?? false
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.grey.shade600,
                      ),
                    ],
                  ),
                  // Bottom row: aggregate statistics (if any issues exist)
                  if (hasIssues) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        // Unfilled roles
                        if (totalUnfilledSlots > 0)
                          _buildAggregateStatChip(
                            icon: Icons.person_off,
                            label: '$totalUnfilledSlots תפקידים חסרים',
                            color: Colors.red,
                          ),
                        // Pending checklist items
                        if (totalPendingChecklist > 0)
                          _buildAggregateStatChip(
                            icon: Icons.pending,
                            label: '$totalPendingChecklist/$totalChecklistItems פריטים ממתינים',
                            color: Colors.orange,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build a small stat chip for aggregate data.
  Widget _buildAggregateStatChip({
    required IconData icon,
    required String label,
    required MaterialColor color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color.shade700),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Build a sliver list of event tiles.
  Widget _buildEventTilesSliver(List<EventSummaryData> summaries, List<Assignment> assignments) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EventSummaryTile(
                data: summaries[index],
                allAssignments: assignments,
              ),
            );
          },
          childCount: summaries.length,
        ),
      ),
    );
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
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
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
