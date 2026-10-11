import 'package:equatable/equatable.dart';

import 'event.dart';
import 'subtask.dart';
import 'team_member.dart';

/// A task on the דו יומי task screen: work tied to an event, assigned to one or
/// more team members, optionally broken into [subtasks].
///
/// Every timestamp is stamped by the backend. Completion is derived there too:
/// a task with subtasks is complete exactly when all of them are done.
class TaskItem extends Equatable {
  final String id;
  final String eventId; // Foreign key to Event
  final String title;
  final String description;
  final List<Subtask> subtasks;
  final DateTime? dueAt; // Due date and time; null = no deadline
  final List<String> assigneeIds; // Foreign keys to TeamMember

  // The assignees' shared status note. Overwritten on each save; the audit log
  // keeps the history.
  final String? assigneeUpdate;
  final DateTime? assigneeUpdateAt;
  final String? assigneeUpdateById;
  final String? assigneeUpdateByName; // Denormalized for display

  final bool isComplete;
  final DateTime? completedAt;
  final String? completedById;

  final DateTime createdAt;
  final String createdById;
  final DateTime updatedAt; // Bumped by every write to the task

  // Computed fields (populated by the repository)
  final Event? event;
  final List<TeamMember> assignees;

  const TaskItem({
    required this.id,
    required this.eventId,
    required this.title,
    this.description = '',
    this.subtasks = const [],
    this.dueAt,
    required this.assigneeIds,
    this.assigneeUpdate,
    this.assigneeUpdateAt,
    this.assigneeUpdateById,
    this.assigneeUpdateByName,
    this.isComplete = false,
    this.completedAt,
    this.completedById,
    required this.createdAt,
    required this.createdById,
    required this.updatedAt,
    this.event,
    this.assignees = const [],
  });

  bool get hasSubtasks => subtasks.isNotEmpty;

  int get doneSubtaskCount =>
      subtasks.where((subtask) => subtask.isDone).length;

  /// Share of subtasks done, from 0 to 1. Zero when there are no subtasks.
  double get progress =>
      subtasks.isEmpty ? 0 : doneSubtaskCount / subtasks.length;

  bool isAssignedTo(String memberId) => assigneeIds.contains(memberId);

  TaskItem copyWith({
    String? id,
    String? eventId,
    String? title,
    String? description,
    List<Subtask>? subtasks,
    DateTime? dueAt,
    List<String>? assigneeIds,
    String? assigneeUpdate,
    DateTime? assigneeUpdateAt,
    String? assigneeUpdateById,
    String? assigneeUpdateByName,
    bool? isComplete,
    DateTime? completedAt,
    String? completedById,
    DateTime? createdAt,
    String? createdById,
    DateTime? updatedAt,
    Event? event,
    List<TeamMember>? assignees,
    bool clearDueAt = false, // Flag to explicitly clear the nullable due date
  }) {
    return TaskItem(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      title: title ?? this.title,
      description: description ?? this.description,
      subtasks: subtasks ?? this.subtasks,
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      assigneeIds: assigneeIds ?? this.assigneeIds,
      assigneeUpdate: assigneeUpdate ?? this.assigneeUpdate,
      assigneeUpdateAt: assigneeUpdateAt ?? this.assigneeUpdateAt,
      assigneeUpdateById: assigneeUpdateById ?? this.assigneeUpdateById,
      assigneeUpdateByName: assigneeUpdateByName ?? this.assigneeUpdateByName,
      isComplete: isComplete ?? this.isComplete,
      completedAt: completedAt ?? this.completedAt,
      completedById: completedById ?? this.completedById,
      createdAt: createdAt ?? this.createdAt,
      createdById: createdById ?? this.createdById,
      updatedAt: updatedAt ?? this.updatedAt,
      event: event ?? this.event,
      assignees: assignees ?? this.assignees,
    );
  }

  @override
  List<Object?> get props => [
        id,
        eventId,
        title,
        description,
        subtasks,
        dueAt,
        assigneeIds,
        assigneeUpdate,
        assigneeUpdateAt,
        assigneeUpdateById,
        assigneeUpdateByName,
        isComplete,
        completedAt,
        completedById,
        createdAt,
        createdById,
        updatedAt,
        event,
        assignees,
      ];

  @override
  String toString() {
    return 'TaskItem{id: $id, title: $title, eventId: $eventId, isComplete: $isComplete}';
  }
}
