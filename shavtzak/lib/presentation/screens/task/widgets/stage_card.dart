import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/task_item.dart';

final DateFormat _dayFormat = DateFormat('dd/MM');

/// "21/10 · 08:00–10:45 · לובי": the stage's day, time and place, skipping
/// whatever is missing.
String stageSummaryLine(Stage stage) {
  final start = stage.startTime;
  final end = stage.endTime;
  final time = start == null ? null : (end == null ? start : '$start–$end');
  return [
    _dayFormat.format(stage.date),
    if (time != null) time,
    if (stage.hotelLocation.isNotEmpty) stage.hotelLocation,
  ].join(' · ');
}

/// One stage on the event screen: its title line, its details behind a fold,
/// and the tasks under it.
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
        side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(width: 6),
                // Kept left-to-right so "2/5" never renders as "5/2" under RTL.
                Text(
                  '($done/${allTasks.length})',
                  key: Key('stage-task-count-${stage.id}'),
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey.shade700),
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
              child: Column(children: [for (final task in tasks) taskBuilder(task)]),
            ),
        ],
      ),
    );
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
          if (stage.notes.isNotEmpty)
            section('הערות', stage.notes, 'stage-notes-${stage.id}'),
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
              label: Text(contact.phone, textDirection: TextDirection.ltr),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}
