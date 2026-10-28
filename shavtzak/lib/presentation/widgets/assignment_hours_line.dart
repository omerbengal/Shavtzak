import 'package:flutter/material.dart';

import '../../core/utils/custom_hours.dart';
import '../../domain/entities/assignment.dart';

/// A member's own hours for one assignment, as a line under their name in the
/// assignment dialogs: `שעות: 27.10 14:00–23:00`.
///
/// Empty when the assignment has no hours of its own, or hours that cannot be
/// read (the member is then held for the whole event, as the dialog already
/// shows). Text only, set apart from the notes box below it by the same
/// padding.
class AssignmentHoursLine extends StatelessWidget {
  const AssignmentHoursLine({super.key, required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final window = assignment.customWindow;
    if (window == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 26, top: 4),
      child: Text(
        'שעות: ${formatCustomHours(window)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }
}
