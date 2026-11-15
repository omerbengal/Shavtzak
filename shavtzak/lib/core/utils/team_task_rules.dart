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

/// The owners in [TeamTask.ownerIds] order, with whether each is a permanent
/// team member (the app's mark); an id with no joined member reads
/// "חבר צוות לא ידוע", unmarked.
List<({String id, String name, bool permanent})> teamTaskOwnerChips(TeamTask task) {
  final byId = {for (final member in task.owners) member.id: member};
  return [
    for (final id in task.ownerIds)
      (
        id: id,
        name: byId[id]?.name ?? unknownMemberLabel,
        permanent: byId[id]?.isPermanent ?? false,
      ),
  ];
}

/// The owners' names in [TeamTask.ownerIds] order; an id with no joined member
/// (deleted from the team) reads "חבר צוות לא ידוע".
List<String> teamTaskOwnerNames(TeamTask task) {
  final byId = {for (final member in task.owners) member.id: member.name};
  return [for (final id in task.ownerIds) byId[id] ?? unknownMemberLabel];
}

/// The task's owners as the backend derives them (`deriveOwnerIds`): its own
/// [TeamTask.assigneeIds] without subtasks, else every subtask owner, once.
List<String> teamTaskOwnerIds(TeamTask task) {
  if (task.subtasks.isEmpty) return task.assigneeIds.toSet().toList();
  return {for (final subtask in task.subtasks) ...subtask.assigneeIds}.toList();
}

/// A parent's status, computed from its subtasks as the backend does
/// (`team_tasks.ts` deriveParentStatus; Omer, round 4: never set by hand).
/// Cancelled and duplicate subtasks do not count; of the rest: every one open
/// = open, every one done = done, anything else = in progress. Every subtask
/// cancelled or a duplicate = cancelled.
TeamTaskStatus teamTaskParentStatus(List<TeamSubtask> subtasks) {
  final counted = [
    for (final subtask in subtasks)
      if (subtask.status != TeamTaskStatus.cancelled && subtask.status != TeamTaskStatus.duplicate)
        subtask.status,
  ];
  if (counted.isEmpty) return TeamTaskStatus.cancelled;
  if (counted.every((status) => status == TeamTaskStatus.open)) return TeamTaskStatus.open;
  if (counted.every((status) => status == TeamTaskStatus.done)) return TeamTaskStatus.done;
  return TeamTaskStatus.inProgress;
}

/// [task] with the status its subtasks give it; a task without subtasks
/// keeps its own.
TeamTask withParentStatus(TeamTask task) {
  if (task.subtasks.isEmpty) return task;
  final status = teamTaskParentStatus(task.subtasks);
  if (status == task.status && task.duplicateOfId == null) return task;
  return task.copyWith(status: status, duplicateOfId: () => null);
}

/// [task] with subtask [subtaskId] set to [status], and the parent's status
/// that follows ([teamTaskParentStatus]).
TeamTask withSubtaskStatus(
  TeamTask task,
  String subtaskId,
  TeamTaskStatus status, {
  String? duplicateOfId,
}) {
  if (!task.subtasks.any((subtask) => subtask.id == subtaskId)) return task;
  final subtasks = [
    for (final subtask in task.subtasks)
      subtask.id == subtaskId
          ? subtask.copyWith(
              status: status,
              duplicateOfId: () => status == TeamTaskStatus.duplicate ? duplicateOfId : null,
            )
          : subtask,
  ];
  return withParentStatus(task.copyWith(subtasks: subtasks));
}

/// The quick tick in the parent's list: done, or back to open.
TeamTask withSubtaskTicked(TeamTask task, String subtaskId, bool isDone) =>
    withSubtaskStatus(task, subtaskId, isDone ? TeamTaskStatus.done : TeamTaskStatus.open);

/// What the "המשימות שלי" tab lists for [viewerId] (Omer, round 2): every task
/// they own that has no subtasks, and every subtask they own as its own row
/// ([TeamTask.subtaskView], the parent's title shown above it).
List<TeamTask> myTeamTaskRows(List<TeamTask> tasks, String viewerId) => [
      for (final task in tasks)
        if (task.subtasks.isEmpty) ...[
          if (task.ownerIds.contains(viewerId)) task,
        ] else
          for (final subtask in task.subtasks)
            if (subtask.assigneeIds.contains(viewerId)) TeamTask.subtaskView(task, subtask),
    ];

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

/// What the list shows: a set of statuses, optionally some owners (any of
/// them, round 7: several like the statuses), one link, only the late tasks
/// ("באיחור", round 7) and a search text.
class TeamTaskFilter extends Equatable {
  final Set<TeamTaskStatus> statuses;

  /// The owners shown; empty = everyone.
  final Set<String> ownerIds;
  final TaskLink? link;

  /// Only the tasks that are late ([isTeamTaskLate]); a parent counts when
  /// it or one of its subtasks is.
  final bool lateOnly;

  /// Words looked up in a task's title, description and subtasks' titles.
  final String query;

  const TeamTaskFilter({
    required this.statuses,
    this.ownerIds = const {},
    this.link,
    this.lateOnly = false,
    this.query = '',
  });

  /// Every status except "לא רלוונטי/בוטל" and "כפילות".
  static const TeamTaskFilter initial = TeamTaskFilter(statuses: {
    TeamTaskStatus.open,
    TeamTaskStatus.inProgress,
    TeamTaskStatus.done,
  });

  bool get isInitial => this == initial;

  /// Whether the statuses differ from the initial ones (the status chip's
  /// colour; the owner and link have their own chips).
  bool get statusesChanged =>
      statuses.length != initial.statuses.length || !statuses.containsAll(initial.statuses);

  /// Whether any of the filters (status, owner, link, late) is set.
  bool get anyFilterSet => statusesChanged || ownerIds.isNotEmpty || link != null || lateOnly;

  /// [query] trimmed and lower-cased; empty = no search.
  String get searchText => query.trim().toLowerCase();

  TeamTaskFilter copyWith({
    Set<TeamTaskStatus>? statuses,
    Set<String>? ownerIds,
    TaskLink? Function()? link,
    bool? lateOnly,
    String? query,
  }) =>
      TeamTaskFilter(
        statuses: statuses ?? this.statuses,
        ownerIds: ownerIds ?? this.ownerIds,
        link: link != null ? link() : this.link,
        lateOnly: lateOnly ?? this.lateOnly,
        query: query ?? this.query,
      );

  @override
  List<Object?> get props => [
        statuses.toList()..sort((a, b) => a.index - b.index),
        ownerIds.toList()..sort(),
        link,
        lateOnly,
        query,
      ];
}

/// Whether [task] or one of its subtasks still to be done is late: the
/// "באיחור" filter (round 7).
bool isTeamTaskOrSubtaskLate(TeamTask task, DateTime now) =>
    isTeamTaskLate(task, now) ||
    task.subtasks.any((subtask) => isTeamTaskLate(TeamTask.subtaskView(task, subtask), now));

/// [tasks] that pass [filter]. A category link also matches the tasks linked
/// to an event of that category ([eventCategoryById]: event id → category id).
/// [now] decides "באיחור" (default: the clock).
List<TeamTask> applyTeamTaskFilter(
  List<TeamTask> tasks,
  TeamTaskFilter filter,
  Map<String, String?> eventCategoryById, {
  DateTime? now,
}) {
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

  final today = now ?? DateTime.now();
  final search = filter.searchText;
  return [
    for (final task in tasks)
      if (filter.statuses.contains(task.status) &&
          (filter.ownerIds.isEmpty || task.ownerIds.any(filter.ownerIds.contains)) &&
          linkMatches(task) &&
          (!filter.lateOnly || isTeamTaskOrSubtaskLate(task, today)) &&
          (search.isEmpty ||
              _textMatches(task.title, task.description, search) ||
              task.subtasks.any((s) => _textMatches(s.title, s.description, search))))
        task,
  ];
}

bool _textMatches(String title, String description, String search) =>
    title.toLowerCase().contains(search) || description.toLowerCase().contains(search);

/// The subtasks of [task] shown nested under it in "כל המשימות": those that
/// pass the status and owner filters and, while searching, match the search
/// themselves unless the task itself matches. With "באיחור", only the late
/// subtasks unless the task itself is late.
List<TeamSubtask> visibleSubtasks(TeamTask task, TeamTaskFilter filter, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final search = filter.searchText;
  final parentMatches = search.isEmpty || _textMatches(task.title, task.description, search);
  final parentLate = !filter.lateOnly || isTeamTaskLate(task, today);
  return [
    for (final subtask in task.subtasks)
      if (filter.statuses.contains(subtask.status) &&
          (filter.ownerIds.isEmpty || subtask.assigneeIds.any(filter.ownerIds.contains)) &&
          (parentLate || isTeamTaskLate(TeamTask.subtaskView(task, subtask), today)) &&
          (parentMatches || _textMatches(subtask.title, subtask.description, search)))
        subtask,
  ];
}

/// Whether [member] gets the "משימות" tab: a manager always; anyone else when
/// one of [myTasks] (the tasks they own) is not cancelled or a duplicate.
bool showTeamTasksTab(TeamMember member, List<TeamTask> myTasks) {
  if (canManageTeamTasks(member)) return true;
  return myTasks.any(
      (task) => task.status != TeamTaskStatus.cancelled && task.status != TeamTaskStatus.duplicate);
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
