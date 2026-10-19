import 'package:equatable/equatable.dart';

import '../../domain/entities/event.dart';
import '../../domain/entities/stage.dart';
import '../../domain/entities/task_item.dart';
import 'task_utils.dart';

/// How much of a stage or an event is done, late or due soon; the lists the
/// filters and the assignee check open; and the rows an open list keeps.
/// `now` is always injected so the rules can be tested at their boundaries.

/// One event's part of the board: its stages and the tasks the screens can
/// show, those whose stage exists.
class EventTaskBoard extends Equatable {
  const EventTaskBoard({
    required this.event,
    required this.stages,
    required this.tasks,
  });

  final Event event;

  /// This event's stages, in screen order.
  final List<Stage> stages;

  /// This event's tasks whose stage exists, earliest due first.
  final List<TaskItem> tasks;

  /// [stageId]'s tasks, earliest due first.
  List<TaskItem> tasksOf(String stageId) =>
      tasks.where((task) => task.stageId == stageId).toList();

  Stage? stageById(String id) {
    for (final stage in stages) {
      if (stage.id == id) return stage;
    }
    return null;
  }

  TaskItem? taskById(String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  @override
  List<Object?> get props => [event, stages, tasks];
}

/// [event]'s board out of every stage and task.
EventTaskBoard eventTaskBoard(
  Event event, {
  required List<Stage> stages,
  required List<TaskItem> tasks,
}) {
  final eventStages = sortStages(
    stages.where((stage) => stage.eventId == event.id).toList(),
  );
  final stageIds = {for (final stage in eventStages) stage.id};
  return EventTaskBoard(
    event: event,
    stages: eventStages,
    tasks: sortTasks(
      tasks
          .where((task) =>
              task.eventId == event.id && stageIds.contains(task.stageId))
          .toList(),
    ),
  );
}

/// How a group of tasks stands. [late] and [dueSoon] count unfinished tasks
/// only, so they never overlap [done] or each other.
class TaskProgress extends Equatable {
  const TaskProgress({
    this.total = 0,
    this.done = 0,
    this.late = 0,
    this.dueSoon = 0,
  });

  final int total;
  final int done;
  final int late;
  final int dueSoon;

  /// Not done yet.
  int get missing => total - done;

  /// Missing, but neither late nor due in the next half hour.
  int get rest => missing - late - dueSoon;

  @override
  List<Object?> get props => [total, done, late, dueSoon];
}

TaskProgress taskProgress(Iterable<TaskItem> tasks, DateTime now) {
  var total = 0;
  var done = 0;
  var late = 0;
  var dueSoon = 0;
  for (final task in tasks) {
    total++;
    if (task.isComplete) {
      done++;
    } else if (taskDueStatus(task, now) == TaskDueStatus.overdue) {
      late++;
    } else if (isDueSoon(task, now)) {
      dueSoon++;
    }
  }
  return TaskProgress(total: total, done: done, late: late, dueSoon: dueSoon);
}

/// The colour a stage's count takes: the worst case among its tasks.
enum CountTone { none, done, late, soon, open }

CountTone countTone(TaskProgress progress) {
  if (progress.total == 0) return CountTone.none;
  if (progress.missing == 0) return CountTone.done;
  if (progress.late > 0) return CountTone.late;
  if (progress.dueSoon > 0) return CountTone.soon;
  return CountTone.open;
}

/// "1 חסרה", "3 חסרות".
String missingLabel(int missing) =>
    missing == 1 ? '1 חסרה' : '$missing חסרות';

/// [one] for exactly one, otherwise the number and [many]: "משימה אחת",
/// "4 משימות".
String hebrewCount(int n, {required String one, required String many}) =>
    n == 1 ? one : '$n $many';

/// The unfinished tasks whose due time has passed, longest overdue first.
List<TaskItem> lateTasks(Iterable<TaskItem> tasks, DateTime now) => sortTasks(
      filterTasks(
        tasks.toList(),
        now: now,
        statuses: const {TaskDueStatus.overdue},
      ),
    );

/// The unfinished tasks reporting in the next half hour, soonest first.
List<TaskItem> dueSoonTasks(Iterable<TaskItem> tasks, DateTime now) =>
    sortTasks(
      filterTasks(tasks.toList(), now: now, dueWithin: taskDueSoonWindow),
    );

/// [task]'s assignees who are no longer assigned to its event, in the
/// task's order. A member who was deleted counts as removed too.
List<String> removedAssigneeIds(TaskItem task, Set<String> assignedIds) => [
      for (final id in task.assigneeIds)
        if (!assignedIds.contains(id)) id,
    ];

/// The tasks with at least one assignee no longer on the event.
List<TaskItem> tasksWithRemovedAssignees(
  Iterable<TaskItem> tasks,
  Set<String> assignedIds,
) =>
    [
      for (final task in tasks)
        if (removedAssigneeIds(task, assignedIds).isNotEmpty) task,
    ];

/// The rows an open list shows: everything in [matching], plus every row it
/// showed before ([heldIds]) that still exists in [all], earliest due first.
/// A row that stops matching (ticked, say) stays where it was.
List<TaskItem> heldRows({
  required List<TaskItem> matching,
  required Set<String> heldIds,
  required List<TaskItem> all,
}) {
  final matchingIds = {for (final task in matching) task.id};
  return sortTasks([
    ...matching,
    for (final task in all)
      if (heldIds.contains(task.id) && !matchingIds.contains(task.id)) task,
  ]);
}
