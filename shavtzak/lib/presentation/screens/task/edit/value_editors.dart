import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/phone_input_formatter.dart';
import '../../../../core/utils/rtl_text_field_utils.dart';
import '../../../../core/utils/search_utils.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/subtask.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../event/widgets/event_time_field.dart';
import '../task_style.dart';

/// The editors of the editing screen, one per kind of value. Each has the
/// shape of an `EditorBuilder`: it starts from a draft, reports every change,
/// and may ask to save.

const Uuid _uuid = Uuid();

/// A line of text, or several when [multiline]. A single line saves on
/// Enter; several save on Ctrl+Enter (Enter starts a new line).
class TextValueEditor extends StatefulWidget {
  const TextValueEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onSubmit,
    this.multiline = false,
    this.hint,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final bool multiline;
  final String? hint;

  @override
  State<TextValueEditor> createState() => _TextValueEditorState();
}

class _TextValueEditorState extends State<TextValueEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  late final FocusNode _focus = createRtlCursorFixedFocusNode(_controller);

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = RtlArrowKeys(
        child: TextField(
      key: const Key('edit-text'),
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      minLines: widget.multiline ? 2 : 1,
      maxLines: widget.multiline ? null : 1,
      keyboardType:
          widget.multiline ? TextInputType.multiline : TextInputType.text,
      textInputAction:
          widget.multiline ? TextInputAction.newline : TextInputAction.done,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.multiline ? null : (_) => widget.onSubmit(),
    ));
    if (!widget.multiline) return field;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            widget.onSubmit,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            widget.onSubmit,
      },
      child: field,
    );
  }
}

/// An optional `HH:mm`, typed the way the event form's times are. '' is none.
class TimeValueEditor extends StatefulWidget {
  const TimeValueEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.label,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  State<TimeValueEditor> createState() => _TimeValueEditorState();
}

class _TimeValueEditorState extends State<TimeValueEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EventTimeField(
      key: const Key('edit-time'),
      controller: _controller,
      label: widget.label,
      hint: 'לא חובה',
      logKey: 'editTime',
      onChanged: () => widget.onChanged(_controller.text.trim()),
      onTimeSet: (value) => widget.onChanged(value),
    );
  }
}

/// A stage's start and end, as one value.
typedef StageTimes = ({String start, String end});

class StageTimesEditor extends StatefulWidget {
  const StageTimesEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final StageTimes initial;
  final ValueChanged<StageTimes> onChanged;

  @override
  State<StageTimesEditor> createState() => _StageTimesEditorState();
}

class _StageTimesEditorState extends State<StageTimesEditor> {
  late final TextEditingController _start =
      TextEditingController(text: widget.initial.start);
  late final TextEditingController _end =
      TextEditingController(text: widget.initial.end);

  void _report() =>
      widget.onChanged((start: _start.text.trim(), end: _end.text.trim()));

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Row(
        children: [
          Expanded(
            child: EventTimeField(
              key: const Key('edit-start'),
              controller: _start,
              label: 'שעת התחלה',
              hint: 'לא חובה',
              logKey: 'editStageStart',
              onChanged: _report,
              onTimeSet: (_) => _report(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EventTimeField(
              key: const Key('edit-end'),
              controller: _end,
              label: 'שעת סיום',
              hint: 'לטווח שעות',
              logKey: 'editStageEnd',
              onChanged: _report,
              onTimeSet: (_) => _report(),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the event's days; picking one saves it.
class DayValueEditor extends StatelessWidget {
  const DayValueEditor({
    super.key,
    required this.initial,
    required this.days,
    required this.onChanged,
    required this.onSubmit,
  });

  final DateTime initial;
  final List<DateTime> days;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final options = {...days, initial}.toList()..sort();
    return DropdownButton<DateTime>(
      key: const Key('edit-day'),
      value: initial,
      isDense: true,
      autofocus: true,
      items: [
        for (final day in options)
          DropdownMenuItem(
            value: day,
            child: Text(
              'יום ${hebrewWeekday(day)} ${day.day}/${day.month}',
              key: Key('edit-day-${day.month}-${day.day}'),
            ),
          ),
      ],
      onChanged: (day) {
        if (day == null) return;
        onChanged(day);
        onSubmit();
      },
    );
  }
}

/// Who a task is given to: the members assigned to the event, plus anyone
/// already on the task who no longer is, so they can be taken off.
class AssigneesEditor extends StatefulWidget {
  const AssigneesEditor({
    super.key,
    required this.initial,
    required this.offered,
    required this.current,
    required this.onChanged,
  });

  final List<String> initial;

  /// The event's assigned members, by name.
  final List<TeamMember> offered;

  /// The task's assignees as they stand.
  final List<TeamMember> current;
  final ValueChanged<List<String>> onChanged;

  @override
  State<AssigneesEditor> createState() => _AssigneesEditorState();
}

class _AssigneesEditorState extends State<AssigneesEditor> {
  late final List<String> _picked = [...widget.initial];
  String _query = '';

  void _toggle(String id, bool on) {
    setState(() {
      if (on) {
        if (!_picked.contains(id)) _picked.add(id);
      } else {
        _picked.remove(id);
      }
    });
    widget.onChanged([..._picked]);
  }

  @override
  Widget build(BuildContext context) {
    final offeredIds = {for (final member in widget.offered) member.id};
    final members = [
      ...widget.offered,
      for (final member in widget.current)
        if (!offeredIds.contains(member.id)) member,
    ];
    final query = normalizeForSearch(_query.trim()).toLowerCase();
    final visible = query.isEmpty
        ? members
        : members
            .where((member) =>
                normalizeForSearch(member.name).toLowerCase().contains(query))
            .toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RtlArrowKeys(
              child: TextField(
            key: const Key('edit-assignee-search'),
            autofocus: true,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'חיפוש חבר צוות...',
              prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          )),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('אין משובצים לאירוע זה'),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: TaskStyle.editAssigneesMaxHeight,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final member in visible)
                  CheckboxListTile(
                    key: Key('edit-assignee-${member.id}'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(member.name),
                    subtitle: offeredIds.contains(member.id)
                        ? null
                        : const Text('כבר לא משובץ/ת לאירוע'),
                    value: _picked.contains(member.id),
                    onChanged: (on) => _toggle(member.id, on ?? false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line {
  _Line({required this.id, required String text, this.isDone = false})
      : controller = TextEditingController(text: text) {
    focus = createRtlCursorFixedFocusNode(controller);
  }

  final String id;
  final bool isDone;
  final TextEditingController controller;
  late final FocusNode focus;

  void dispose() {
    focus.dispose();
    controller.dispose();
  }
}

/// A task's subtasks as an editable list. Enter adds a line under the
/// current one, Backspace on an empty line removes it, ✕ deletes, ⋮⋮
/// reorders. A line keeps its subtask's id, so a renamed subtask keeps its
/// tick; empty lines are left out.
class SubtasksEditor extends StatefulWidget {
  const SubtasksEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final List<Subtask> initial;
  final ValueChanged<List<Subtask>> onChanged;

  @override
  State<SubtasksEditor> createState() => _SubtasksEditorState();
}

class _SubtasksEditorState extends State<SubtasksEditor> {
  late final List<_Line> _lines = [
    for (final subtask in widget.initial)
      _Line(id: subtask.id, text: subtask.title, isDone: subtask.isDone),
  ];

  @override
  void initState() {
    super.initState();
    if (_lines.isEmpty) _lines.add(_Line(id: _uuid.v4(), text: ''));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lines.last.focus.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _report() {
    widget.onChanged([
      for (final line in _lines)
        if (line.controller.text.trim().isNotEmpty)
          Subtask(
            id: line.id,
            title: line.controller.text.trim(),
            isDone: line.isDone,
          ),
    ]);
  }

  void _insertAfter(int index) {
    final line = _Line(id: _uuid.v4(), text: '');
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
          // `onReorder`, not the newer `onReorderItem`: CI builds with
          // Flutter 3.41 (.github/workflows/web.yml), which lacks it.
          // ignore: deprecated_member_use
          onReorder: (from, to) {
            // `to` counts the moved line still in place.
            final target = to > from ? to - 1 : to;
            setState(() => _lines.insert(target, _lines.removeAt(from)));
            _report();
          },
          itemBuilder: (context, index) {
            final line = _lines[index];
            return Row(
              key: ObjectKey(line),
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.drag_indicator,
                        size: 18, color: TaskStyle.editFaint),
                  ),
                ),
                Expanded(
                  child: Focus(
                    onKeyEvent: (_, event) => _onKey(index, event),
                    child: RtlArrowKeys(
                        child: TextField(
                      key: Key('edit-subtask-$index'),
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
                    )),
                  ),
                ),
                IconButton(
                  key: Key('edit-subtask-remove-$index'),
                  tooltip: 'מחיקה',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => _remove(index),
                ),
              ],
            );
          },
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('edit-subtask-add'),
            onPressed: () => _insertAfter(_lines.length - 1),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('תת-משימה'),
          ),
        ),
      ],
    );
  }
}

class _ContactLine {
  _ContactLine(StageContact contact)
      : id = contact.id,
        name = TextEditingController(text: contact.name),
        phone = TextEditingController(text: contact.phone),
        role = TextEditingController(text: contact.role);

  final String id;
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController role;

  bool get isBlank =>
      name.text.trim().isEmpty &&
      phone.text.trim().isEmpty &&
      role.text.trim().isEmpty;

  StageContact get contact => StageContact(
        id: id,
        name: name.text.trim(),
        phone: phone.text.trim(),
        role: role.text.trim(),
      );

  void dispose() {
    name.dispose();
    phone.dispose();
    role.dispose();
  }
}

/// A stage's contacts: name, phone and role each, ✕ to remove, and a line to
/// add one. Blank lines are left out.
class ContactsEditor extends StatefulWidget {
  const ContactsEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final List<StageContact> initial;
  final ValueChanged<List<StageContact>> onChanged;

  @override
  State<ContactsEditor> createState() => _ContactsEditorState();
}

class _ContactsEditorState extends State<ContactsEditor> {
  late final List<_ContactLine> _lines = [
    for (final contact in widget.initial) _ContactLine(contact),
  ];

  @override
  void initState() {
    super.initState();
    if (_lines.isEmpty) {
      _lines.add(_ContactLine(StageContact(id: _uuid.v4(), name: '')));
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
          if (!line.isBlank) line.contact,
      ]);

  Widget _field(
    TextEditingController controller,
    String hint,
    Key key, {
    bool phone = false,
    bool autofocus = false,
  }) {
    final field = TextField(
      key: key,
      controller: controller,
      autofocus: autofocus,
      keyboardType: phone ? TextInputType.phone : TextInputType.text,
      inputFormatters: phone ? [PhoneNumberTextInputFormatter()] : null,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _report(),
    );
    // A phone number reads left to right, so its arrows already point right.
    return phone ? field : RtlArrowKeys(child: field);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < _lines.length; index++)
          Padding(
            key: ObjectKey(_lines[index]),
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _field(
                      _lines[index].name, 'שם', Key('edit-contact-name-$index'),
                      autofocus: index == _lines.length - 1),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: _field(_lines[index].phone, 'טלפון',
                      Key('edit-contact-phone-$index'),
                      phone: true),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: _field(_lines[index].role, 'תפקיד',
                      Key('edit-contact-role-$index')),
                ),
                IconButton(
                  key: Key('edit-contact-remove-$index'),
                  tooltip: 'הסרה',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    final line = _lines[index];
                    setState(() => _lines.removeAt(index));
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => line.dispose());
                    _report();
                  },
                ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('edit-contact-add'),
            onPressed: () => setState(() => _lines
                .add(_ContactLine(StageContact(id: _uuid.v4(), name: '')))),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('איש קשר'),
          ),
        ),
      ],
    );
  }
}
