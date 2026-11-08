import 'package:flutter/material.dart';

import '../../../../core/utils/task_schedule.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';
import 'edit_context.dart';
import 'edit_rules.dart';
import 'editable_value.dart';
import 'task_edit_row.dart';
import 'value_editors.dart';

/// A stage as a soft card: every one of its details in the heading, each
/// edited where it sits, and its tasks below — a table on a wide window,
/// small cards on a phone. On a wide window a task dragged from another stage
/// can be dropped on it.
class StageEditCard extends StatefulWidget {
  const StageEditCard({
    super.key,
    required this.stage,
    required this.tasks,
    required this.allTaskCount,
    required this.ctx,
  });

  final Stage stage;

  /// The tasks to show, after the filters.
  final List<TaskItem> tasks;

  /// How many tasks the stage holds, for the delete warning.
  final int allTaskCount;
  final EditContext ctx;

  @override
  State<StageEditCard> createState() => _StageEditCardState();
}

class _StageEditCardState extends State<StageEditCard> {
  /// On a phone the requirements and contacts fold away.
  bool _moreOpen = false;

  Stage get stage => widget.stage;
  EditContext get ctx => widget.ctx;

  void _commit(Stage next) => ctx.onStageCommit(next);

  @override
  Widget build(BuildContext context) {
    final card = DragTarget<TaskItem>(
      onWillAcceptWithDetails: (details) =>
          ctx.wide && details.data.stageId != stage.id,
      onAcceptWithDetails: (details) => ctx.onMoveTask(details.data, stage),
      builder: (context, candidates, _) => _buildCard(candidates.isNotEmpty),
    );
    return Padding(
      key: ctx.keyFor(stage.id),
      padding: const EdgeInsets.only(bottom: TaskStyle.editCardGap),
      child: card,
    );
  }

  Widget _buildCard(bool dropping) {
    final highlighted = ctx.highlightId == stage.id;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TaskStyle.editCardRadius),
        boxShadow: TaskStyle.editCardShadow,
      ),
      // A dark frame round the whole stage, its details and its tasks, drawn
      // on top so it frames everything inside the rounded corners.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TaskStyle.editCardRadius),
        border: Border.all(
          color: TaskStyle.editStageBorder,
          width: TaskStyle.editStageBorderWidth,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TaskStyle.editCardRadius),
        child: AnimatedContainer(
          key: Key('edit-stage-${stage.id}'),
          duration: const Duration(milliseconds: 200),
          color: dropping ? TaskStyle.editDropTarget : TaskStyle.editCard,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    color: highlighted
                        ? TaskStyle.editHighlight
                        : (dropping
                            ? TaskStyle.editDropTarget
                            : TaskStyle.editCardHeader),
                    padding: EdgeInsets.fromLTRB(
                        14, 12, ctx.wide ? 22 : 16, 12),
                    child: _buildHeading(),
                  ),
                  const Divider(height: 1, color: TaskStyle.editCardHeaderLine),
                  // The stage's tasks sit in a tinted well, each a white
                  // card of its own, so where one ends and the next starts
                  // is plain.
                  ColoredBox(
                    color: dropping
                        ? TaskStyle.editDropTarget
                        : TaskStyle.editTaskWell,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (ctx.wide && widget.tasks.isNotEmpty)
                          const TaskEditHeader(),
                        if (!ctx.wide) const SizedBox(height: 6),
                        for (final task in widget.tasks)
                          ctx.wide
                              ? TaskEditRow(task: task, ctx: ctx)
                              : TaskEditCard(task: task, ctx: ctx),
                        _addTaskButton(),
                      ],
                    ),
                  ),
                ],
              ),
              const PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: TaskStyle.editCardEdgeWidth,
                child: ColoredBox(color: TaskStyle.editCardEdge),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addTaskButton() => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: TextButton.icon(
            key: Key('edit-task-add-${stage.id}'),
            onPressed: () => ctx.onAddTask(stage),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('משימה'),
          ),
        ),
      );

  Widget _buildHeading() {
    final times = (start: stage.startTime ?? '', end: stage.endTime ?? '');
    final line = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        EditableValue<String>(
          key: Key('edit-stage-title-${stage.id}'),
          value: stage.title,
          wide: ctx.wide,
          expand: false,
          sheetTitle: 'שם השלב',
          display: Text(
            stage.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          validate: (value) => validateRequiredText(value, 'שם לשלב'),
          editor: (context, draft, onChanged, onSubmit) => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: TextValueEditor(
              initial: draft,
              onChanged: onChanged,
              onSubmit: onSubmit,
            ),
          ),
          onCommit: (value) => _commit(stage.copyWith(title: value.trim())),
        ),
        EditableValue<DateTime>(
          key: Key('edit-stage-day-${stage.id}'),
          value: stage.date,
          wide: ctx.wide,
          expand: false,
          sheetTitle: 'היום של השלב',
          display: _iconText(Icons.calendar_today, editDayLabel(stage.date)),
          editor: (context, draft, onChanged, onSubmit) => DayValueEditor(
            initial: draft,
            days: ctx.days,
            onChanged: onChanged,
            onSubmit: onSubmit,
          ),
          onCommit: (day) => _commit(stage.copyWith(date: day)),
        ),
        EditableValue<StageTimes>(
          key: Key('edit-stage-times-${stage.id}'),
          value: times,
          wide: ctx.wide,
          expand: false,
          sheetTitle: 'שעות השלב',
          display: stageTimeLabel(stage).isEmpty
              ? _iconText(Icons.schedule, 'הוספת שעה', faint: true)
              : _iconText(Icons.schedule, stageTimeLabel(stage)),
          validate: (draft) => validateStageTimes(draft.start, draft.end),
          editor: (context, draft, onChanged, _) => StageTimesEditor(
            initial: draft,
            onChanged: onChanged,
          ),
          onCommit: (draft) => _commit(stage.copyWith(
            startTime: draft.start.isEmpty ? null : draft.start,
            endTime: draft.end.isEmpty ? null : draft.end,
            clearStartTime: draft.start.isEmpty,
            clearEndTime: draft.end.isEmpty,
          )),
        ),
      ],
    );

    final delete = TextButton.icon(
      key: Key('edit-stage-delete-${stage.id}'),
      onPressed: () => ctx.onDeleteStage(stage, widget.allTaskCount),
      style: TextButton.styleFrom(foregroundColor: TaskStyle.editMuted),
      icon: const Icon(Icons.delete_outline, size: 18),
      label: Text(ctx.wide ? 'מחיקת השלב' : 'מחיקה'),
    );

    final location = _field('מיקום', _textValue(
      id: 'location',
      value: stage.hotelLocation,
      title: 'מיקום במלון',
      placeholder: 'הוספת מיקום',
      apply: (v) => stage.copyWith(hotelLocation: v),
    ));
    final notes = _field('הערות', _textValue(
      id: 'notes',
      value: stage.notes,
      title: 'הערות',
      placeholder: 'הוספת הערה',
      multiline: true,
      apply: (v) => stage.copyWith(notes: v),
    ));
    final requirements = _field('דרישות', _textValue(
      id: 'requirements',
      value: stage.requirements,
      title: 'דרישות מהמלון',
      placeholder: 'הוספת דרישות',
      multiline: true,
      apply: (v) => stage.copyWith(requirements: v),
    ));
    final contacts = _field('אנשי קשר', _contactsValue());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: line), delete],
        ),
        const SizedBox(height: 8),
        if (ctx.wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: [location, requirements])),
              const SizedBox(width: 18),
              Expanded(child: Column(children: [notes, contacts])),
            ],
          )
        else ...[
          location,
          notes,
          if (_moreOpen) ...[requirements, contacts],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: Key('edit-stage-more-${stage.id}'),
              onPressed: () => setState(() => _moreOpen = !_moreOpen),
              child: Text(_moreOpen
                  ? '▴ פחות פרטים'
                  : '▾ עוד פרטים: דרישות, '
                      '${stage.contacts.isEmpty ? 'אנשי קשר' : '${stage.contacts.length} אנשי קשר'}'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _iconText(IconData icon, String text, {bool faint = false}) {
    final color = faint ? TaskStyle.editFaint : const Color(0xFF4B5563);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: color),
          ),
        ),
      ],
    );
  }

  Widget _field(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: TaskStyle.editLabelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: TaskStyle.editLabel,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  Widget _textValue({
    required String id,
    required String value,
    required String title,
    required String placeholder,
    required Stage Function(String value) apply,
    bool multiline = false,
  }) {
    return EditableValue<String>(
      key: Key('edit-stage-$id-${stage.id}'),
      value: value,
      wide: ctx.wide,
      sheetTitle: title,
      display: value.isEmpty
          ? editPlaceholder(placeholder)
          : Text(value, style: const TextStyle(fontSize: 13, height: 1.45)),
      editor: (context, draft, onChanged, onSubmit) => TextValueEditor(
        initial: draft,
        onChanged: onChanged,
        onSubmit: onSubmit,
        multiline: multiline,
      ),
      onCommit: (next) => _commit(apply(next.trim())),
    );
  }

  Widget _contactsValue() {
    return EditableValue<List<StageContact>>(
      key: Key('edit-stage-contacts-${stage.id}'),
      value: stage.contacts,
      wide: ctx.wide,
      sheetTitle: 'אנשי קשר',
      display: stage.contacts.isEmpty
          ? editPlaceholder('+ איש קשר')
          : Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final contact in stage.contacts)
                  Container(
                    key: Key('edit-contact-chip-${contact.id}'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                        text: contact.name,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      TextSpan(
                        text: [
                          if (contact.role.isNotEmpty) contact.role,
                          if (contact.phone.isNotEmpty) ltr(contact.phone),
                        ].map((part) => ' · $part').join(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: TaskStyle.editMuted,
                        ),
                      ),
                    ])),
                  ),
              ],
            ),
      validate: validateContacts,
      editor: (context, draft, onChanged, _) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ContactsEditor(initial: draft, onChanged: onChanged),
      ),
      onCommit: (list) => _commit(stage.copyWith(contacts: list)),
    );
  }
}
