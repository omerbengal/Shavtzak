import 'package:flutter/material.dart';

import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_schedule.dart';
import '../../../../domain/entities/event.dart';
import '../task_style.dart';
import 'progress_strip.dart';

/// The event at a glance, above the calendar: its days and place, and how
/// much of it is done.
class EventSummary extends StatelessWidget {
  const EventSummary({
    super.key,
    required this.event,
    required this.progress,
    this.action,
  });

  final Event event;
  final TaskProgress progress;

  /// Sits at the end of the days line, such as the managers' download.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = eventDaysLabel(event);
    return Padding(
      key: const Key('event-summary'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  event.location.isEmpty ? days : '$days · ${event.location}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: TaskStyle.neutralText),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: ProgressStrip(progress: progress)),
              const SizedBox(width: 10),
              Text(
                '${ltr('${progress.done}/${progress.total}')} הושלמו',
                key: const Key('event-done-count'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
