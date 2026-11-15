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

  const UpdateTeamTask(this.task, {this.completion});

  @override
  List<Object?> get props => [task];
}

class DeleteTeamTask extends TeamTaskEvent {
  final String id;
  final CrudActionCompleter? completion;

  const DeleteTeamTask(this.id, {this.completion});

  @override
  List<Object?> get props => [id];
}

/// With [subtaskId], the status of that subtask of task [id].
class SetTeamTaskStatus extends TeamTaskEvent {
  final String id;
  final TeamTaskStatus status;
  final String? duplicateOfId;
  final String? subtaskId;
  final CrudActionCompleter? completion;

  const SetTeamTaskStatus(
    this.id,
    this.status, {
    this.duplicateOfId,
    this.subtaskId,
    this.completion,
  });

  @override
  List<Object?> get props => [id, status, duplicateOfId, subtaskId];
}

class ToggleTeamSubtask extends TeamTaskEvent {
  final String taskId;
  final String subtaskId;
  final bool isDone;
  final CrudActionCompleter? completion;

  const ToggleTeamSubtask(this.taskId, this.subtaskId, this.isDone, {this.completion});

  @override
  List<Object?> get props => [taskId, subtaskId, isDone];
}

/// With [subtaskId], into that subtask's own log.
class AddTeamTaskUpdate extends TeamTaskEvent {
  final String id;
  final String text;
  final String? subtaskId;
  final CrudActionCompleter? completion;

  const AddTeamTaskUpdate(this.id, this.text, {this.subtaskId, this.completion});

  @override
  List<Object?> get props => [id, text, subtaskId];
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
