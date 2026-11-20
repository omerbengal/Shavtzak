import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/web/keep_input_focus.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';
import 'team_task_style.dart';

/// Tags ("@") in a task's update log (Omer, 19/11/2026), like Instagram /
/// Facebook mentions: typing "@" in the update field lists the team members,
/// a pick writes "@<name>" into the text, and the sent update carries the
/// tagged ids. The tagged member is not an owner: the task shows in their
/// "המשימות שלי" with an @ mark and a box they tick (a popup with an optional
/// line) when they did what they were tagged for.

/// The colour of a tag: the "@" mark, a highlighted name.
const Color mentionColor = Color(0xFF8E24AA);
const Color mentionLight = Color(0xFFF3E5F5);

/// The "@" query the caret is in: the text from the last "@" before
/// [caret] (at the start or after a space or a line break) up to [caret],
/// when it is at most [maxQuery] long, holds no line break and does not end
/// with a space (after a pick, or a finished word: typing on brings the list
/// back, so a two-word name still works). Null = not tagging now.
({int start, String query})? activeMentionQuery(String text, int caret, {int maxQuery = 24}) {
  if (caret < 0 || caret > text.length) return null;
  final at = text.lastIndexOf('@', caret == 0 ? 0 : caret - 1);
  if (at < 0 || caret == 0) return null;
  if (at > 0 && !RegExp(r'\s').hasMatch(text[at - 1])) return null;
  final query = text.substring(at + 1, caret);
  if (query.length > maxQuery || query.contains('\n')) return null;
  if (query.isNotEmpty && RegExp(r'\s$').hasMatch(query)) return null;
  return (start: at, query: query);
}

/// The members [query] picks: their name holds it (ignoring case, points and
/// quotes), the ones whose name starts with it first, then by name. All of
/// them (Omer, msg 5313: a bare "@" lists the whole team; the list scrolls).
List<TeamMember> mentionCandidates(List<TeamMember> members, String query) {
  final wanted = normalizeTeamTaskSearch(query.trim());
  final matches = [
    for (final member in members)
      if (wanted.isEmpty || normalizeTeamTaskSearch(member.name).contains(wanted)) member,
  ];
  int rank(TeamMember m) => normalizeTeamTaskSearch(m.name).startsWith(wanted) ? 0 : 1;
  matches.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : compareHebrewText(a.name, b.name);
  });
  return matches;
}

/// The ids among [picked] (name → id, the members picked from the list)
/// whose "@<name>" is still in [text].
List<String> mentionIdsInText(String text, Map<String, String> picked) => [
      for (final entry in picked.entries)
        if (text.contains('@${entry.key}')) entry.value,
    ];

/// One character deleted inside or at the end of a tag (Omer, 20/11/2026:
/// "כמו בכל הפלטפורמות"): [next] is [old] with one character gone (a
/// backspace or a forward delete, nothing selected), and that character is
/// part of an "@<name>" of [names] in [old]. Then the whole tag goes, the
/// caret where it began; otherwise null (leave [next] as it is).
TextEditingValue? removeWholeMention(
    TextEditingValue old, TextEditingValue next, Iterable<String> names) {
  if (next.text.length != old.text.length - 1) return null;
  if (!old.selection.isValid || !old.selection.isCollapsed) return null;
  if (!next.selection.isValid || !next.selection.isCollapsed) return null;
  final at = next.selection.baseOffset;
  if (at < 0 || at >= old.text.length) return null;
  if (old.text.replaceRange(at, at + 1, '') != next.text) return null;
  final sorted = names.where((n) => n.isNotEmpty).toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (sorted.isEmpty) return null;
  final pattern = RegExp(sorted.map((n) => RegExp.escape('@$n')).join('|'));
  for (final match in pattern.allMatches(old.text)) {
    if (match.start <= at && at < match.end) {
      return TextEditingValue(
        text: old.text.replaceRange(match.start, match.end, ''),
        selection: TextSelection.collapsed(offset: match.start),
      );
    }
  }
  return null;
}

/// The update field (Omer, msg 5298): a name picked from the "@" list shows
/// in the tag's colour while the update is still being written, so it is
/// clear the tag took. One delete on a tag removes all of it (20/11/2026).
class MentionTextEditingController extends TextEditingController {
  /// The names picked from the list (their "@<name>" is coloured).
  final Set<String> picked = {};

  @override
  set value(TextEditingValue newValue) {
    final names = [for (final name in picked) if (text.contains('@$name')) name];
    final whole = names.isEmpty ? null : removeWholeMention(value, newValue, names);
    super.value = whole ?? newValue;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final names = [for (final name in picked) if (text.contains('@$name')) name];
    if (names.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    return mentionSpans(text, names, style: style);
  }
}

/// [text] with every "@<name>" of [names] in the tag's colour.
TextSpan mentionSpans(String text, Iterable<String> names, {TextStyle? style}) {
  final sorted = names.where((n) => n.isNotEmpty).toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (sorted.isEmpty) return TextSpan(text: text, style: style);
  final pattern = RegExp(sorted.map((n) => RegExp.escape('@$n')).join('|'));
  final spans = <TextSpan>[];
  var last = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > last) spans.add(TextSpan(text: text.substring(last, match.start)));
    spans.add(TextSpan(
      text: match.group(0),
      style: const TextStyle(
        color: mentionColor,
        fontWeight: FontWeight.w600,
        backgroundColor: mentionLight,
      ),
    ));
    last = match.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return TextSpan(style: style, children: spans);
}

/// The suggestions above the update field (Omer, msg 5298) while the caret
/// is in an "@" query; a tap calls [onPick]. Every match is listed, in a box
/// of at most [maxHeight] that scrolls (Omer, msg 5313), each name with the
/// permanent member's blue shield, as everywhere in the app.
class MentionSuggestions extends StatefulWidget {
  const MentionSuggestions({
    super.key,
    required this.members,
    required this.onPick,
    this.maxHeight = 264,
  });

  final List<TeamMember> members;
  final ValueChanged<TeamMember> onPick;
  final double maxHeight;

  @override
  State<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends State<MentionSuggestions> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _box = GlobalKey();

  @override
  void dispose() {
    keepInputFocusIn(this, null);
    _scroll.dispose();
    super.dispose();
  }

  /// A touch on the list must not take the focus from the field, or the
  /// phone's keyboard goes down mid-sentence (Omer, 20/11/2026).
  void _keepFocusOverList() {
    if (!mounted) return;
    final box = _box.currentContext?.findRenderObject() as RenderBox?;
    keepInputFocusIn(
      this,
      box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    if (members.isEmpty) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) => _keepFocusOverList());
    return Container(
      key: const Key('team-task-mention-suggestions'),
      margin: const EdgeInsets.only(bottom: 4),
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: TaskStyle.rest),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, -2))],
      ),
      child: Scrollbar(
        key: _box,
        controller: _scroll,
        thumbVisibility: true,
        child: ListView.builder(
          key: const Key('team-task-mention-list'),
          controller: _scroll,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
            return InkWell(
              key: Key('team-task-mention-option-${member.id}'),
              onTap: () => widget.onPick(member),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    const Text('@',
                        style: TextStyle(color: mentionColor, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Expanded(child: MemberNameText(name: member.name, permanent: member.isPermanent)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The coloured "@" of a task the viewer is tagged in (not an owner).
class MentionMark extends StatelessWidget {
  const MentionMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'תויגת במשימה',
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: mentionColor, shape: BoxShape.circle),
          child: Text(
            '@',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.68,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      );
}

/// The tagged member's box for one tag: empty while it is open, ticked once
/// they marked it done. A tap on an open one asks first
/// ([showMentionDoneDialog]).
class MentionDoneBox extends StatelessWidget {
  const MentionDoneBox({super.key, required this.task, required this.mention, this.size = 24});

  final TeamTask task;
  final TeamTaskMention mention;
  final double size;

  @override
  Widget build(BuildContext context) {
    final done = mention.isDone;
    final icon = Icon(
      done ? Icons.check_box : Icons.check_box_outline_blank,
      size: size,
      color: done ? TaskStyle.done : mentionColor,
    );
    return Tooltip(
      message: done ? 'סימנת כבוצע' : 'סימון כבוצע',
      child: InkWell(
        key: Key('team-task-mention-box-${task.id}-${mention.updateId}'),
        customBorder: const CircleBorder(),
        onTap: done ? null : () => showMentionDoneDialog(context, task, mention),
        child: Padding(padding: const EdgeInsets.all(6), child: icon),
      ),
    );
  }
}

/// "סמן כבוצע" for one tag (Omer, 19/11/2026): an optional line, "ביטול"
/// leaves the box empty, "סמן כבוצע" ticks it and writes the line to the log,
/// linked to the update that tagged (20/11/2026).
///
/// The dialog stays open with a spinner on its button until the server
/// answers (Omer, 20/11/2026: it vanished and nothing showed until the item
/// went); a failure keeps it open with the error under the field.
Future<void> showMentionDoneDialog(
    BuildContext context, TeamTask task, TeamTaskMention mention) async {
  Logger.action('open:teamTaskMentionDone', {'taskId': task.id, 'updateId': mention.updateId});
  final bloc = context.read<TeamTaskBloc>();
  final state = bloc.state;
  final name = state is TeamTasksLoaded
      ? state.members.where((m) => m.id == mention.memberId).firstOrNull?.name
      : null;
  final title = mentionItemTitle(task, mention, memberName: name);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: _MentionDoneDialog(bloc: bloc, task: task, mention: mention, title: title),
    ),
  );
}

class _MentionDoneDialog extends StatefulWidget {
  const _MentionDoneDialog({
    required this.bloc,
    required this.task,
    required this.mention,
    required this.title,
  });

  final TeamTaskBloc bloc;
  final TeamTask task;
  final TeamTaskMention mention;
  final String title;

  @override
  State<_MentionDoneDialog> createState() => _MentionDoneDialogState();
}

class _MentionDoneDialogState extends State<_MentionDoneDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final completion = CrudActionCompleter();
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.bloc.add(MarkTeamTaskMentionDone(
        widget.task.id, widget.mention.updateId, _controller.text.trim(),
        completion: completion));
    final result = await completion.future;
    if (!mounted) return;
    if (result.isFailure) {
      setState(() {
        _saving = false;
        _error = result.message ?? 'הפעולה נכשלה. נסו שוב.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        key: const Key('team-task-mention-done-dialog'),
        title: const Text('סימון כבוצע'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (widget.title != task.title)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('במשימה: ${task.title}',
                      style: const TextStyle(
                          fontSize: TaskStyle.rowMetaSize, color: TaskStyle.neutralText)),
                ),
              const SizedBox(height: 10),
              RtlArrowKeys(
                multiline: true,
                child: TextField(
                  key: const Key('team-task-mention-done-text'),
                  controller: _controller,
                  autofocus: true,
                  enabled: !_saving,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'מה עשית? (לא חובה)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('team-task-mention-done-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('team-task-mention-done-cancel'),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          FilledButton(
            key: const Key('team-task-mention-done-confirm'),
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    key: Key('team-task-mention-done-spinner'),
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('סמן כבוצע'),
          ),
        ],
      ),
    );
  }
}
