import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// Data class for events overview chart
class EventsOverviewData {
  final int fullyStaffed;
  final int notFullyStaffed;
  final int noQuotas;

  const EventsOverviewData({
    required this.fullyStaffed,
    required this.notFullyStaffed,
    required this.noQuotas,
  });

  int get total => fullyStaffed + notFullyStaffed + noQuotas;
  bool get isEmpty => total == 0;
}

/// Chart 1: Events Overview - Donut chart showing upcoming events by staffing status
class EventsOverviewChart extends StatelessWidget {
  final EventsOverviewData data;
  final bool isVerticalLayout;

  const EventsOverviewChart({
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
          'סטטוס אירועים',
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
          '${data.total}',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'אירועים',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildSections(double radius) {
    final sections = <PieChartSectionData>[];

    if (data.fullyStaffed > 0) {
      sections.add(PieChartSectionData(
        value: data.fullyStaffed.toDouble(),
        title: '',
        color: Colors.green.shade400,
        radius: radius,
      ));
    }

    if (data.notFullyStaffed > 0) {
      sections.add(PieChartSectionData(
        value: data.notFullyStaffed.toDouble(),
        title: '',
        color: Colors.orange.shade400,
        radius: radius,
      ));
    }

    if (data.noQuotas > 0) {
      sections.add(PieChartSectionData(
        value: data.noQuotas.toDouble(),
        title: '',
        color: Colors.grey.shade400,
        radius: radius,
      ));
    }

    return sections;
  }

  Widget _buildLegend() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        if (data.fullyStaffed > 0)
          _legendItem('מאויש (${data.fullyStaffed})', Colors.green.shade400),
        if (data.notFullyStaffed > 0)
          _legendItem('לא מאויש (${data.notFullyStaffed})', Colors.orange.shade400),
        if (data.noQuotas > 0)
          _legendItem('ללא מכסות (${data.noQuotas})', Colors.grey.shade400),
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
