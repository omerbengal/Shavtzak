import '../../domain/entities/event.dart';
import '../../domain/entities/stage.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/entities/team_member.dart';
import 'event_filter_utils.dart';
import 'search_utils.dart';

/// Pure helpers behind the tasks screen: which colour a task gets, who may act
/// on it, and how the list is filtered and ordered. `now` is always injected so
/// the rules can be tested at their boundaries.

/// The "דו יומי" category in `utilities/Lists`. Tasks belong to its events
/// only. Matched by id, so renaming the category changes nothing here.
const String duYomiCategoryId = 'dc8b7dd8-f633-4b6a-8169-a94d0561bbd5';

/// How far ahead the "התייצבות בחצי שעה הקרובה" filter looks.
const Duration taskDueSoonWindow = Duration(minutes: 30);

/// Where a task stands relative to its due time. Ordered by urgency, which is
/// also the order the list is shown in.
enum TaskDueStatus { overdue, dueToday, open, completed }

/// Completed wins. Otherwise a task is overdue once its due time has passed,
/// due today while its due time is still ahead on today's date, and open in
/// every other case, including when it has no due date.
TaskDueStatus taskDueStatus(TaskItem task, DateTime now) {
  if (task.isComplete) return TaskDueStatus.completed;
  final dueAt = task.dueAt;
  if (dueAt == null) return TaskDueStatus.open;
  if (dueAt.isBefore(now)) return TaskDueStatus.overdue;
  final isToday = dueAt.year == now.year &&
      dueAt.month == now.month &&
      dueAt.day == now.day;
  return isToday ? TaskDueStatus.dueToday : TaskDueStatus.open;
}

/// Whether [user] may create, edit and delete tasks.
bool canManageTasks(TeamMember user) => user.isAdmin || user.canManageTasks;

/// Whether [user] may tick subtasks, complete [task] and write its update.
bool canUpdateTaskProgress(TaskItem task, TeamMember user) =>
    canManageTasks(user) || task.isAssignedTo(user.id);

/// Filter [tasks]. Every restriction is optional and they combine with AND.
///
/// - [onlyAssigneeId] is the "my tasks" toggle.
/// - [query] matches the title, the description and the event name.
/// - An empty [statuses] or [assigneeIds] means no restriction.
/// - In [statuses], [TaskDueStatus.open] means every unfinished task whose due
///   time has not passed, so it takes in the tasks due later today as well.
/// - [dueWithin] keeps unfinished tasks whose assembly time falls between
///   [now] and that long from it, both ends included. A task without an
///   assembly time never matches, and one already overdue is not "due soon".
List<TaskItem> filterTasks(
  List<TaskItem> tasks, {
  required DateTime now,
  String query = '',
  String? onlyAssigneeId,
  Set<TaskDueStatus> statuses = const {},
  Set<String> assigneeIds = const {},
  Duration? dueWithin,
}) {
  final normalizedQuery = _searchable(query.trim());
  return tasks.where((task) {
    if (dueWithin != null && !_isDueWithin(task, now, dueWithin)) {
      return false;
    }
    if (onlyAssigneeId != null && !task.isAssignedTo(onlyAssigneeId)) {
      return false;
    }
    if (statuses.isNotEmpty &&
        !_passesStatusFilter(taskDueStatus(task, now), statuses)) {
      return false;
    }
    if (assigneeIds.isNotEmpty &&
        !task.assigneeIds.any(assigneeIds.contains)) {
      return false;
    }
    if (normalizedQuery.isEmpty) return true;
    return _searchable(task.title).contains(normalizedQuery) ||
        _searchable(task.description).contains(normalizedQuery) ||
        _searchable(task.event?.name ?? '').contains(normalizedQuery);
  }).toList();
}

/// A sorted copy of [tasks]: earliest due date first, undated ones last.
///
/// Completion does not move a task, so ticking one leaves it where it was.
/// Ties fall back to the title so the order does not jump between rebuilds.
List<TaskItem> sortTasks(List<TaskItem> tasks) {
  final sorted = [...tasks];
  sorted.sort((a, b) {
    final byDate = _compareNullsLast(a.dueAt, b.dueAt);
    if (byDate != 0) return byDate;
    return a.title.compareTo(b.title);
  });
  return sorted;
}

/// The members a task may be assigned to, out of [members]: active and not
/// archived, by name.
List<TeamMember> assignableTaskMembers(List<TeamMember> members) {
  final offered = members
      .where((member) => member.isActive && !member.isArchived)
      .toList();
  offered.sort((a, b) => a.name.compareTo(b.name));
  return offered;
}

final RegExp _hourMinute = RegExp(r'^(\d{2}):(\d{2})$');

/// Whether [time] is a complete `HH:mm` on the 24-hour clock. The forms refuse
/// to save a non-empty time that fails this, rather than quietly dropping it.
bool isValidDueTime(String time) => _parseHourMinute(time) != null;

({int hour, int minute})? _parseHourMinute(String time) {
  final match = _hourMinute.firstMatch(time.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return (hour: hour, minute: minute);
}

String _searchable(String text) => normalizeForSearch(text).toLowerCase();

/// Whether a task in [status] passes a filter for [chosen]. A task due later
/// today is unfinished and not past due, so "open" in the filter covers it
/// too, even though its own status, and its colour, is "due today".
bool _passesStatusFilter(TaskDueStatus status, Set<TaskDueStatus> chosen) =>
    chosen.contains(status) ||
    (status == TaskDueStatus.dueToday && chosen.contains(TaskDueStatus.open));

bool _isDueWithin(TaskItem task, DateTime now, Duration window) {
  final dueAt = task.dueAt;
  if (task.isComplete || dueAt == null || !task.hasAssemblyTime) return false;
  return !dueAt.isBefore(now) && !dueAt.isAfter(now.add(window));
}

/// Ascending by date with nulls after every real date.
int _compareNullsLast(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

// ---- stages and events ----

/// A copy of [stages] in screen order: by day, then start time (stages with no
/// time first on their day), then title.
List<Stage> sortStages(List<Stage> stages) {
  final sorted = [...stages];
  sorted.sort((a, b) {
    final byDay = a.date.compareTo(b.date);
    if (byDay != 0) return byDay;
    final byTime = (a.startTime ?? '').compareTo(b.startTime ?? '');
    if (byTime != 0) return byTime;
    return a.title.compareTo(b.title);
  });
  return sorted;
}

/// One stage on the event screen with the tasks shown under it.
class StageTasks {
  const StageTasks(this.stage, this.tasks);

  final Stage stage;
  final List<TaskItem> tasks;
}

/// The stages to draw, in order, each with its share of [visibleTasks].
///
/// With [showEveryStage] (all tasks, no search, no filter) every stage shows,
/// empty ones included, so a manager can add tasks to them. Otherwise only
/// stages holding at least one visible task show. A task whose stage is not in
/// [stages] is left out.
List<StageTasks> stagesToShow({
  required List<Stage> stages,
  required List<TaskItem> visibleTasks,
  required bool showEveryStage,
}) {
  final tasksByStage = <String, List<TaskItem>>{};
  for (final task in visibleTasks) {
    tasksByStage.putIfAbsent(task.stageId, () => []).add(task);
  }
  return [
    for (final stage in sortStages(stages))
      if (showEveryStage || tasksByStage.containsKey(stage.id))
        StageTasks(stage, tasksByStage[stage.id] ?? const []),
  ];
}

/// Every day of [event], first to last, each at local midnight. A stage's date
/// is picked from these.
List<DateTime> eventDays(Event event) {
  final first = DateTime(
    event.startDate.year,
    event.startDate.month,
    event.startDate.day,
  );
  final last = DateTime(
    event.endDate.year,
    event.endDate.month,
    event.endDate.day,
  );
  final days = <DateTime>[first];
  // Calendar arithmetic on day numbers, so a clock change cannot skip a day.
  while (days.length < 60) {
    final next = DateTime(first.year, first.month, first.day + days.length);
    if (next.isAfter(last)) break;
    days.add(next);
  }
  return days;
}

/// The events the tasks screen lists: active events of the "דו יומי" category,
/// split into those not over yet (nearest first) and past ones (latest first).
({List<Event> upcoming, List<Event> past}) taskEvents(
  List<Event> events, {
  required DateTime now,
}) {
  final split = splitEventsByPast(
    events
        .where((event) =>
            !event.isDeactivated && event.categoryId == duYomiCategoryId)
        .toList(),
    now,
  );
  return (upcoming: split.future, past: split.past);
}

/// The counts on an event's row in the event list.
class TaskEventSummary {
  const TaskEventSummary({
    required this.stageCount,
    required this.openTaskCount,
    required this.myOpenTaskCount,
  });

  final int stageCount;
  final int openTaskCount;
  final int myOpenTaskCount;
}

TaskEventSummary summarizeTaskEvent(
  String eventId, {
  required List<TaskItem> tasks,
  required List<Stage> stages,
  required String memberId,
}) {
  final stageIds = {
    for (final stage in stages)
      if (stage.eventId == eventId) stage.id,
  };
  // Only tasks the event screen can show: a task whose stage is gone (or that
  // predates stages) is not counted.
  final open = tasks
      .where((task) =>
          task.eventId == eventId &&
          stageIds.contains(task.stageId) &&
          !task.isComplete)
      .toList();
  return TaskEventSummary(
    stageCount: stageIds.length,
    openTaskCount: open.length,
    myOpenTaskCount: open.where((task) => task.isAssignedTo(memberId)).length,
  );
}
