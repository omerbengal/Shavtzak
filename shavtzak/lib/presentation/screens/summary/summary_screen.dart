import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/role_types.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/utils/event_assignment_status.dart';
import '../../../domain/entities/event.dart';
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

                return _buildContent(metrics);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildContent(_SummaryMetrics metrics) {
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
        // Section 2: Event Tiles
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: EventSummaryTile(data: metrics.eventSummaries[index]),
                );
              },
              childCount: metrics.eventSummaries.length,
            ),
          ),
        ),
        // Bottom padding
        const SliverToBoxAdapter(
          child: SizedBox(height: 16),
        ),
      ],
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
      final missingRoles = <RoleType, int>{};
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
            // Try to parse role key to RoleType enum
            final roleType = RoleType.values.firstWhere(
              (rt) => rt.key == entry.key,
              orElse: () => RoleType.medic, // Fallback
            );
            missingRoles[roleType] = missing;
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
