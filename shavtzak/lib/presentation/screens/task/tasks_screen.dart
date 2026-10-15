import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/logger.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/utils/task_utils.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/task/task_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/test_environment_indicator.dart';
import 'event_tasks_screen.dart';

/// The דו יומי task screen, at `/tasks`: the list of דו יומי events. Choosing
/// one opens its own screen at `/tasks/<eventId>`.
///
/// Reachable only by link: nothing in the app navigates here. Every signed-in
/// member can read it.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, this.clock});

  /// The current time. Injected by tests; defaults to [DateTime.now].
  final DateTime Function()? clock;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _isPastExpanded = false;

  @override
  void initState() {
    super.initState();
    context.read<TaskBloc>().add(const LoadTasks());
  }

  void _openEvent(Event event) {
    Logger.action('tap:taskEvent');
    context.go('${EnvironmentService.instance.routePrefix}/tasks/${event.id}');
  }

  void _goHome(TeamMember user) {
    Logger.action('tap:tasksHome');
    final prefix = EnvironmentService.instance.routePrefix;
    final String home;
    if (user.isAdmin) {
      home = '/admin';
    } else if (user.canAccessSummaryScreen ||
        user.canAccessShamapExport ||
        user.canAccessConstraintsExamining) {
      home = '/choice';
    } else {
      home = '/user/assignments';
    }
    context.go('$prefix$home');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
        builder: (context, authState) {
          if (authState is! UserAuthenticated) {
            return const Scaffold(
              body: Center(child: Text('גישה לא מורשית - דרוש אימות')),
            );
          }
          final user = authState.user;
          return Scaffold(
            appBar: AppBar(
              title: const Text('משימות דו יומי'),
              leading: IconButton(
                key: const Key('tasks-home'),
                tooltip: 'חזרה לדף הבית',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => _goHome(user),
              ),
            ),
            body: TestEnvironmentIndicator(
              child: BlocBuilder<TaskBloc, TaskState>(
                builder: (context, state) => _buildBody(state, user),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(TaskState state, TeamMember user) {
    if (state is TasksError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(state.message),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('tasks-retry'),
              onPressed: () => context.read<TaskBloc>().add(const LoadTasks()),
              icon: const Icon(Icons.refresh),
              label: const Text('נסה שוב'),
            ),
          ],
        ),
      );
    }
    if (state is! TasksLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = (widget.clock ?? DateTime.now)();
    final events = taskEvents(state.events, now: now);
    Widget row(Event event) => _EventRow(
          event: event,
          summary: summarizeTaskEvent(
            event.id,
            tasks: state.tasks,
            stages: state.stages,
            memberId: user.id,
          ),
          onTap: () => _openEvent(event),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SectionHeader(
          title: 'אירועים קרובים',
          count: events.upcoming.length,
          color: Colors.blue.shade700,
        ),
        if (events.upcoming.isEmpty)
          const _EmptySection('אין אירועי דו יומי קרובים')
        else
          ...events.upcoming.map(row),
        const SizedBox(height: 16),
        _SectionHeader(
          key: const Key('tasks-past-toggle'),
          title: 'אירועים שעברו',
          count: events.past.length,
          color: Colors.grey.shade600,
          isExpanded: _isPastExpanded,
          onToggle: () {
            Logger.action('toggle:tasksPastEvents', {'on': !_isPastExpanded});
            setState(() => _isPastExpanded = !_isPastExpanded);
          },
        ),
        if (_isPastExpanded && events.past.isEmpty)
          const _EmptySection('אין אירועים קודמים'),
        if (_isPastExpanded) ...events.past.map(row),
      ],
    );
  }
}

/// A section title with its count, styled after `/user/assignments`. With
/// [onToggle] it folds open and closed.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.color,
    this.isExpanded,
    this.onToggle,
  });

  final String title;
  final int count;
  final Color color;
  final bool? isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final expanded = isExpanded;
    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (expanded != null) ...[
            Icon(
              expanded ? Icons.expand_less : Icons.chevron_left,
              color: color,
            ),
            const SizedBox(width: 4),
          ],
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
    if (onToggle == null) return header;
    return InkWell(onTap: onToggle, child: header);
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
      ),
    );
  }
}

/// One event in the list: name, dates, place and how much is open in it.
class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.summary,
    required this.onTap,
  });

  final Event event;
  final TaskEventSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = [
      summary.stageCount == 1 ? 'שלב אחד' : '${summary.stageCount} שלבים',
      summary.openTaskCount == 1
          ? 'משימה פתוחה אחת'
          : '${summary.openTaskCount} משימות פתוחות',
      if (summary.myOpenTaskCount > 0) '${summary.myOpenTaskCount} שלך',
    ].join(' · ');
    return Card(
      key: Key('task-event-${event.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        taskEventDates(event),
                        if (event.location.isNotEmpty) event.location,
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      counts,
                      key: Key('task-event-summary-${event.id}'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }
}
