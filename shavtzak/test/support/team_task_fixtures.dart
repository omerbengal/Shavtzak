import 'package:shavtzak/domain/entities/category.dart';
import 'package:shavtzak/domain/entities/task_topic.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import 'task_fixtures.dart';

/// Builders for team task tests. Every argument has a default.
TeamTask buildTeamTask({
  String id = 't1',
  String title = 'להזמין אולם',
  TaskLink? link,
  List<String> assigneeIds = const ['m1'],
  List<TeamSubtask> subtasks = const [],
  String? deadline,
  TeamTaskStatus status = TeamTaskStatus.open,
  String? duplicateOfId,
  List<String>? ownerIds,
  List<TaskUpdateEntry> updates = const [],
}) {
  final owners = ownerIds ??
      (subtasks.isEmpty
          ? assigneeIds
          : subtasks.map((s) => s.assigneeId).whereType<String>().toSet().toList());
  return TeamTask(
    id: id,
    title: title,
    link: link,
    assigneeIds: subtasks.isEmpty ? assigneeIds : const [],
    subtasks: subtasks,
    deadline: deadline,
    status: status,
    duplicateOfId: duplicateOfId,
    ownerIds: owners,
    updates: updates,
    createdAt: fixtureCreatedAt,
    updatedAt: fixtureCreatedAt,
  );
}

Category buildCategory({String id = 'c1', String name = 'אירועי חנוכה', bool isArchived = false}) =>
    Category(
      id: id,
      name: name,
      sortOrder: 0,
      isArchived: isArchived,
      createdAt: fixtureCreatedAt,
      updatedAt: fixtureCreatedAt,
    );

TaskTopic buildTopic({String id = 'p1', String name = 'נשות מגדים', bool isArchived = false}) =>
    TaskTopic(id: id, name: name, isArchived: isArchived);
