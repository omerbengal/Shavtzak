import 'package:flutter/material.dart';

import '../../../../core/utils/task_progress.dart';
import '../task_style.dart';

/// A thin bar showing how a group of tasks stands: done in green, late in
/// red, due in the next half hour in orange, the rest in grey, each as wide
/// as its share. It fills from the left, as the stage headers always have.
class ProgressStrip extends StatelessWidget {
  const ProgressStrip({
    super.key,
    required this.progress,
    this.height = TaskStyle.stripHeight,
  });

  final TaskProgress progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final segments = [
      ('strip-done', progress.done, TaskStyle.done),
      ('strip-late', progress.late, TaskStyle.late),
      ('strip-soon', progress.dueSoon, TaskStyle.soon),
      ('strip-rest', progress.rest, TaskStyle.rest),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        // Left to right, so the strip grows from the left under RTL too.
        child: Row(
          textDirection: TextDirection.ltr,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: progress.total == 0
              ? const [
                  Expanded(
                    child: ColoredBox(
                      key: Key('strip-rest'),
                      color: TaskStyle.rest,
                    ),
                  ),
                ]
              : [
                  for (final (key, count, color) in segments)
                    if (count > 0)
                      Expanded(
                        flex: count,
                        child: ColoredBox(key: Key(key), color: color),
                      ),
                ],
        ),
      ),
    );
  }
}
