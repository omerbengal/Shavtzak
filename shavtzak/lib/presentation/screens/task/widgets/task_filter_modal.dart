import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/team_member.dart';

/// What the tasks screen's filter button has selected. An empty group means
/// "no restriction" for that group.
class TaskFilterSelection extends Equatable {
  /// Only unfinished tasks due within [taskDueSoonWindow] from now.
  final bool dueSoon;
  final Set<TaskDueStatus> statuses;
  final Set<String> eventIds;
  final Set<String> assigneeIds;

  const TaskFilterSelection({
    this.dueSoon = false,
    this.statuses = const {},
    this.eventIds = const {},
    this.assigneeIds = const {},
  });

  /// How many of the restrictions are in use; shown on the badge.
  int get activeCount =>
      (dueSoon ? 1 : 0) +
      (statuses.isEmpty ? 0 : 1) +
      (eventIds.isEmpty ? 0 : 1) +
      (assigneeIds.isEmpty ? 0 : 1);

  bool get isEmpty => activeCount == 0;

  @override
  List<Object?> get props => [dueSoon, statuses, eventIds, assigneeIds];
}

final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

const Map<TaskDueStatus, String> _statusLabels = {
  TaskDueStatus.overdue: 'באיחור',
  TaskDueStatus.dueToday: 'להיום',
  TaskDueStatus.open: 'פתוחה',
  TaskDueStatus.completed: 'הושלמה',
};

/// Pick which tasks to show: those due soon, or by status, event and assignee.
///
/// A bottom sheet like the other screens' filters: every tick is reported
/// through [onChanged] at once, so the list behind it narrows as the member
/// goes, and there is nothing to apply. [events] and [members] are the ones
/// worth offering: those that actually have tasks.
Future<void> showTaskFilterModal(
  BuildContext context, {
  required TaskFilterSelection current,
  required List<Event> events,
  required List<TeamMember> members,
  required ValueChanged<TaskFilterSelection> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TaskFilterModal(
      current: current,
      events: events,
      members: members,
      onChanged: onChanged,
    ),
  );
}

class _TaskFilterModal extends StatefulWidget {
  const _TaskFilterModal({
    required this.current,
    required this.events,
    required this.members,
    required this.onChanged,
  });

  final TaskFilterSelection current;
  final List<Event> events;
  final List<TeamMember> members;
  final ValueChanged<TaskFilterSelection> onChanged;

  @override
  State<_TaskFilterModal> createState() => _TaskFilterModalState();
}

class _TaskFilterModalState extends State<_TaskFilterModal> {
  late bool _dueSoon = widget.current.dueSoon;
  late final Set<TaskDueStatus> _statuses = {...widget.current.statuses};
  late final Set<String> _eventIds = {...widget.current.eventIds};
  late final Set<String> _assigneeIds = {...widget.current.assigneeIds};

  /// Report the selection as it now stands. Copies the sets: the caller keeps
  /// what it is given, and these go on changing.
  void _report() {
    widget.onChanged(TaskFilterSelection(
      dueSoon: _dueSoon,
      statuses: {..._statuses},
      eventIds: {..._eventIds},
      assigneeIds: {..._assigneeIds},
    ));
  }

  void _toggle<T>(Set<T> selection, T value, bool selected) {
    setState(() {
      if (selected) {
        selection.add(value);
      } else {
        selection.remove(value);
      }
    });
    _report();
  }

  void _clear() {
    Logger.action('tap:clearTaskFilters');
    setState(() {
      _dueSoon = false;
      _statuses.clear();
      _eventIds.clear();
      _assigneeIds.clear();
    });
    _report();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        // Gives the tiles something to draw their ink on, above the sheet's
        // background colour.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Icon(Icons.filter_list, color: Colors.blue),
                    SizedBox(width: 12),
                    Text(
                      'סינון משימות',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        key: const Key('filter-due-soon'),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'משימות לחצי שעה הקרובה',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        value: _dueSoon,
                        onChanged: (value) {
                          setState(() => _dueSoon = value ?? false);
                          _report();
                        },
                      ),
                      const Divider(height: 1),
                      const _SectionHeader('סטטוס'),
                      for (final status in TaskDueStatus.values)
                        CheckboxListTile(
                          key: Key('filter-status-${status.name}'),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
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
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(event.name),
                            // דו יומי events tend to share a name; the date is
                            // what tells them apart.
                            subtitle: Text(_dateFormat.format(event.startDate)),
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
                            controlAffinity: ListTileControlAffinity.leading,
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
              // Footer with Close and Clear buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      key: const Key('filter-clear'),
                      onPressed: _clear,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('נקה'),
                    ),
                    ElevatedButton(
                      key: const Key('filter-close'),
                      onPressed: () {
                        Logger.action('tap:close:taskFilterModal');
                        Navigator.pop(context);
                      },
                      child: const Text('סגור'),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
