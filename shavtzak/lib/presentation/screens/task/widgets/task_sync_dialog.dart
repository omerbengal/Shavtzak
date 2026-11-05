import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/services/task_import_files.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/task_import/task_import_diff.dart';
import '../../../../core/utils/task_import/task_import_parser.dart';
import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../domain/entities/stage_sync_plan.dart';
import '../../../../domain/entities/team_member.dart';
import 'task_import_dialog.dart';

/// Reads an updated import file for an event that already has stages, shows
/// what it would add, remove and change, and on confirm saves exactly that.
///
/// [board] is the event as it was when the file was picked; the difference
/// is worked out against it. The save goes through [onSync]; the dialog
/// stays open with a spinner until it answers and returns the difference on
/// success.
Future<TaskImportDiff?> showTaskSyncDialog(
  BuildContext context, {
  required PickedImportFile file,
  required EventTaskBoard board,
  required TaskImportFiles files,
  required Stream<List<TeamMember>> assignees,
  required Future<CrudActionResult> Function(StageSyncPlan plan) onSync,
  required String currentUserId,
  required DateTime now,
}) {
  return showDialog<TaskImportDiff>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TaskSyncDialog(
      file: file,
      board: board,
      files: files,
      assignees: assignees,
      onSync: onSync,
      currentUserId: currentUserId,
      now: now,
    ),
  );
}

class _TaskSyncDialog extends StatefulWidget {
  const _TaskSyncDialog({
    required this.file,
    required this.board,
    required this.files,
    required this.assignees,
    required this.onSync,
    required this.currentUserId,
    required this.now,
  });

  final PickedImportFile file;
  final EventTaskBoard board;
  final TaskImportFiles files;
  final Stream<List<TeamMember>> assignees;
  final Future<CrudActionResult> Function(StageSyncPlan plan) onSync;
  final String currentUserId;
  final DateTime now;

  @override
  State<_TaskSyncDialog> createState() => _TaskSyncDialogState();
}

class _Reading {
  const _Reading(this.problems, this.diff);

  final List<ImportProblem> problems;
  final TaskImportDiff? diff;
}

class _TaskSyncDialogState extends State<_TaskSyncDialog> {
  late PickedImportFile _file = widget.file;
  StreamSubscription<List<TeamMember>>? _subscription;
  List<TeamMember>? _members;
  bool _membersFailed = false;
  _Reading? _reading;
  bool _isSaving = false;
  String? _saveError;

  // Once sent, the new ids stay fixed until another file is picked, so a
  // retry of a save that did reach the backend is recognised as a replay.
  bool _wasSent = false;

  TaskImportDiff? get _diff => _reading?.diff;

  bool get _canSave =>
      !_isSaving && !_membersFailed && (_diff?.hasChanges ?? false);

  @override
  void initState() {
    super.initState();
    _subscription = widget.assignees.listen(
      (members) {
        if (!mounted) return;
        setState(() {
          _members = members;
          _membersFailed = false;
          if (!_wasSent) _reading = _read();
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _membersFailed = true);
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  _Reading? _read() {
    final members = _members;
    if (members == null) return null;
    try {
      final result = parseTaskImport(
        _file.bytes,
        event: widget.board.event,
        candidates: members,
        currentUserId: widget.currentUserId,
        now: widget.now,
      );
      if (!result.isValid) return _Reading(result.problems, null);
      return _Reading(const [], diffTaskImport(widget.board, result.stages));
    } catch (error) {
      Logger.warning('tasksSync:parseFailed', {'error': '$error'});
      return const _Reading([ImportProblem('לא ניתן היה לקרוא את הקובץ')], null);
    }
  }

  Future<void> _pickAgain() async {
    PickedImportFile? picked;
    try {
      picked = await widget.files.pickXlsx();
    } catch (error) {
      Logger.warning('tasksSync:readFailed', {'error': '$error'});
      if (mounted) setState(() => _saveError = importFileReadError);
      return;
    }
    final file = picked;
    if (file == null || !mounted) return;
    setState(() {
      _file = file;
      _saveError = null;
      _wasSent = false;
      _reading = _read();
    });
  }

  Future<void> _save() async {
    final diff = _diff;
    if (!_canSave || diff == null) return;
    setState(() {
      _isSaving = true;
      _wasSent = true;
      _saveError = null;
    });
    final outcome = await widget.onSync(diff.plan);
    if (!mounted) return;
    if (outcome.isSuccess) {
      Navigator.of(context).pop(diff);
      return;
    }
    setState(() {
      _isSaving = false;
      _saveError = outcome.message ?? 'העדכון נכשל. נסו שוב.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: !_isSaving,
        child: Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                  child: Text('עדכון מאקסל', style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _file.name,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: _buildContent(theme),
                  ),
                ),
                if (_saveError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Text(
                      _saveError!,
                      key: const Key('task-sync-error'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        key: const Key('task-sync-pick-again'),
                        onPressed: _isSaving ? null : _pickAgain,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('בחירת קובץ אחר'),
                      ),
                      TextButton(
                        key: const Key('task-sync-cancel'),
                        onPressed:
                            _isSaving ? null : () => Navigator.of(context).pop(),
                        child: Text(_canSave ? 'ביטול' : 'סגירה'),
                      ),
                      FilledButton(
                        key: const Key('task-sync-confirm'),
                        onPressed: _canSave ? _save : null,
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('עדכון'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_membersFailed) {
      return Text(
        'טעינת המשובצים לאירוע נכשלה, ולכן לא ניתן לבדוק את האחראים. נסו שוב.',
        key: const Key('task-sync-members-error'),
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.error),
      );
    }
    final reading = _reading;
    if (reading == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (reading.problems.isNotEmpty) return ImportProblemsView(reading.problems);
    final diff = reading.diff!;
    if (!diff.hasChanges) {
      return Text(
        'הקובץ זהה לשלבים ולמשימות שבאירוע. אין מה לעדכן.',
        key: const Key('task-sync-no-changes'),
        style: theme.textTheme.bodyLarge,
      );
    }
    return TaskDiffView(diff);
  }
}

/// The difference itself: counts, a warning when progress would be lost,
/// then each stage that changes with its tasks that change.
class TaskDiffView extends StatelessWidget {
  const TaskDiffView(this.diff, {super.key});

  final TaskImportDiff diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = diff.stages.where((stage) => stage.hasChanges).toList();
    final quietStages = diff.stages.length - changed.length;
    final lost = diff.lostProgressCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _countsLine('שלבים', [
            (diff.stageCount(ChangeKind.added), 'חדשים', 'חדש'),
            (diff.stageCount(ChangeKind.removed), 'נמחקים', 'נמחק'),
            (diff.stageCount(ChangeKind.changed), 'משתנים', 'משתנה'),
          ]),
          key: const Key('task-sync-stage-counts'),
          style: theme.textTheme.titleSmall,
        ),
        Text(
          _countsLine('משימות', [
            (diff.taskCount(ChangeKind.added), 'חדשות', 'חדשה'),
            (diff.taskCount(ChangeKind.removed), 'נמחקות', 'נמחקת'),
            (diff.taskCount(ChangeKind.changed), 'משתנות', 'משתנה'),
            (diff.movedTaskCount, 'עוברות שלב', 'עוברת שלב'),
          ]),
          key: const Key('task-sync-task-counts'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'סימוני הביצוע ועדכוני האחראים נשמרים בכל משימה שנשארת.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
        ),
        if (lost > 0) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('task-sync-lost-warning'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lost == 1
                        ? 'שינוי אחד מוחק התקדמות שכבר סומנה (מסומן למטה).'
                        : '$lost שינויים מוחקים התקדמות שכבר סומנה (מסומנים למטה).',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final stage in changed) _StageBlock(stage),
        if (quietStages > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              quietStages == 1
                  ? 'ועוד שלב אחד ללא שינוי'
                  : 'ועוד $quietStages שלבים ללא שינוי',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade700),
            ),
          ),
      ],
    );
  }
}

String _countsLine(String what, List<(int, String, String)> parts) {
  final shown = [
    for (final (count, many, one) in parts)
      if (count > 0) count == 1 ? '1 $one' : '$count $many',
  ];
  return '$what: ${shown.isEmpty ? 'ללא שינוי' : shown.join(' · ')}';
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

_Badge? _stageBadge(ChangeKind kind) => switch (kind) {
      ChangeKind.added => _Badge('חדש', Colors.green.shade700),
      ChangeKind.removed => _Badge('נמחק', Colors.red.shade700),
      ChangeKind.changed => _Badge('משתנה', Colors.blue.shade700),
      ChangeKind.unchanged => null,
    };

_Badge _taskBadge(TaskChange task) {
  if (task.movedFrom != null) return _Badge('עוברת שלב', Colors.purple.shade700);
  return switch (task.kind) {
    ChangeKind.added => _Badge('חדשה', Colors.green.shade700),
    ChangeKind.removed => _Badge('נמחקת', Colors.red.shade700),
    _ => _Badge('משתנה', Colors.blue.shade700),
  };
}

class _StageBlock extends StatelessWidget {
  const _StageBlock(this.change);

  final StageChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = change.stage;
    final badge = _stageBadge(change.kind);
    final shownTasks =
        change.tasks.where((task) => task.kind != ChangeKind.unchanged).toList();
    final quietTasks = change.tasks.length - shownTasks.length;
    return Container(
      key: Key('task-sync-stage-${stage.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stage.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: change.kind == ChangeKind.removed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              if (badge != null) badge,
            ],
          ),
          Text(
            stageSummaryLine(stage),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey.shade700),
          ),
          for (final field in change.fields) _FieldLine(field),
          if (change.kind == ChangeKind.removed && change.tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'יחד עם המשימות שבו:',
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (final task in shownTasks) _TaskLine(task),
          if (quietTasks > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                quietTasks == 1
                    ? 'ועוד משימה אחת ללא שינוי'
                    : 'ועוד $quietTasks משימות ללא שינוי',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine(this.change);

  final TaskChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final warnings = change.lostProgress;
    // The subtask lists are shown as added / removed lines, not in full.
    final fields = change.fields
        .where((field) => field.label != TaskColumns.subtasks)
        .toList();
    final reordered = change.fields.any((f) => f.label == TaskColumns.subtasks) &&
        change.addedSubtasks.isEmpty &&
        change.removedSubtasks.isEmpty;
    return Padding(
      key: Key('task-sync-task-${(change.after ?? change.before)!.id}'),
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _taskBadge(change),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  change.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    decoration: change.kind == ChangeKind.removed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (change.movedFrom != null)
            Text('מהשלב "${change.movedFrom}"', style: small),
          for (final field in fields) _FieldLine(field),
          for (final title in change.addedSubtasks)
            Text('+ תת משימה: $title',
                style: small?.copyWith(color: Colors.green.shade800)),
          for (final subtask in change.removedSubtasks)
            Text('− תת משימה: ${subtask.title}',
                style: small?.copyWith(color: Colors.red.shade800)),
          if (reordered) Text('סדר תתי המשימות משתנה', style: small),
          for (final warning in warnings)
            Row(
              children: [
                Icon(Icons.warning_amber,
                    size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'יימחק: $warning',
                    style: small?.copyWith(color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "label: before ← after", or on separate lines when either is long.
class _FieldLine extends StatelessWidget {
  const _FieldLine(this.field);

  final FieldChange field;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final before = field.before.isEmpty ? '(ריק)' : field.before;
    final after = field.after.isEmpty ? '(ריק)' : field.after;
    final long = before.length + after.length > 50 ||
        before.contains('\n') ||
        after.contains('\n');
    if (!long) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('${field.label}: $before ← $after', style: small),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${field.label}:',
              style: small?.copyWith(fontWeight: FontWeight.w600)),
          Text('היה: $before',
              style: small?.copyWith(color: Colors.red.shade800)),
          Text('יהיה: $after',
              style: small?.copyWith(color: Colors.green.shade800)),
        ],
      ),
    );
  }
}
