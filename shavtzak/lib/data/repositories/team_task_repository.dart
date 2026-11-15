import 'package:equatable/equatable.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/utils/team_task_rules.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/task_topic.dart';
import '../../domain/entities/team_member.dart';
import '../../domain/entities/team_task.dart';
import '../data_sources/database_interface.dart';

/// Everything the team tasks screen shows: the tasks the viewer may see,
/// populated, plus the lists they were joined with (also the pickers' lists).
class TeamTaskBoard extends Equatable {
  final List<TeamTask> tasks;
  final List<Event> events;
  final List<Category> categories;
  final List<TaskTopic> topics;
  final List<TeamMember> members;

  const TeamTaskBoard({
    required this.tasks,
    this.events = const [],
    this.categories = const [],
    this.topics = const [],
    this.members = const [],
  });

  @override
  List<Object?> get props => [tasks, events, categories, topics, members];
}

/// Repository for the team tasks screen.
class TeamTaskRepository {
  final DatabaseInterface _database;

  TeamTaskRepository(this._database);

  /// The tasks [viewer] may see, live: every task for a manager, only the
  /// tasks they own otherwise (the Firestore rule refuses a non-manager the
  /// whole collection, so this must be the `ownerIds` query).
  Stream<List<TeamTask>> watchTasksFor(TeamMember viewer) => canManageTeamTasks(viewer)
      ? _database.watchAllTeamTasks()
      : _database.watchOwnedTeamTasks(viewer.id);

  /// [watchTasksFor], joined with live events, categories, topics and
  /// members, so renaming any of them re-emits the affected tasks.
  Stream<TeamTaskBoard> watchBoardFor(TeamMember viewer) {
    return Rx.combineLatest5<List<TeamTask>, List<Event>, List<Category>, List<TaskTopic>,
        List<TeamMember>, TeamTaskBoard>(
      watchTasksFor(viewer),
      _database.watchEvents().startWith(const []),
      _database.watchCategories().startWith(const []),
      _database.watchTaskTopics().startWith(const []),
      _database.watchTeamMembers().startWith(const []),
      (tasks, events, categories, topics, members) {
        final eventsById = {for (final event in events) event.id: event};
        final categoriesById = {for (final category in categories) category.id: category};
        final topicsById = {for (final topic in topics) topic.id: topic};
        final membersById = {for (final member in members) member.id: member};
        TeamTask populate(TeamTask task) {
          final link = task.link;
          return task.copyWith(
            event: () => link?.type == TaskLinkType.event ? eventsById[link!.id] : null,
            category: () =>
                link?.type == TaskLinkType.category ? categoriesById[link!.id] : null,
            topic: () => link?.type == TaskLinkType.topic ? topicsById[link!.id] : null,
            // A member who was deleted leaves a dangling id behind; it is kept
            // in ownerIds and simply not joined.
            owners: task.ownerIds.map((id) => membersById[id]).whereType<TeamMember>().toList(),
            subtasks: [
              for (final subtask in task.subtasks)
                subtask.copyWith(
                  assignee: () =>
                      subtask.assigneeId == null ? null : membersById[subtask.assigneeId],
                ),
            ],
          );
        }

        return TeamTaskBoard(
          tasks: tasks.map(populate).toList(),
          events: events,
          categories: categories,
          topics: topics,
          members: members,
        );
      },
    );
  }

  Future<void> insertTask(TeamTask task) => _database.insertTeamTask(task);

  Future<void> updateTask(TeamTask task) => _database.updateTeamTask(task);

  Future<void> deleteTask(String id) => _database.deleteTeamTask(id);

  Future<void> setStatus(String id, TeamTaskStatus status, {String? duplicateOfId}) =>
      _database.setTeamTaskStatus(id, status, duplicateOfId: duplicateOfId);

  Future<void> setSubtaskDone(String id, String subtaskId, bool isDone) =>
      _database.setTeamSubtaskDone(id, subtaskId, isDone);

  Future<void> addUpdate(String id, String text) => _database.addTeamTaskUpdate(id, text);

  Future<void> insertTopic(TaskTopic topic) => _database.insertTaskTopic(topic);

  Future<void> updateTopic(TaskTopic topic) => _database.updateTaskTopic(topic);

  Future<void> archiveTopic(String id) => _database.archiveTaskTopic(id);

  Future<void> restoreTopic(String id) => _database.restoreTaskTopic(id);
}
