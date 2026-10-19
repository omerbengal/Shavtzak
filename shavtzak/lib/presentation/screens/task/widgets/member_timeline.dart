import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/subtask.dart';
import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';

final DateFormat _dayKeyFormat = DateFormat('yyyy-MM-dd');

/// "המשימות שלי": the viewer's tasks threaded through every stage of the
/// event, in time order, under a header per day.
///
/// It opens on the current stage: earlier stages fold into one line above
/// it, its own tasks get full rows to tick, and later stages show their
/// tasks compactly. Stages without the viewer's tasks stay as one line, so
/// the list is also the event's schedule. Late tasks of the viewer, from any
/// stage, are pinned on top.
///
/// Where it opens is taken once, when it is created, so time passing moves
/// the highlight and the captions but never re-folds or reshapes the list.
class MemberTimeline extends StatefulWidget {
  const MemberTimeline({
    super.key,
    required this.board,
    required this.viewerId,
    required this.now,
    required this.canTick,
    required this.onOpenTask,
    required this.onOpenStage,
    required this.onSetComplete,
    required this.onToggleSubtask,
    required this.onOpenMyLate,
    required this.onShowAllStages,
    this.bottomPadding = 0,
  });

  final EventTaskBoard board;
  final String viewerId;
  final DateTime now;

  /// False while a manager previews someone else's timeline.
  final bool canTick;

  final ValueChanged<TaskItem> onOpenTask;
  final ValueChanged<Stage> onOpenStage;
  final void Function(TaskItem task, bool isComplete) onSetComplete;
  final void Function(TaskItem task, Subtask subtask, bool isDone)
      onToggleSubtask;

  /// Opens the viewer's late tasks, when there are several.
  final VoidCallback onOpenMyLate;

  /// Switches to "כל השלבים".
  final VoidCallback onShowAllStages;

  /// Room below the last stage for an open sheet.
  final double bottomPadding;

  @override
  State<MemberTimeline> createState() => _MemberTimelineState();
}

class _MemberTimelineState extends State<MemberTimeline> {
  /// The stage the timeline opened on: it keeps the full rows.
  String? _anchorId;
  Set<String> _folded = const {};
  bool _earlierOpen = false;

  @override
  void initState() {
    super.initState();
    _takeAnchor();
  }

  @override
  void didUpdateWidget(MemberTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final anchorId = _anchorId;
    final anchorGone = anchorId == null
        ? widget.board.stages.isNotEmpty
        : widget.board.stageById(anchorId) == null;
    if (anchorGone) _takeAnchor();
  }

  void _takeAnchor() {
    final anchor = timelineAnchor(widget.board.stages, widget.now);
    _anchorId = anchor?.id;
    _folded = anchor == null
        ? const {}
        : foldedStageIds(widget.board.stages, anchor);
  }

  void _toggleEarlier() {
    Logger.action('toggle:myEarlierStages', {'on': !_earlierOpen});
    setState(() => _earlierOpen = !_earlierOpen);
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final now = widget.now;
    final mine = [
      for (final task in board.tasks)
        if (task.isAssignedTo(widget.viewerId)) task,
    ];
    final groups = stagesToShow(
      stages: board.stages,
      visibleTasks: mine,
      showEveryStage: true,
    );
    final late = lateTasks(mine, now);
    final folded = {
      for (final id in _folded)
        if (board.stageById(id) != null) id,
    };
    final marks = _LiveMarks(
      highlightId: timelineAnchor(board.stages, now)?.id,
      currentIds: {for (final stage in currentStages(board.stages, now)) stage.id},
      nextId: _nextStageId(board.stages, now),
    );

    final days = <DateTime, List<StageTasks>>{};
    for (final group in groups) {
      if (!_earlierOpen && folded.contains(group.stage.id)) continue;
      final date = group.stage.date;
      days
          .putIfAbsent(DateTime(date.year, date.month, date.day), () => [])
          .add(group);
    }

    return CustomScrollView(
      slivers: [
        if (late.isNotEmpty)
          SliverToBoxAdapter(
            child: _LateBanner(
              late: late,
              onOpenTask: widget.onOpenTask,
              onOpenMyLate: widget.onOpenMyLate,
            ),
          ),
        if (mine.isEmpty)
          SliverToBoxAdapter(
            child: _NoTasksNote(onShowAllStages: widget.onShowAllStages),
          ),
        if (folded.isNotEmpty)
          SliverToBoxAdapter(
            child: _FoldLine(
              text: _foldText(folded, mine),
              isOpen: _earlierOpen,
              onToggle: _toggleEarlier,
            ),
          ),
        for (final entry in days.entries)
          SliverMainAxisGroup(
            slivers: [
              PinnedHeaderSliver(
                child: _DayHeader(day: entry.key, now: now),
              ),
              SliverList.list(
                children: [
                  for (final group in entry.value)
                    _buildStage(group, marks),
                ],
              ),
            ],
          ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: widget.bottomPadding + 24),
        ),
      ],
    );
  }

  String _foldText(Set<String> folded, List<TaskItem> mine) {
    final stages = hebrewCount(
      folded.length,
      one: 'שלב קודם אחד',
      many: 'שלבים קודמים',
    );
    final mineThere =
        mine.where((task) => folded.contains(task.stageId)).toList();
    if (mineThere.isEmpty) return stages;
    final done = mineThere.where((task) => task.isComplete).length;
    return '$stages · ${hebrewCount(done, one: 'משימה אחת שלך הושלמה', many: 'משימות שלך הושלמו')}';
  }

  /// The first timed stage, in screen order, that has not started yet.
  String? _nextStageId(List<Stage> stages, DateTime now) {
    for (final stage in stages) {
      final span = stageSpan(stage, stages);
      if (span != null && span.start.isAfter(now)) return stage.id;
    }
    return null;
  }

  Widget _buildStage(StageTasks group, _LiveMarks marks) {
    final stage = group.stage;
    final isOpening = stage.id == _anchorId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StageLine(
            stage: stage,
            myTasks: group.tasks,
            isOpening: isOpening,
            isHighlighted: stage.id == marks.highlightId,
            kicker: marks.currentIds.contains(stage.id)
                ? _Kicker.now
                : (stage.id == marks.nextId ? _Kicker.next : null),
            onOpen: () => widget.onOpenStage(stage),
          ),
          for (final task in group.tasks)
            _TaskLine(
              task: task,
              viewerId: widget.viewerId,
              now: widget.now,
              isFull: isOpening,
              canTick: widget.canTick,
              onOpen: () => widget.onOpenTask(task),
              onSetComplete: (value) => widget.onSetComplete(task, value),
              onToggleSubtask: (subtask, value) =>
                  widget.onToggleSubtask(task, subtask, value),
            ),
        ],
      ),
    );
  }
}

/// What moves with the clock: the highlighted stage, the stages running now
/// and the next one to start.
class _LiveMarks {
  const _LiveMarks({
    required this.highlightId,
    required this.currentIds,
    required this.nextId,
  });

  final String? highlightId;
  final Set<String> currentIds;
  final String? nextId;
}

enum _Kicker { now, next }

const double _railInset = 10;

/// A row hung on the timeline's rail: the line runs down the start side of
/// [child], with [marker] on it.
class _Railed extends StatelessWidget {
  const _Railed({
    required this.marker,
    required this.child,
    this.markerSize = 16,
    this.markerTop = 12,
  });

  final Widget marker;
  final Widget child;
  final double markerSize;
  final double markerTop;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsetsDirectional.only(start: _railInset),
          padding: const EdgeInsetsDirectional.only(start: 12),
          decoration: const BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: TaskStyle.rest, width: 2),
            ),
          ),
          child: child,
        ),
        PositionedDirectional(
          start: _railInset + 1 - markerSize / 2,
          top: markerTop,
          child: SizedBox(
            width: markerSize,
            height: markerSize,
            child: marker,
          ),
        ),
      ],
    );
  }
}

/// The time column on the start side: two short lines, left to right.
class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.top, this.bottom, this.topColor});

  final String top;
  final String? bottom;
  final Color? topColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TaskStyle.timeColumnWidth,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Text(
              top,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: topColor,
              ),
            ),
            if (bottom != null)
              Text(
                bottom!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: TaskStyle.faintText,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StageLine extends StatelessWidget {
  const _StageLine({
    required this.stage,
    required this.myTasks,
    required this.isOpening,
    required this.isHighlighted,
    required this.kicker,
    required this.onOpen,
  });

  final Stage stage;
  final List<TaskItem> myTasks;
  final bool isOpening;
  final bool isHighlighted;
  final _Kicker? kicker;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final startMinute = minutesOfDay(stage.startTime);
    final endMinute = minutesOfDay(stage.endTime);
    final start = startMinute == null ? null : stage.startTime;
    // An end only when it really comes after the start.
    final end = startMinute != null && endMinute != null && endMinute > startMinute
        ? stage.endTime
        : null;
    final allDone =
        myTasks.isNotEmpty && myTasks.every((task) => task.isComplete);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TimeColumn(
          top: start == null ? '' : ltr(start),
          bottom: end == null ? null : ltr(end),
        ),
        Expanded(
          child: _Railed(
            marker: _StageNode(isHighlighted: isHighlighted, isDone: allDone),
            child: InkWell(
              key: Key('my-stage-${stage.id}'),
              onTap: onOpen,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(top: 6, bottom: 2),
                padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 10, 7),
                decoration: isHighlighted
                    ? BoxDecoration(
                        color: TaskStyle.currentLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: TaskStyle.current.withValues(alpha: 0.45),
                          width: 1.5,
                        ),
                      )
                    : null,
                child: myTasks.isEmpty ? _buildOneLine() : _buildFull(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildKicker() {
    switch (kicker) {
      case _Kicker.now:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: TaskStyle.current,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'עכשיו',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case _Kicker.next:
        return const Text(
          'השלב הבא',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: TaskStyle.faintText,
          ),
        );
      case null:
        return null;
    }
  }

  Widget _buildOneLine() {
    final kickerWidget = _buildKicker();
    final place = stage.hotelLocation;
    return Row(
      children: [
        if (kickerWidget != null) ...[kickerWidget, const SizedBox(width: 6)],
        Expanded(
          child: Text(
            place.isEmpty ? stage.title : '${stage.title} · $place',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'אין לך משימות',
          style: TextStyle(fontSize: 12, color: TaskStyle.faintText),
        ),
      ],
    );
  }

  Widget _buildFull() {
    final kickerWidget = _buildKicker();
    final open = myTasks.where((task) => !task.isComplete).length;
    final String? count;
    if (isOpening) {
      count = open == 0
          ? null
          : hebrewCount(open, one: 'פתוחה אחת שלך', many: 'פתוחות שלך');
    } else {
      count = hebrewCount(
        myTasks.length,
        one: 'משימה אחת שלך',
        many: 'משימות שלך',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kickerWidget != null) ...[
          Align(alignment: AlignmentDirectional.centerStart, child: kickerWidget),
          const SizedBox(height: 2),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                stage.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (count != null)
              Text(
                count,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: TaskStyle.mine,
                ),
              ),
          ],
        ),
        if (stage.hotelLocation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: TaskStyle.neutralText,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    stage.hotelLocation,
                    style: const TextStyle(
                      fontSize: 12,
                      color: TaskStyle.neutralText,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StageNode extends StatelessWidget {
  const _StageNode({required this.isHighlighted, required this.isDone});

  final bool isHighlighted;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    if (isDone && !isHighlighted) {
      return Container(
        decoration: const BoxDecoration(
          color: TaskStyle.done,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 11, color: Colors.white),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isHighlighted ? TaskStyle.current : TaskStyle.faintText,
          width: isHighlighted ? 4 : 2,
        ),
      ),
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({
    required this.task,
    required this.viewerId,
    required this.now,
    required this.isFull,
    required this.canTick,
    required this.onOpen,
    required this.onSetComplete,
    required this.onToggleSubtask,
  });

  final TaskItem task;
  final String viewerId;
  final DateTime now;

  /// Full rows, with tick boxes, on the stage the timeline opened on;
  /// compact ones elsewhere.
  final bool isFull;
  final bool canTick;
  final VoidCallback onOpen;
  final ValueChanged<bool> onSetComplete;
  final void Function(Subtask subtask, bool isDone) onToggleSubtask;

  @override
  Widget build(BuildContext context) {
    final isLate = taskDueStatus(task, now) == TaskDueStatus.overdue;
    final others = [
      for (final member in task.assignees)
        if (member.id != viewerId) member.name,
    ];
    return Row(
      key: Key('my-task-${task.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TimeColumn(
          top: task.hasAssemblyTime ? ltr(task.assemblyTime!) : 'ללא שעה',
          bottom: task.hasAssemblyTime ? 'התייצבות' : null,
          topColor: isLate ? TaskStyle.lateDark : null,
        ),
        Expanded(
          child: _Railed(
            markerSize: 8,
            markerTop: isFull ? 18 : 14,
            marker: Container(
              decoration: BoxDecoration(
                color: task.isComplete
                    ? TaskStyle.done
                    : (isLate ? TaskStyle.late : TaskStyle.faintText),
                shape: BoxShape.circle,
              ),
            ),
            child: isFull ? _buildFull(others) : _buildCompact(others),
          ),
        ),
      ],
    );
  }

  TextStyle _titleStyle(double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        decoration:
            task.isComplete ? TextDecoration.lineThrough : TextDecoration.none,
        color: task.isComplete ? TaskStyle.faintText : null,
      );

  Widget _withOthers(List<String> others) => Text(
        'עם ${others.join(', ')}',
        style: const TextStyle(
          fontSize: TaskStyle.rowMetaSize,
          color: TaskStyle.neutralText,
        ),
      );

  Widget _buildFull(List<String> others) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: TaskStyle.rest),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!task.hasSubtasks)
                      Checkbox(
                        key: Key('my-task-tick-${task.id}'),
                        value: task.isComplete,
                        onChanged: canTick
                            ? (value) => onSetComplete(value ?? false)
                            : null,
                      )
                    else
                      const SizedBox(width: 8, height: 40),
                    Expanded(
                      child: Text(
                        task.title,
                        style: _titleStyle(TaskStyle.rowTitleSize),
                      ),
                    ),
                    if (task.hasSubtasks)
                      Text(
                        ltr('${task.doneSubtaskCount}/${task.subtasks.length}'),
                        style: const TextStyle(
                          fontSize: TaskStyle.rowMetaSize,
                          fontWeight: FontWeight.w600,
                          color: TaskStyle.neutralText,
                        ),
                      ),
                  ],
                ),
                if (others.isNotEmpty)
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: task.hasSubtasks ? 8 : 40,
                    ),
                    child: _withOthers(others),
                  ),
                for (final subtask in task.subtasks)
                  Row(
                    children: [
                      Checkbox(
                        key: Key('my-subtask-${task.id}-${subtask.id}'),
                        value: subtask.isDone,
                        visualDensity: VisualDensity.compact,
                        onChanged: canTick
                            ? (value) => onToggleSubtask(subtask, value ?? false)
                            : null,
                      ),
                      Expanded(
                        child: Text(
                          subtask.title,
                          style: TextStyle(
                            fontSize: 14,
                            decoration: subtask.isDone
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            color: subtask.isDone ? TaskStyle.faintText : null,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompact(List<String> others) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _titleStyle(14),
            ),
            if (others.isNotEmpty) _withOthers(others),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.now});

  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('my-day-${_dayKeyFormat.format(day)}'),
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        dayLabel(day, now),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: TaskStyle.mine,
        ),
      ),
    );
  }
}

/// The viewer's late tasks, one line, until they are ticked.
class _LateBanner extends StatelessWidget {
  const _LateBanner({
    required this.late,
    required this.onOpenTask,
    required this.onOpenMyLate,
  });

  final List<TaskItem> late;
  final ValueChanged<TaskItem> onOpenTask;
  final VoidCallback onOpenMyLate;

  @override
  Widget build(BuildContext context) {
    final String text;
    final VoidCallback onTap;
    if (late.length == 1) {
      final task = late.single;
      final time = task.hasAssemblyTime ? ', ${ltr(task.assemblyTime!)}' : '';
      text = 'משימה שלך באיחור · ${task.title} · '
          '${task.stage?.title ?? ''}$time';
      onTap = () => onOpenTask(task);
    } else {
      text = '${late.length} משימות שלך באיחור';
      onTap = onOpenMyLate;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: TaskStyle.lateLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: TaskStyle.late.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('my-late-banner'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: TaskStyle.late,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: TaskStyle.lateDark,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_left, color: TaskStyle.lateDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoTasksNote extends StatelessWidget {
  const _NoTasksNote({required this.onShowAllStages});

  final VoidCallback onShowAllStages;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('my-no-tasks'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: TaskStyle.currentLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Expanded(child: Text('אין לך משימות באירוע זה')),
          TextButton(
            key: const Key('my-show-all'),
            onPressed: onShowAllStages,
            child: const Text('לכל השלבים'),
          ),
        ],
      ),
    );
  }
}

class _FoldLine extends StatelessWidget {
  const _FoldLine({
    required this.text,
    required this.isOpen,
    required this.onToggle,
  });

  final String text;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('my-earlier-toggle'),
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: TaskStyle.rest)),
        ),
        child: Row(
          children: [
            Icon(
              isOpen ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: TaskStyle.neutralText,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: TaskStyle.neutralText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
