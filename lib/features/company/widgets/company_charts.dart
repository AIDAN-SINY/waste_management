import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../superadmin/theme.dart';

/// Bar chart card for the company console Overview: managers per agency
/// (or per company when no agency is selected).
class CcBarChart extends StatelessWidget {
  const CcBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 180,
  });

  /// One value per label (e.g. managers count per agency).
  final List<double> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty || values.every((v) => v == 0)) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No data yet',
            style: SuperAdminTheme.inter(12, color: SuperAdminTheme.muted),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: SuperAdminTheme.ink,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final index = group.x.toInt();
                if (index < 0 || index >= labels.length) return null;
                return BarTooltipItem(
                  '${labels[index]}\n${rod.toY.toInt()}',
                  SuperAdminTheme.inter(11, color: SuperAdminTheme.cream),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _shortLabel(labels[index]),
                      style: SuperAdminTheme.inter(
                        10.5,
                        color: SuperAdminTheme.muted,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    color: SuperAdminTheme.gold,
                    width: 28,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Shortens "Yaoundé — Bastos" to "Yaoundé" for the axis labels.
  String _shortLabel(String label) {
    final parts = label.split('—');
    return parts.first.trim();
  }
}

/// Donut chart (status / distribution) for the company console Overview.
class CcDonutChart extends StatelessWidget {
  const CcDonutChart({
    super.key,
    required this.values,
    required this.labels,
    required this.colors,
    this.centerLabel = '',
    this.centerValue = '',
    this.height = 180,
  });

  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final String centerLabel;
  final String centerValue;
  final double height;

  double get _total {
    double t = 0;
    for (final v in values) {
      t += v;
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    if (_total == 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No data yet',
            style: SuperAdminTheme.inter(12, color: SuperAdminTheme.muted),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 42,
                    startDegreeOffset: -90,
                    sections: [
                      for (var i = 0; i < values.length; i++)
                        PieChartSectionData(
                          value: values[i],
                          color: colors[i % colors.length],
                          radius: 26,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (centerValue.isNotEmpty)
                      Text(
                        centerValue,
                        style: SuperAdminTheme.sora(
                          18,
                          weight: FontWeight.w700,
                        ),
                      ),
                    if (centerLabel.isNotEmpty)
                      Text(
                        centerLabel,
                        style: SuperAdminTheme.inter(
                          10.5,
                          color: SuperAdminTheme.muted,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < values.length; i++) ...[
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          labels[i],
                          overflow: TextOverflow.ellipsis,
                          style: SuperAdminTheme.inter(
                            11.5,
                            color: SuperAdminTheme.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${values[i].round()}',
                        style: SuperAdminTheme.inter(
                          12,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (i < values.length - 1) const SizedBox(height: 9),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
