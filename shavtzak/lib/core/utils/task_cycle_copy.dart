import 'package:uuid/uuid.dart';

import '../../domain/entities/event.dart';
import '../../domain/entities/imported_stage.dart';
import '../../domain/entities/stage.dart';
import '../../domain/entities/subtask.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/entities/team_member.dart';
import 'task_progress.dart';
import 'task_utils.dart';

/// "העתקה ממחזור קודם": a new דו יומי event (מחזור) takes every stage and
/// task of an earlier one, instead of exporting it to Excel and importing the
/// file back. Pure functions; the copy is saved through the same backend call
/// as the Excel import (`stage.import`).

/// An earlier event that can be copied: an active דו יומי event, other than
/// [targetEventId], with at least one stage. Latest first.
List<EventTaskBoard> cycleSources({
  required List<Event> events,
  required List<Stage> stages,
  required List<TaskItem> tasks,
  required String targetEventId,
}) {
  final sources = <EventTaskBoard>[];
  for (final event in events) {
    if (event.id == targetEventId) continue;
    if (event.isDeactivated || event.categoryId != duYomiCategoryId) continue;
    final board = eventTaskBoard(event, stages: stages, tasks: tasks);
    if (board.stages.isNotEmpty) sources.add(board);
  }
  sources.sort((a, b) => b.event.startDate.compareTo(a.event.startDate));
  return sources;
}

/// What copying produced, ready for `stage.import`, and what the person
/// should know before saving it.
class CycleCopy {
  const CycleCopy({
    required this.stages,
    required this.givenToYou,
    required this.movedToLastDay,
  });

  final List<ImportedStage> stages;

  /// Tasks none of whose people are assigned to the new event: they go to
  /// the person copying, to be reassigned in "עריכה".
  final List<TaskItem> givenToYou;

  /// Stages whose day the new event does not have (the old one was longer):
  /// they sit on its last day.
  final int movedToLastDay;

  int get taskCount =>
      stages.fold(0, (sum, imported) => sum + imported.tasks.length);
}

/// Copies [source] into [target]. A stage keeps its place in the event: the
/// first day's stages land on the new first day, and so on. Everything else
/// is kept (titles, times, details, contacts, descriptions, sub-tasks) with
/// new ids, nothing done. A task keeps the people who are also assigned to
/// [target] ([members]); one left with nobody goes to [currentUser].
CycleCopy copyCycle(
  EventTaskBoard source, {
  required Event target,
  required List<TeamMember> members,
  required TeamMember currentUser,
  required DateTime now,
  String Function()? newId,
}) {
  final makeId = newId ?? const Uuid().v4;
  final sourceDays = eventDays(source.event);
  final targetDays = eventDays(target);
  final memberById = {for (final member in members) member.id: member};
  final givenToYou = <TaskItem>[];
  var movedToLastDay = 0;

  int dayIndex(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final index = sourceDays.indexOf(day);
    if (index >= 0) return index;
    // A stage outside its event's days (data from before the backend check):
    // count from the first day.
    final fromFirst = DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(sourceDays.first.year,
            sourceDays.first.month, sourceDays.first.day))
        .inDays;
    return fromFirst < 0 ? 0 : fromFirst;
  }

  final copied = <ImportedStage>[];
  for (final stage in source.stages) {
    final index = dayIndex(stage.date);
    if (index >= targetDays.length) movedToLastDay++;
    final newStage = Stage(
      id: makeId(),
      eventId: target.id,
      title: stage.title,
      date: targetDays[index.clamp(0, targetDays.length - 1)],
      startTime: stage.startTime,
      endTime: stage.endTime,
      requirements: stage.requirements,
      hotelLocation: stage.hotelLocation,
      notes: stage.notes,
      contacts: [
        for (final contact in stage.contacts)
          StageContact(
            id: makeId(),
            name: contact.name,
            phone: contact.phone,
            role: contact.role,
          ),
      ],
      createdAt: now,
      createdById: currentUser.id,
      updatedAt: now,
    );
    final tasks = <TaskItem>[];
    for (final task in source.tasks) {
      if (task.stageId != stage.id) continue;
      var people = [
        for (final id in task.assigneeIds)
          if (memberById[id] != null) memberById[id]!,
      ];
      final orphan = people.isEmpty;
      if (orphan) people = [currentUser];
      final copy = TaskItem(
        id: makeId(),
        eventId: target.id,
        stageId: newStage.id,
        title: task.title,
        description: task.description,
        subtasks: [
          for (final subtask in task.subtasks)
            Subtask(id: makeId(), title: subtask.title),
        ],
        assemblyTime: task.assemblyTime,
        assigneeIds: [for (final member in people) member.id],
        createdAt: now,
        createdById: currentUser.id,
        updatedAt: now,
        event: target,
        stage: newStage,
        assignees: people,
      );
      tasks.add(copy);
      if (orphan) givenToYou.add(copy);
    }
    copied.add(ImportedStage(stage: newStage, tasks: List.unmodifiable(tasks)));
  }
  return CycleCopy(
    stages: List.unmodifiable(copied),
    givenToYou: List.unmodifiable(givenToYou),
    movedToLastDay: movedToLastDay,
  );
}
