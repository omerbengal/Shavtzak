import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';
import '../../task/widgets/confirm_delete_dialog.dart';
import 'team_task_mentions.dart';
import 'team_task_style.dart';

/// A task's update log: the field for a new update (when [canWrite]) and
/// every past update, newest first. Used by the task screen and by the quick
/// update card of "המשימות שלי" (Omer, round 5).
///
/// Round 10: each update has a ⋯ menu (עריכה / מחיקה) for its writer; with
/// [canEditAll] (a manager in "כל המשימות") for every update, also the ones
/// with no writer ("מהאקסל"). In "המשימות שלי" a manager is a member like
/// any other: only their own.
class TeamTaskUpdateLog extends StatefulWidget {
  const TeamTaskUpdateLog({
    super.key,
    required this.task,
    required this.canWrite,
    this.canEditAll = false,
  });

  final TeamTask task;
  final bool canWrite;
  final bool canEditAll;

  @override
  State<TeamTaskUpdateLog> createState() => _TeamTaskUpdateLogState();
}

class _TeamTaskUpdateLogState extends State<TeamTaskUpdateLog> {
  /// Colours a picked name while the update is written (msg 5298).
  final MentionTextEditingController _update = MentionTextEditingController();
  final FocusNode _updateFocus = FocusNode();
  bool _sending = false;

  /// The "@" list opens above the field (Omer, msg 5298), in the overlay so
  /// the field does not move.
  final OverlayPortalController _suggestions = OverlayPortalController();
  final LayerLink _fieldLink = LayerLink();

  @override
  void initState() {
    super.initState();
    // Always shown: it draws nothing while there is no "@" query.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _suggestions.show();
    });
  }

  /// The members picked from the "@" list for the update being written,
  /// name → id (19/11/2026).
  final Map<String, String> _picked = {};

  /// The update being edited in place, and its draft.
  String? _editingId;
  final TextEditingController _edit = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _update.dispose();
    _updateFocus.dispose();
    _edit.dispose();
    super.dispose();
  }

  bool _canChange(TaskUpdateEntry entry, String viewerId) =>
      widget.canEditAll || (entry.byId.isNotEmpty && entry.byId == viewerId);

  void _startEdit(TaskUpdateEntry entry) {
    _edit.text = entry.text;
    setState(() => _editingId = entry.id);
  }

  Future<void> _saveEdit(TaskUpdateEntry entry) async {
    final text = _edit.text.trim();
    if (text.isEmpty) return;
    if (text == entry.text) {
      setState(() => _editingId = null);
      return;
    }
    final task = widget.task;
    final completion = CrudActionCompleter();
    setState(() => _saving = true);
    context
        .read<TeamTaskBloc>()
        .add(EditTeamTaskUpdate(task.id, entry.id, text, completion: completion));
    final result = await completion.future;
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.isSuccess) _editingId = null;
    });
    if (result.isFailure) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')),
      );
    }
  }

  Future<void> _delete(TaskUpdateEntry entry) {
    final task = widget.task;
    final bloc = context.read<TeamTaskBloc>();
    return showConfirmDeleteDialog(
      context,
      title: 'מחיקת עדכון',
      message: 'למחוק את העדכון "${entry.text}"?',
      keyPrefix: 'team-task-log-delete',
      onDelete: () {
        final completion = CrudActionCompleter();
        bloc.add(DeleteTeamTaskUpdate(task.id, entry.id, completion: completion));
        return completion.future;
      },
    );
  }

  Widget _entryMenu(TaskUpdateEntry entry) {
    return SizedBox(
      width: 28,
      height: 24,
      child: PopupMenuButton<String>(
        key: Key('team-task-log-menu-${entry.id}'),
        tooltip: 'עוד',
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: const Icon(Icons.more_horiz, color: TaskStyle.faintText),
        onSelected: (value) {
          if (value == 'edit') _startEdit(entry);
          if (value == 'delete') _delete(entry);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            key: Key('team-task-log-edit'),
            value: 'edit',
            child: Text('עריכה'),
          ),
          PopupMenuItem(
            key: Key('team-task-log-delete'),
            value: 'delete',
            child: Text('מחיקה'),
          ),
        ],
      ),
    );
  }

  Widget _editor(TaskUpdateEntry entry) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: RtlArrowKeys(
            multiline: true,
            child: TextField(
              key: const Key('team-task-log-edit-field'),
              controller: _edit,
              autofocus: true,
              readOnly: _saving,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('team-task-log-edit-cancel'),
          tooltip: 'ביטול',
          visualDensity: VisualDensity.compact,
          onPressed: _saving ? null : () => setState(() => _editingId = null),
          icon: const Icon(Icons.close, size: 18),
        ),
        IconButton(
          key: const Key('team-task-log-edit-save'),
          tooltip: 'שמירה',
          visualDensity: VisualDensity.compact,
          onPressed: _saving ? null : () => _saveEdit(entry),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
        ),
      ],
    );
  }

  /// The "@" query the caret is in, or null.
  ({int start, String query})? get _mentionQuery {
    final selection = _update.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    return activeMentionQuery(_update.text, selection.baseOffset);
  }

  /// [member] picked from the "@" list: "@<name> " in place of the query.
  void _pickMention(TeamMember member, ({int start, String query}) at) {
    Logger.action('tap:teamTaskMention', {'memberId': member.id});
    final text = _update.text;
    final insert = '@${member.name} ';
    final end = at.start + 1 + at.query.length;
    _update.value = TextEditingValue(
      text: text.replaceRange(at.start, end, insert),
      selection: TextSelection.collapsed(offset: at.start + insert.length),
    );
    setState(() {
      _picked[member.name] = member.id;
      _update.picked.add(member.name);
    });
    _updateFocus.requestFocus();
  }

  Future<void> _send() async {
    final task = widget.task;
    final text = _update.text.trim();
    if (text.isEmpty) return;
    final completion = CrudActionCompleter();
    setState(() => _sending = true);
    context.read<TeamTaskBloc>().add(AddTeamTaskUpdate(task.id, text,
        mentionIds: mentionIdsInText(text, _picked), completion: completion));
    final result = await completion.future;
    if (!mounted) return;
    setState(() => _sending = false);
    if (result.isSuccess) {
      _update.clear();
      _picked.clear();
      _update.picked.clear();
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(result.message ?? 'הפעולה נכשלה')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final state = context.watch<TeamTaskBloc>().state;
    final viewerId = state is TeamTasksLoaded ? state.viewer.id : '';
    final members = state is TeamTasksLoaded ? state.members : const <TeamMember>[];
    final nameById = {for (final m in members) m.id: m.name};
    final query = widget.canWrite ? _mentionQuery : null;
    // Who can be tagged: the active team, not the writer.
    final candidates = query == null
        ? const <TeamMember>[]
        : mentionCandidates(
            [
              for (final m in members)
                if (m.isActive && !m.isArchived && m.id != viewerId) m,
            ],
            query.query,
          );
    final links = teamTaskLogLinks(task.updates);
    final openTags = {
      for (final mention in task.mentions)
        if (!mention.isDone && mention.updateId.isNotEmpty) mention.updateId,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canWrite)
          _withSuggestions(
            query == null || candidates.isEmpty
                ? null
                : MentionSuggestions(
                    members: candidates,
                    onPick: (member) => _pickMention(member, query),
                  ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: RtlArrowKeys(
                    multiline: true,
                    child: TextField(
                      key: const Key('team-task-update-field'),
                      controller: _update,
                      focusNode: _updateFocus,
                      readOnly: _sending,
                      minLines: 1,
                      maxLines: 4,
                      // The "@" list follows the text and the caret.
                      onChanged: (_) => setState(() {}),
                      onTap: () => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '+ עדכון (@ לתיוג)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('team-task-update-send'),
                  tooltip: 'הוספת עדכון',
                  onPressed: _sending ? null : _send,
                  // Spins until the update is saved (Omer, round 4).
                  icon: _sending
                      ? const SizedBox(
                          key: Key('team-task-update-sending'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        if (task.updates.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('אין עדכונים עדיין', style: TextStyle(color: TaskStyle.faintText)),
          ),
        for (final (index, entry) in task.updates.indexed)
          _linked(
              links,
              index,
              Container(
                key: Key('team-task-log-${entry.id}'),
                margin: const EdgeInsets.only(top: _entryGap),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: TaskStyle.updateBox,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_editingId == entry.id)
                      _editor(entry)
                    else
                      Text.rich(
                        // The tagged names in the tag's colour (19/11/2026).
                        mentionSpans(entry.text, [
                          for (final id in entry.mentionIds)
                            if (nameById[id] != null) nameById[id]!,
                        ]),
                        key: Key('team-task-log-text-${entry.id}'),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${entry.byName ?? unknownMemberLabel} · ${logStamp(entry.at)}'
                            '${entry.editedAt != null ? ' · (נערך)' : ''}',
                            style: const TextStyle(fontSize: 12, color: TaskStyle.faintText),
                          ),
                        ),
                        // A tag in it not marked done yet (20/11/2026).
                        if (openTags.contains(entry.id))
                          Container(
                            key: Key('team-task-log-pending-${entry.id}'),
                            margin: const EdgeInsetsDirectional.only(end: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: mentionColor),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Text(
                              'עוד לא בוצע',
                              style: TextStyle(fontSize: 11, color: mentionColor),
                            ),
                          ),
                        if (_editingId != entry.id && _canChange(entry, viewerId))
                          _entryMenu(entry),
                      ],
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  /// The gap above each update in the log.
  static const double _entryGap = 6;

  /// [field] with [suggestions] (the "@" list) drawn right above it, over
  /// whatever is there (Omer, msg 5298); a tap on it still counts as inside
  /// the field, so the field keeps its focus.
  Widget _withSuggestions(Widget? suggestions, Widget field) {
    return OverlayPortal(
      controller: _suggestions,
      overlayChildBuilder: (context) {
        if (suggestions == null) return const SizedBox.shrink();
        final box = _fieldLink.leaderSize;
        return Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _fieldLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            child: TextFieldTapRegion(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Material(
                  type: MaterialType.transparency,
                  child: SizedBox(width: box?.width ?? 320, child: suggestions),
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(link: _fieldLink, child: field),
    );
  }

  /// [entry] (the update at [index]) with the log's brackets beside it, on
  /// the right (Omer, 20/11/2026): a "done" line joined to the update that
  /// tagged its writer, each link in a colour and a lane of its own.
  Widget _linked(List<TeamTaskLogLink> links, int index, Widget entry) {
    if (links.isEmpty) return entry;
    final lanes = links.map((link) => link.lane).reduce((a, b) => a > b ? a : b) + 1;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: TeamTaskLogLinkPainter.widthFor(lanes),
            child: CustomPaint(
              key: Key('team-task-log-links-$index'),
              painter: TeamTaskLogLinkPainter(links: links, index: index, topGap: _entryGap),
            ),
          ),
          Expanded(child: entry),
        ],
      ),
    );
  }
}

/// Draws, for the update at [index], its part of every bracket of [links]:
/// the line passing by, or the bend into the update with a dot on its edge.
/// The box of the update is on the painter's left (the log is right to left,
/// the brackets on its right side); lane 0 is nearest it.
class TeamTaskLogLinkPainter extends CustomPainter {
  TeamTaskLogLinkPainter({required this.links, required this.index, required this.topGap});

  final List<TeamTaskLogLink> links;
  final int index;

  /// The empty room above the update's box (its top margin).
  final double topGap;

  /// One colour per link, in the log's order, repeating.
  static const List<Color> colors = [
    mentionColor,
    Color(0xFF00897B),
    Color(0xFFEF6C00),
    Color(0xFF1E88E5),
    Color(0xFFD81B60),
    Color(0xFF6D4C41),
  ];

  static const double _first = 7;
  static const double _laneGap = 9;

  static double widthFor(int lanes) => _first + lanes * _laneGap + 2;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = topGap + (size.height - topGap) / 2;
    for (final (order, link) in links.indexed) {
      if (!link.spans(index)) continue;
      final x = _first + link.lane * _laneGap;
      final paint = Paint()
        ..color = colors[order % colors.length]
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      if (index == link.doneIndex) {
        path
          ..moveTo(0, mid)
          ..lineTo(x, mid)
          ..lineTo(x, size.height);
      } else if (index == link.tagIndex) {
        path
          ..moveTo(x, 0)
          ..lineTo(x, mid)
          ..lineTo(0, mid);
      } else {
        path
          ..moveTo(x, 0)
          ..lineTo(x, size.height);
      }
      canvas.drawPath(path, paint);
      if (index == link.doneIndex || index == link.tagIndex) {
        canvas.drawCircle(Offset(2.5, mid), 3.5, Paint()..color = paint.color);
      }
    }
  }

  @override
  bool shouldRepaint(TeamTaskLogLinkPainter old) =>
      old.index != index || old.topGap != topGap || !_sameLinks(old.links, links);

  static bool _sameLinks(List<TeamTaskLogLink> a, List<TeamTaskLogLink> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The quick update card of "המשימות שלי" (Omer, round 5): the task's whole
/// log, newest first, with the field for a new update on top. It follows the
/// task live, so a sent update shows in the list at once.
Future<void> showTeamTaskUpdatesDialog(BuildContext context, String taskId) {
  final bloc = context.read<TeamTaskBloc>();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => BlocProvider.value(
      value: bloc,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: BlocBuilder<TeamTaskBloc, TeamTaskState>(
          builder: (context, state) {
            final task = state is TeamTasksLoaded ? state.taskById(taskId) : null;
            return AlertDialog(
              key: const Key('team-task-updates-dialog'),
              title: Text(task?.title ?? ''),
              content: SizedBox(
                width: 460,
                child: task == null
                    ? const Text('המשימה נמחקה')
                    : SingleChildScrollView(
                        child: TeamTaskUpdateLog(task: task, canWrite: true),
                      ),
              ),
              actions: [
                TextButton(
                  key: const Key('team-task-updates-close'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('סגירה'),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
