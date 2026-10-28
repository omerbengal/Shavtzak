import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/services/task_import_files.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/task_import/task_import_parser.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/imported_stage.dart';
import '../../../../domain/entities/team_member.dart';

/// Shown when the browser could not hand over the picked file's contents.
const String importFileReadError =
    'לא ניתן היה לקרוא את הקובץ. אם הוא פתוח באקסל, סגרו אותו ונסו שוב.';

/// Checks [file] against [event] and, when it is clean, imports it.
///
/// The file is parsed here, once the members assigned to the event arrive
/// (names are matched against them). Any problem blocks the import; the
/// person fixes the file and picks it again from this dialog. The import
/// itself goes through [onImport]; the dialog stays open with a spinner until
/// it answers and returns the result on success.
Future<TaskImportResult?> showTaskImportDialog(
  BuildContext context, {
  required PickedImportFile file,
  required Event event,
  required TaskImportFiles files,
  required Stream<List<TeamMember>> assignees,
  required Future<CrudActionResult> Function(List<ImportedStage> stages)
      onImport,
  required String currentUserId,
  required DateTime now,
}) {
  return showDialog<TaskImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TaskImportDialog(
      file: file,
      event: event,
      files: files,
      assignees: assignees,
      onImport: onImport,
      currentUserId: currentUserId,
      now: now,
    ),
  );
}

class _TaskImportDialog extends StatefulWidget {
  const _TaskImportDialog({
    required this.file,
    required this.event,
    required this.files,
    required this.assignees,
    required this.onImport,
    required this.currentUserId,
    required this.now,
  });

  final PickedImportFile file;
  final Event event;
  final TaskImportFiles files;
  final Stream<List<TeamMember>> assignees;
  final Future<CrudActionResult> Function(List<ImportedStage> stages) onImport;
  final String currentUserId;
  final DateTime now;

  @override
  State<_TaskImportDialog> createState() => _TaskImportDialogState();
}

class _TaskImportDialogState extends State<_TaskImportDialog> {
  late PickedImportFile _file = widget.file;
  StreamSubscription<List<TeamMember>>? _subscription;
  List<TeamMember>? _members;
  bool _membersFailed = false;
  TaskImportResult? _result;
  bool _isImporting = false;
  String? _importError;

  // Once an import was sent, its ids stay fixed until another file is
  // picked: a retry of an import that did reach the backend must send the
  // same ids, so the backend can tell it is a replay.
  bool _wasSent = false;

  bool get _canImport =>
      !_isImporting && !_membersFailed && (_result?.isValid ?? false);

  @override
  void initState() {
    super.initState();
    _subscription = widget.assignees.listen(
      (members) {
        if (!mounted) return;
        setState(() {
          _members = members;
          _membersFailed = false;
          if (!_wasSent) _result = _parse();
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

  TaskImportResult? _parse() {
    final members = _members;
    if (members == null) return null;
    try {
      return parseTaskImport(
        _file.bytes,
        event: widget.event,
        candidates: members,
        currentUserId: widget.currentUserId,
        now: widget.now,
      );
    } catch (error) {
      // A file the parser did not expect must not leave the spinner up.
      Logger.warning('tasksImport:parseFailed', {'error': '$error'});
      return const TaskImportResult(
        stages: [],
        problems: [ImportProblem('לא ניתן היה לקרוא את הקובץ')],
      );
    }
  }

  Future<void> _pickAgain() async {
    PickedImportFile? picked;
    try {
      picked = await widget.files.pickXlsx();
    } catch (error) {
      Logger.warning('tasksImport:readFailed', {'error': '$error'});
      if (mounted) setState(() => _importError = importFileReadError);
      return;
    }
    final file = picked;
    if (file == null || !mounted) return;
    setState(() {
      _file = file;
      _importError = null;
      _wasSent = false;
      _result = _parse();
    });
  }

  Future<void> _import() async {
    final result = _result;
    if (!_canImport || result == null) return;
    setState(() {
      _isImporting = true;
      _wasSent = true;
      _importError = null;
    });
    final outcome = await widget.onImport(result.stages);
    if (!mounted) return;
    if (outcome.isSuccess) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _isImporting = false;
      _importError = outcome.message ?? 'הייבוא נכשל. נסו שוב.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: !_isImporting,
        child: Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                  child: Text('ייבוא מאקסל', style: theme.textTheme.titleLarge),
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
                    child: _buildContent(theme, result),
                  ),
                ),
                if (_importError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Text(
                      _importError!,
                      key: const Key('task-import-error'),
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
                        key: const Key('task-import-pick-again'),
                        onPressed: _isImporting ? null : _pickAgain,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('בחירת קובץ אחר'),
                      ),
                      TextButton(
                        key: const Key('task-import-cancel'),
                        onPressed: _isImporting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(
                          result?.isValid ?? false ? 'ביטול' : 'סגירה',
                        ),
                      ),
                      FilledButton(
                        key: const Key('task-import-confirm'),
                        onPressed: _canImport ? _import : null,
                        child: _isImporting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('ייבוא'),
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

  Widget _buildContent(ThemeData theme, TaskImportResult? result) {
    if (_membersFailed) {
      return Text(
        'טעינת המשובצים לאירוע נכשלה, ולכן לא ניתן לבדוק את האחראים. נסו שוב.',
        key: const Key('task-import-members-error'),
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.error),
      );
    }
    if (result == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (result.problems.isNotEmpty) {
      final count = result.problems.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 1 ? 'נמצאה בעיה אחת בקובץ' : 'נמצאו $count בעיות בקובץ',
            key: const Key('task-import-problem-count'),
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      result.problems[i].text,
                      key: Key('task-import-problem-$i'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'יש לתקן את הקובץ ולבחור אותו שוב. דבר לא נשמר.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey.shade700),
          ),
        ],
      );
    }
    final byId = {
      for (final imported in result.stages) imported.stage.id: imported
    };
    final ordered =
        sortStages([for (final imported in result.stages) imported.stage]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${result.stages.length} שלבים · ${result.taskCount} משימות · '
          '${result.contactCount} אנשי קשר',
          key: const Key('task-import-summary'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final stage in ordered)
          Padding(
            key: Key('task-import-stage-${stage.id}'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stage.title,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        stageSummaryLine(stage),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                Text('${byId[stage.id]!.tasks.length} משימות'),
              ],
            ),
          ),
      ],
    );
  }
}
