import 'package:flutter/material.dart';

import '../../../../domain/entities/subtask.dart';
import '../../../../domain/entities/task_item.dart';
import '../../../../domain/entities/team_member.dart';
import '../task_style.dart';
import 'edit_context.dart';
import 'edit_rules.dart';
import 'editable_value.dart';
import 'value_editors.dart';

/// The editable values of one task, shared by the wide row and the phone
/// card so both edit the same way.
class _TaskValues {
  const _TaskValues(this.task, this.ctx);

  final TaskItem task;
  final EditContext ctx;

  Widget time() {
    final time = task.assemblyTime ?? '';
    return EditableValue<String>(
      key: Key('edit-task-time-${task.id}'),
      value: time,
      wide: ctx.wide,
      sheetTitle: 'שעת התייצבות',
      display: time.isEmpty
          ? editPlaceholder('—')
          : Text(
              time,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
      validate: validateAssemblyTime,
      editor: (context, draft, onChanged, _) => TimeValueEditor(
        initial: draft,
        onChanged: onChanged,
        label: 'שעת התייצבות',
      ),
      onCommit: (value) => ctx.onTaskCommit(value.isEmpty
          ? task.copyWith(clearAssemblyTime: true)
          : task.copyWith(assemblyTime: value)),
    );
  }

  Widget title() => EditableValue<String>(
        key: Key('edit-task-title-${task.id}'),
        value: task.title,
        wide: ctx.wide,
        sheetTitle: 'שם המשימה',
        display: Text(task.title,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        validate: (value) => validateRequiredText(value, 'שם למשימה'),
        editor: (context, draft, onChanged, onSubmit) => TextValueEditor(
          initial: draft,
          onChanged: onChanged,
          onSubmit: onSubmit,
        ),
        onCommit: (value) => ctx.onTaskCommit(task.copyWith(title: value.trim())),
      );

  Widget description() => EditableValue<String>(
        key: Key('edit-task-description-${task.id}'),
        value: task.description,
        wide: ctx.wide,
        sheetTitle: 'תיאור',
        display: task.description.isEmpty
            ? editPlaceholder('הוספת תיאור')
            : Text(task.description,
                style: const TextStyle(color: TaskStyle.editMuted)),
        editor: (context, draft, onChanged, onSubmit) => TextValueEditor(
          initial: draft,
          onChanged: onChanged,
          onSubmit: onSubmit,
          multiline: true,
        ),
        onCommit: (value) =>
            ctx.onTaskCommit(task.copyWith(description: value.trim())),
      );

  Widget assignees() => EditableValue<List<String>>(
        key: Key('edit-task-assignees-${task.id}'),
        value: task.assigneeIds,
        wide: ctx.wide,
        sheetTitle: 'אחראים',
        display: task.assignees.isEmpty
            ? editPlaceholder('בחירת אחראים')
            : AssigneeFaces(members: task.assignees),
        validate: validateAssignees,
        editor: (context, draft, onChanged, _) => AssigneesEditor(
          initial: draft,
          offered: ctx.eventAssignees,
          current: task.assignees,
          onChanged: onChanged,
        ),
        onCommit: (ids) => ctx.onTaskCommit(task.copyWith(assigneeIds: ids)),
      );

  Widget subtasks() => EditableValue<List<Subtask>>(
        key: Key('edit-task-subtasks-${task.id}'),
        value: task.subtasks,
        wide: ctx.wide,
        sheetTitle: 'תתי-משימות',
        display: task.subtasks.isEmpty
            ? editPlaceholder('הוספת תתי-משימות')
            : BulletList(items: [for (final s in task.subtasks) s.title]),
        editor: (context, draft, onChanged, _) => SubtasksEditor(
          initial: draft,
          onChanged: onChanged,
        ),
        onCommit: (list) => ctx.onTaskCommit(task.copyWith(subtasks: list)),
      );

  Widget menu(BuildContext context) => PopupMenuButton<String>(
        key: Key('edit-task-menu-${task.id}'),
        tooltip: 'פעולות',
        icon: const Icon(Icons.more_horiz, color: TaskStyle.editMuted),
        onSelected: (choice) async {
          if (choice == 'delete') {
            ctx.onDeleteTask(task);
            return;
          }
          final to = await pickStage(
            context,
            stages: ctx.stages,
            currentStageId: task.stageId,
          );
          if (to != null) ctx.onMoveTask(task, to);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'move',
            key: Key('edit-task-move'),
            child: ListTile(
              leading: Icon(Icons.swap_horiz),
              title: Text('העברה לשלב אחר…'),
              dense: true,
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            key: Key('edit-task-delete'),
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text('מחיקה', style: TextStyle(color: Colors.red)),
              dense: true,
            ),
          ),
        ],
      );
}

/// The column headings above a wide stage's rows.
class TaskEditHeader extends StatelessWidget {
  const TaskEditHeader({super.key});

  @override
  Widget build(BuildContext context) {
    Widget label(String text) => Text(
          text,
          style: const TextStyle(
            fontSize: 11.5,
            color: TaskStyle.editLabel,
            fontWeight: FontWeight.w500,
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
      child: Row(
        children: [
          const SizedBox(width: TaskStyle.editHandleWidth),
          SizedBox(width: TaskStyle.editTimeWidth, child: label('התייצבות')),
          Expanded(flex: 3, child: label('משימה')),
          const SizedBox(width: 12),
          Expanded(flex: 4, child: label('תיאור')),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: label('אחראים')),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: label('תת-משימות')),
          const SizedBox(width: TaskStyle.editMenuWidth),
        ],
      ),
    );
  }
}

/// One task as a table row, on a wide window. Its ⋮⋮ drags it to another
/// stage.
class TaskEditRow extends StatelessWidget {
  const TaskEditRow({super.key, required this.task, required this.ctx});

  final TaskItem task;
  final EditContext ctx;

  @override
  Widget build(BuildContext context) {
    final values = _TaskValues(task, ctx);
    final highlighted = ctx.highlightId == task.id;
    return AnimatedContainer(
      key: ctx.keyFor(task.id),
      duration: const Duration(milliseconds: 300),
      color: highlighted ? TaskStyle.editHighlight : Colors.transparent,
      child: Container(
        key: Key('edit-task-row-${task.id}'),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: TaskStyle.editRowLine)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: TaskStyle.editHandleWidth,
              child: Draggable<TaskItem>(
                key: Key('edit-task-drag-${task.id}'),
                data: task,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: _DragFeedback(title: task.title),
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.drag_indicator,
                        size: 18, color: TaskStyle.editFaint),
                  ),
                ),
              ),
            ),
            SizedBox(width: TaskStyle.editTimeWidth, child: values.time()),
            Expanded(flex: 3, child: values.title()),
            const SizedBox(width: 12),
            Expanded(flex: 4, child: values.description()),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: values.assignees()),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: values.subtasks()),
            SizedBox(width: TaskStyle.editMenuWidth, child: values.menu(context)),
          ],
        ),
      ),
    );
  }
}

/// One task as a small card, on a phone: every detail stacked.
class TaskEditCard extends StatelessWidget {
  const TaskEditCard({super.key, required this.task, required this.ctx});

  final TaskItem task;
  final EditContext ctx;

  @override
  Widget build(BuildContext context) {
    final values = _TaskValues(task, ctx);
    final highlighted = ctx.highlightId == task.id;
    return AnimatedContainer(
      key: ctx.keyFor(task.id),
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      decoration: BoxDecoration(
        color: highlighted ? TaskStyle.editHighlight : TaskStyle.editCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: TaskStyle.editRowLine),
      ),
      child: Column(
        key: Key('edit-task-card-${task.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 64, child: values.time()),
              Expanded(child: values.title()),
              values.menu(context),
            ],
          ),
          values.description(),
          values.assignees(),
          values.subtasks(),
        ],
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(title),
        ),
      ),
    );
  }
}

/// The assignees as coloured initial circles, with their first names.
class AssigneeFaces extends StatelessWidget {
  const AssigneeFaces({super.key, required this.members});

  final List<TeamMember> members;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final member in members)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: TaskStyle.editAvatarSize,
                height: TaskStyle.editAvatarSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TaskStyle.editAvatarColor(member.id),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials(member.name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                firstName(member.name),
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(width: 6),
            ],
          ),
      ],
    );
  }
}

/// Lines with a bullet each.
class BulletList extends StatelessWidget {
  const BulletList({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Text('• $item',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF4B5563))),
      ],
    );
  }
}
