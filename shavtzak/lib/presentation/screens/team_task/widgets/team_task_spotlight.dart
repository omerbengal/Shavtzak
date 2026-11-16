import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../core/utils/team_task_spotlight.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';
import 'team_task_actions.dart';
import 'team_task_style.dart';

/// "זרקור" (Spotlight, Omer 16/11/2026): a quick pass over the viewer's tasks
/// in "המשימות שלי", one card at a time, the quietest first
/// ([spotlightQueue]). Each card shows where the task belongs, how long it
/// has been quiet and its last update, with four big actions: a short
/// update, "סיימתי", "לא עכשיו" and another status. ✕ leaves at any moment;
/// after the last card a summary closes the pass.
///
/// Opens over the screen with [taskIds] in order ([title] = what the pass
/// covers, e.g. a topic). Returns the ids it changed (closed or updated) so
/// the list can flash them on the way back.
Future<Set<String>> showTeamTaskSpotlight(
  BuildContext context, {
  required List<String> taskIds,
  String? title,
  DateTime Function()? clock,
}) async {
  final bloc = context.read<TeamTaskBloc>();
  final touched = await Navigator.of(context).push<Set<String>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: TeamTaskSpotlight(taskIds: taskIds, title: title, clock: clock),
      ),
    ),
  );
  return touched ?? const {};
}

/// The short updates one tap away (the "עדכון קצר" chips of the design).
const List<String> spotlightQuickUpdates = [
  'התקדמתי 👍',
  'מחכה למישהו ⏳',
  'תקוע 🧱',
  'כמעט גמור 🏁',
];

class TeamTaskSpotlight extends StatefulWidget {
  const TeamTaskSpotlight({super.key, required this.taskIds, this.title, this.clock});

  final List<String> taskIds;
  final String? title;
  final DateTime Function()? clock;

  @override
  State<TeamTaskSpotlight> createState() => _TeamTaskSpotlightState();
}

class _TeamTaskSpotlightState extends State<TeamTaskSpotlight> {
  int _index = 0;
  SpotlightTally _tally = const SpotlightTally();

  /// The short update field is open on the current card.
  bool _composing = false;

  /// An action of the current card is on its way to the backend.
  bool _busy = false;

  final TextEditingController _update = TextEditingController();
  final FocusNode _updateFocus = FocusNode();

  int get _total => widget.taskIds.length;
  bool get _finished => _index >= _total;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void dispose() {
    _update.dispose();
    _updateFocus.dispose();
    super.dispose();
  }

  void _leave() {
    Logger.action('tap:spotlightClose', {'at': _index, 'of': _total});
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    Navigator.of(context).pop(_tally.touched);
  }

  void _next() {
    setState(() {
      _index++;
      _composing = false;
      _update.clear();
    });
  }

  void _skip(String id) {
    Logger.action('tap:spotlightSkip');
    setState(() => _tally = _tally.skip(id));
    _next();
  }

  void _openComposer() {
    Logger.action('tap:spotlightCompose');
    setState(() => _composing = true);
    _updateFocus.requestFocus();
  }

  void _pickQuick(String text) {
    Logger.action('tap:spotlightQuickUpdate', {'text': text});
    final current = _update.text.trim();
    _update.text = current.isEmpty ? '$text ' : '$text $current';
    _update.selection = TextSelection.collapsed(offset: _update.text.length);
    _updateFocus.requestFocus();
  }

  Future<CrudActionResult> _await(CrudActionCompleter completion) async {
    setState(() => _busy = true);
    final result = await completion.future;
    if (mounted) setState(() => _busy = false);
    return result;
  }

  void _failed(CrudActionResult result) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')),
    );
  }

  Future<void> _send(TeamTask task) async {
    final text = _update.text.trim();
    if (text.isEmpty) return;
    Logger.action('tap:spotlightSend');
    final completion = CrudActionCompleter();
    context.read<TeamTaskBloc>().add(task.isSubtask
        ? AddTeamTaskUpdate(task.parentId!, text, subtaskId: task.id, completion: completion)
        : AddTeamTaskUpdate(task.id, text, completion: completion));
    final result = await _await(completion);
    if (!mounted) return;
    if (!result.isSuccess) return _failed(result);
    setState(() => _tally = _tally.update(task.id));
    _next();
  }

  Future<bool> _setStatus(TeamTask task, TeamTaskStatus status, {String? original}) async {
    final completion = CrudActionCompleter();
    context.read<TeamTaskBloc>().add(task.isSubtask
        ? SetTeamTaskStatus(task.parentId!, status,
            subtaskId: task.id, duplicateOfId: original, completion: completion)
        : SetTeamTaskStatus(task.id, status, duplicateOfId: original, completion: completion));
    final result = await _await(completion);
    if (!mounted) return false;
    if (!result.isSuccess) _failed(result);
    return result.isSuccess;
  }

  /// "סיימתי" or a status from the menu. Closing it (done, cancelled,
  /// duplicate) moves on with a "ביטול" that puts the old status back and
  /// returns to the card; "פתוחה" / "בטיפול" stays on the card.
  Future<void> _changeStatus(TeamTask task, TeamTaskStatus status) async {
    if (status == task.status) return;
    Logger.action('tap:spotlightStatus', {'status': status.key});
    String? original;
    if (status == TeamTaskStatus.duplicate) {
      final state = context.read<TeamTaskBloc>().state;
      if (state is! TeamTasksLoaded) return;
      original = await pickDuplicateOriginal(context, state, task);
      if (original == null || !mounted) return;
    }
    final previous = task.status;
    final at = _index;
    if (!await _setStatus(task, status, original: original) || !mounted) return;
    if (status.isActive) return;
    setState(() => _tally = _tally.close(task.id));
    _next();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      key: const Key('spotlight-undo-bar'),
      duration: const Duration(seconds: 4),
      content: Text(status == TeamTaskStatus.done
          ? 'סומנה כבוצעה'
          : 'סומנה כ"${status.hebrewLabel}"'),
      action: SnackBarAction(
        key: const Key('spotlight-undo'),
        label: 'ביטול',
        onPressed: () async {
          Logger.action('tap:spotlightUndo');
          if (!mounted) return;
          final current = context.read<TeamTaskBloc>().state;
          final now = current is TeamTasksLoaded ? current.taskById(task.id) : null;
          if (now == null || !await _setStatus(now, previous) || !mounted) return;
          setState(() {
            _tally = _tally.reopen(task.id);
            _index = at;
            _composing = false;
          });
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.title == null ? 'זרקור' : 'זרקור · ${widget.title}';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: const Key('spotlight-screen'),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const Key('spotlight-close'),
            tooltip: 'יציאה מהזרקור',
            icon: const Icon(Icons.close),
            onPressed: _leave,
          ),
          title: Text(label, overflow: TextOverflow.ellipsis),
          actions: [
            if (!_finished)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: Center(
                  child: Text(
                    '${_index + 1} מתוך $_total',
                    key: const Key('spotlight-counter'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            LinearProgressIndicator(
              key: const Key('spotlight-progress'),
              value: _total == 0 ? 1 : _index / _total,
              minHeight: 4,
              backgroundColor: TaskStyle.rest,
              color: TaskStyle.done,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: TeamTaskStyle.maxListWidth),
                  child: _finished ? _summary() : _current(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _current() {
    return BlocBuilder<TeamTaskBloc, TeamTaskState>(
      builder: (context, state) {
        final id = widget.taskIds[_index];
        final task = state is TeamTasksLoaded ? state.taskById(id) : null;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey('spotlight-$_index-$id'),
            child: task == null ? _gone(id) : _page(task),
          ),
        );
      },
    );
  }

  /// The task left the viewer's list meanwhile (deleted, given to another).
  Widget _gone(String id) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('המשימה הזו כבר לא ברשימה שלך',
              style: TextStyle(color: TaskStyle.neutralText)),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('spotlight-gone-next'),
            onPressed: () => _skip(id),
            child: const Text('הבאה'),
          ),
        ],
      ),
    );
  }

  Widget _page(TeamTask task) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _card(task),
        const SizedBox(height: 16),
        if (_composing) _composer(task) else _actions(task),
      ],
    );
  }

  Widget _card(TeamTask task) {
    final now = _now;
    final quiet = teamTaskQuietDays(task, now);
    final isQuiet = quiet == null || quiet >= spotlightQuietDays;
    final last = task.updates.isEmpty ? null : task.updates.first;
    final deadline = task.deadlineDate;
    final late = isTeamTaskLate(task, now);
    final owners = teamTaskOwnerChips(task);
    final linkKind = switch (task.link?.type) {
      TaskLinkType.event => 'אירוע · ',
      TaskLinkType.category => 'קטגוריה · ',
      TaskLinkType.topic => 'נושא · ',
      null => '',
    };
    return Container(
      key: Key('spotlight-card-${task.id}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TaskStyle.stageCard,
        border: Border.all(color: TaskStyle.stageCardBorder),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x1A0A1E3C), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: TaskStyle.stageHeader,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$linkKind${teamTaskLinkLabel(task)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: TaskStyle.rowMetaSize,
                      fontWeight: FontWeight.w700,
                      color: TaskStyle.neutralText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: Key('spotlight-quiet-${task.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isQuiet ? TaskStyle.soonLight : TaskStyle.chip,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    teamTaskQuietLabel(task, now),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isQuiet ? TaskStyle.soonDark : TaskStyle.neutralText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.isSubtask)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      task.parentTitle ?? '',
                      style: const TextStyle(
                        fontSize: TaskStyle.rowMetaSize,
                        color: TaskStyle.neutralText,
                      ),
                    ),
                  ),
                Text(
                  task.title,
                  key: Key('spotlight-title-${task.id}'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TeamTaskStatusChip(status: task.status, dense: true),
                    if (deadline != null)
                      Text(
                        late ? 'באיחור · עד ${shortDate(deadline)}' : 'עד ${shortDate(deadline)}',
                        style: TextStyle(
                          fontSize: TaskStyle.rowMetaSize,
                          color: late ? TaskStyle.late : TaskStyle.neutralText,
                          fontWeight: late ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    for (final owner in owners)
                      MemberInitialsAvatar(
                        memberId: owner.id,
                        name: owner.name,
                        highlight: owner.id == _viewerId(),
                        size: TeamTaskStyle.avatarSize,
                      ),
                  ],
                ),
                if (task.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    task.description.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: TaskStyle.neutralText),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  key: Key('spotlight-last-${task.id}'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TaskStyle.updateBox,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: last == null
                      ? const Text('אין עדכון עדיין', style: TextStyle(color: TaskStyle.faintText))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'עדכון אחרון · ${last.byName ?? unknownMemberLabel} · ${logStamp(last.at)}',
                              style: const TextStyle(fontSize: 12, color: TaskStyle.faintText),
                            ),
                            const SizedBox(height: 2),
                            Text(last.text, maxLines: 5, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _viewerId() {
    final state = context.read<TeamTaskBloc>().state;
    return state is TeamTasksLoaded ? state.viewer.id : null;
  }

  Widget _bigButton({
    required Key key,
    required String label,
    IconData? icon,
    required Color background,
    required Color foreground,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        onPressed: _busy ? null : onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 6)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _actions(TeamTask task) {
    const gap = SizedBox(width: 8);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _bigButton(
                key: const Key('spotlight-update'),
                label: 'עדכון קצר',
                icon: Icons.add_comment_outlined,
                background: TaskStyle.currentLight,
                foreground: TaskStyle.mine,
                onPressed: _openComposer,
              ),
            ),
            gap,
            Expanded(
              child: _bigButton(
                key: const Key('spotlight-done'),
                label: 'סיימתי',
                icon: Icons.check,
                background: TaskStyle.doneLight,
                foreground: TaskStyle.doneDark,
                onPressed: () => _changeStatus(task, TeamTaskStatus.done),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _bigButton(
                key: const Key('spotlight-skip'),
                label: 'לא עכשיו',
                icon: Icons.schedule,
                background: TaskStyle.chip,
                foreground: TaskStyle.neutralText,
                onPressed: () => _skip(task.id),
              ),
            ),
            gap,
            Expanded(
              child: PopupMenuButton<TeamTaskStatus>(
                key: const Key('spotlight-status'),
                tooltip: 'שינוי סטטוס',
                enabled: !_busy,
                onSelected: (status) => _changeStatus(task, status),
                itemBuilder: (context) => teamTaskStatusMenuItems(),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: TaskStyle.chip,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TeamTaskStatusIcon(status: task.status, size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        'סטטוס',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: TaskStyle.neutralText,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: TaskStyle.neutralText),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SizedBox(
              key: Key('spotlight-busy'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  Widget _composer(TeamTask task) {
    return Column(
      key: const Key('spotlight-composer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < spotlightQuickUpdates.length; i++)
              ActionChip(
                key: Key('spotlight-chip-$i'),
                label: Text(spotlightQuickUpdates[i]),
                backgroundColor: TaskStyle.stageCard,
                side: const BorderSide(color: TaskStyle.stageCardBorder),
                onPressed: _busy ? null : () => _pickQuick(spotlightQuickUpdates[i]),
              ),
          ],
        ),
        const SizedBox(height: 10),
        RtlArrowKeys(
          multiline: true,
          child: TextField(
            key: const Key('spotlight-update-field'),
            controller: _update,
            focusNode: _updateFocus,
            readOnly: _busy,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'מה קרה במשימה?',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _update,
                builder: (context, value, _) => _bigButton(
                  key: const Key('spotlight-send'),
                  label: 'שליחה והבאה',
                  icon: Icons.send,
                  background: TaskStyle.mine,
                  foreground: Colors.white,
                  onPressed: value.text.trim().isEmpty ? null : () => _send(task),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('spotlight-compose-cancel'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _composing = false;
                        _update.clear();
                      }),
              child: const Text('ביטול'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summary() {
    final allClear = _tally.skipped.isEmpty && _total > 0;
    return Padding(
      key: const Key('spotlight-summary'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(allClear ? '🎉' : '👏', style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          Text(
            _total == 1 ? 'עברת על משימה אחת' : 'עברת על $_total משימות',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            _tally.summary,
            key: const Key('spotlight-tally'),
            style: const TextStyle(fontSize: 15, color: TaskStyle.neutralText),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('spotlight-finish'),
            onPressed: () {
              Logger.action('tap:spotlightFinish');
              ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
              Navigator.of(context).pop(_tally.touched);
            },
            child: const Text('חזרה לרשימה'),
          ),
        ],
      ),
    );
  }
}
