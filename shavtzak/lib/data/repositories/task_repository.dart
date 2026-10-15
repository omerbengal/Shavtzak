import 'package:equatable/equatable.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/utils/task_utils.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/stage.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/entities/team_member.dart';
import '../data_sources/database_interface.dart';
import '../../domain/entities/imported_stage.dart';

/// Everything the tasks screens show: the populated tasks, plus the events,
/// stages and members they were joined with.
class TaskBoard extends Equatable {
  final List<TaskItem> tasks;
  final List<Event> events;
  final List<Stage> stages;
  final List<TeamMember> members;

  const TaskBoard({
    required this.tasks,
    this.events = const [],
    this.stages = const [],
    this.members = const [],
  });

  @override
  List<Object?> get props => [tasks, events, stages, members];
}

/// Repository for the tasks screen.
class TaskRepository {
  final DatabaseInterface _database;

  TaskRepository(this._database);

  /// Every task, populated with its [Event], its [Stage] and its assignee
  /// [TeamMember]s, together with the full event, stage and member lists.
  ///
  /// Built from four live streams rather than a tasks stream plus one-shot
  /// reads, so renaming an event or a member, or moving a stage, re-emits the
  /// affected tasks, and the first paint never waits on an awaited `get`.
  Stream<TaskBoard> watchBoard() {
    return Rx.combineLatest4<List<TaskItem>, List<Event>, List<Stage>,
        List<TeamMember>, TaskBoard>(
      _database.watchTasks(),
      _database.watchEvents(),
      _database.watchStages(),
      _database.watchTeamMembers(),
      (tasks, events, stages, members) {
        final eventsById = {for (final event in events) event.id: event};
        final stagesById = {for (final stage in stages) stage.id: stage};
        final membersById = {for (final member in members) member.id: member};
        return TaskBoard(
          tasks: tasks
              .map((task) => task.copyWith(
                    event: eventsById[task.eventId],
                    stage: stagesById[task.stageId],
                    // A member who was deleted leaves a dangling id behind; it
                    // is simply not shown.
                    assignees: task.assigneeIds
                        .map((id) => membersById[id])
                        .whereType<TeamMember>()
                        .toList(),
                  ))
              .toList(),
          events: events,
          stages: stages,
          members: members,
        );
      },
    );
  }

  /// The members a task on [eventId] may be given to: those assigned to that
  /// event who are still active, by name.
  ///
  /// Live on both sides, so assigning or unassigning someone, and renaming or
  /// archiving a member, each re-emit the list.
  Stream<List<TeamMember>> watchEventAssignees(String eventId) {
    return Rx.combineLatest2<List<String>, List<TeamMember>, List<TeamMember>>(
      _database.watchAssignedMemberIds(eventId),
      _database.watchTeamMembers(),
      (assignedIds, members) {
        final assigned = assignedIds.toSet();
        return assignableTaskMembers(
          members.where((member) => assigned.contains(member.id)).toList(),
        );
      },
    );
  }

  /// The populated tasks alone. See [watchBoard].
  Stream<List<TaskItem>> watchTasks() =>
      watchBoard().map((board) => board.tasks);

  Future<void> insertTask(TaskItem task) => _database.insertTask(task);

  Future<void> updateTask(TaskItem task) => _database.updateTask(task);

  Future<void> deleteTask(String taskId) => _database.deleteTask(taskId);

  Future<void> setSubtaskDone(String taskId, String subtaskId, bool isDone) =>
      _database.setSubtaskDone(taskId, subtaskId, isDone);

  Future<void> setTaskComplete(String taskId, bool isComplete) =>
      _database.setTaskComplete(taskId, isComplete);

  Future<void> setTaskAssigneeUpdate(String taskId, String text) =>
      _database.setTaskAssigneeUpdate(taskId, text);

  Future<void> insertStage(Stage stage) => _database.insertStage(stage);

  Future<void> updateStage(Stage stage) => _database.updateStage(stage);

  /// Deletes the stage and every task under it.
  Future<void> deleteStage(String stageId) => _database.deleteStage(stageId);

  Future<void> importStages(String eventId, List<ImportedStage> stages) =>
      _database.importStages(eventId, stages);
}
