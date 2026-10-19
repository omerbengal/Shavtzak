import 'package:flutter/material.dart';

import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../task_style.dart';

/// The count at the end of a stage on the calendar: what is still missing,
/// coloured by the worst case among it, or a green tick once everything is
/// done. A stage with no tasks gets nothing.
class StageCountButton extends StatelessWidget {
  const StageCountButton({
    super.key,
    required this.progress,
    required this.onPressed,
  });

  final TaskProgress progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tone = countTone(progress);
    if (tone == CountTone.none) return const SizedBox.shrink();
    final (foreground, background, border) = switch (tone) {
      CountTone.done => (
          TaskStyle.doneDark,
          TaskStyle.doneLight,
          TaskStyle.doneLight,
        ),
      CountTone.late => (
          TaskStyle.lateDark,
          TaskStyle.lateLight,
          TaskStyle.late,
        ),
      CountTone.soon => (
          TaskStyle.soonDark,
          TaskStyle.soonLight,
          TaskStyle.soon,
        ),
      _ => (TaskStyle.neutralText, Colors.white, TaskStyle.rest),
    };
    final label = tone == CountTone.done
        ? ltr('${progress.done}/${progress.total}')
        : missingLabel(progress.missing);
    final radius = BorderRadius.circular(14);
    return InkWell(
      onTap: onPressed,
      borderRadius: radius,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (tone == CountTone.done) ...[
                Icon(Icons.check, size: 14, color: foreground),
                const SizedBox(width: 2),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
