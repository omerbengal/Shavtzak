import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/rtl_text_field_utils.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/edit/value_editors.dart';
import '../../task/task_style.dart';

const Uuid _uuid = Uuid();

class _SubLine {
  _SubLine(TeamSubtask subtask)
      : id = subtask.id,
        isDone = subtask.isDone,
        assigneeId = subtask.assigneeId,
        contacts = subtask.contacts,
        showContacts = false,
        controller = TextEditingController(text: subtask.title) {
    focus = createRtlCursorFixedFocusNode(controller);
  }

  final String id;
  final bool isDone;
  String? assigneeId;
  List<StageContact> contacts;
  bool showContacts;
  final TextEditingController controller;
  late final FocusNode focus;

  TeamSubtask get subtask => TeamSubtask(
        id: id,
        title: controller.text.trim(),
        isDone: isDone,
        assigneeId: assigneeId,
        contacts: contacts,
      );

  void dispose() {
    focus.dispose();
    controller.dispose();
  }
}

/// A task's subtasks, typed the way the דו יומי subtasks are: one line each,
/// Enter adds a line under the current one, Backspace on an empty line
/// removes it, ✕ deletes, ⋮⋮ reorders. Each line also carries its owner (one
/// team member, from the person button) and its own contacts (the phone
/// button opens them under the line). A line keeps its subtask's id, so a
/// renamed subtask keeps its tick; empty lines are left out.
class TeamSubtasksEditor extends StatefulWidget {
  const TeamSubtasksEditor({
    super.key,
    required this.initial,
    required this.members,
    required this.onChanged,
    this.startWithLine = true,
  });

  final List<TeamSubtask> initial;

  /// Who a subtask may be given to: the active team members.
  final List<TeamMember> members;
  final ValueChanged<List<TeamSubtask>> onChanged;

  /// With no subtasks yet, open on one empty, focused line (the editing
  /// dialog). False inside a longer form, where only "+ תת-משימה" adds one.
  final bool startWithLine;

  @override
  State<TeamSubtasksEditor> createState() => _TeamSubtasksEditorState();
}

class _TeamSubtasksEditorState extends State<TeamSubtasksEditor> {
  late final List<_SubLine> _lines = [for (final s in widget.initial) _SubLine(s)];

  @override
  void initState() {
    super.initState();
    if (_lines.isEmpty && widget.startWithLine) {
      _lines.add(_SubLine(TeamSubtask(id: _uuid.v4(), title: '')));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lines.isNotEmpty) _lines.last.focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _report() => widget.onChanged([
        for (final line in _lines)
          if (line.controller.text.trim().isNotEmpty) line.subtask,
      ]);

  void _insertAfter(int index) {
    final line = _SubLine(TeamSubtask(id: _uuid.v4(), title: ''));
    setState(() => _lines.insert(index + 1, line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) line.focus.requestFocus();
    });
  }

  void _remove(int index, {bool focusPrevious = false}) {
    final line = _lines[index];
    setState(() => _lines.removeAt(index));
    if (focusPrevious && index > 0) _lines[index - 1].focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => line.dispose());
    _report();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _lines[index].controller.text.isEmpty &&
        _lines.length > 1) {
      _remove(index, focusPrevious: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _lines.length,
          // `onReorder`, as the דו יומי SubtasksEditor (see there).
          // ignore: deprecated_member_use
          onReorder: (from, to) {
            final target = to > from ? to - 1 : to;
            setState(() => _lines.insert(target, _lines.removeAt(from)));
            _report();
          },
          itemBuilder: (context, index) => _line(index),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('team-subtask-add'),
            onPressed: () => _insertAfter(_lines.length - 1),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('תת-משימה'),
          ),
        ),
      ],
    );
  }

  Widget _line(int index) {
    final line = _lines[index];
    return Column(
      key: ObjectKey(line),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.drag_indicator, size: 18, color: TaskStyle.editFaint),
              ),
            ),
            Expanded(
              child: Focus(
                onKeyEvent: (_, event) => _onKey(index, event),
                child: RtlArrowKeys(
                  child: TextField(
                    key: Key('team-subtask-title-$index'),
                    controller: line.controller,
                    focusNode: line.focus,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'תת-משימה',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => _report(),
                    onSubmitted: (_) => _insertAfter(index),
                  ),
                ),
              ),
            ),
            _ownerButton(index, line),
            IconButton(
              key: Key('team-subtask-contacts-$index'),
              tooltip: line.contacts.isEmpty
                  ? 'אנשי קשר'
                  : 'אנשי קשר (${line.contacts.length})',
              visualDensity: VisualDensity.compact,
              icon: Badge(
                isLabelVisible: line.contacts.isNotEmpty,
                label: Text('${line.contacts.length}'),
                child: Icon(
                  Icons.contact_phone_outlined,
                  size: 18,
                  color: line.showContacts ? TaskStyle.edit : TaskStyle.editMuted,
                ),
              ),
              onPressed: () => setState(() => line.showContacts = !line.showContacts),
            ),
            IconButton(
              key: Key('team-subtask-remove-$index'),
              tooltip: 'מחיקה',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _remove(index),
            ),
          ],
        ),
        if (line.showContacts)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26, bottom: 6),
            child: ContactsEditor(
              initial: line.contacts,
              onChanged: (contacts) {
                setState(() => line.contacts = contacts);
                _report();
              },
            ),
          ),
      ],
    );
  }

  /// The line's owner: their name in a small chip, or a person icon when it
  /// has none. A tap lists the team.
  Widget _ownerButton(int index, _SubLine line) {
    final id = line.assigneeId;
    final name = id == null
        ? null
        : widget.members.where((m) => m.id == id).firstOrNull?.name ?? 'חבר צוות לא ידוע';
    return PopupMenuButton<String>(
      key: Key('team-subtask-owner-$index'),
      tooltip: 'אחראי',
      onSelected: (value) {
        setState(() => line.assigneeId = value.isEmpty ? null : value);
        _report();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: '', child: Text('ללא אחראי')),
        for (final member in widget.members)
          PopupMenuItem(
            key: Key('team-subtask-owner-option-${member.id}'),
            value: member.id,
            child: Text(member.name),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: name == null
            ? const Icon(Icons.person_add_alt, size: 18, color: TaskStyle.editMuted)
            : Container(
                constraints: const BoxConstraints(maxWidth: 110),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: TaskStyle.editTaskWell,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
      ),
    );
  }
}
