part of 'task_bloc.dart';

abstract class TaskEvent extends Equatable {
  const TaskEvent();

  @override
  List<Object?> get props => [];
}

/// Start watching every task. Ignored while a subscription is already live.
class LoadTasks extends TaskEvent {
  const LoadTasks();
}

class CreateStage extends TaskEvent {
  final Stage stage;
  final CrudActionCompleter? completion;

  const CreateStage(this.stage, {this.completion});

  @override
  List<Object?> get props => [stage];
}

class ImportStages extends TaskEvent {
  final String eventId;
  final List<ImportedStage> stages;
  final CrudActionCompleter? completion;

  const ImportStages(this.eventId, this.stages, {this.completion});

  @override
  List<Object?> get props => [eventId, stages];
}

class UpdateStage extends TaskEvent {
  final Stage stage;
  final CrudActionCompleter? completion;

  const UpdateStage(this.stage, {this.completion});

  @override
  List<Object?> get props => [stage];
}

/// Delete a stage and every task under it.
class DeleteStage extends TaskEvent {
  final String stageId;
  final CrudActionCompleter? completion;

  const DeleteStage(this.stageId, {this.completion});

  @override
  List<Object?> get props => [stageId];
}

class CreateTask extends TaskEvent {
  final TaskItem task;
  final CrudActionCompleter? completion;

  const CreateTask(this.task, {this.completion});

  @override
  List<Object?> get props => [task];
}

class UpdateTask extends TaskEvent {
  final TaskItem task;
  final CrudActionCompleter? completion;

  const UpdateTask(this.task, {this.completion});

  @override
  List<Object?> get props => [task];
}

class DeleteTask extends TaskEvent {
  final String taskId;
  final CrudActionCompleter? completion;

  const DeleteTask(this.taskId, {this.completion});

  @override
  List<Object?> get props => [taskId];
}

class ToggleSubtask extends TaskEvent {
  final String taskId;
  final String subtaskId;
  final bool isDone;
  final CrudActionCompleter? completion;

  const ToggleSubtask({
    required this.taskId,
    required this.subtaskId,
    required this.isDone,
    this.completion,
  });

  @override
  List<Object?> get props => [taskId, subtaskId, isDone];
}

/// Complete or reopen a task that has no subtasks.
class SetTaskComplete extends TaskEvent {
  final String taskId;
  final bool isComplete;
  final CrudActionCompleter? completion;

  const SetTaskComplete({
    required this.taskId,
    required this.isComplete,
    this.completion,
  });

  @override
  List<Object?> get props => [taskId, isComplete];
}

/// Save the assignees' status note. An empty [text] clears it.
class SaveAssigneeUpdate extends TaskEvent {
  final String taskId;
  final String text;
  final CrudActionCompleter? completion;

  const SaveAssigneeUpdate({
    required this.taskId,
    required this.text,
    this.completion,
  });

  @override
  List<Object?> get props => [taskId, text];
}
