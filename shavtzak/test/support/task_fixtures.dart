import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

/// Shared builders for task tests. Every argument has a default so a test
/// states only the fields it is about.

final DateTime fixtureCreatedAt = DateTime(2026, 10, 1, 9);

Event buildEvent({
  String id = 'e1',
  String name = 'דו יומי צפון',
  DateTime? startDate,
  DateTime? endDate,
  String location = 'חיפה',
  bool isDeactivated = false,
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
  );
}

TeamMember buildMember({
  String id = 'm1',
  String name = 'דנה',
  bool isAdmin = false,
  bool canManageTasks = false,
  bool isActive = true,
  bool isArchived = false,
}) {
  return TeamMember(
    id: id,
    name: name,
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

TaskItem buildTask({
  String id = 't1',
  String eventId = 'e1',
  String title = 'להזמין אוטובוס',
  String description = '',
  List<Subtask> subtasks = const [],
  DateTime? dueAt,
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
  return TaskItem(
    id: id,
    eventId: eventId,
    title: title,
    description: description,
    subtasks: subtasks,
    dueAt: dueAt,
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
    assignees: assignees,
  );
}
