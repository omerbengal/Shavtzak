import 'package:flutter/material.dart';

import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../task/task_style.dart';
import 'team_task_actions.dart';
import 'team_task_mentions.dart';
import 'team_task_style.dart';

/// One task in the list (design A, Omer round 3): the status circle, the
/// title, and under it the urgency when not "רגילה", the deadline (red when
/// late) and the owners' initials. With [showEvents] (a task linked to
/// several events, on top of a category's card) the events' names show as
/// small chips under the title (16/11/2026).
///
/// [canChangeStatus] makes the status circle open the status menu, and
/// [onAddUpdate] adds a button for a new update, both without opening the
/// task (Omer, round 4: "המשימות שלי").
class TeamTaskRow extends StatelessWidget {
  const TeamTaskRow({
    super.key,
    required this.task,
    required this.now,
    required this.viewerId,
    required this.onTap,
    this.showEvents = false,
    this.canChangeStatus = false,
    this.onAddUpdate,
    this.selected = false,
    this.showCreated = false,
    this.mention,
    this.mentionTitle,
    this.mentionByName,
  });

  /// One tag of the viewer, who is only tagged ("@") in the task
  /// (19/11/2026): the box they tick when they did what they were tagged for
  /// stands where the status is, and a coloured @ marks the title. Each tag
  /// is a row of its own (20/11/2026), titled [mentionTitle] (the text of
  /// the update that tagged them), with the task's title under it and
  /// [mentionByName] (who tagged them) and when.
  final TeamTaskMention? mention;
  final String? mentionTitle;
  final String? mentionByName;

  /// "כל המשימות" (msg 4480): the creation date in the row's bottom-left
  /// corner.
  final bool showCreated;

  /// Its task is the one open in the side panel (wide window, round 7).
  final bool selected;

  final bool canChangeStatus;
  final VoidCallback? onAddUpdate;

  /// The room around a tappable status circle, so a finger can hit it.
  static const double _tapPadding = 6;

  /// The task's events as chips (a task linked to several events).
  final bool showEvents;

  final TeamTask task;
  final DateTime now;
  final String viewerId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final faded = !task.status.isActive;
    return InkWell(
      key: Key(mention == null
          ? 'team-task-row-${task.id}'
          : 'team-task-row-${task.id}-${mention!.updateId}'),
      onTap: onTap,
      // Visible on a mouse hover (desktop) over every row (Omer, round 4).
      hoverColor: TeamTaskStyle.rowHover,
      child: ColoredBox(
        color: selected ? TeamTaskStyle.rowSelected : Colors.transparent,
        child: Opacity(
          opacity: faded ? 0.6 : 1,
          child: _full(),
        ),
      ),
    );
  }

  TextStyle _titleStyle(double size, FontWeight weight) {
    final done = task.status == TeamTaskStatus.done;
    return TextStyle(
      fontSize: size,
      fontWeight: done ? FontWeight.w500 : weight,
      color: done ? TaskStyle.faintText : null,
      decoration: done ? TextDecoration.lineThrough : null,
    );
  }

  /// The status circle, opening the status menu when [canChangeStatus].
  Widget _status(double size) {
    final mention = this.mention;
    if (mention != null) {
      return MentionDoneBox(task: task, mention: mention, size: size);
    }
    final icon = TeamTaskStatusIcon(status: task.status, size: size);
    if (!canChangeStatus) return icon;
    return TeamTaskStatusMenu(
      key: Key('team-task-status-tap-${task.id}'),
      task: task,
      child: Padding(padding: const EdgeInsets.all(_tapPadding), child: icon),
    );
  }

  /// The width the status circle and the gap after it take: what the lines
  /// under the title are indented by.
  double _lead(double size) =>
      canChangeStatus || mention != null ? size + 2 * _tapPadding + 2 : size + 8;

  List<Widget> _owners(double size) => [
        for (final owner in teamTaskOwnerChips(task))
          MemberInitialsAvatar(
            memberId: owner.id,
            name: owner.name,
            highlight: owner.id == viewerId,
            size: size,
          ),
      ];

  Widget _full() {
    final late = isTeamTaskLate(task, now);
    final deadline = task.deadlineDate;
    final owners = _owners(TeamTaskStyle.avatarSize);
    final lead = _lead(TeamTaskStyle.statusIconSize);
    final urgent = task.urgency != TeamTaskUrgency.normal;
    final events = showEvents ? task.events : const [];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _status(TeamTaskStyle.statusIconSize),
              SizedBox(width: canChangeStatus || mention != null ? 2 : 8),
              if (mention != null) ...[
                MentionMark(key: Key('team-task-mention-mark-${task.id}')),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  mention == null ? task.title : (mentionTitle ?? task.title),
                  style: _titleStyle(TaskStyle.rowTitleSize, FontWeight.w600),
                ),
              ),
              if (onAddUpdate != null)
                IconButton(
                  key: Key('team-task-quick-update-${task.id}'),
                  tooltip: 'הוספת עדכון',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_comment_outlined, size: 20, color: TaskStyle.mine),
                  onPressed: onAddUpdate,
                ),
            ],
          ),
          if (mention != null) ..._mentionLines(lead),
          if (mention == null && events.isNotEmpty)
            Padding(
              padding: EdgeInsetsDirectional.only(start: lead, top: 4),
              child: Wrap(
                key: Key('team-task-events-${task.id}'),
                spacing: 4,
                runSpacing: 4,
                children: [for (final event in events) TeamTaskEventChip(name: event.name)],
              ),
            ),
          if (mention == null && (urgent || deadline != null || owners.isNotEmpty || showCreated))
            Padding(
              padding: EdgeInsetsDirectional.only(start: lead, top: 5),
              child: _withCreated(Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (urgent)
                    TeamTaskUrgencyChip(
                      key: Key('team-task-urgency-${task.id}'),
                      urgency: task.urgency,
                    ),
                  if (deadline != null)
                    Text(
                      late ? 'באיחור · עד ${shortDate(deadline)}' : 'עד ${shortDate(deadline)}',
                      key: Key('team-task-deadline-${task.id}'),
                      style: TextStyle(
                        fontSize: TaskStyle.rowMetaSize,
                        color: late ? TaskStyle.late : TaskStyle.neutralText,
                        fontWeight: late ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ...owners,
                ],
              )),
            ),
        ],
      ),
    );
  }

  /// A tag's lines under its title (Omer, 20/11/2026): the task it is in,
  /// smaller, as a chip like an event's, then who tagged them and when.
  List<Widget> _mentionLines(double lead) {
    final mention = this.mention!;
    const meta = TextStyle(fontSize: TaskStyle.rowMetaSize, color: TaskStyle.neutralText);
    final by = mentionByName;
    return [
      if ((mentionTitle ?? task.title) != task.title)
        Padding(
          padding: EdgeInsetsDirectional.only(start: lead, top: 4),
          child: Wrap(
            key: Key('team-task-mention-parent-${task.id}-${mention.updateId}'),
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('במשימה:', style: meta),
              TeamTaskEventChip(name: task.title),
            ],
          ),
        ),
      Padding(
        padding: EdgeInsetsDirectional.only(start: lead, top: 4),
        child: Text(
          '${by == null ? 'תויגת' : 'תויגת ע"י $by'} · ${logStamp(mention.at)}',
          style: meta,
        ),
      ),
    ];
  }

  /// [meta] with the creation date at the row's end (left in Hebrew), on its
  /// last line, when [showCreated].
  ///
  /// When the line is too narrow to keep [_minMetaWidth] for the chips beside
  /// the date ("נוצרה DD/MM, HH:mm" is longer than the old "d.M", msg 4516),
  /// the date goes under them, still at the left.
  Widget _withCreated(Widget meta) {
    if (!showCreated) return meta;
    final created = TeamTaskCreatedText(key: Key('team-task-created-${task.id}'), task: task);
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
        text: TextSpan(text: teamTaskCreatedLabel(task), style: teamTaskCreatedStyle),
        textDirection: TextDirection.rtl,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      // Room for the "new" dot too, so a row does not jump when it goes.
      final dateWidth =
          painter.width + TeamTaskCreatedText.dotSize + TeamTaskCreatedText.dotGap;
      painter.dispose();
      if (box.maxWidth - dateWidth - 8 < _minMetaWidth) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            meta,
            const SizedBox(height: 2),
            Align(alignment: AlignmentDirectional.centerEnd, child: created),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: meta),
          const SizedBox(width: 8),
          created,
        ],
      );
    });
  }

  /// The least room the chips keep beside the creation date.
  static const double _minMetaWidth = 170;
}
