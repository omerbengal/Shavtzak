import 'package:flutter/material.dart';

import '../../domain/entities/assignment_label.dart';

class AssignmentLabelChip extends StatelessWidget {
  final AssignmentLabel label;
  final double fontSize;
  final EdgeInsetsGeometry? padding;
  final int maxLines;

  const AssignmentLabelChip({
    super.key,
    required this.label,
    this.fontSize = 11,
    this.padding,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(label.color);

    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label.hebrewName,
        maxLines: maxLines,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  static Color _colorFromHex(String hex) {
    final normalized = hex.replaceAll('#', '').trim();
    final buffer = StringBuffer();
    if (normalized.length == 6) {
      buffer.write('FF');
    }
    buffer.write(normalized);
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
