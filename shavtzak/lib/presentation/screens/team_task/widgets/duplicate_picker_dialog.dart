import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';
import 'task_link_picker.dart';
import 'team_task_style.dart';

/// "כפילות של איזו משימה?" (Omer, msg 4581: a long list of titles only): the
/// other tasks grouped as in the list (a card per category / event / topic,
/// coloured like it, with an event's section inside its category), a search
/// bar that matches as the list's does ([teamTaskSearchText]), and per row the
/// title, the owners and the status. [task] itself and the duplicates are not
/// offered. Pops the chosen task's id; null = cancelled.
class DuplicatePickerDialog extends StatefulWidget {
  const DuplicatePickerDialog({
    super.key,
    required this.state,
    required this.task,
    this.now,
  });

  final TeamTasksLoaded state;
  final TeamTask task;

  /// Injected by tests; the event order (nearest first) depends on it.
  final DateTime? now;

  @override
  State<DuplicatePickerDialog> createState() => _DuplicatePickerDialogState();
}

class _DuplicatePickerDialogState extends State<DuplicatePickerDialog> {
  String _query = '';

  List<TeamTask> get _candidates {
    final state = widget.state;
    final eventCategoryById = {for (final e in state.events) e.id: e.categoryId};
    final categoryNameById = {for (final c in state.categories) c.id: c.name};
    final search = normalizeTeamTaskSearch(_query);
    return [
      for (final t in state.all)
        if (t.id != widget.task.id &&
            t.status != TeamTaskStatus.duplicate &&
            (search.isEmpty ||
                teamTaskSearchText(t, eventCategoryById, categoryNameById).contains(search)))
          t,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupTeamTasks(
      _candidates,
      widget.now ?? DateTime.now(),
      categories: widget.state.categories,
      compare: compareTeamTasksByOwners,
    );
    final size = MediaQuery.sizeOf(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        key: const Key('duplicate-picker'),
        title: const Text('כפילות של איזו משימה?'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: SizedBox(
          width: 460,
          height: (size.height * 0.7).clamp(300.0, 620.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RtlArrowKeys(
                child: TextField(
                  key: const Key('duplicate-search'),
                  autofocus: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'חיפוש...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: groups.isEmpty
                    ? Center(
                        child: Text(
                          _query.trim().isEmpty ? 'אין משימות אחרות' : 'לא נמצאו משימות',
                          style: const TextStyle(color: TaskStyle.faintText),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final group in groups) _card(group),
                        ],
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
        ],
      ),
    );
  }

  /// One card, coloured and titled as in the list.
  Widget _card(TeamTaskGroup group) {
    final isCategory = group.type == TaskLinkType.category;
    final colorValue = isCategory
        ? widget.state.categories.where((c) => c.id == group.link?.id).firstOrNull?.colorValue
        : null;
    final rows = <Widget>[
      for (final task in group.tasks) _row(task),
      for (final task in group.severalEventTasks) _row(task, showEvents: true),
      for (final section in group.sections) ...[
        Container(
          key: Key('duplicate-section-${section.key}'),
          color: TeamTaskStyle.sectionHeader,
          padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 10, 5),
          child: Row(
            children: [
              const Icon(Icons.event_outlined, size: 15, color: TaskStyle.neutralText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
        for (final task in section.tasks) _row(task),
      ],
    ];
    return Container(
      key: Key('duplicate-card-${group.key}'),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TaskStyle.stageCard,
        border: Border.all(color: TaskStyle.stageCardBorder),
        borderRadius: BorderRadius.circular(TaskStyle.stageCardRadius),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: TeamTaskStyle.categoryHeader(colorValue),
              padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 10, 7),
              child: Text(
                '${teamTaskGroupKind(group.type)}${group.label}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: TaskStyle.stageCardDivider),
              row,
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(TeamTask task, {bool showEvents = false}) {
    final owners = teamTaskOwnerNames(task);
    return InkWell(
      key: Key('duplicate-original-${task.id}'),
      hoverColor: TeamTaskStyle.rowHover,
      onTap: () {
        Logger.action('tap:duplicateOriginal', {'taskId': task.id});
        Navigator.of(context).pop(task.id);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: TeamTaskStatusIcon(
                status: task.status,
                size: TeamTaskStyle.smallStatusIconSize,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (showEvents && task.events.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final event in task.events) TeamTaskEventChip(name: event.name),
                        ],
                      ),
                    ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TeamTaskStatusChip(status: task.status, dense: true),
                      Text(
                        owners.isEmpty ? 'ללא אחראי' : owners.join(', '),
                        key: Key('duplicate-owners-${task.id}'),
                        style: const TextStyle(
                          fontSize: TaskStyle.rowMetaSize,
                          color: TaskStyle.neutralText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
