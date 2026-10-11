import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/event.dart';
import '../../domain/entities/subtask.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/entities/team_member.dart';

/// Converts between [TaskItem] entities, Firestore documents and the payload
/// the backend's task mutations accept.
class TaskItemModel {
  /// Builds a [TaskItem] from a stored document.
  ///
  /// Tolerant by design: the tasks screen reads the whole collection through
  /// one stream, so a single document with a missing or malformed field must
  /// not throw and blank the list for everyone.
  static TaskItem fromMap(
    String id,
    Map<String, dynamic> data, {
    Event? event,
    List<TeamMember> assignees = const [],
  }) {
    return TaskItem(
      id: id,
      eventId: _string(data['eventId']) ?? '',
      title: _string(data['title']) ?? '',
      description: _string(data['description']) ?? '',
      subtasks: _subtasks(data['subtasks']),
      dueAt: _date(data['dueAt']),
      assigneeIds: _stringList(data['assigneeIds']),
      assigneeUpdate: _string(data['assigneeUpdate']),
      assigneeUpdateAt: _date(data['assigneeUpdateAt']),
      assigneeUpdateById: _string(data['assigneeUpdateById']),
      assigneeUpdateByName: _string(data['assigneeUpdateByName']),
      isComplete: data['isComplete'] == true,
      completedAt: _date(data['completedAt']),
      completedById: _string(data['completedById']),
      createdAt: _date(data['createdAt']) ?? _epoch,
      createdById: _string(data['createdById']) ?? '',
      updatedAt: _date(data['updatedAt']) ?? _epoch,
      event: event,
      assignees: assignees,
    );
  }

  /// The payload for `task.insert` and `task.update`.
  ///
  /// Carries only what a task manager edits. Progress, completion and every
  /// timestamp are owned by the backend, so a subtask is sent without `isDone`.
  /// The due date goes out as a UTC instant: an ISO string with no zone would
  /// be read by the server in its own zone, three hours off.
  static Map<String, dynamic> toMutationPayload(TaskItem task) {
    return {
      'id': task.id,
      'eventId': task.eventId,
      'title': task.title,
      'description': task.description,
      'dueAt': task.dueAt?.toUtc().toIso8601String(),
      'assigneeIds': task.assigneeIds,
      'subtasks': task.subtasks
          .map((subtask) => {'id': subtask.id, 'title': subtask.title})
          .toList(),
    };
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  static String? _string(Object? value) => value is String ? value : null;

  static DateTime? _date(Object? value) =>
      value is Timestamp ? value.toDate() : null;

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  static List<Subtask> _subtasks(Object? value) {
    if (value is! List) return const [];
    final subtasks = <Subtask>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final title = entry['title'];
      if (id is! String || id.isEmpty || title is! String) continue;
      subtasks.add(Subtask(id: id, title: title, isDone: entry['isDone'] == true));
    }
    return subtasks;
  }
}
