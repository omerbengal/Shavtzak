import 'package:rxdart/rxdart.dart';

import '../../domain/entities/event.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/entities/team_member.dart';
import '../data_sources/database_interface.dart';

/// Repository for the tasks screen.
class TaskRepository {
  final DatabaseInterface _database;

  TaskRepository(this._database);

  /// Every task, populated with its [Event] and assignee [TeamMember]s.
  ///
  /// Built from three live streams rather than a tasks stream plus one-shot
  /// reads, so renaming an event or a member re-emits the affected tasks, and
  /// the first paint never waits on an awaited `get`.
  Stream<List<TaskItem>> watchTasks() {
    return Rx.combineLatest3<List<TaskItem>, List<Event>, List<TeamMember>,
        List<TaskItem>>(
      _database.watchTasks(),
      _database.watchEvents(),
      _database.watchTeamMembers(),
      (tasks, events, members) {
        final eventsById = {for (final event in events) event.id: event};
        final membersById = {for (final member in members) member.id: member};
        return tasks
            .map((task) => task.copyWith(
                  event: eventsById[task.eventId],
                  // A member who was deleted leaves a dangling id behind; it is
                  // simply not shown.
                  assignees: task.assigneeIds
                      .map((id) => membersById[id])
                      .whereType<TeamMember>()
                      .toList(),
                ))
            .toList();
      },
    );
  }

  Future<void> insertTask(TaskItem task) => _database.insertTask(task);

  Future<void> updateTask(TaskItem task) => _database.updateTask(task);

  Future<void> deleteTask(String taskId) => _database.deleteTask(taskId);

  Future<void> setSubtaskDone(String taskId, String subtaskId, bool isDone) =>
      _database.setSubtaskDone(taskId, subtaskId, isDone);

  Future<void> setTaskComplete(String taskId, bool isComplete) =>
      _database.setTaskComplete(taskId, isComplete);

  Future<void> setTaskAssigneeUpdate(String taskId, String text) =>
      _database.setTaskAssigneeUpdate(taskId, text);
}
