import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Model for a filter option
class FilterOption {
  final String label;
  final String count;

  const FilterOption({
    required this.label,
    required this.count,
  });
}

/// Interactive filter bar widget with animated circle indicator
///
/// Displays a row of filter options with counts, showing an animated
/// circle around the selected option. Supports hover states on web
/// and smooth animations when switching filters.
class InteractiveFilterBar extends StatefulWidget {
  /// List of filter options to display
  final List<FilterOption> options;

  /// Currently selected index
  final int selectedIndex;

  /// Callback when a filter option is tapped
  final ValueChanged<int> onFilterChanged;

  /// Background color of the bar
  final Color? backgroundColor;

  /// Color of the animated circle indicator
  final Color indicatorColor;

  /// Color of the number text
  final Color numberColor;

  /// Color of the label text
  final Color labelColor;

  const InteractiveFilterBar({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onFilterChanged,
    this.backgroundColor,
    this.indicatorColor = Colors.blue,
    this.numberColor = Colors.blue,
    this.labelColor = Colors.grey,
  });

  @override
  State<InteractiveFilterBar> createState() => _InteractiveFilterBarState();
}

class _InteractiveFilterBarState extends State<InteractiveFilterBar> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: widget.backgroundColor ?? Colors.blue.shade50,
      child: Row(
        children: List.generate(
          widget.options.length,
          (index) => Expanded(
            child: _buildFilterOption(index),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterOption(int index) {
    final option = widget.options[index];
    final isSelected = index == widget.selectedIndex;
    final isHovered = index == _hoveredIndex;

    // Colors for selected state
    final lightGreen = Colors.green.shade100;
    final darkGreen = Colors.green.shade700;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          option.count,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isSelected ? darkGreen : widget.numberColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          option.label,
          style: TextStyle(
            fontSize: 14,
            color: isSelected ? darkGreen : widget.labelColor,
          ),
        ),
      ],
    );

    // Wrap content with animated square indicator when selected
    Widget itemWidget = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? lightGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );

    // Add hover effect for web
    if (kIsWeb) {
      itemWidget = MouseRegion(
        cursor: isSelected ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) {
          if (!isSelected) {
            setState(() {
              _hoveredIndex = index;
            });
          }
        },
        onExit: (_) {
          setState(() {
            _hoveredIndex = null;
          });
        },
        child: itemWidget,
      );
    }

    return InkWell(
      onTap: isSelected ? null : () => widget.onFilterChanged(index),
      borderRadius: BorderRadius.circular(12),
      splashColor: Colors.green.withOpacity(0.2),
      highlightColor: Colors.green.withOpacity(0.1),
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: isHovered && !isSelected ? 0.7 : 1.0,
          child: itemWidget,
        ),
      ),
    );
  }
}
