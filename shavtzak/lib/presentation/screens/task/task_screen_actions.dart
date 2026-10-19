import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/debug/logger.dart';
import '../../../core/services/task_import_files.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/task_import/task_import_template.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/stage.dart';
import '../../../domain/entities/subtask.dart';
import '../../../domain/entities/task_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/task/task_bloc.dart';
import 'widgets/assignee_update_dialog.dart';
import 'widgets/confirm_delete_dialog.dart';
import 'widgets/stage_form_modal.dart';
import 'widgets/task_form_modal.dart';
import 'widgets/task_import_dialog.dart';

/// The tasks screen's actions: each sends one [TaskBloc] event. The forms
/// and dialogs show their own outcome; a tick that fails is reported in a
/// red snackbar.
mixin TaskScreenActions<T extends StatefulWidget> on State<T> {
  /// The screen's ticking "now", handed to the forms.
  DateTime get actionTime;

  /// Picking the import file and saving the template; faked in tests.
  TaskImportFiles get importFiles;

  Future<CrudActionResult> sendTaskEvent(
    TaskEvent Function(CrudActionCompleter completion) build,
  ) {
    final completion = CrudActionCompleter();
    context.read<TaskBloc>().add(build(completion));
    return completion.future;
  }

  /// For the ticks, which have no dialog: a failure goes to a snackbar.
  Future<void> dispatchTaskEvent(
    TaskEvent Function(CrudActionCompleter completion) build,
  ) async {
    final result = await sendTaskEvent(build);
    if (!mounted || result.isSuccess) return;
    _showError(result.message ?? 'הפעולה נכשלה. נסו שוב.');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
        ),
      );
  }

  Future<void> createStage(Event event, TeamMember user) {
    Logger.action('tap:stageAdd');
    return showStageFormModal(
      context,
      event: event,
      onSave: (stage) =>
          sendTaskEvent((completion) => CreateStage(stage, completion: completion)),
      currentUserId: user.id,
      now: actionTime,
    );
  }

  Future<void> editStage(Stage stage, Event event, TeamMember user) {
    Logger.action('tap:stageEdit');
    return showStageFormModal(
      context,
      existing: stage,
      event: event,
      onSave: (next) =>
          sendTaskEvent((completion) => UpdateStage(next, completion: completion)),
      currentUserId: user.id,
      now: actionTime,
    );
  }

  Future<void> importFromExcel(Event event, TeamMember user) async {
    Logger.action('tap:tasksImport');
    final file = await importFiles.pickXlsx();
    if (file == null || !mounted) return;
    final result = await showTaskImportDialog(
      context,
      file: file,
      event: event,
      files: importFiles,
      assignees: context.read<TaskRepository>().watchEventAssignees(event.id),
      onImport: (stages) => sendTaskEvent(
        (completion) => ImportStages(event.id, stages, completion: completion),
      ),
      currentUserId: user.id,
      now: actionTime,
    );
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          'יובאו ${result.stages.length} שלבים ו-${result.taskCount} משימות',
        ),
      ));
  }

  void downloadTemplate(Event event) {
    Logger.action('tap:tasksImportTemplate');
    importFiles.saveXlsx(
      buildTaskImportTemplate(event),
      taskImportTemplateFileName,
    );
  }

  Future<void> deleteStage(Stage stage, int taskCount) {
    Logger.action('tap:stageDelete', {'tasks': taskCount});
    final tasksLine = switch (taskCount) {
      0 => '',
      1 => ' תימחק גם המשימה שבו.',
      _ => ' יימחקו גם $taskCount המשימות שבו.',
    };
    return showConfirmDeleteDialog(
      context,
      title: 'מחיקת שלב',
      message: 'למחוק את השלב "${stage.title}"?$tasksLine לא ניתן לשחזר.',
      keyPrefix: 'stage-delete',
      onDelete: () =>
          sendTaskEvent((completion) => DeleteStage(stage.id, completion: completion)),
    );
  }

  Future<void> createTask(Event event, Stage stage, TeamMember user) {
    Logger.action('tap:taskAdd');
    return showTaskFormModal(
      context,
      event: event,
      stage: stage,
      watchEventAssignees: context.read<TaskRepository>().watchEventAssignees,
      onSave: (task) =>
          sendTaskEvent((completion) => CreateTask(task, completion: completion)),
      currentUserId: user.id,
      now: actionTime,
    );
  }

  Future<void> editTask(
    TaskItem existing,
    Event event,
    Stage stage,
    TeamMember user,
  ) {
    Logger.action('tap:taskEdit');
    return showTaskFormModal(
      context,
      existing: existing,
      event: event,
      stage: stage,
      watchEventAssignees: context.read<TaskRepository>().watchEventAssignees,
      onSave: (task) =>
          sendTaskEvent((completion) => UpdateTask(task, completion: completion)),
      currentUserId: user.id,
      now: actionTime,
    );
  }

  Future<void> deleteTask(TaskItem task) {
    Logger.action('tap:taskDelete');
    return showConfirmDeleteDialog(
      context,
      title: 'מחיקת משימה',
      message: 'למחוק את "${task.title}"? לא ניתן לשחזר.',
      keyPrefix: 'task-delete',
      onDelete: () =>
          sendTaskEvent((completion) => DeleteTask(task.id, completion: completion)),
    );
  }

  Future<void> editUpdate(TaskItem task) {
    Logger.action('tap:taskUpdate');
    return showAssigneeUpdateDialog(
      context,
      initialText: task.assigneeUpdate,
      onSave: (text) => sendTaskEvent(
        (completion) => SaveAssigneeUpdate(
          taskId: task.id,
          text: text,
          completion: completion,
        ),
      ),
    );
  }

  void toggleSubtask(TaskItem task, Subtask subtask, bool isDone) {
    Logger.action('toggle:subtask', {'on': isDone});
    dispatchTaskEvent(
      (completion) => ToggleSubtask(
        taskId: task.id,
        subtaskId: subtask.id,
        isDone: isDone,
        completion: completion,
      ),
    );
  }

  void setComplete(TaskItem task, bool isComplete) {
    Logger.action('toggle:taskComplete', {'on': isComplete});
    dispatchTaskEvent(
      (completion) => SetTaskComplete(
        taskId: task.id,
        isComplete: isComplete,
        completion: completion,
      ),
    );
  }

  Future<void> callPhone(String phone) async {
    Logger.action('tap:stageContactCall');
    final uri =
        Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[-\s()]'), ''));
    final launched = await canLaunchUrl(uri) && await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('טלפון: $phone')));
    }
  }
}
