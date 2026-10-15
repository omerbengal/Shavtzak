part of 'task_bloc.dart';

abstract class TaskState extends Equatable {
  const TaskState();

  @override
  List<Object?> get props => [];
}

class TasksInitial extends TaskState {
  const TasksInitial();
}

class TasksLoading extends TaskState {
  const TasksLoading();
}

class TasksLoaded extends TaskState {
  final List<TaskItem> tasks;

  /// Every event, stage and member, live, so the screens do not depend on
  /// which other screens happened to load them.
  final List<Event> events;
  final List<Stage> stages;
  final List<TeamMember> members;

  const TasksLoaded(
    this.tasks, {
    this.events = const [],
    this.stages = const [],
    this.members = const [],
  });

  @override
  List<Object?> get props => [tasks, events, stages, members];
}

class TasksError extends TaskState {
  final String message;

  const TasksError(this.message);

  @override
  List<Object?> get props => [message];
}
