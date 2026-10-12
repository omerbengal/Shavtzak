import '../../domain/entities/event.dart';
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

/// How far ahead the "due in the next half hour" filter looks.
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
/// - An empty [statuses], [eventIds] or [assigneeIds] means no restriction.
/// - In [statuses], [TaskDueStatus.open] means every unfinished task whose due
///   time has not passed, so it takes in the tasks due later today as well.
/// - [dueWithin] keeps unfinished tasks due between [now] and that long from
///   it, both ends included. A task that is already overdue is not "due soon".
List<TaskItem> filterTasks(
  List<TaskItem> tasks, {
  required DateTime now,
  String query = '',
  String? onlyAssigneeId,
  Set<TaskDueStatus> statuses = const {},
  Set<String> eventIds = const {},
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
    if (eventIds.isNotEmpty && !eventIds.contains(task.eventId)) {
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

/// A sorted copy of [tasks]: overdue, due today, open, then completed.
///
/// Unfinished tasks run earliest due date first with undated ones last;
/// completed tasks run most recently completed first. Ties fall back to the
/// title so the order does not jump between rebuilds.
List<TaskItem> sortTasks(List<TaskItem> tasks, DateTime now) {
  final sorted = [...tasks];
  sorted.sort((a, b) {
    final statusA = taskDueStatus(a, now);
    final statusB = taskDueStatus(b, now);
    if (statusA != statusB) return statusA.index.compareTo(statusB.index);

    final byDate = statusA == TaskDueStatus.completed
        ? _compareNullsLast(b.completedAt, a.completedAt)
        : _compareNullsLast(a.dueAt, b.dueAt);
    if (byDate != 0) return byDate;
    return a.title.compareTo(b.title);
  });
  return sorted;
}

/// The events a task may be attached to: דו יומי events that have not finished
/// yet and are not on hold, earliest first.
///
/// [current] is the event of the task being edited. It stays pickable even
/// after it has passed or when it is not a דו יומי event, otherwise editing an
/// old task would force a new event.
List<Event> pickableTaskEvents(
  List<Event> events, {
  required DateTime now,
  Event? current,
}) {
  final upcoming = splitEventsByPast(
    events
        .where((event) =>
            !event.isDeactivated && event.categoryId == duYomiCategoryId)
        .toList(),
    now,
  ).future;
  if (current == null || upcoming.any((event) => event.id == current.id)) {
    return upcoming;
  }
  return [current, ...upcoming];
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

/// Combine the form's due date and its `HH:mm` time text into one instant.
///
/// No date means no due date. A date with a missing or unusable time is due at
/// the end of that day, so "by the 20th" does not turn red on the 20th at
/// midnight.
DateTime? composeDueAt(DateTime? date, String time) {
  if (date == null) return null;
  final parsed = _parseHourMinute(time);
  return DateTime(
    date.year,
    date.month,
    date.day,
    parsed?.hour ?? 23,
    parsed?.minute ?? 59,
  );
}

/// Whether [time] is a complete `HH:mm` on the 24-hour clock. The task form
/// refuses to save a non-empty due time that fails this, rather than quietly
/// turning it into the end of the day.
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
  if (task.isComplete || dueAt == null) return false;
  return !dueAt.isBefore(now) && !dueAt.isAfter(now.add(window));
}

/// Ascending by date with nulls after every real date. Swap the arguments for
/// descending; nulls then sort first, which is fine for completed tasks since
/// a completed task without a completion time is not expected.
int _compareNullsLast(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
