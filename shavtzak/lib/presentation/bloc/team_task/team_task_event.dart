part of 'team_task_bloc.dart';

abstract class TeamTaskEvent extends Equatable {
  const TeamTaskEvent();

  @override
  List<Object?> get props => [];
}

/// Start watching the tasks [viewer] may see. A new viewer replaces the
/// subscription; the same viewer again is ignored.
class TeamTasksSubscribe extends TeamTaskEvent {
  final TeamMember viewer;

  const TeamTasksSubscribe(this.viewer);

  @override
  List<Object?> get props => [viewer];
}

class TeamTaskFilterChanged extends TeamTaskEvent {
  final TeamTaskFilter filter;

  const TeamTaskFilterChanged(this.filter);

  @override
  List<Object?> get props => [filter];
}

class CreateTeamTask extends TeamTaskEvent {
  final TeamTask task;
  final CrudActionCompleter? completion;

  const CreateTeamTask(this.task, {this.completion});

  @override
  List<Object?> get props => [task];
}

/// A manager's edit of any value. Shown at once, until the stream brings the
/// saved task back.
class UpdateTeamTask extends TeamTaskEvent {
  final TeamTask task;
  final CrudActionCompleter? completion;

  /// The draft ([TeamTaskDraftChanged.field]) this edit sends: dropped in the
  /// same step the edit is laid over the task, so nothing flickers.
  final String? draftField;

  const UpdateTeamTask(this.task, {this.completion, this.draftField});

  @override
  List<Object?> get props => [task];
}

/// A manager's change to one field that is not sent yet (a picker with no
/// save button waits a moment for the next tick, [DebouncedSaver]): shown
/// over task [id] at once. [apply] null drops it.
class TeamTaskDraftChanged extends TeamTaskEvent {
  final String id;
  final String field;
  final TeamTask Function(TeamTask task)? apply;

  const TeamTaskDraftChanged(this.id, this.field, this.apply);

  @override
  List<Object?> get props => [id, field, apply];
}

class DeleteTeamTask extends TeamTaskEvent {
  final String id;
  final CrudActionCompleter? completion;

  const DeleteTeamTask(this.id, {this.completion});

  @override
  List<Object?> get props => [id];
}

class SetTeamTaskStatus extends TeamTaskEvent {
  final String id;
  final TeamTaskStatus status;
  final String? duplicateOfId;
  final CrudActionCompleter? completion;

  const SetTeamTaskStatus(
    this.id,
    this.status, {
    this.duplicateOfId,
    this.completion,
  });

  @override
  List<Object?> get props => [id, status, duplicateOfId];
}

class AddTeamTaskUpdate extends TeamTaskEvent {
  final String id;
  final String text;
  final CrudActionCompleter? completion;

  const AddTeamTaskUpdate(this.id, this.text, {this.completion});

  @override
  List<Object?> get props => [id, text];
}

/// A new text for an update of the log: its writer, or a manager in "כל
/// המשימות" (round 10).
class EditTeamTaskUpdate extends TeamTaskEvent {
  final String id;
  final String updateId;
  final String text;
  final CrudActionCompleter? completion;

  const EditTeamTaskUpdate(this.id, this.updateId, this.text, {this.completion});

  @override
  List<Object?> get props => [id, updateId, text];
}

class DeleteTeamTaskUpdate extends TeamTaskEvent {
  final String id;
  final String updateId;
  final CrudActionCompleter? completion;

  const DeleteTeamTaskUpdate(this.id, this.updateId, {this.completion});

  @override
  List<Object?> get props => [id, updateId];
}

/// A new "אירוע שעוד לא נוצר" (round 10).
class CreatePendingEvent extends TeamTaskEvent {
  final TaskTopic pendingEvent;
  final CrudActionCompleter? completion;

  const CreatePendingEvent(this.pendingEvent, {this.completion});

  @override
  List<Object?> get props => [pendingEvent];
}

/// Placeholder [id] becomes the real event [eventId]: all its tasks move.
class LinkPendingEvent extends TeamTaskEvent {
  final String id;
  final String eventId;
  final CrudActionCompleter? completion;

  const LinkPendingEvent(this.id, this.eventId, {this.completion});

  @override
  List<Object?> get props => [id, eventId];
}

class CreateTaskTopic extends TeamTaskEvent {
  final TaskTopic topic;
  final CrudActionCompleter? completion;

  const CreateTaskTopic(this.topic, {this.completion});

  @override
  List<Object?> get props => [topic];
}

class UpdateTaskTopic extends TeamTaskEvent {
  final TaskTopic topic;
  final CrudActionCompleter? completion;

  const UpdateTaskTopic(this.topic, {this.completion});

  @override
  List<Object?> get props => [topic];
}

class ArchiveTaskTopic extends TeamTaskEvent {
  final String id;
  final bool archive;
  final CrudActionCompleter? completion;

  /// [archive] false = restore.
  const ArchiveTaskTopic(this.id, {this.archive = true, this.completion});

  @override
  List<Object?> get props => [id, archive];
}

/// Deletes a topic for good; its tasks move to "ללא שיוך".
class DeleteTaskTopic extends TeamTaskEvent {
  final String id;
  final CrudActionCompleter? completion;

  const DeleteTaskTopic(this.id, {this.completion});

  @override
  List<Object?> get props => [id];
}

class _BoardArrived extends TeamTaskEvent {
  final TeamTaskBoard board;

  const _BoardArrived(this.board);

  @override
  List<Object?> get props => [board];
}

class _BoardFailed extends TeamTaskEvent {
  final String message;

  const _BoardFailed(this.message);

  @override
  List<Object?> get props => [message];
}
