import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../domain/entities/stage.dart';
import '../task_style.dart';
import 'stage_block.dart';

final DateFormat _dayKeyFormat = DateFormat('yyyy-MM-dd');
final DateFormat _nowFormat = DateFormat('HH:mm');

String _two(int hour) => hour.toString().padLeft(2, '0');

DateTime _dayOf(DateTime date) => DateTime(date.year, date.month, date.day);

/// "כל השלבים" for one day, or a few days side by side: the
/// stages with no time in a row on top, then an hour grid with each timed
/// stage placed by its start and end, and a red line at now on today.
///
/// It does not scroll by itself; its parent scrolls it.
class DayCalendar extends StatelessWidget {
  const DayCalendar({
    super.key,
    required this.days,
    required this.stagesByDay,
    required this.progressByStage,
    required this.currentStageIds,
    required this.now,
    required this.hourHeight,
    this.outlinedStageIds = const {},
    this.fadeOthers = false,
    this.focusStageId,
    this.focusKey,
    required this.onOpenStage,
  });

  /// The days shown, first on the start side.
  final List<DateTime> days;

  /// Each day's stages, keyed by the day at local midnight.
  final Map<DateTime, List<Stage>> stagesByDay;
  final Map<String, TaskProgress> progressByStage;

  /// The stages running now, tinted blue.
  final Set<String> currentStageIds;
  final DateTime now;
  final double hourHeight;

  /// The stages the sheet is about, drawn with a thick outline.
  final Set<String> outlinedStageIds;

  /// Whether the stages that are not outlined fade.
  final bool fadeOthers;

  /// The stage whose block carries [focusKey], so a parent can scroll to it.
  final String? focusStageId;
  final GlobalKey? focusKey;
  final void Function(Stage stage, {required bool missingOnly}) onOpenStage;

  List<Stage> _stagesOf(DateTime day) => stagesByDay[_dayOf(day)] ?? const [];

  Widget _block(Stage stage, double height, {bool fadesOut = false}) {
    final outlined = outlinedStageIds.contains(stage.id);
    final block = StageBlock(
      key: Key('stage-block-${stage.id}'),
      stage: stage,
      progress: progressByStage[stage.id] ?? const TaskProgress(),
      isCurrent: currentStageIds.contains(stage.id),
      isOutlined: outlined,
      isFaded: fadeOthers && !outlined,
      height: height,
      fadesOut: fadesOut,
      onOpen: () => _open(stage, missingOnly: false),
      onOpenMissing: () => _open(stage, missingOnly: true),
    );
    if (focusKey != null && stage.id == focusStageId) {
      return KeyedSubtree(key: focusKey, child: block);
    }
    return block;
  }

  void _open(Stage stage, {required bool missingOnly}) {
    Logger.action('tap:calendarStage', {
      'stageId': stage.id,
      'missingOnly': missingOnly,
    });
    onOpenStage(stage, missingOnly: missingOnly);
  }

  @override
  Widget build(BuildContext context) {
    final minBlockMinutes = TaskStyle.minBlockMinutes(hourHeight);
    final layouts = {
      for (final day in days)
        day: layoutDay(
          _stagesOf(day),
          minBlockMinutes: minBlockMinutes,
        ),
    };
    final hours = calendarHours(
      [for (final day in days) ..._stagesOf(day)],
      minBlockMinutes: minBlockMinutes,
    );
    final hasAllDay = layouts.values.any((layout) => layout.allDay.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (days.length > 1) _headerRow(),
        if (hasAllDay) _allDayRow(layouts),
        if (hours != null)
          LayoutBuilder(
            builder: (context, constraints) => _grid(
              context,
              layouts,
              hours.first,
              hours.last,
              dayWidth: (constraints.maxWidth - TaskStyle.hourLabelWidth) /
                  days.length,
            ),
          ),
      ],
    );
  }

  double _need(BuildContext context, Stage stage, double width) =>
      math.max(
        TaskStyle.minBlockHeight,
        StageBlock.heightFor(
          context,
          stage: stage,
          progress: progressByStage[stage.id] ?? const TaskProgress(),
          width: width,
        ),
      );

  /// A row of cells: the label column on the start side, then one cell per
  /// day.
  Widget _perDay({Key? key, Widget label = const SizedBox.shrink(),
      required Widget Function(DateTime day) cell}) {
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: TaskStyle.hourLabelWidth, child: label),
        for (final day in days) Expanded(child: cell(day)),
      ],
    );
  }

  Widget _headerRow() => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _perDay(
          cell: (day) => Padding(
            key: Key('day-header-${_dayKeyFormat.format(day)}'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              dayLabel(day, now),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TaskStyle.filterFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );

  Widget _allDayRow(Map<DateTime, DayLayout> layouts) => Padding(
        key: const Key('all-day-row'),
        padding: const EdgeInsets.only(bottom: 6),
        child: _perDay(
          cell: (day) => LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(
                0.0,
                math.min(
                  constraints.maxWidth - TaskStyle.blockGap,
                  TaskStyle.allDayBlockWidth,
                ),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: TaskStyle.blockGap / 2),
                child: Wrap(
                  spacing: TaskStyle.blockGap * 2,
                  runSpacing: TaskStyle.blockGap * 2,
                  children: [
                    for (final stage in layouts[day]!.allDay)
                      SizedBox(
                        width: width,
                        child: _block(stage, _need(context, stage, width)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Widget _grid(
    BuildContext context,
    Map<DateTime, DayLayout> layouts,
    int first,
    int last, {
    required double dayWidth,
  }) {
    double widthOf(CalendarBlock block) =>
        dayWidth / block.columnCount - TaskStyle.blockGap;
    final needs = <CalendarBlock, double>{};
    for (final layout in layouts.values) {
      for (final block in layout.blocks) {
        needs[block] = _need(context, block.stage, widthOf(block)) +
            (block.hasEnd ? 0 : TaskStyle.openEndFadeHeight);
      }
      for (final band in layout.bands) {
        needs[band] = _need(context, band.stage, dayWidth - TaskStyle.blockGap);
      }
    }
    final axis = buildTimeAxis(
      [for (final day in days) layouts[day]!],
      firstHour: first,
      lastHour: last,
      hourHeight: hourHeight,
      needOf: (block) => needs[block] ?? TaskStyle.minBlockHeight,
      squashFromMinutes: TaskStyle.squashFromMinutes,
      squashedHeight: TaskStyle.squashedGapHeight,
    );
    final gridHeight = axis.height;
    final nowMinute = now.hour * 60 + now.minute;
    final showsNow = days.any((day) => _dayOf(day) == _dayOf(now)) &&
        nowMinute >= first * 60 &&
        nowMinute <= last * 60;
    final nowTop = axis.before(nowMinute);
    final hourMarks = [
      for (var hour = first; hour <= last; hour++)
        if (!axis.isSquashed(hour * 60)) hour,
    ];

    return SizedBox(
      height: gridHeight,
      child: _perDay(
        label: SizedBox(
          height: gridHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Each hour's line reaches into this column a little, next to
              // its label, so the hours read even where a block covers them.
              for (final hour in hourMarks)
                PositionedDirectional(
                  end: 0,
                  width: TaskStyle.hourTickLength,
                  top: math.min(axis.before(hour * 60), gridHeight - 1),
                  height: 1,
                  child: ColoredBox(
                    key: Key('hour-tick-${_two(hour)}'),
                    color: TaskStyle.rest,
                  ),
                ),
              for (final hour in hourMarks)
                if (hour < last)
                  PositionedDirectional(
                    start: 0,
                    end: TaskStyle.hourTickLength,
                    top: axis.before(hour * 60) - TaskStyle.hourLabelBoxHeight / 2,
                    height: TaskStyle.hourLabelBoxHeight,
                    child: Center(
                      child: Text(
                        _two(hour),
                        key: Key('hour-label-${_two(hour)}'),
                        style: const TextStyle(
                          fontSize: TaskStyle.hourLabelSize,
                          color: TaskStyle.faintText,
                        ),
                      ),
                    ),
                  ),
              for (final (from, to) in axis.squashed)
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  top: axis.before(from),
                  height: axis.before(to) - axis.before(from),
                  child: const Center(
                    child: Text(
                      '⋮',
                      key: Key('squashed-gap'),
                      style: TextStyle(
                        fontSize: TaskStyle.hourLabelSize,
                        color: TaskStyle.faintText,
                      ),
                    ),
                  ),
                ),
              if (showsNow)
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  top: nowTop - TaskStyle.nowPillHeight / 2,
                  height: TaskStyle.nowPillHeight,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: TaskStyle.late,
                      borderRadius:
                          BorderRadius.circular(TaskStyle.nowPillHeight / 2),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ltr(_nowFormat.format(now)),
                        style: const TextStyle(
                          fontSize: TaskStyle.hourLabelSize,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        cell: (day) => SizedBox(
          key: Key('day-column-${_dayKeyFormat.format(day)}'),
          height: gridHeight,
          child: Stack(
            children: [
              for (final hour in hourMarks)
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  top: math.min(axis.before(hour * 60), gridHeight - 1),
                  height: 1,
                  child: const ColoredBox(color: TaskStyle.rest),
                ),
              for (final block in layouts[day]!.blocks)
                _placed(
                  block,
                  start: block.column * dayWidth / block.columnCount,
                  width: dayWidth / block.columnCount,
                  top: axis.after(block.startMinute),
                  height: _heightOf(
                    block,
                    span: axis.before(block.endMinute) -
                        axis.after(block.startMinute),
                    need: needs[block] ?? TaskStyle.minBlockHeight,
                  ),
                ),
              // On top of the blocks they cut across.
              for (final band in layouts[day]!.bands)
                _placed(
                  band,
                  start: 0,
                  width: dayWidth,
                  top: axis.bandTop(layouts[day]!, band),
                  height: needs[band] ?? TaskStyle.minBlockHeight,
                ),
              if (showsNow && _dayOf(day) == _dayOf(now))
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  top: nowTop - TaskStyle.nowLineWidth / 2,
                  height: TaskStyle.nowLineWidth,
                  child: const IgnorePointer(
                    child: ColoredBox(
                      key: Key('now-line'),
                      color: TaskStyle.late,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A stage with an end fills its time; one without stops under its text.
  static double _heightOf(CalendarBlock block,
          {required double span, required double need}) =>
      block.hasEnd ? span : math.min(span, need);

  Widget _placed(
    CalendarBlock block, {
    required double start,
    required double width,
    required double top,
    required double height,
  }) {
    return PositionedDirectional(
      start: start,
      top: top,
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TaskStyle.blockGap / 2),
        child: _block(block.stage, height, fadesOut: !block.hasEnd),
      ),
    );
  }
}
