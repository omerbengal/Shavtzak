import 'package:flutter/material.dart';

import '../task_style.dart';

/// The two filters of "כל השלבים".
enum TaskFilter { late, dueSoon }

/// One row, always: "סינון:" and the two filters as toggles. On a narrow
/// phone the whole row shrinks rather than wrap.
///
/// One filter at a time; a filter with nothing in it is disabled unless it
/// is the one on, so it can still be switched off.
class TaskFilterBar extends StatelessWidget {
  const TaskFilterBar({
    super.key,
    required this.lateCount,
    required this.soonCount,
    required this.active,
    required this.onChanged,
  });

  final int lateCount;
  final int soonCount;
  final TaskFilter? active;

  /// Reports the filter chosen, or null when the one on is switched off.
  final ValueChanged<TaskFilter?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('task-filter-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_list, size: 18, color: TaskStyle.neutralText),
            const SizedBox(width: 4),
            const Text(
              'סינון:',
              style: TextStyle(
                fontSize: TaskStyle.filterFontSize,
                fontWeight: FontWeight.w600,
                color: TaskStyle.neutralText,
              ),
            ),
            const SizedBox(width: 8),
            _toggle(
              key: const Key('filter-late'),
              filter: TaskFilter.late,
              label: 'באיחור ($lateCount)',
              count: lateCount,
              light: TaskStyle.lateLight,
              dark: TaskStyle.lateDark,
            ),
            const SizedBox(width: 6),
            _toggle(
              key: const Key('filter-soon'),
              filter: TaskFilter.dueSoon,
              label: 'התייצבות בחצי שעה הקרובה ($soonCount)',
              count: soonCount,
              light: TaskStyle.soonLight,
              dark: TaskStyle.soonDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle({
    required Key key,
    required TaskFilter filter,
    required String label,
    required int count,
    required Color light,
    required Color dark,
  }) {
    final isOn = active == filter;
    return FilterChip(
      key: key,
      label: Text(
        label,
        style: TextStyle(
          fontSize: TaskStyle.filterFontSize,
          fontWeight: isOn ? FontWeight.w600 : FontWeight.normal,
          color: isOn ? dark : null,
        ),
      ),
      selected: isOn,
      showCheckmark: true,
      checkmarkColor: dark,
      // Explicit both ways: the app's chip theme is blue, which reads as on.
      backgroundColor: Colors.white,
      selectedColor: light,
      side: BorderSide(color: isOn ? dark : TaskStyle.rest),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: count == 0 && !isOn ? null : (_) => onChanged(isOn ? null : filter),
    );
  }
}
