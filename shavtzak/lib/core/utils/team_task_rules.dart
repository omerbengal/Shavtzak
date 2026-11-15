import 'package:equatable/equatable.dart';

import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../../domain/entities/team_task.dart';
import 'israel_calendar.dart';

/// Pure rules of the team tasks screen ("משימות"): late, permissions,
/// grouping, sorting, the filter and whether a member gets the tab. `now` is
/// always injected.

/// Late = a deadline before today's Israel date while the task is still open
/// or in progress. The deadline day itself is not late.
bool isTeamTaskLate(TeamTask task, DateTime now) {
  final deadline = task.deadlineDate;
  if (deadline == null || !task.status.isActive) return false;
  return deadline.isBefore(IsraelCalendar.calendarDay(now));
}

/// Admins and members with "ניהול משימות" see and edit every task.
bool canManageTeamTasks(TeamMember member) => member.isAdmin || member.canManageTasks;

bool isTeamTaskOwner(TeamTask task, String memberId) => task.ownerIds.contains(memberId);

const String unknownMemberLabel = 'חבר צוות לא ידוע';

/// The owners' names in [TeamTask.ownerIds] order; an id with no joined member
/// (deleted from the team) reads "חבר צוות לא ידוע".
List<String> teamTaskOwnerNames(TeamTask task) {
  final byId = {for (final member in task.owners) member.id: member.name};
  return [for (final id in task.ownerIds) byId[id] ?? unknownMemberLabel];
}

/// [task] with subtask [subtaskId] ticked or unticked, and the status the
/// backend gives it (`team_tasks.ts` withAutoStatus): cancelled and duplicate
/// never change; every subtask done = done; a done task with an open subtask
/// and an open task with a ticked one = in progress.
TeamTask withSubtaskTicked(TeamTask task, String subtaskId, bool isDone) {
  if (!task.subtasks.any((subtask) => subtask.id == subtaskId)) return task;
  final subtasks = [
    for (final subtask in task.subtasks)
      subtask.id == subtaskId ? subtask.copyWith(isDone: isDone) : subtask,
  ];
  var status = task.status;
  if (status != TeamTaskStatus.cancelled && status != TeamTaskStatus.duplicate) {
    if (subtasks.every((subtask) => subtask.isDone)) {
      status = TeamTaskStatus.done;
    } else if (status == TeamTaskStatus.done ||
        (status == TeamTaskStatus.open && subtasks.any((subtask) => subtask.isDone))) {
      status = TeamTaskStatus.inProgress;
    }
  }
  return task.copyWith(subtasks: subtasks, status: status);
}

/// One group of the list: the tasks of one event, category or topic, or the
/// tasks with no link ("ללא שיוך", [type] null).
class TeamTaskGroup extends Equatable {
  final String key;
  final String label;
  final TaskLinkType? type;
  final List<TeamTask> tasks;

  const TeamTaskGroup({
    required this.key,
    required this.label,
    required this.type,
    required this.tasks,
  });

  @override
  List<Object?> get props => [key, label, type, tasks];
}

const String noLinkLabel = 'ללא שיוך';

/// The group's title for [task]'s link. A link whose target is gone (a
/// deleted event, category or topic) still gets a group of its own.
String teamTaskLinkLabel(TeamTask task) {
  final link = task.link;
  if (link == null) return noLinkLabel;
  switch (link.type) {
    case TaskLinkType.event:
      return task.event?.name ?? 'אירוע שנמחק';
    case TaskLinkType.category:
      return task.category?.name ?? 'קטגוריה שנמחקה';
    case TaskLinkType.topic:
      return task.topic?.name ?? 'נושא שנמחק';
  }
}

/// The order inside a group: still-active tasks first, by deadline (none
/// last), then the title; done, cancelled and duplicate at the bottom.
int compareTeamTasks(TeamTask a, TeamTask b) {
  final activeA = a.status.isActive ? 0 : 1;
  final activeB = b.status.isActive ? 0 : 1;
  if (activeA != activeB) return activeA.compareTo(activeB);
  final byDeadline = _compareDeadlines(a.deadline, b.deadline);
  if (byDeadline != 0) return byDeadline;
  return a.title.compareTo(b.title);
}

int _compareDeadlines(String? a, String? b) {
  if (a == b) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  // yyyy-MM-dd strings compare in date order.
  return a.compareTo(b);
}

/// [tasks] grouped by link. Groups are ordered by their nearest deadline of a
/// still-active task (none last), then by label; "ללא שיוך" is always last.
List<TeamTaskGroup> groupTeamTasks(List<TeamTask> tasks, DateTime now) {
  final byKey = <String, List<TeamTask>>{};
  final labels = <String, String>{};
  final types = <String, TaskLinkType?>{};
  for (final task in tasks) {
    final link = task.link;
    final key = link == null ? 'none' : '${link.type.key}:${link.id}';
    byKey.putIfAbsent(key, () => []).add(task);
    labels[key] = teamTaskLinkLabel(task);
    types[key] = link?.type;
  }

  String? nearest(List<TeamTask> group) {
    String? best;
    for (final task in group) {
      if (!task.status.isActive || task.deadline == null) continue;
      if (best == null || task.deadline!.compareTo(best) < 0) best = task.deadline;
    }
    return best;
  }

  final groups = [
    for (final entry in byKey.entries)
      TeamTaskGroup(
        key: entry.key,
        label: labels[entry.key]!,
        type: types[entry.key],
        tasks: [...entry.value]..sort(compareTeamTasks),
      ),
  ];
  final nearestByKey = {for (final group in groups) group.key: nearest(group.tasks)};
  groups.sort((a, b) {
    final noneA = a.type == null ? 1 : 0;
    final noneB = b.type == null ? 1 : 0;
    if (noneA != noneB) return noneA.compareTo(noneB);
    final byDeadline = _compareDeadlines(nearestByKey[a.key], nearestByKey[b.key]);
    if (byDeadline != 0) return byDeadline;
    return a.label.compareTo(b.label);
  });
  return groups;
}

/// What the list shows: a set of statuses, optionally one owner and one link.
class TeamTaskFilter extends Equatable {
  final Set<TeamTaskStatus> statuses;
  final String? ownerId;
  final TaskLink? link;

  const TeamTaskFilter({required this.statuses, this.ownerId, this.link});

  /// Every status except "לא רלוונטי/בוטל" and "כפילות".
  static const TeamTaskFilter initial = TeamTaskFilter(statuses: {
    TeamTaskStatus.open,
    TeamTaskStatus.inProgress,
    TeamTaskStatus.done,
  });

  bool get isInitial => this == initial;

  TeamTaskFilter copyWith({
    Set<TeamTaskStatus>? statuses,
    String? Function()? ownerId,
    TaskLink? Function()? link,
  }) =>
      TeamTaskFilter(
        statuses: statuses ?? this.statuses,
        ownerId: ownerId != null ? ownerId() : this.ownerId,
        link: link != null ? link() : this.link,
      );

  @override
  List<Object?> get props => [statuses.toList()..sort((a, b) => a.index - b.index), ownerId, link];
}

/// [tasks] that pass [filter]. A category link also matches the tasks linked
/// to an event of that category ([eventCategoryById]: event id → category id).
List<TeamTask> applyTeamTaskFilter(
  List<TeamTask> tasks,
  TeamTaskFilter filter,
  Map<String, String?> eventCategoryById,
) {
  bool linkMatches(TeamTask task) {
    final wanted = filter.link;
    if (wanted == null) return true;
    final link = task.link;
    if (link == null) return false;
    if (link == wanted) return true;
    return wanted.type == TaskLinkType.category &&
        link.type == TaskLinkType.event &&
        (eventCategoryById[link.id] ?? task.event?.categoryId) == wanted.id;
  }

  return [
    for (final task in tasks)
      if (filter.statuses.contains(task.status) &&
          (filter.ownerId == null || task.ownerIds.contains(filter.ownerId)) &&
          linkMatches(task))
        task,
  ];
}

/// Whether [member] gets the "משימות" tab: a manager always; anyone else when
/// one of [myTasks] (the tasks they own) is not cancelled or a duplicate.
bool showTeamTasksTab(TeamMember member, List<TeamTask> myTasks) {
  if (canManageTeamTasks(member)) return true;
  return myTasks.any((task) =>
      task.status != TeamTaskStatus.cancelled && task.status != TeamTaskStatus.duplicate);
}

/// The events a task can be linked to: those that have not ended before
/// today's Israel date, the nearest first (Omer, round 2).
List<Event> linkableEvents(List<Event> events, DateTime now) {
  final today = IsraelCalendar.calendarDay(now);
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  return [
    for (final event in events)
      if (!day(event.endDate).isBefore(today)) event,
  ]..sort((a, b) => a.startDate.compareTo(b.startDate));
}
