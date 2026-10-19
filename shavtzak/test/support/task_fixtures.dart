import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

/// Shared builders for task tests. Every argument has a default so a test
/// states only the fields it is about.

final DateTime fixtureCreatedAt = DateTime(2026, 10, 1, 9);

/// The id of the "דו יומי" category in `utilities/Lists`, written out rather
/// than read from the app so a wrong id in the app fails the tests.
const String fixtureDuYomiCategoryId = 'dc8b7dd8-f633-4b6a-8169-a94d0561bbd5';

Event buildEvent({
  String id = 'e1',
  String name = 'דו יומי צפון',
  DateTime? startDate,
  DateTime? endDate,
  String location = 'חיפה',
  bool isDeactivated = false,
  String? categoryId = fixtureDuYomiCategoryId,
}) {
  final start = startDate ?? DateTime(2026, 10, 20);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: endDate ?? start,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '16:00',
    location: location,
    requiresArmed: false,
    roleRequirements: const {},
    createdAt: fixtureCreatedAt,
    updatedAt: fixtureCreatedAt,
    isDeactivated: isDeactivated,
    categoryId: categoryId,
  );
}

TeamMember buildMember({
  String id = 'm1',
  String name = 'דנה',
  bool isAdmin = false,
  bool canManageTasks = false,
  bool isActive = true,
  bool isArchived = false,
  String? phoneNumber,
}) {
  return TeamMember(
    id: id,
    name: name,
    phoneNumber: phoneNumber,
    isActive: isActive,
    isArchived: isArchived,
    constraints: const [],
    roleCapabilities: const {},
    createdAt: fixtureCreatedAt,
    updatedAt: fixtureCreatedAt,
    uniqueKey: 'key-$id',
    isAdmin: isAdmin,
    canManageTasks: canManageTasks,
  );
}

Stage buildStage({
  String id = 'st1',
  String eventId = 'e1',
  String title = 'קליטה',
  DateTime? date,
  String? startTime,
  String? endTime,
  String requirements = '',
  String hotelLocation = '',
  String notes = '',
  List<StageContact> contacts = const [],
}) {
  return Stage(
    id: id,
    eventId: eventId,
    title: title,
    date: date ?? DateTime(2026, 10, 20),
    startTime: startTime,
    endTime: endTime,
    requirements: requirements,
    hotelLocation: hotelLocation,
    notes: notes,
    contacts: contacts,
    createdAt: fixtureCreatedAt,
    createdById: 'm-admin',
    updatedAt: fixtureCreatedAt,
  );
}

/// [dueAt] is a shorthand for tests about due times: it puts the task under a
/// stage on that day with the assembly time set to that hour, which is how a
/// task gets a due moment now. Pass [stage] and [assemblyTime] instead to be
/// explicit.
TaskItem buildTask({
  String id = 't1',
  String eventId = 'e1',
  String stageId = 'st1',
  String title = 'להזמין אוטובוס',
  String description = '',
  List<Subtask> subtasks = const [],
  DateTime? dueAt,
  String? assemblyTime,
  Stage? stage,
  List<String> assigneeIds = const ['m1'],
  String? assigneeUpdate,
  DateTime? assigneeUpdateAt,
  String? assigneeUpdateById,
  String? assigneeUpdateByName,
  bool isComplete = false,
  DateTime? completedAt,
  String? completedById,
  DateTime? createdAt,
  String createdById = 'm-admin',
  DateTime? updatedAt,
  Event? event,
  List<TeamMember> assignees = const [],
}) {
  var effectiveStage = stage;
  var effectiveTime = assemblyTime;
  if (dueAt != null) {
    effectiveStage ??= buildStage(
      id: stageId,
      eventId: eventId,
      date: DateTime(dueAt.year, dueAt.month, dueAt.day),
    );
    effectiveTime ??= '${dueAt.hour.toString().padLeft(2, '0')}:'
        '${dueAt.minute.toString().padLeft(2, '0')}';
  }
  return TaskItem(
    id: id,
    eventId: eventId,
    stageId: effectiveStage?.id ?? stageId,
    title: title,
    description: description,
    subtasks: subtasks,
    assemblyTime: effectiveTime,
    assigneeIds: assigneeIds,
    assigneeUpdate: assigneeUpdate,
    assigneeUpdateAt: assigneeUpdateAt,
    assigneeUpdateById: assigneeUpdateById,
    assigneeUpdateByName: assigneeUpdateByName,
    isComplete: isComplete,
    completedAt: completedAt,
    completedById: completedById,
    createdAt: createdAt ?? fixtureCreatedAt,
    createdById: createdById,
    updatedAt: updatedAt ?? fixtureCreatedAt,
    event: event,
    stage: effectiveStage,
    assignees: assignees,
  );
}
