import 'package:flutter/material.dart';

import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../domain/entities/stage.dart';
import '../task_style.dart';
import 'stage_count_button.dart';

/// One stage on the day calendar, [height] tall: its whole title, wrapped,
/// then its place and time, then the viewer's own count and the stage's
/// count button. Its background fills green from the left with the share of
/// its tasks that are done.
///
/// Nothing is cut short: the calendar asks [heightFor] how tall the block
/// must be and makes the room.
///
/// Tapping the count button opens the stage's missing tasks; tapping the
/// block anywhere else opens all of them.
class StageBlock extends StatelessWidget {
  const StageBlock({
    super.key,
    required this.stage,
    required this.progress,
    required this.mineCount,
    required this.isCurrent,
    required this.isOutlined,
    required this.isFaded,
    required this.height,
    required this.onOpen,
    required this.onOpenMissing,
  });

  final Stage stage;
  final TaskProgress progress;

  /// How many of the stage's tasks are the viewer's.
  final int mineCount;

  /// Running now: tinted blue under the green.
  final bool isCurrent;

  /// Drawn with a thick outline, as the stage the sheet shows.
  final bool isOutlined;

  /// Drawn see-through, so the outlined stages stand out.
  final bool isFaded;
  final double height;
  final VoidCallback onOpen;
  final VoidCallback onOpenMissing;

  static const _padding = EdgeInsetsDirectional.fromSTEB(6, 3, 6, 3);
  static const _detailsGap = 2.0;
  static const _badgesGap = 3.0;

  static const _titleStyle = TextStyle(
    fontSize: TaskStyle.blockTitleSize,
    fontWeight: FontWeight.w600,
  );
  static const _detailsStyle = TextStyle(
    fontSize: TaskStyle.blockMetaSize,
    color: TaskStyle.neutralText,
  );

  static String _detailsOf(Stage stage) => [
        if (stage.hotelLocation.isNotEmpty) stage.hotelLocation,
        if (stageTimeLabel(stage).isNotEmpty) stageTimeLabel(stage),
      ].join(' · ');

  static bool _hasBadges(TaskProgress progress, int mineCount) =>
      mineCount > 0 || countTone(progress) != CountTone.none;

  /// The height a block [width] wide needs to show all of [stage]: the
  /// title and details wrapped in full, and the badges under them.
  static double heightFor(
    BuildContext context, {
    required Stage stage,
    required TaskProgress progress,
    required int mineCount,
    required double width,
  }) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final textWidth = (width - _padding.horizontal).clamp(1.0, double.infinity);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: textWidth);
      final measured = painter.height;
      painter.dispose();
      return measured;
    }

    var needed = _padding.vertical + measure(stage.title, _titleStyle);
    final details = _detailsOf(stage);
    if (details.isNotEmpty) {
      needed += _detailsGap + measure(details, _detailsStyle);
    }
    if (_hasBadges(progress, mineCount)) {
      needed += _badgesGap + TaskStyle.blockBadgeRowHeight;
    }
    // A pixel to spare against rounding.
    return needed.ceilToDouble() + 1;
  }

  @override
  Widget build(BuildContext context) {
    final details = _detailsOf(stage);
    final radius = BorderRadius.circular(TaskStyle.blockRadius);
    final doneShare =
        progress.total == 0 ? 0.0 : progress.done / progress.total;

    Widget block = SizedBox(
      height: height,
      child: Material(
        color: isCurrent ? TaskStyle.currentLight : Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: isOutlined
              ? const BorderSide(
                  color: TaskStyle.mine, width: TaskStyle.outlineWidth)
              : const BorderSide(color: TaskStyle.rest),
        ),
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            children: [
              if (doneShare > 0)
                // From the left, under RTL too, as the stage headers fill.
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: doneShare,
                      heightFactor: 1,
                      child: ColoredBox(
                        key: Key('stage-fill-${stage.id}'),
                        color: TaskStyle.blockDoneFill,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: _padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(stage.title, style: _titleStyle),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: _detailsGap),
                      Text(details, style: _detailsStyle),
                    ],
                    if (_hasBadges(progress, mineCount)) ...[
                      const SizedBox(height: _badgesGap),
                      SizedBox(
                        height: TaskStyle.blockBadgeRowHeight,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (mineCount > 0) _mineBadge(),
                                if (mineCount > 0 &&
                                    countTone(progress) != CountTone.none)
                                  const SizedBox(width: 4),
                                if (countTone(progress) != CountTone.none)
                                  StageCountButton(
                                    key: Key('stage-count-${stage.id}'),
                                    progress: progress,
                                    onPressed: onOpenMissing,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (progress.late > 0)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: TaskStyle.lateEdgeWidth,
                  child: ColoredBox(
                    key: Key('stage-late-${stage.id}'),
                    color: TaskStyle.late,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (isFaded) {
      block = Opacity(opacity: TaskStyle.fadedOpacity, child: block);
    }
    return block;
  }

  Widget _mineBadge() => Row(
        key: Key('stage-mine-${stage.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person,
              size: TaskStyle.mineIconSize, color: TaskStyle.mine),
          Text(
            '$mineCount',
            style: const TextStyle(
              fontSize: TaskStyle.blockMetaSize,
              fontWeight: FontWeight.w600,
              color: TaskStyle.mine,
            ),
          ),
        ],
      );
}
