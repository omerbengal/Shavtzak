import 'package:equatable/equatable.dart';

import 'event.dart';
import 'stage.dart';
import 'subtask.dart';
import 'team_member.dart';

/// A task on the דו יומי task screen: work under one [Stage] of an event,
/// assigned to one or more team members, optionally broken into [subtasks].
///
/// Every timestamp is stamped by the backend. Completion is derived there too:
/// a task with subtasks is complete exactly when all of them are done.
class TaskItem extends Equatable {
  final String id;
  final String eventId; // Foreign key to Event
  final String stageId; // Foreign key to Stage; fixed once the task exists
  final String title;
  final String description;
  final List<Subtask> subtasks;

  /// The assembly (התייצבות) time on the stage's day, `HH:mm`; null = none.
  final String? assemblyTime;
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
  final Stage? stage;
  final List<TeamMember> assignees;

  const TaskItem({
    required this.id,
    required this.eventId,
    required this.stageId,
    required this.title,
    this.description = '',
    this.subtasks = const [],
    this.assemblyTime,
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
    this.stage,
    this.assignees = const [],
  });

  /// When the task is due: its stage's day at the assembly time, or the end of
  /// that day when there is no assembly time. Null while the stage is unknown.
  DateTime? get dueAt {
    final day = stage?.date;
    if (day == null) return null;
    final time = _hourMinute.firstMatch(assemblyTime ?? '');
    if (time == null) return DateTime(day.year, day.month, day.day, 23, 59);
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(time.group(1)!),
      int.parse(time.group(2)!),
    );
  }

  /// Whether the task has an assembly time, rather than the end-of-day default.
  bool get hasAssemblyTime => _hourMinute.hasMatch(assemblyTime ?? '');

  static final RegExp _hourMinute = RegExp(r'^(\d{2}):(\d{2})$');

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
    String? stageId,
    String? title,
    String? description,
    List<Subtask>? subtasks,
    String? assemblyTime,
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
    Stage? stage,
    List<TeamMember>? assignees,
    bool clearAssemblyTime = false, // Flag to explicitly clear the time
  }) {
    return TaskItem(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      stageId: stageId ?? this.stageId,
      title: title ?? this.title,
      description: description ?? this.description,
      subtasks: subtasks ?? this.subtasks,
      assemblyTime:
          clearAssemblyTime ? null : (assemblyTime ?? this.assemblyTime),
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
      stage: stage ?? this.stage,
      assignees: assignees ?? this.assignees,
    );
  }

  @override
  List<Object?> get props => [
        id,
        eventId,
        stageId,
        title,
        description,
        subtasks,
        assemblyTime,
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
        stage,
        assignees,
      ];

  @override
  String toString() {
    return 'TaskItem{id: $id, title: $title, eventId: $eventId, isComplete: $isComplete}';
  }
}
