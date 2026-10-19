import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../domain/entities/stage.dart';
import '../task_style.dart';
import 'progress_strip.dart';
import 'stage_count_button.dart';

/// One stage on the day calendar, [height] tall: its title, wrapping as far
/// as the block allows; its place and time when tall enough; a progress
/// strip when taller; and at the end of the title line the viewer's own
/// count and the stage's count button.
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

  /// Running now: tinted blue unless everything is done.
  final bool isCurrent;

  /// Drawn with a thick outline, as the stage the sheet shows.
  final bool isOutlined;

  /// Drawn see-through, so the outlined stages stand out.
  final bool isFaded;
  final double height;
  final VoidCallback onOpen;
  final VoidCallback onOpenMissing;

  static const _padding = EdgeInsetsDirectional.fromSTEB(6, 3, 6, 3);

  Color get _background {
    if (progress.total > 0 && progress.missing == 0) return TaskStyle.doneLight;
    if (isCurrent) return TaskStyle.currentLight;
    return Colors.white;
  }

  String get _details => [
        if (stage.hotelLocation.isNotEmpty) stage.hotelLocation,
        if (stageTimeLabel(stage).isNotEmpty) stageTimeLabel(stage),
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final showDetails =
        details.isNotEmpty && height >= TaskStyle.blockDetailsMinHeight;
    final showStrip = height >= TaskStyle.blockProgressMinHeight;
    final radius = BorderRadius.circular(TaskStyle.blockRadius);

    Widget block = SizedBox(
      height: height,
      child: Material(
        color: _background,
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
              Padding(
                padding: _padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _titleLine()),
                    if (showDetails)
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TaskStyle.blockMetaSize,
                          color: TaskStyle.neutralText,
                        ),
                      ),
                    if (showStrip) ...[
                      const SizedBox(height: 3),
                      ProgressStrip(progress: progress),
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

  Widget _titleLine() {
    final hasCount = countTone(progress) != CountTone.none;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trailing = [
          if (mineCount > 0) _mineBadge(),
          if (mineCount > 0 && hasCount) const SizedBox(width: 4),
          if (hasCount)
            StageCountButton(
              key: Key('stage-count-${stage.id}'),
              progress: progress,
              onPressed: onOpenMissing,
            ),
        ];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _title(context)),
            if (trailing.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      constraints.maxWidth * TaskStyle.blockTrailingMaxShare,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.topEnd,
                  child: Row(mainAxisSize: MainAxisSize.min, children: trailing),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The title on as many lines as fit the height it has, the last of them
  /// cut with an ellipsis.
  Widget _title(BuildContext context) {
    const style = TextStyle(
      fontSize: TaskStyle.blockTitleSize,
      fontWeight: FontWeight.w600,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: stage.title, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final lineHeight = painter.height;
        painter.dispose();
        final lines = lineHeight <= 0 || !constraints.hasBoundedHeight
            ? 1
            : math.max(1, (constraints.maxHeight / lineHeight).floor());
        return Text(
          stage.title,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
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
