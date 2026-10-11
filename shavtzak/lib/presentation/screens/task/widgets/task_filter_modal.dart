import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/team_member.dart';

/// What the tasks screen's filter button has selected. An empty group means
/// "no restriction" for that group.
class TaskFilterSelection extends Equatable {
  final Set<TaskDueStatus> statuses;
  final Set<String> eventIds;
  final Set<String> assigneeIds;

  const TaskFilterSelection({
    this.statuses = const {},
    this.eventIds = const {},
    this.assigneeIds = const {},
  });

  /// How many of the three groups restrict the list; shown on the badge.
  int get activeCount =>
      (statuses.isEmpty ? 0 : 1) +
      (eventIds.isEmpty ? 0 : 1) +
      (assigneeIds.isEmpty ? 0 : 1);

  bool get isEmpty => activeCount == 0;

  @override
  List<Object?> get props => [statuses, eventIds, assigneeIds];
}

const Map<TaskDueStatus, String> _statusLabels = {
  TaskDueStatus.overdue: 'באיחור',
  TaskDueStatus.dueToday: 'להיום',
  TaskDueStatus.open: 'פתוחה',
  TaskDueStatus.completed: 'הושלמה',
};

/// Pick which tasks to show, by status, event and assignee.
///
/// Returns the new selection, or null when cancelled. [events] and [members]
/// are the ones worth offering: those that actually have tasks.
Future<TaskFilterSelection?> showTaskFilterModal(
  BuildContext context, {
  required TaskFilterSelection current,
  required List<Event> events,
  required List<TeamMember> members,
}) {
  return showDialog<TaskFilterSelection>(
    context: context,
    builder: (context) => _TaskFilterModal(
      current: current,
      events: events,
      members: members,
    ),
  );
}

class _TaskFilterModal extends StatefulWidget {
  const _TaskFilterModal({
    required this.current,
    required this.events,
    required this.members,
  });

  final TaskFilterSelection current;
  final List<Event> events;
  final List<TeamMember> members;

  @override
  State<_TaskFilterModal> createState() => _TaskFilterModalState();
}

class _TaskFilterModalState extends State<_TaskFilterModal> {
  late final Set<TaskDueStatus> _statuses = {...widget.current.statuses};
  late final Set<String> _eventIds = {...widget.current.eventIds};
  late final Set<String> _assigneeIds = {...widget.current.assigneeIds};

  void _toggle<T>(Set<T> selection, T value, bool selected) {
    setState(() {
      if (selected) {
        selection.add(value);
      } else {
        selection.remove(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text('סינון משימות', style: theme.textTheme.titleLarge),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SectionHeader('סטטוס'),
                      for (final status in TaskDueStatus.values)
                        CheckboxListTile(
                          key: Key('filter-status-${status.name}'),
                          dense: true,
                          title: Text(_statusLabels[status]!),
                          value: _statuses.contains(status),
                          onChanged: (value) =>
                              _toggle(_statuses, status, value ?? false),
                        ),
                      if (widget.events.isNotEmpty) ...[
                        const _SectionHeader('אירוע'),
                        for (final event in widget.events)
                          CheckboxListTile(
                            key: Key('filter-event-${event.id}'),
                            dense: true,
                            title: Text(event.name),
                            value: _eventIds.contains(event.id),
                            onChanged: (value) =>
                                _toggle(_eventIds, event.id, value ?? false),
                          ),
                      ],
                      if (widget.members.isNotEmpty) ...[
                        const _SectionHeader('אחראי'),
                        for (final member in widget.members)
                          CheckboxListTile(
                            key: Key('filter-assignee-${member.id}'),
                            dense: true,
                            title: Text(member.name),
                            value: _assigneeIds.contains(member.id),
                            onChanged: (value) => _toggle(
                              _assigneeIds,
                              member.id,
                              value ?? false,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    TextButton(
                      key: const Key('filter-clear'),
                      onPressed: () => Navigator.of(context)
                          .pop(const TaskFilterSelection()),
                      child: const Text('ניקוי'),
                    ),
                    const Spacer(),
                    TextButton(
                      key: const Key('filter-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('ביטול'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('filter-apply'),
                      onPressed: () => Navigator.of(context).pop(
                        TaskFilterSelection(
                          statuses: _statuses,
                          eventIds: _eventIds,
                          assigneeIds: _assigneeIds,
                        ),
                      ),
                      child: const Text('החל'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
