import 'package:flutter/material.dart';

import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../core/utils/validators.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';

/// A stage at the top of the sheet: its title, then its day, time and place,
/// with the pencil and the bin for managers.
class StageSheetHeader extends StatelessWidget {
  const StageSheetHeader({
    super.key,
    required this.stage,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final Stage stage;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wraps in full: a name never collapses into "…".
              Text(stage.title),
              Text(
                stageSummaryLine(stage),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: TaskStyle.neutralText,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        if (canManage) ...[
          IconButton(
            key: Key('stage-edit-${stage.id}'),
            tooltip: 'עריכת השלב',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit, color: TaskStyle.edit),
            onPressed: onEdit,
          ),
          IconButton(
            key: Key('stage-delete-${stage.id}'),
            tooltip: 'מחיקת השלב',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete, color: TaskStyle.delete),
            onPressed: onDelete,
          ),
        ],
      ],
    );
  }
}

/// A stage in the sheet: its notes, hotel requirements and contacts, the
/// "חסרות | הכל" switch, and its tasks.
///
/// [rows] come already held by the screen, so a row ticked in "חסרות" stays
/// where it is until the person switches view.
class StageSheetBody extends StatelessWidget {
  const StageSheetBody({
    super.key,
    required this.stage,
    required this.rows,
    required this.progress,
    required this.missingOnly,
    required this.onSwitch,
    required this.rowBuilder,
    required this.canManage,
    required this.onAddTask,
    required this.onCallPhone,
    this.tableBuilder,
  });

  final Stage stage;
  final List<TaskItem> rows;

  /// On a wide screen the rows are one table, built by this.
  final Widget Function(List<TaskItem> rows)? tableBuilder;

  /// The whole stage, live: the switch's counts and the done count.
  final TaskProgress progress;
  final bool missingOnly;

  /// Reports the side chosen: true for the missing tasks only.
  final ValueChanged<bool> onSwitch;
  final Widget Function(TaskItem task) rowBuilder;
  final bool canManage;
  final VoidCallback onAddTask;
  final ValueChanged<String> onCallPhone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: Key('stage-sheet-${stage.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildSections(theme),
          ),
        ),
        if (progress.total == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'אין עדיין משימות בשלב זה',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: TaskStyle.neutralText),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  key: const Key('stage-switch'),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    selectedBackgroundColor: TaskStyle.mine,
                    selectedForegroundColor: Colors.white,
                  ),
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text('חסרות (${progress.missing})'),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('הכל (${progress.total})'),
                    ),
                  ],
                  selected: {missingOnly},
                  onSelectionChanged: (selection) => onSwitch(selection.first),
                ),
                Text(
                  '${ltr('${progress.done}/${progress.total}')} הושלמו',
                  key: Key('stage-done-count-${stage.id}'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: TaskStyle.neutralText),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'כל המשימות בשלב הושלמו',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: TaskStyle.doneDark),
              ),
            ),
          if (tableBuilder != null && rows.isNotEmpty)
            tableBuilder!(rows)
          else
            for (final task in rows) rowBuilder(task),
        ],
        if (canManage)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                key: Key('stage-add-task-${stage.id}'),
                onPressed: onAddTask,
                icon: const Icon(Icons.add),
                label: const Text('משימה חדשה'),
              ),
            ),
          ),
      ],
    );
  }

  /// The notes, the hotel requirements and the contacts, each one section;
  /// those with nothing in them are left out.
  List<Widget> _buildSections(ThemeData theme) {
    Widget title(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(color: TaskStyle.mine),
          ),
        );
    Widget section(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
    return [
      if (stage.notes.isNotEmpty)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.sticky_note_2_outlined,
                size: 16,
                color: TaskStyle.neutralText,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(stage.notes, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      if (stage.requirements.isNotEmpty)
        section([
          title('דרישות מהמלון ולוגיסטיקה'),
          Text(stage.requirements, style: theme.textTheme.bodyMedium),
        ]),
      if (stage.contacts.isNotEmpty)
        section([
          title('אנשי קשר'),
          for (final contact in stage.contacts) _buildContact(theme, contact),
        ]),
    ];
  }

  Widget _buildContact(ThemeData theme, StageContact contact) {
    final label = contact.role.isEmpty
        ? contact.name
        : '${contact.name} · ${contact.role}';
    // Capped, so on a wide sheet the phone stays near the name.
    final row = Row(
      key: Key('stage-contact-${contact.id}'),
      children: [
        const Icon(Icons.person_outline, size: 18, color: TaskStyle.neutralText),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        if (contact.phone.isNotEmpty)
          TextButton.icon(
            key: Key('stage-contact-call-${contact.id}'),
            onPressed: () => onCallPhone(contact.phone),
            icon: const Icon(Icons.phone, size: 18),
            label: Text(
              Validators.formatPhoneNumber(contact.phone),
              textDirection: TextDirection.ltr,
            ),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: TaskStyle.readableWidth),
      child: row,
    );
  }
}
