import 'package:flutter/material.dart';

import '../../task/task_style.dart';

/// An on/off switch with its words inside the track (Omer, 20/11/2026:
/// "שהטקסט יהיה בתוך המתג"), sized like the filter chips beside it: off is a
/// chip's outline with the knob on the right, on is filled blue (the colour of
/// a set filter) with the knob on the left, as a switch moves in RTL.
class TeamTaskLabeledSwitch extends StatelessWidget {
  const TeamTaskLabeledSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  static const double _height = 30;
  static const double _knob = 22;
  static const Duration _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final knob = AnimatedContainer(
      duration: _duration,
      width: _knob,
      height: _knob,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: value ? Colors.white : TaskStyle.neutralText,
      ),
      child: value ? const Icon(Icons.check, size: 15, color: TaskStyle.mine) : null,
    );
    final text = Text(
      label,
      style: TextStyle(
        fontSize: TaskStyle.filterFontSize,
        fontWeight: value ? FontWeight.w600 : FontWeight.normal,
        color: value ? Colors.white : TaskStyle.neutralText,
      ),
    );
    return Semantics(
      toggled: value,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(_height / 2),
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: _duration,
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: value ? TaskStyle.mine : Colors.transparent,
            border: Border.all(color: value ? TaskStyle.mine : TaskStyle.rest),
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            // The row is RTL: off = knob first (right), on = knob last (left).
            children: value
                ? [
                    const SizedBox(width: 6),
                    text,
                    const SizedBox(width: 6),
                    knob,
                  ]
                : [
                    knob,
                    const SizedBox(width: 6),
                    text,
                    const SizedBox(width: 6),
                  ],
          ),
        ),
      ),
    );
  }
}
