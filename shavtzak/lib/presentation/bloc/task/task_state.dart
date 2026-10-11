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

  /// Every event and member, live. The task form picks from these, so the
  /// screen does not depend on which other screens happened to load them.
  final List<Event> events;
  final List<TeamMember> members;

  const TasksLoaded(
    this.tasks, {
    this.events = const [],
    this.members = const [],
  });

  @override
  List<Object?> get props => [tasks, events, members];
}

class TasksError extends TaskState {
  final String message;

  const TasksError(this.message);

  @override
  List<Object?> get props => [message];
}
