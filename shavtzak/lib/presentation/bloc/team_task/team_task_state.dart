part of 'team_task_bloc.dart';

abstract class TeamTaskState extends Equatable {
  const TeamTaskState();

  @override
  List<Object?> get props => [];
}

class TeamTasksInitial extends TeamTaskState {
  const TeamTasksInitial();
}

class TeamTasksError extends TeamTaskState {
  final String message;

  const TeamTasksError(this.message);

  @override
  List<Object?> get props => [message];
}

class TeamTasksLoaded extends TeamTaskState {
  final TeamMember viewer;

  /// Every task the viewer may see, with unconfirmed ticks and edits laid over.
  final List<TeamTask> all;

  /// The viewer's rows of "המשימות שלי": the tasks without subtasks they own,
  /// and each subtask they own as its own row ([myTeamTaskRows]).
  final List<TeamTask> mine;

  /// [all] / [mine] after [filter], grouped by link.
  final List<TeamTaskGroup> allGroups;
  final List<TeamTaskGroup> mineGroups;
  final TeamTaskFilter filter;
  final bool canManage;

  final List<Event> events;
  final List<Category> categories;
  final List<TaskTopic> topics;
  final List<TeamMember> members;

  const TeamTasksLoaded({
    required this.viewer,
    required this.all,
    required this.mine,
    required this.allGroups,
    required this.mineGroups,
    required this.filter,
    required this.canManage,
    this.events = const [],
    this.categories = const [],
    this.topics = const [],
    this.members = const [],
  });

  /// A task, or a subtask as a task of its own ([TeamTask.subtaskView]).
  TeamTask? taskById(String id) {
    for (final task in all) {
      if (task.id == id) return task;
    }
    for (final task in all) {
      for (final subtask in task.subtasks) {
        if (subtask.id == id) return TeamTask.subtaskView(task, subtask);
      }
    }
    return null;
  }

  /// What a duplicate points to: the original's title, or a note when it is
  /// gone (deleted, or for a member not a manager, not one of theirs).
  String duplicateOriginalLabel(TeamTask task) {
    final id = task.duplicateOfId;
    if (id == null) return '';
    final original = taskById(id);
    if (original != null) return original.title;
    return canManage ? '(המקורית נמחקה)' : '(משימה אחרת)';
  }

  @override
  List<Object?> get props => [
        viewer,
        all,
        mine,
        allGroups,
        mineGroups,
        filter,
        canManage,
        events,
        categories,
        topics,
        members,
      ];
}
