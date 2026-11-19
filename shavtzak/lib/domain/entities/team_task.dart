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

/// How urgent a task is (Omer, 16/11/2026: three levels). A task with no
/// stored urgency reads as [normal]; only the others are shown on a row.
enum TeamTaskUrgency {
  low('low', 'נמוכה'),
  normal('normal', 'רגילה'),
  high('high', 'גבוהה');

  const TeamTaskUrgency(this.key, this.hebrewLabel);

  /// The value stored in Firestore and sent to the backend.
  final String key;
  final String hebrewLabel;

  /// An unknown or missing key reads as [normal].
  static TeamTaskUrgency fromKey(Object? key) =>
      values.firstWhere((urgency) => urgency.key == key, orElse: () => normal);
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

/// What a team task belongs to: an event (the first one when it has several,
/// see [TeamTask.eventIds]), a category, a topic or a pending event.
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

/// A team task ("משימה") of the headquarters team: linked to one or more
/// events, a category, a topic or a pending event, with owners, contacts, an
/// optional date deadline, an urgency, a status and an update log. Stored in
/// `teamTasks`; every write goes through the backend (`teamTask.*`).
/// Subtasks were removed from the app (Omer, 16/11/2026).
class TeamTask extends Equatable {
  final String id;
  final String title;
  final String description;
  final TaskLink? link;

  /// Every event of a task linked to several events (16/11/2026), [link]'s
  /// event first; empty unless [link] is an event. Older app versions read
  /// only [link], so they still see the first event. Use [linkedEventIds].
  final List<String> eventIds;
  final TeamTaskUrgency urgency;

  /// The task's owners.
  final List<String> assigneeIds;
  final List<StageContact> contacts;

  /// `yyyy-MM-dd`, or null for no deadline.
  final String? deadline;
  final TeamTaskStatus status;
  final String? duplicateOfId;

  /// Newest first.
  final List<TaskUpdateEntry> updates;

  /// Derived by the backend on every write: the owners, once each.
  final List<String> ownerIds;
  final DateTime? completedAt;

  /// When the status last changed (written by the backend's
  /// `teamTask.setStatus` since 19/11/2026); null = not since then.
  final DateTime? statusChangedAt;
  final DateTime createdAt;
  final String createdById;
  final DateTime updatedAt;

  // Joined by the repository.
  /// [link]'s event (the first one).
  final Event? event;

  /// The events behind [linkedEventIds] that still exist, in that order.
  final List<Event> events;
  final Category? category;
  final TaskTopic? topic;

  /// The "אירוע שעוד לא נוצר" behind a [TaskLinkType.pendingEvent] link.
  final TaskTopic? pendingEvent;

  /// The members behind [ownerIds] still on the team, in that order.
  final List<TeamMember> owners;

  const TeamTask({
    required this.id,
    required this.title,
    this.description = '',
    this.link,
    this.eventIds = const [],
    this.urgency = TeamTaskUrgency.normal,
    this.assigneeIds = const [],
    this.contacts = const [],
    this.deadline,
    this.status = TeamTaskStatus.open,
    this.duplicateOfId,
    this.updates = const [],
    this.ownerIds = const [],
    this.completedAt,
    this.statusChangedAt,
    required this.createdAt,
    this.createdById = '',
    required this.updatedAt,
    this.event,
    this.events = const [],
    this.category,
    this.topic,
    this.pendingEvent,
    this.owners = const [],
  });

  /// The ids of every event the task is linked to, [link]'s first: the
  /// stored [eventIds], or [link]'s event alone (a document from before
  /// 16/11/2026); none unless [link] is an event.
  List<String> get linkedEventIds {
    final link = this.link;
    if (link == null || link.type != TaskLinkType.event) return const [];
    return [link.id, ...eventIds.where((id) => id != link.id)];
  }

  /// Linked to more than one event.
  bool get hasSeveralEvents => linkedEventIds.length > 1;

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

  TeamTask copyWith({
    String? title,
    String? description,
    TaskLink? Function()? link,
    List<String>? eventIds,
    TeamTaskUrgency? urgency,
    List<String>? assigneeIds,
    List<StageContact>? contacts,
    String? Function()? deadline,
    TeamTaskStatus? status,
    String? Function()? duplicateOfId,
    List<TaskUpdateEntry>? updates,
    List<String>? ownerIds,
    DateTime? Function()? completedAt,
    DateTime? Function()? statusChangedAt,
    DateTime? updatedAt,
    Event? Function()? event,
    List<Event>? events,
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
        eventIds: eventIds ?? this.eventIds,
        urgency: urgency ?? this.urgency,
        assigneeIds: assigneeIds ?? this.assigneeIds,
        contacts: contacts ?? this.contacts,
        deadline: deadline != null ? deadline() : this.deadline,
        status: status ?? this.status,
        duplicateOfId: duplicateOfId != null ? duplicateOfId() : this.duplicateOfId,
        updates: updates ?? this.updates,
        ownerIds: ownerIds ?? this.ownerIds,
        completedAt: completedAt != null ? completedAt() : this.completedAt,
        statusChangedAt: statusChangedAt != null ? statusChangedAt() : this.statusChangedAt,
        createdAt: createdAt,
        createdById: createdById,
        updatedAt: updatedAt ?? this.updatedAt,
        event: event != null ? event() : this.event,
        events: events ?? this.events,
        category: category != null ? category() : this.category,
        topic: topic != null ? topic() : this.topic,
        pendingEvent: pendingEvent != null ? pendingEvent() : this.pendingEvent,
        owners: owners ?? this.owners,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        link,
        eventIds,
        urgency,
        assigneeIds,
        contacts,
        deadline,
        status,
        duplicateOfId,
        updates,
        ownerIds,
        completedAt,
        statusChangedAt,
        createdAt,
        createdById,
        updatedAt,
        event,
        events,
        category,
        topic,
        pendingEvent,
        owners,
      ];
}
