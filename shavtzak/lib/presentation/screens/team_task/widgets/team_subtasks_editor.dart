import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/edit/value_editors.dart';

class _SubLine {
  _SubLine(TeamSubtask subtask)
      : id = subtask.id,
        isDone = subtask.isDone,
        assigneeId = subtask.assigneeId,
        contacts = subtask.contacts,
        title = TextEditingController(text: subtask.title);

  final String id;
  final bool isDone;
  String? assigneeId;
  List<StageContact> contacts;
  bool showContacts = false;
  final TextEditingController title;

  TeamSubtask get subtask => TeamSubtask(
        id: id,
        title: title.text.trim(),
        isDone: isDone,
        assigneeId: assigneeId,
        contacts: contacts,
      );
}

/// A task's subtasks: each with a title, its owner (one team member) and its
/// own contacts; ✕ removes, "תת-משימה" adds. Blank titles are left out.
class TeamSubtasksEditor extends StatefulWidget {
  const TeamSubtasksEditor({
    super.key,
    required this.initial,
    required this.members,
    required this.onChanged,
  });

  final List<TeamSubtask> initial;

  /// Who a subtask may be given to: the active team members.
  final List<TeamMember> members;
  final ValueChanged<List<TeamSubtask>> onChanged;

  @override
  State<TeamSubtasksEditor> createState() => _TeamSubtasksEditorState();
}

class _TeamSubtasksEditorState extends State<TeamSubtasksEditor> {
  late final List<_SubLine> _lines = [for (final s in widget.initial) _SubLine(s)];

  @override
  void dispose() {
    for (final line in _lines) {
      line.title.dispose();
    }
    super.dispose();
  }

  void _report() => widget.onChanged([
        for (final line in _lines)
          if (line.title.text.trim().isNotEmpty) line.subtask,
      ]);

  @override
  Widget build(BuildContext context) {
    final memberIds = {for (final m in widget.members) m.id};
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < _lines.length; index++) _line(index, memberIds),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('team-subtask-add'),
            onPressed: () => setState(() => _lines.add(_SubLine(
                TeamSubtask(id: const Uuid().v4(), title: '')))),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('תת-משימה'),
          ),
        ),
      ],
    );
  }

  Widget _line(int index, Set<String> memberIds) {
    final line = _lines[index];
    final assignee = line.assigneeId;
    return Padding(
      key: ObjectKey(line),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: RtlArrowKeys(
                  child: TextField(
                    key: Key('team-subtask-title-$index'),
                    controller: line.title,
                    autofocus: line.title.text.isEmpty,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'שם תת-המשימה',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _report(),
                  ),
                ),
              ),
              IconButton(
                key: Key('team-subtask-remove-$index'),
                tooltip: 'הסרה',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  setState(() => _lines.removeAt(index));
                  WidgetsBinding.instance.addPostFrameCallback((_) => line.title.dispose());
                  _report();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String?>(
                  key: Key('team-subtask-owner-$index'),
                  isExpanded: true,
                  isDense: true,
                  value: assignee,
                  hint: const Text('אחראי'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('ללא אחראי')),
                    if (assignee != null && !memberIds.contains(assignee))
                      DropdownMenuItem<String?>(
                          value: assignee, child: const Text('חבר צוות לא ידוע')),
                    for (final member in widget.members)
                      DropdownMenuItem<String?>(value: member.id, child: Text(member.name)),
                  ],
                  onChanged: (value) {
                    setState(() => line.assigneeId = value);
                    _report();
                  },
                ),
              ),
              TextButton(
                key: Key('team-subtask-contacts-$index'),
                onPressed: () => setState(() => line.showContacts = !line.showContacts),
                child: Text(line.contacts.isEmpty
                    ? 'אנשי קשר'
                    : 'אנשי קשר (${line.contacts.length})'),
              ),
            ],
          ),
          if (line.showContacts)
            ContactsEditor(
              initial: line.contacts,
              onChanged: (contacts) {
                line.contacts = contacts;
                _report();
              },
            ),
        ],
      ),
    );
  }
}
