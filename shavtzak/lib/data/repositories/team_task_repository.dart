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

  /// "אירוע שעוד לא נוצר" placeholders (round 10).
  final List<TaskTopic> pendingEvents;

  const TeamTaskBoard({
    required this.tasks,
    this.events = const [],
    this.categories = const [],
    this.topics = const [],
    this.members = const [],
    this.pendingEvents = const [],
  });

  @override
  List<Object?> get props => [tasks, events, categories, topics, members, pendingEvents];
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
    return Rx.combineLatest6<List<TeamTask>, List<Event>, List<Category>, List<TaskTopic>,
        List<TeamMember>, List<TaskTopic>, TeamTaskBoard>(
      watchTasksFor(viewer),
      _database.watchEvents().startWith(const []),
      _database.watchCategories().startWith(const []),
      _database.watchTaskTopics().startWith(const []),
      _database.watchTeamMembers().startWith(const []),
      _database.watchPendingEvents().startWith(const []),
      (tasks, events, categories, topics, members, pendingEvents) {
        final pendingById = {for (final pending in pendingEvents) pending.id: pending};
        final eventsById = {for (final event in events) event.id: event};
        final categoriesById = {for (final category in categories) category.id: category};
        final topicsById = {for (final topic in topics) topic.id: topic};
        final membersById = {for (final member in members) member.id: member};
        TeamTask populate(TeamTask task) {
          final link = task.link;
          return task.copyWith(
            event: () => link?.type == TaskLinkType.event ? eventsById[link!.id] : null,
            // A deleted event drops out of the list, as from the card.
            events: task.linkedEventIds.map((id) => eventsById[id]).whereType<Event>().toList(),
            category: () =>
                link?.type == TaskLinkType.category ? categoriesById[link!.id] : null,
            topic: () => link?.type == TaskLinkType.topic ? topicsById[link!.id] : null,
            pendingEvent: () =>
                link?.type == TaskLinkType.pendingEvent ? pendingById[link!.id] : null,
            // A member who was deleted leaves a dangling id behind; it is kept
            // in ownerIds and simply not joined.
            owners: task.ownerIds.map((id) => membersById[id]).whereType<TeamMember>().toList(),
          );
        }

        return TeamTaskBoard(
          tasks: tasks.map(populate).toList(),
          events: events,
          categories: categories,
          topics: topics,
          members: members,
          pendingEvents: pendingEvents,
        );
      },
    );
  }

  Future<void> insertTask(TeamTask task) => _database.insertTeamTask(task);

  Future<void> updateTask(TeamTask task) => _database.updateTeamTask(task);

  Future<void> deleteTask(String id) => _database.deleteTeamTask(id);

  Future<void> setStatus(String id, TeamTaskStatus status, {String? duplicateOfId}) =>
      _database.setTeamTaskStatus(id, status, duplicateOfId: duplicateOfId);

  Future<void> addUpdate(String id, String text, {List<String> mentionIds = const []}) =>
      _database.addTeamTaskUpdate(id, text, mentionIds: mentionIds);

  Future<void> setMentionDone(String id, String updateId, String text) =>
      _database.setTeamTaskMentionDone(id, updateId, text);

  Future<void> editUpdate(String id, String updateId, String text) =>
      _database.editTeamTaskUpdate(id, updateId, text);

  Future<void> deleteUpdate(String id, String updateId) =>
      _database.deleteTeamTaskUpdate(id, updateId);

  Future<void> insertPendingEvent(TaskTopic pendingEvent) =>
      _database.insertPendingEvent(pendingEvent);

  Future<void> updatePendingEvent(TaskTopic pendingEvent) =>
      _database.updatePendingEvent(pendingEvent);

  Future<void> deletePendingEvent(String id) => _database.deletePendingEvent(id);

  Future<void> linkPendingEvent(String id, String eventId) =>
      _database.linkPendingEvent(id, eventId);

  Future<void> insertTopic(TaskTopic topic) => _database.insertTaskTopic(topic);

  Future<void> updateTopic(TaskTopic topic) => _database.updateTaskTopic(topic);

  Future<void> archiveTopic(String id) => _database.archiveTaskTopic(id);

  Future<void> restoreTopic(String id) => _database.restoreTaskTopic(id);

  Future<void> deleteTopic(String id) => _database.permanentlyDeleteTaskTopic(id);
}
