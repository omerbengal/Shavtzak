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
import 'subtask_ticks.dart';

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

  /// Whether the late banner has its place on top. Decided with the anchor,
  /// so a banner appearing, or going once its tasks are ticked, never moves
  /// the list under the reader; what it says stays live.
  bool _hasBanner = false;

  /// Set when the page comes back to the foreground: nobody is reading at
  /// that moment, so the timeline may open again on the stage of now.
  bool _retakeOnBuild = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _takeAnchor();
    // A phone keeps the tab for hours; coming back to it reopens the
    // timeline on the current stage. Retaken on the next build, by which
    // time the screen has brought "now" up to date.
    _lifecycle = AppLifecycleListener(onResume: () {
      if (!mounted) return;
      setState(() => _retakeOnBuild = true);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
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
    _hasBanner = lateTasks(
      [
        for (final task in widget.board.tasks)
          if (task.isAssignedTo(widget.viewerId)) task,
      ],
      widget.now,
    ).isNotEmpty;
  }

  /// Compact rows whose subtasks were opened in place. Kept across data
  /// updates, so ticking a subtask never folds its row away.
  final Set<String> _expanded = <String>{};

  void _expand(TaskItem task) {
    Logger.action('expand:myTaskSubtasks');
    setState(() => _expanded.add(task.id));
  }

  void _toggleEarlier() {
    Logger.action('toggle:myEarlierStages', {'on': !_earlierOpen});
    setState(() => _earlierOpen = !_earlierOpen);
  }

  @override
  Widget build(BuildContext context) {
    if (_retakeOnBuild) {
      _retakeOnBuild = false;
      _earlierOpen = false;
      _takeAnchor();
    }
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
        if (_hasBanner)
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
    final text =
        '$stages · ${hebrewCount(done, one: 'משימה אחת שלך הושלמה', many: 'משימות שלך הושלמו')}';
    // Open tasks of mine in there that the late banner does not show, such
    // as one with no report time, which is late only once its day is over.
    final hidden = mineThere
        .where((task) =>
            !task.isComplete &&
            taskDueStatus(task, widget.now) != TaskDueStatus.overdue)
        .length;
    if (hidden == 0) return text;
    return '$text · ${hebrewCount(hidden, one: 'אחת עדיין פתוחה', many: 'עדיין פתוחות')}';
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
    final isHighlighted = stage.id == marks.highlightId;
    // One card per stage: the stage is the tinted header, the viewer's
    // tasks are the white rows under it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TaskStyle.stageCardInset,
        0,
        TaskStyle.stageCardInset,
        TaskStyle.stageCardGap,
      ),
      child: Material(
        key: Key('my-stage-card-${stage.id}'),
        color: TaskStyle.stageCard,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TaskStyle.stageCardRadius),
          side: isHighlighted
              ? BorderSide(
                  color: TaskStyle.current.withValues(alpha: 0.45),
                  width: TaskStyle.stageCardCurrentBorderWidth,
                )
              : const BorderSide(
                  color: TaskStyle.stageCardBorder,
                  width: TaskStyle.stageCardBorderWidth,
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StageHeader(
              stage: stage,
              myTasks: group.tasks,
              isOpening: isOpening,
              isHighlighted: isHighlighted,
              kicker: marks.currentIds.contains(stage.id)
                  ? _Kicker.now
                  : (stage.id == marks.nextId ? _Kicker.next : null),
              onOpen: () => widget.onOpenStage(stage),
            ),
            for (final task in group.tasks) ...[
              const Divider(
                height: 1,
                thickness: 1,
                color: TaskStyle.stageCardDivider,
              ),
              _TaskLine(
                task: task,
                viewerId: widget.viewerId,
                now: widget.now,
                isFull: isOpening,
                canTick: widget.canTick,
                isExpanded: _expanded.contains(task.id),
                onExpand: () => _expand(task),
                onOpen: () => widget.onOpenTask(task),
                onSetComplete: (value) => widget.onSetComplete(task, value),
                onToggleSubtask: (subtask, value) =>
                    widget.onToggleSubtask(task, subtask, value),
              ),
            ],
          ],
        ),
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

/// The time column on the start side: two short lines, left to right.
class _TimeColumn extends StatelessWidget {
  const _TimeColumn({
    required this.top,
    this.bottom,
    this.topColor,
    this.topPadding = 10,
  });

  final String top;
  final String? bottom;
  final Color? topColor;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TaskStyle.timeColumnWidth,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding),
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

/// The tinted strip at the top of a stage's card: its time, title, place,
/// "now"/"next" caption and the viewer's count.
class _StageHeader extends StatelessWidget {
  const _StageHeader({
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
    final Color tint;
    if (isHighlighted) {
      tint = TaskStyle.currentLight;
    } else if (allDone) {
      tint = TaskStyle.doneLight;
    } else {
      tint = TaskStyle.stageHeader;
    }
    return Material(
      key: Key('my-stage-header-${stage.id}'),
      color: tint,
      child: InkWell(
        key: Key('my-stage-${stage.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TimeColumn(
                top: start == null ? '' : ltr(start),
                bottom: end == null ? null : ltr(end),
                topPadding: 0,
              ),
              Expanded(
                child: myTasks.isEmpty ? _buildOneLine() : _buildFull(),
              ),
              if (allDone && !isHighlighted)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 6, top: 1),
                  child: Icon(
                    Icons.check_circle,
                    size: 18,
                    color: TaskStyle.done,
                  ),
                ),
            ],
          ),
        ),
      ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kickerWidget != null) ...[kickerWidget, const SizedBox(width: 6)],
        // Wraps in full: a name never collapses into "…".
        Expanded(
          child: Text(
            place.isEmpty ? stage.title : '${stage.title} · $place',
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

class _TaskLine extends StatelessWidget {
  const _TaskLine({
    required this.task,
    required this.viewerId,
    required this.now,
    required this.isFull,
    required this.canTick,
    required this.isExpanded,
    required this.onExpand,
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

  /// Whether a compact row lists its subtasks. A full row always does.
  final bool isExpanded;

  /// Opens a compact row's subtasks in place.
  final VoidCallback onExpand;
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
    // A white row inside its stage's card, under the tinted header.
    return Material(
      key: Key('my-task-${task.id}'),
      color: TaskStyle.stageCard,
      child: InkWell(
        // A task with subtasks first lists them in place; once they show, a
        // tap opens the task.
        onTap: task.hasSubtasks && !isFull && !isExpanded ? onExpand : onOpen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TimeColumn(
              top: task.hasAssemblyTime ? ltr(task.assemblyTime!) : 'ללא שעה',
              bottom: task.hasAssemblyTime ? 'התייצבות' : null,
              topColor: isLate ? TaskStyle.lateDark : null,
              topPadding: isFull ? 14 : 10,
            ),
            Expanded(
              child: isFull ? _buildFull(others) : _buildCompact(others),
            ),
          ],
        ),
      ),
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
    final update = _updateText();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 4, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!task.hasSubtasks)
                Checkbox(
                  key: Key('my-task-tick-${task.id}'),
                  value: task.isComplete,
                  onChanged:
                      canTick ? (value) => onSetComplete(value ?? false) : null,
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
          if (update != null)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: task.hasSubtasks ? 8 : 40,
              ),
              child: update,
            ),
          if (task.hasSubtasks) _subtasks(),
        ],
      ),
    );
  }

  Widget _subtasks() => SubtaskTicks(
        task: task,
        canTick: canTick,
        onToggle: onToggleSubtask,
        listKeyPrefix: 'my-task',
        tickKeyPrefix: 'my-subtask',
      );

  /// The assignee update under the task, as on [TaskRow]; wraps in full.
  Widget? _updateText() {
    final line = assigneeUpdateLine(task, now);
    if (line == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: TaskStyle.updateLineGap),
      child: Text(
        line,
        key: Key('my-task-update-${task.id}'),
        style: const TextStyle(
          fontSize: TaskStyle.rowMetaSize,
          color: TaskStyle.neutralText,
        ),
      ),
    );
  }

  /// One line per task, with its tick box (or its subtasks done over total),
  /// so a task can be ticked from any stage, as in the mockup. A task with
  /// subtasks lists them under it once opened in place.
  Widget _buildCompact(List<String> others) {
    final update = _updateText();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 2, 10, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: task.hasSubtasks
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      ltr('${task.doneSubtaskCount}/${task.subtasks.length}'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: TaskStyle.rowMetaSize,
                        fontWeight: FontWeight.w600,
                        color: TaskStyle.neutralText,
                      ),
                    ),
                  )
                : Checkbox(
                    key: Key('my-task-tick-${task.id}'),
                    value: task.isComplete,
                    visualDensity: VisualDensity.compact,
                    onChanged: canTick
                        ? (value) => onSetComplete(value ?? false)
                        : null,
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title, style: _titleStyle(14)),
                  if (others.isNotEmpty) _withOthers(others),
                  if (update != null) update,
                  if (isExpanded && task.hasSubtasks) _subtasks(),
                ],
              ),
            ),
          ),
        ],
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

/// The viewer's late tasks, until they are ticked. Its text wraps, and the
/// banner keeps at least the height of the text it opened with, so ticking
/// a task never shortens it and moves the list.
class _LateBanner extends StatefulWidget {
  const _LateBanner({
    required this.late,
    required this.onOpenTask,
    required this.onOpenMyLate,
  });

  final List<TaskItem> late;
  final ValueChanged<TaskItem> onOpenTask;
  final VoidCallback onOpenMyLate;

  @override
  State<_LateBanner> createState() => _LateBannerState();
}

class _LateBannerState extends State<_LateBanner> {
  /// The text the banner opened with: its height is kept.
  String? _openingText;

  @override
  Widget build(BuildContext context) {
    final late = widget.late;
    final onOpenTask = widget.onOpenTask;
    final onOpenMyLate = widget.onOpenMyLate;
    // Once everything late is ticked the banner stays, green and the same
    // height, until the timeline opens again: the list must not move.
    final isClear = late.isEmpty;
    final String text;
    final VoidCallback? onTap;
    if (isClear) {
      text = 'אין לך יותר משימות באיחור';
      onTap = null;
    } else if (late.length == 1) {
      final task = late.single;
      final time = task.hasAssemblyTime ? ', ${ltr(task.assemblyTime!)}' : '';
      text = 'משימה שלך באיחור · ${task.title} · '
          '${task.stage?.title ?? ''}$time';
      onTap = () => onOpenTask(task);
    } else {
      text = '${late.length} משימות שלך באיחור';
      onTap = onOpenMyLate;
    }
    final opening = _openingText ??= text;
    final strong = isClear ? TaskStyle.done : TaskStyle.late;
    final dark = isClear ? TaskStyle.doneDark : TaskStyle.lateDark;
    final textStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: dark,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: isClear ? TaskStyle.doneLight : TaskStyle.lateLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: strong.withValues(alpha: 0.45)),
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
                  decoration: BoxDecoration(
                    color: strong,
                    shape: BoxShape.circle,
                  ),
                  child: isClear
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : const Text(
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
                  child: Stack(
                    children: [
                      // Holds the opening height without showing.
                      if (opening != text)
                        Visibility(
                          visible: false,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Text(opening, style: textStyle),
                        ),
                      Text(text, style: textStyle),
                    ],
                  ),
                ),
                if (isClear)
                  const SizedBox(width: 24, height: 24)
                else
                  Icon(Icons.chevron_left, color: dark),
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
