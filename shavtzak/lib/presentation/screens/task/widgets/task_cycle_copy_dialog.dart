import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/task_cycle_copy.dart';
import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/imported_stage.dart';
import '../../../../domain/entities/team_member.dart';

/// "העתקה ממחזור קודם": pick an earlier event ([sources], latest first),
/// see what the copy brings, and save it through [onImport]. Returns the
/// copy on success.
Future<CycleCopy?> showTaskCycleCopyDialog(
  BuildContext context, {
  required Event target,
  required List<EventTaskBoard> sources,
  required Stream<List<TeamMember>> assignees,
  required TeamMember currentUser,
  required DateTime now,
  required Future<CrudActionResult> Function(List<ImportedStage> stages)
      onImport,
}) {
  return showDialog<CycleCopy>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CycleCopyDialog(
      target: target,
      sources: sources,
      assignees: assignees,
      currentUser: currentUser,
      now: now,
      onImport: onImport,
    ),
  );
}

class _CycleCopyDialog extends StatefulWidget {
  const _CycleCopyDialog({
    required this.target,
    required this.sources,
    required this.assignees,
    required this.currentUser,
    required this.now,
    required this.onImport,
  });

  final Event target;
  final List<EventTaskBoard> sources;
  final Stream<List<TeamMember>> assignees;
  final TeamMember currentUser;
  final DateTime now;
  final Future<CrudActionResult> Function(List<ImportedStage> stages) onImport;

  @override
  State<_CycleCopyDialog> createState() => _CycleCopyDialogState();
}

class _CycleCopyDialogState extends State<_CycleCopyDialog> {
  StreamSubscription<List<TeamMember>>? _subscription;
  List<TeamMember>? _members;
  bool _membersFailed = false;
  EventTaskBoard? _source;
  CycleCopy? _copy;
  bool _isSaving = false;
  String? _error;

  // Once a copy was sent its ids stay fixed, so a retry of a call that did
  // reach the backend is recognised as a replay.
  bool _wasSent = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.assignees.listen(
      (members) {
        if (!mounted) return;
        setState(() {
          _members = members;
          _membersFailed = false;
          if (!_wasSent) _copy = _build();
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

  CycleCopy? _build() {
    final source = _source;
    final members = _members;
    if (source == null || members == null) return null;
    return copyCycle(
      source,
      target: widget.target,
      members: members,
      currentUser: widget.currentUser,
      now: widget.now,
    );
  }

  void _pick(EventTaskBoard? source) => setState(() {
        _source = source;
        _wasSent = false;
        _error = null;
        _copy = _build();
      });

  Future<void> _save() async {
    final copy = _copy;
    if (copy == null || _isSaving) return;
    setState(() {
      _isSaving = true;
      _wasSent = true;
      _error = null;
    });
    final outcome = await widget.onImport(copy.stages);
    if (!mounted) return;
    if (outcome.isSuccess) {
      Navigator.of(context).pop(copy);
      return;
    }
    setState(() {
      _isSaving = false;
      _error = outcome.message ?? 'ההעתקה נכשלה. נסו שוב.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picking = _source == null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: !_isSaving,
        child: Dialog(
          key: const Key('cycle-copy-dialog'),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                  child: Text('העתקה ממחזור קודם',
                      style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    picking
                        ? 'מאיזה מחזור להעתיק את השלבים והמשימות?'
                        : 'מ"${_source!.event.name}" אל "${widget.target.name}"',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: picking ? _buildSources(theme) : _buildPreview(theme),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Text(
                      _error!,
                      key: const Key('cycle-copy-error'),
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
                      if (!picking)
                        TextButton(
                          key: const Key('cycle-copy-back'),
                          onPressed: _isSaving ? null : () => _pick(null),
                          child: const Text('מחזור אחר'),
                        ),
                      TextButton(
                        key: const Key('cycle-copy-cancel'),
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('ביטול'),
                      ),
                      if (!picking)
                        FilledButton(
                          key: const Key('cycle-copy-confirm'),
                          onPressed:
                              _copy == null || _isSaving ? null : _save,
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('העתקה'),
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

  Widget _buildSources(ThemeData theme) {
    if (widget.sources.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'אין מחזור קודם עם שלבים להעתקה.',
          key: Key('cycle-copy-none'),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final source in widget.sources)
          ListTile(
            key: Key('cycle-copy-source-${source.event.id}'),
            title: Text(source.event.name),
            subtitle: Text(
              '${eventDaysLabel(source.event)} · '
              '${source.stages.length} שלבים · ${source.tasks.length} משימות',
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => _pick(source),
          ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    if (_membersFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'טעינת המשובצים לאירוע נכשלה, ולכן לא ניתן לשבץ אחראים. נסו שוב.',
          key: const Key('cycle-copy-members-error'),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.error),
        ),
      );
    }
    final copy = _copy;
    if (copy == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final mine = copy.givenToYou;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${copy.stages.length} שלבים · ${copy.taskCount} משימות',
            key: const Key('cycle-copy-summary'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'כל שלב עובר ליום המקביל במחזור החדש (יום ראשון ליום ראשון, וכן '
            'הלאה), עם השעות, הפרטים, אנשי הקשר והמשימות. שום דבר לא מסומן '
            'כבוצע.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey.shade700),
          ),
          if (copy.movedToLastDay > 0) ...[
            const SizedBox(height: 8),
            _note(
              theme,
              key: const Key('cycle-copy-last-day'),
              text: copy.movedToLastDay == 1
                  ? 'המחזור החדש קצר יותר: שלב אחד הועבר ליום האחרון שלו.'
                  : 'המחזור החדש קצר יותר: ${copy.movedToLastDay} שלבים '
                      'הועברו ליום האחרון שלו.',
            ),
          ],
          if (mine.isNotEmpty) ...[
            const SizedBox(height: 8),
            _note(
              theme,
              key: const Key('cycle-copy-given-to-you'),
              text: mine.length == 1
                  ? 'למשימה אחת אין אחראי ששובץ למחזור החדש, ולכן היא תשובץ על '
                      'שמך. אפשר להחליף אחר כך ב"עריכה":'
                  : 'ל-${mine.length} משימות אין אחראי ששובץ למחזור החדש, '
                      'ולכן הן ישובצו על שמך. אפשר להחליף אחר כך ב"עריכה":',
            ),
            const SizedBox(height: 4),
            for (final task in mine)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 26, top: 2),
                child: Text('• ${task.title}',
                    style: theme.textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }

  Widget _note(ThemeData theme, {required Key key, required String text}) {
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
