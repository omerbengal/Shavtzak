import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/utils/task_schedule.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';
import 'assignee_chips.dart';

final DateFormat _timeFormat = DateFormat('HH:mm');
final DateFormat _dayTimeFormat = DateFormat('dd/MM HH:mm');

/// A stage's tasks as a table, for the wide layout's panel: what a phone
/// [TaskRow] carries, laid out as columns.
///
/// Display-only: ticking, opening, editing, deleting and calling are
/// reported through the callbacks. The rows are drawn in the order given.
class StageTaskTable extends StatelessWidget {
  const StageTaskTable({
    super.key,
    required this.tasks,
    required this.now,
    required this.viewerId,
    required this.canTick,
    required this.canManage,
    required this.removedAssigneeIds,
    required this.onSetComplete,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onCallPhone,
  });

  /// Drawn in the order given.
  final List<TaskItem> tasks;

  /// The current time, injected so the colour rules can be tested.
  final DateTime now;

  /// Who is looking: their own chip is drawn in [TaskStyle.mine].
  final String viewerId;

  /// Whether the viewer may complete a task from its tick box.
  final bool Function(TaskItem task) canTick;

  /// Whether the rows carry a pencil and a bin.
  final bool canManage;

  /// A task's assignees no longer on the event, from the managers' check.
  final List<String> Function(TaskItem task) removedAssigneeIds;

  final void Function(TaskItem task, bool isComplete) onSetComplete;
  final ValueChanged<TaskItem> onOpen;
  final ValueChanged<TaskItem> onEdit;
  final ValueChanged<TaskItem> onDelete;
  final ValueChanged<String> onCallPhone;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('stage-table'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const Divider(height: 1),
        for (final task in tasks) ...[
          _TableRow(
            task: task,
            now: now,
            viewerId: viewerId,
            canTick: canTick(task),
            canManage: canManage,
            removedAssigneeIds: removedAssigneeIds(task),
            onSetComplete: (isComplete) => onSetComplete(task, isComplete),
            onOpen: () => onOpen(task),
            onEdit: () => onEdit(task),
            onDelete: () => onDelete(task),
            onCallPhone: onCallPhone,
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }

  Widget _buildHeader() {
    Widget label(String text) => Text(
          text,
          style: const TextStyle(
            fontSize: TaskStyle.tableHeaderSize,
            fontWeight: FontWeight.w600,
            color: TaskStyle.neutralText,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: TaskStyle.tableRowVerticalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: TaskStyle.tableTickWidth),
          SizedBox(width: TaskStyle.tableTimeWidth, child: label('התייצבות')),
          const SizedBox(width: TaskStyle.tableCellGap),
          Expanded(flex: TaskStyle.tableTitleFlex, child: label('משימה')),
          const SizedBox(width: TaskStyle.tableCellGap),
          Expanded(flex: TaskStyle.tableAssigneesFlex, child: label('אחראים')),
          const SizedBox(width: TaskStyle.tableCellGap),
          SizedBox(
              width: TaskStyle.tableSubtasksWidth, child: label('תת-משימות')),
          if (canManage) const SizedBox(width: TaskStyle.tableActionsWidth),
        ],
      ),
    );
  }
}

/// One task as a table row; tracks the mouse so its pencil and bin show
/// only while it is hovered.
class _TableRow extends StatefulWidget {
  const _TableRow({
    required this.task,
    required this.now,
    required this.viewerId,
    required this.canTick,
    required this.canManage,
    required this.removedAssigneeIds,
    required this.onSetComplete,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onCallPhone,
  });

  final TaskItem task;
  final DateTime now;
  final String viewerId;
  final bool canTick;
  final bool canManage;
  final List<String> removedAssigneeIds;
  final ValueChanged<bool> onSetComplete;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onCallPhone;

  @override
  State<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends State<_TableRow> {
  bool _hovered = false;

  TaskItem get task => widget.task;

  @override
  Widget build(BuildContext context) {
    final isLate = taskDueStatus(task, widget.now) == TaskDueStatus.overdue;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        key: Key('table-row-${task.id}'),
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: TaskStyle.tableRowVerticalPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: TaskStyle.tableTickWidth, child: _buildTick()),
              SizedBox(
                width: TaskStyle.tableTimeWidth,
                child: _buildTime(isLate),
              ),
              const SizedBox(width: TaskStyle.tableCellGap),
              Expanded(
                flex: TaskStyle.tableTitleFlex,
                child: _buildTask(isLate),
              ),
              const SizedBox(width: TaskStyle.tableCellGap),
              Expanded(
                flex: TaskStyle.tableAssigneesFlex,
                child: AssigneeChips(
                  task: task,
                  viewerId: widget.viewerId,
                  removedAssigneeIds: widget.removedAssigneeIds,
                  onCallPhone: widget.onCallPhone,
                  keyPrefix: 'table',
                ),
              ),
              const SizedBox(width: TaskStyle.tableCellGap),
              SizedBox(
                width: TaskStyle.tableSubtasksWidth,
                child: _buildSubtasks(),
              ),
              if (widget.canManage)
                SizedBox(
                  width: TaskStyle.tableActionsWidth,
                  child: _buildActions(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A tick box for a task without subtasks; one with them completes by
  /// itself once they all are, so it has none.
  Widget? _buildTick() {
    if (task.hasSubtasks) return null;
    return Checkbox(
      key: Key('table-tick-${task.id}'),
      value: task.isComplete,
      onChanged:
          widget.canTick ? (value) => widget.onSetComplete(value ?? false) : null,
    );
  }

  /// The report time, orange in the next half hour and red once late.
  Widget _buildTime(bool isLate) {
    final isSoon = isDueSoon(task, widget.now);
    final color = isLate
        ? TaskStyle.lateDark
        : (isSoon ? TaskStyle.soonDark : TaskStyle.neutralText);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        task.hasAssemblyTime ? ltr(task.assemblyTime!) : 'ללא שעה',
        key: Key('table-time-${task.id}'),
        style: TextStyle(
          fontSize: TaskStyle.rowMetaSize,
          color: color,
          fontWeight: isLate || isSoon ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  /// The title with its late mark, then the description and the update line.
  Widget _buildTask(bool isLate) {
    final update = _updateLine();
    const meta = TextStyle(
      fontSize: TaskStyle.rowMetaSize,
      color: TaskStyle.neutralText,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // Wraps in full: a name never collapses into "…".
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontSize: TaskStyle.rowTitleSize,
                    fontWeight: FontWeight.w600,
                    decoration: task.isComplete
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    color: task.isComplete ? TaskStyle.faintText : null,
                  ),
                ),
              ),
              if (isLate) ...[
                const SizedBox(width: 6),
                Container(
                  key: Key('table-late-${task.id}'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(
                    color: TaskStyle.late,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'באיחור',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: TaskStyle.lateMarkSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(task.description, style: meta),
          ],
          if (update != null) ...[
            const SizedBox(height: 4),
            Text(update, key: Key('table-update-${task.id}'), style: meta),
          ],
        ],
      ),
    );
  }

  Widget _buildSubtasks() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        task.hasSubtasks
            ? ltr('${task.doneSubtaskCount}/${task.subtasks.length}')
            : '—',
        style: TextStyle(
          fontSize: TaskStyle.rowMetaSize,
          fontWeight: task.hasSubtasks ? FontWeight.w600 : FontWeight.normal,
          color: task.hasSubtasks && task.isComplete
              ? TaskStyle.doneDark
              : TaskStyle.neutralText,
        ),
      ),
    );
  }

  /// The pencil and the bin: invisible until the row is hovered, yet still
  /// tappable, so a touch screen reaches them too.
  Widget _buildActions() {
    return Opacity(
      opacity: _hovered ? 1 : 0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('table-edit-${task.id}'),
            tooltip: 'עריכה',
            icon: const Icon(Icons.edit, color: TaskStyle.edit),
            onPressed: widget.onEdit,
          ),
          IconButton(
            key: Key('table-delete-${task.id}'),
            tooltip: 'מחיקה',
            icon: const Icon(Icons.delete, color: TaskStyle.delete),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }

  /// The note, then its author and time, as on the phone row: the time alone
  /// on today, with the date on any other day. Null when there is no update.
  String? _updateLine() {
    final note = task.assigneeUpdate;
    if (note == null || note.isEmpty) return null;
    final at = task.assigneeUpdateAt;
    final now = widget.now;
    final isToday = at != null &&
        at.year == now.year &&
        at.month == now.month &&
        at.day == now.day;
    final byline = [
      if (task.assigneeUpdateByName != null) task.assigneeUpdateByName!,
      if (at != null) ltr((isToday ? _timeFormat : _dayTimeFormat).format(at)),
    ].join(', ');
    return byline.isEmpty ? note : '$note · $byline';
  }
}
