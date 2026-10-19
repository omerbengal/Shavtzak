import 'package:flutter/material.dart';

import '../../../../core/utils/task_schedule.dart';
import '../../../../core/utils/validators.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/task_item.dart';

/// One stage on the event screen: a title line that folds the rest of the
/// card away, and under it the stage's details (behind a fold of their own)
/// and its tasks.
///
/// Display-only like the task card: the screen owns which folds are open and
/// what every button does. [taskBuilder] draws each of [tasks].
class StageCard extends StatelessWidget {
  const StageCard({
    super.key,
    required this.stage,
    required this.tasks,
    required this.allTasks,
    required this.canManage,
    required this.isOpen,
    required this.onToggleOpen,
    required this.isDetailsOpen,
    required this.onToggleDetails,
    required this.onEdit,
    required this.onDelete,
    required this.onAddTask,
    required this.onCallPhone,
    required this.taskBuilder,
  });

  final Stage stage;

  /// The stage's tasks that pass the current tab, search and filter.
  final List<TaskItem> tasks;

  /// Every task of the stage, for the done/total count.
  final List<TaskItem> allTasks;

  final bool canManage;

  /// Whether the card shows more than its title line.
  final bool isOpen;
  final VoidCallback onToggleOpen;

  final bool isDetailsOpen;
  final VoidCallback onToggleDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddTask;
  final ValueChanged<String> onCallPhone;
  final Widget Function(TaskItem task) taskBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = allTasks.where((task) => task.isComplete).length;
    return Card(
      key: Key('stage-card-${stage.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('stage-toggle-${stage.id}'),
            onTap: onToggleOpen,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _ProgressFill(
                    stageId: stage.id,
                    done: done,
                    total: allTasks.length,
                    doneColor: Colors.green.withValues(alpha: 0.2),
                    leftColor:
                        theme.colorScheme.primary.withValues(alpha: 0.08),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 4, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          isOpen ? Icons.expand_less : Icons.chevron_left,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stage.title,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              stageSummaryLine(stage),
                              key: Key('stage-summary-${stage.id}'),
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey.shade800),
                            ),
                            if (stage.notes.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.sticky_note_2_outlined,
                                      size: 16,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      stage.notes,
                                      key: Key('stage-notes-${stage.id}'),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: Colors.grey.shade800),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 2),
                            // On the left, opposite the title's side. The
                            // numbers are kept left-to-right so "2/5" never
                            // renders as "5/2" under RTL.
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(
                                'משימות: \u2066$done/${allTasks.length}\u2069',
                                key: Key('stage-task-count-${stage.id}'),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey.shade700),
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
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: onEdit,
                        ),
                        IconButton(
                          key: Key('stage-delete-${stage.id}'),
                          tooltip: 'מחיקת השלב',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: onDelete,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isOpen)
            Column(
              key: Key('stage-body-${stage.id}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildBody(theme),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildBody(ThemeData theme) {
    return [
      if (stage.hasDetails) ...[
        const Divider(height: 1),
        InkWell(
          key: Key('stage-details-toggle-${stage.id}'),
          onTap: onToggleDetails,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isDetailsOpen ? Icons.expand_less : Icons.chevron_left,
                  size: 22,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(width: 4),
                Text('פרטי השלב', style: theme.textTheme.titleSmall),
              ],
            ),
          ),
        ),
        if (isDetailsOpen) _buildDetails(theme),
      ],
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 0),
        child: Row(
          children: [
            Text(
              'משימות',
              style: theme.textTheme.titleSmall,
            ),
            const Spacer(),
            if (canManage)
              IconButton(
                key: Key('stage-add-task-${stage.id}'),
                tooltip: 'משימה חדשה בשלב',
                icon: Icon(
                  Icons.add_circle,
                  color: theme.colorScheme.primary,
                ),
                onPressed: onAddTask,
              ),
          ],
        ),
      ),
      if (tasks.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            allTasks.isEmpty ? 'אין עדיין משימות בשלב זה' : 'אין משימות תואמות',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey.shade600),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child:
              Column(children: [for (final task in tasks) taskBuilder(task)]),
        ),
    ];
  }

  Widget _buildDetails(ThemeData theme) {
    Widget section(String title, String text, String key) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 2),
              Text(text, key: Key(key), style: theme.textTheme.bodyMedium),
            ],
          ),
        );

    return Padding(
      key: Key('stage-details-${stage.id}'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stage.requirements.isNotEmpty)
            section('דרישות מהמלון ולוגיסטיקה', stage.requirements,
                'stage-requirements-${stage.id}'),
          if (stage.contacts.isNotEmpty) ...[
            Text(
              'אנשי קשר',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            for (final contact in stage.contacts) _buildContact(theme, contact),
          ],
        ],
      ),
    );
  }

  Widget _buildContact(ThemeData theme, StageContact contact) {
    final label = contact.role.isEmpty
        ? contact.name
        : '${contact.name} · ${contact.role}';
    return Padding(
      key: Key('stage-contact-${contact.id}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 18, color: Colors.grey.shade700),
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
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

/// The title line's background, doubling as the stage's progress bar: the
/// done share of its tasks in [doneColor] growing from the left edge, the rest
/// in [leftColor]. A stage without tasks is all [leftColor].
class _ProgressFill extends StatelessWidget {
  const _ProgressFill({
    required this.stageId,
    required this.done,
    required this.total,
    required this.doneColor,
    required this.leftColor,
  });

  final String stageId;
  final int done;
  final int total;
  final Color doneColor;
  final Color leftColor;

  @override
  Widget build(BuildContext context) {
    final left = total - done;
    // Laid out left-to-right so the fill grows from the left under RTL too.
    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (done > 0)
          Expanded(
            flex: done,
            child: ColoredBox(
              key: Key('stage-progress-done-$stageId'),
              color: doneColor,
            ),
          ),
        if (left > 0 || total == 0)
          Expanded(
            flex: left > 0 ? left : 1,
            child: ColoredBox(
              key: Key('stage-progress-left-$stageId'),
              color: leftColor,
            ),
          ),
      ],
    );
  }
}
