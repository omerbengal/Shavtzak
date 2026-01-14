import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// Data class for staffing status chart
class StaffingStatusData {
  final int filledSlots;
  final int unfilledSlots;

  const StaffingStatusData({
    required this.filledSlots,
    required this.unfilledSlots,
  });

  int get totalSlots => filledSlots + unfilledSlots;
  bool get isEmpty => totalSlots == 0;

  double get filledPercentage {
    if (totalSlots == 0) return 0;
    return (filledSlots / totalSlots) * 100;
  }
}

/// Chart 2: Staffing Status - Donut chart showing filled vs unfilled role slots
class StaffingStatusChart extends StatelessWidget {
  final StaffingStatusData data;
  final bool isVerticalLayout;

  const StaffingStatusChart({
    super.key,
    required this.data,
    this.isVerticalLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Text(
          'אין נתונים',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      children: [
        Text(
          'איוש תפקידים',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate outer radius based on available space
              // Vertical: use most of available height
              // Horizontal: use the full width
              final baseDimension = isVerticalLayout
                  ? constraints.maxHeight
                  : constraints.maxWidth;

              // Calculate chart size - BIGGER chart, BIGGER hole for text
              final maxRadius = isVerticalLayout ? 999.0 : 80.0;
              final outerRadius = (baseDimension / 2 - 4).clamp(50.0, maxRadius);
              final centerSpaceRadius = outerRadius * 0.75;  // Bigger hole for text

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: centerSpaceRadius,
                        sections: _buildSections(outerRadius - centerSpaceRadius),
                      ),
                    ),
                    _buildCenterText(),
                  ],
                ),
              );
            },
          ),
        ),
        _buildLegend(),
      ],
    );
  }

  Widget _buildCenterText() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${data.filledPercentage.round()}%',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '${data.filledSlots}/${data.totalSlots}',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildSections(double radius) {
    final sections = <PieChartSectionData>[];

    if (data.filledSlots > 0) {
      sections.add(PieChartSectionData(
        value: data.filledSlots.toDouble(),
        title: '',
        color: Colors.green.shade400,
        radius: radius,
      ));
    }

    if (data.unfilledSlots > 0) {
      sections.add(PieChartSectionData(
        value: data.unfilledSlots.toDouble(),
        title: '',
        color: Colors.red.shade400,
        radius: radius,
      ));
    }

    return sections;
  }

  Widget _buildLegend() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [
        _legendItem('מאויש (${data.filledSlots})', Colors.green.shade400),
        _legendItem('חסר (${data.unfilledSlots})', Colors.red.shade400),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
