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

DateTime _dayOf(DateTime date) => DateTime(date.year, date.month, date.day);

/// "כל השלבים" for one day, or a few days side by side on wide screens: the
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
    required this.mineByStage,
    required this.currentStageIds,
    required this.now,
    required this.hourHeight,
    this.outlinedStageIds = const {},
    this.fadeOthers = false,
    this.focusStageId,
    this.focusKey,
    required this.onOpenStage,
  });

  /// The days shown, first on the start side: one on phones, up to
  /// [TaskStyle.maxSideBySideDays] side by side.
  final List<DateTime> days;

  /// Each day's stages, keyed by the day at local midnight.
  final Map<DateTime, List<Stage>> stagesByDay;
  final Map<String, TaskProgress> progressByStage;

  /// How many of each stage's tasks are the viewer's.
  final Map<String, int> mineByStage;

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

  Widget _block(Stage stage, double height) {
    final outlined = outlinedStageIds.contains(stage.id);
    final block = StageBlock(
      key: Key('stage-block-${stage.id}'),
      stage: stage,
      progress: progressByStage[stage.id] ?? const TaskProgress(),
      mineCount: mineByStage[stage.id] ?? 0,
      isCurrent: currentStageIds.contains(stage.id),
      isOutlined: outlined,
      isFaded: fadeOthers && !outlined,
      height: height,
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
        day: layoutDay(_stagesOf(day), minBlockMinutes: minBlockMinutes),
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
        if (hours != null) _grid(layouts, hours.first, hours.last),
      ],
    );
  }

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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
              final width = math.min(
                constraints.maxWidth - TaskStyle.blockGap,
                TaskStyle.allDayBlockWidth,
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
                        width: math.max(0, width),
                        child: _block(stage, TaskStyle.minBlockHeight),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Widget _grid(Map<DateTime, DayLayout> layouts, int first, int last) {
    final gridHeight = (last - first) * hourHeight;
    final nowMinute = now.hour * 60 + now.minute;
    final showsNow = days.any((day) => _dayOf(day) == _dayOf(now)) &&
        nowMinute >= first * 60 &&
        nowMinute <= last * 60;
    final nowTop = (nowMinute - first * 60) / 60 * hourHeight;

    return SizedBox(
      height: gridHeight,
      child: _perDay(
        label: SizedBox(
          height: gridHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var hour = first; hour < last; hour++)
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  top: (hour - first) * hourHeight,
                  child: Text(
                    hour.toString().padLeft(2, '0'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: TaskStyle.hourLabelSize,
                      color: TaskStyle.faintText,
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
        cell: (day) => _dayColumn(
          day,
          layouts[day]!,
          first: first,
          last: last,
          nowTop: showsNow && _dayOf(day) == _dayOf(now) ? nowTop : null,
        ),
      ),
    );
  }

  Widget _dayColumn(
    DateTime day,
    DayLayout layout, {
    required int first,
    required int last,
    double? nowTop,
  }) {
    final gridHeight = (last - first) * hourHeight;
    return SizedBox(
      key: Key('day-column-${_dayKeyFormat.format(day)}'),
      height: gridHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              for (var hour = first; hour <= last; hour++)
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  top: math.min((hour - first) * hourHeight, gridHeight - 1),
                  height: 1,
                  child: const ColoredBox(color: TaskStyle.rest),
                ),
              for (final block in layout.blocks)
                _placed(block, width: width, first: first, gridHeight: gridHeight),
              if (nowTop != null)
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
          );
        },
      ),
    );
  }

  Widget _placed(
    CalendarBlock block, {
    required double width,
    required int first,
    required double gridHeight,
  }) {
    final columnWidth = width / block.columnCount;
    final height = math.min(
      gridHeight,
      math.max(
        (block.endMinute - block.startMinute) / 60 * hourHeight,
        TaskStyle.minBlockHeight,
      ),
    );
    // A block that would run past the bottom moves up instead.
    final top = math.max(
      0.0,
      math.min(
        (block.startMinute - first * 60) / 60 * hourHeight,
        gridHeight - height,
      ),
    );
    return PositionedDirectional(
      start: block.column * columnWidth,
      top: top,
      width: columnWidth,
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TaskStyle.blockGap / 2),
        child: _block(block.stage, height),
      ),
    );
  }
}
