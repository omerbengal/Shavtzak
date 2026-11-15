import 'package:equatable/equatable.dart';

import 'category.dart';
import 'event.dart';
import 'stage.dart';
import 'task_topic.dart';
import 'team_member.dart';

/// The five statuses of a team task. "באיחור" is not one of them: it is
/// derived from the deadline (`isTeamTaskLate`).
enum TeamTaskStatus {
  open('open', 'פתוחה'),
  inProgress('inProgress', 'בטיפול'),
  done('done', 'בוצעה'),
  cancelled('cancelled', 'לא רלוונטי/בוטל'),
  duplicate('duplicate', 'כפילות');

  const TeamTaskStatus(this.key, this.hebrewLabel);

  /// The value stored in Firestore and sent to the backend.
  final String key;
  final String hebrewLabel;

  /// An unknown key reads as [open], so a newer status never breaks a list.
  static TeamTaskStatus fromKey(Object? key) =>
      values.firstWhere((status) => status.key == key, orElse: () => open);

  /// Still to be done: [open] or [inProgress].
  bool get isActive => this == open || this == inProgress;
}

enum TaskLinkType {
  event('event'),
  category('category'),
  topic('topic'),

  /// "אירוע שעוד לא נוצר" (round 10): a named placeholder for an event that
  /// is not in the app yet, linked later to the real one.
  pendingEvent('pendingEvent');

  const TaskLinkType(this.key);
  final String key;

  static TaskLinkType? fromKey(Object? key) {
    for (final type in values) {
      if (type.key == key) return type;
    }
    return null;
  }
}

/// What a team task belongs to: one event, one category or one topic.
class TaskLink extends Equatable {
  final TaskLinkType type;
  final String id;

  const TaskLink(this.type, this.id);

  Map<String, dynamic> toJson() => {'type': type.key, 'id': id};

  static TaskLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = TaskLinkType.fromKey(raw['type']);
    final id = raw['id'];
    if (type == null || id is! String || id.isEmpty) return null;
    return TaskLink(type, id);
  }

  @override
  List<Object?> get props => [type, id];
}

/// A subtask: a task of its own nested in its parent (Omer, round 2), with
/// a title, description, owners, contacts, a deadline, the five statuses and
/// its own update log. It has no link (its parent's) and no subtasks.
class TeamSubtask extends Equatable {
  final String id;
  final String title;
  final String description;
  final List<String> assigneeIds;
  final List<StageContact> contacts;

  /// `yyyy-MM-dd`, or null for no deadline.
  final String? deadline;
  final TeamTaskStatus status;
  final String? duplicateOfId;

  /// Newest first.
  final List<TaskUpdateEntry> updates;
  final DateTime? completedAt;

  /// The members behind [assigneeIds] still on the team, joined by the
  /// repository.
  final List<TeamMember> assignees;

  const TeamSubtask({
    required this.id,
    required this.title,
    this.description = '',
    this.assigneeIds = const [],
    this.contacts = const [],
    this.deadline,
    this.status = TeamTaskStatus.open,
    this.duplicateOfId,
    this.updates = const [],
    this.completedAt,
    this.assignees = const [],
  });

  bool get isDone => status == TeamTaskStatus.done;

  TeamSubtask copyWith({
    String? title,
    String? description,
    List<String>? assigneeIds,
    List<StageContact>? contacts,
    String? Function()? deadline,
    TeamTaskStatus? status,
    String? Function()? duplicateOfId,
    List<TaskUpdateEntry>? updates,
    DateTime? Function()? completedAt,
    List<TeamMember>? assignees,
  }) =>
      TeamSubtask(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        assigneeIds: assigneeIds ?? this.assigneeIds,
        contacts: contacts ?? this.contacts,
        deadline: deadline != null ? deadline() : this.deadline,
        status: status ?? this.status,
        duplicateOfId: duplicateOfId != null ? duplicateOfId() : this.duplicateOfId,
        updates: updates ?? this.updates,
        completedAt: completedAt != null ? completedAt() : this.completedAt,
        assignees: assignees ?? this.assignees,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        assigneeIds,
        contacts,
        deadline,
        status,
        duplicateOfId,
        updates,
        completedAt,
        assignees,
      ];
}

/// One entry of a task's update log ("יומן עדכונים").
class TaskUpdateEntry extends Equatable {
  final String id;
  final String text;
  final DateTime at;
  final String byId;
  final String? byName;

  const TaskUpdateEntry({
    required this.id,
    required this.text,
    required this.at,
    required this.byId,
    this.byName,
    this.editedAt,
  });

  /// Set once its writer (or a manager) edited it (round 10): "(נערך)".
  final DateTime? editedAt;

  @override
  List<Object?> get props => [id, text, at, byId, byName, editedAt];
}

/// A team task ("משימה") of the headquarters team: linked to an event, a
/// category or a topic, with owners, subtasks, contacts, an optional date
/// deadline, a status and an update log. Stored in `teamTasks`; every write
/// goes through the backend (`teamTask.*`).
class TeamTask extends Equatable {
  final String id;
  final String title;
  final String description;
  final TaskLink? link;

  /// The task's own owners; empty when it has subtasks (their owners are the
  /// task's owners then, see [ownerIds]).
  final List<String> assigneeIds;
  final List<TeamSubtask> subtasks;
  final List<StageContact> contacts;

  /// `yyyy-MM-dd`, or null for no deadline.
  final String? deadline;
  final TeamTaskStatus status;
  final String? duplicateOfId;

  /// Newest first.
  final List<TaskUpdateEntry> updates;

  /// Derived by the backend on every write: [assigneeIds] without subtasks,
  /// else the distinct subtask owners.
  final List<String> ownerIds;
  final DateTime? completedAt;
  final DateTime createdAt;
  final String createdById;
  final DateTime updatedAt;

  // Joined by the repository.
  final Event? event;
  final Category? category;
  final TaskTopic? topic;

  /// The "אירוע שעוד לא נוצר" behind a [TaskLinkType.pendingEvent] link.
  final TaskTopic? pendingEvent;

  /// The members behind [ownerIds] still on the team, in that order.
  final List<TeamMember> owners;

  /// Set only on a subtask shown as a task ([TeamTask.subtaskView]): its
  /// parent's id and title. Never stored.
  final String? parentId;
  final String? parentTitle;

  bool get isSubtask => parentId != null;

  const TeamTask({
    required this.id,
    required this.title,
    this.description = '',
    this.link,
    this.assigneeIds = const [],
    this.subtasks = const [],
    this.contacts = const [],
    this.deadline,
    this.status = TeamTaskStatus.open,
    this.duplicateOfId,
    this.updates = const [],
    this.ownerIds = const [],
    this.completedAt,
    required this.createdAt,
    this.createdById = '',
    required this.updatedAt,
    this.event,
    this.category,
    this.topic,
    this.pendingEvent,
    this.owners = const [],
    this.parentId,
    this.parentTitle,
  });

  /// Subtask [subtask] of [parent] as a task of its own, so the list and the
  /// task screen show it with the same widgets: the parent's link (and joined
  /// target), the subtask's fields, [parentId] / [parentTitle] set.
  factory TeamTask.subtaskView(TeamTask parent, TeamSubtask subtask) => TeamTask(
        id: subtask.id,
        title: subtask.title,
        description: subtask.description,
        link: parent.link,
        assigneeIds: subtask.assigneeIds,
        contacts: subtask.contacts,
        deadline: subtask.deadline,
        status: subtask.status,
        duplicateOfId: subtask.duplicateOfId,
        updates: subtask.updates,
        ownerIds: subtask.assigneeIds,
        completedAt: subtask.completedAt,
        createdAt: parent.createdAt,
        createdById: parent.createdById,
        updatedAt: parent.updatedAt,
        event: parent.event,
        category: parent.category,
        topic: parent.topic,
        pendingEvent: parent.pendingEvent,
        owners: subtask.assignees,
        parentId: parent.id,
        parentTitle: parent.title,
      );

  /// The subtask this view stands for, with the fields a manager edits.
  TeamSubtask toSubtask() => TeamSubtask(
        id: id,
        title: title,
        description: description,
        assigneeIds: assigneeIds,
        contacts: contacts,
        deadline: deadline,
        status: status,
        duplicateOfId: duplicateOfId,
        updates: updates,
        completedAt: completedAt,
        assignees: owners,
      );

  /// [deadline] as a local date, or null.
  DateTime? get deadlineDate {
    final value = deadline;
    if (value == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  int get doneSubtasks => subtasks.where((subtask) => subtask.isDone).length;

  TeamTask copyWith({
    String? title,
    String? description,
    TaskLink? Function()? link,
    List<String>? assigneeIds,
    List<TeamSubtask>? subtasks,
    List<StageContact>? contacts,
    String? Function()? deadline,
    TeamTaskStatus? status,
    String? Function()? duplicateOfId,
    List<TaskUpdateEntry>? updates,
    List<String>? ownerIds,
    DateTime? Function()? completedAt,
    DateTime? updatedAt,
    Event? Function()? event,
    Category? Function()? category,
    TaskTopic? Function()? topic,
    TaskTopic? Function()? pendingEvent,
    List<TeamMember>? owners,
  }) =>
      TeamTask(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        link: link != null ? link() : this.link,
        assigneeIds: assigneeIds ?? this.assigneeIds,
        subtasks: subtasks ?? this.subtasks,
        contacts: contacts ?? this.contacts,
        deadline: deadline != null ? deadline() : this.deadline,
        status: status ?? this.status,
        duplicateOfId: duplicateOfId != null ? duplicateOfId() : this.duplicateOfId,
        updates: updates ?? this.updates,
        ownerIds: ownerIds ?? this.ownerIds,
        completedAt: completedAt != null ? completedAt() : this.completedAt,
        createdAt: createdAt,
        createdById: createdById,
        updatedAt: updatedAt ?? this.updatedAt,
        event: event != null ? event() : this.event,
        category: category != null ? category() : this.category,
        topic: topic != null ? topic() : this.topic,
        pendingEvent: pendingEvent != null ? pendingEvent() : this.pendingEvent,
        owners: owners ?? this.owners,
        parentId: parentId,
        parentTitle: parentTitle,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        link,
        assigneeIds,
        subtasks,
        contacts,
        deadline,
        status,
        duplicateOfId,
        updates,
        ownerIds,
        completedAt,
        createdAt,
        createdById,
        updatedAt,
        event,
        category,
        topic,
        pendingEvent,
        owners,
        parentId,
        parentTitle,
      ];
}
