import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/stage.dart';
import '../../domain/entities/team_task.dart';

/// Converts between [TeamTask] entities, Firestore documents and the payload
/// the backend's `teamTask.insert` / `teamTask.update` accept.
class TeamTaskModel {
  /// Tolerant by design, like `TaskItemModel.fromMap`: one malformed document
  /// must not blank the list for everyone.
  static TeamTask fromMap(String id, Map<String, dynamic> data) {
    final status = TeamTaskStatus.fromKey(data['status']);
    return TeamTask(
      id: id,
      title: _string(data['title']) ?? '',
      description: _string(data['description']) ?? '',
      link: TaskLink.fromJson(data['link']),
      eventIds: _stringList(data['eventIds']),
      urgency: TeamTaskUrgency.fromKey(data['urgency']),
      assigneeIds: _stringList(data['assigneeIds']),
      contacts: contactsFromJson(data['contacts']),
      deadline: _deadline(data['deadline']),
      status: status,
      duplicateOfId:
          status == TeamTaskStatus.duplicate ? _string(data['duplicateOfId']) : null,
      updates: _updates(data['updates']),
      ownerIds: _stringList(data['ownerIds']),
      completedAt: _date(data['completedAt']),
      statusChangedAt: _date(data['statusChangedAt']),
      createdAt: _date(data['createdAt']) ?? _epoch,
      createdById: _string(data['createdById']) ?? '',
      updatedAt: _date(data['updatedAt']) ?? _epoch,
    );
  }

  /// The `task` of `teamTask.insert` / `teamTask.update`: only what a manager
  /// edits. Status, the log and every timestamp have their own operations or
  /// belong to the backend. No `subtasks` key: the backend keeps an old
  /// document's subtasks (removed from the app, 16/11/2026). `link` stays the
  /// first event, so an older app version still sees it.
  static Map<String, dynamic> toMutationPayload(TeamTask task) => {
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'link': task.link?.toJson(),
        'eventIds': task.linkedEventIds,
        'urgency': task.urgency.key,
        'assigneeIds': task.assigneeIds,
        'contacts': contactsToJson(task.contacts),
        'deadline': task.deadline,
      };

  static List<Map<String, dynamic>> contactsToJson(List<StageContact> contacts) => [
        for (final contact in contacts)
          {
            'id': contact.id,
            'name': contact.name,
            'phone': contact.phone,
            'role': contact.role,
          },
      ];

  static List<StageContact> contactsFromJson(Object? value) {
    if (value is! List) return const [];
    final contacts = <StageContact>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || id.isEmpty) continue;
      contacts.add(StageContact(
        id: id,
        name: _string(entry['name']) ?? '',
        phone: _string(entry['phone']) ?? '',
        role: _string(entry['role']) ?? '',
      ));
    }
    return contacts;
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String? _string(Object? value) => value is String ? value : null;

  static String? _deadline(Object? value) =>
      value is String && _datePattern.hasMatch(value) ? value : null;

  static DateTime? _date(Object? value) => value is Timestamp ? value.toDate() : null;

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  static List<TaskUpdateEntry> _updates(Object? value) {
    if (value is! List) return const [];
    final updates = <TaskUpdateEntry>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final text = entry['text'];
      final at = _date(entry['at']);
      if (id is! String || text is! String || at == null) continue;
      updates.add(TaskUpdateEntry(
        id: id,
        text: text,
        at: at,
        byId: _string(entry['byId']) ?? '',
        byName: _string(entry['byName']),
        editedAt: _date(entry['editedAt']),
      ));
    }
    return updates;
  }
}
