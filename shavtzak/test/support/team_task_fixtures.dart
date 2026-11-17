import 'package:shavtzak/domain/entities/category.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/task_topic.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import 'task_fixtures.dart';

/// Builders for team task tests. Every argument has a default.
TeamTask buildTeamTask({
  String id = 't1',
  String title = 'להזמין אולם',
  TaskLink? link,
  List<String> eventIds = const [],
  List<Event> events = const [],
  Event? event,
  Category? category,
  TeamTaskUrgency urgency = TeamTaskUrgency.normal,
  List<String> assigneeIds = const ['m1'],
  String? deadline,
  TeamTaskStatus status = TeamTaskStatus.open,
  String? duplicateOfId,
  List<String>? ownerIds,
  List<TaskUpdateEntry> updates = const [],
  DateTime? createdAt,
}) {
  return TeamTask(
    id: id,
    title: title,
    link: link,
    eventIds: eventIds,
    events: events,
    event: event,
    category: category,
    urgency: urgency,
    assigneeIds: assigneeIds,
    deadline: deadline,
    status: status,
    duplicateOfId: duplicateOfId,
    ownerIds: ownerIds ?? assigneeIds,
    updates: updates,
    createdAt: createdAt ?? fixtureCreatedAt,
    updatedAt: createdAt ?? fixtureCreatedAt,
  );
}

Category buildCategory({
  String id = 'c1',
  String name = 'אירועי חנוכה',
  bool isArchived = false,
  int? colorValue,
}) =>
    Category(
      id: id,
      name: name,
      sortOrder: 0,
      isArchived: isArchived,
      colorValue: colorValue,
      createdAt: fixtureCreatedAt,
      updatedAt: fixtureCreatedAt,
    );

TaskTopic buildTopic({String id = 'p1', String name = 'נשות מגדים', bool isArchived = false}) =>
    TaskTopic(id: id, name: name, isArchived: isArchived);
