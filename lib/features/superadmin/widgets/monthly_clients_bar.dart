import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../backoffice/models.dart';
import '../theme.dart';

/// Bar chart annuel « nouveaux clients abonnés par mois » (Jan → Déc).
///
/// Partagé par la console super admin (Overview plateforme + fiche société)
/// et la console entreprise (Overview du General Administrator).
class MonthlyClientsBar extends StatelessWidget {
  const MonthlyClientsBar({super.key, required this.values, this.height = 170});

  /// Une valeur par mois (index 0 = janvier), longueur 12.
  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
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
                if (index < 0 || index >= subscriptionMonthLabels.length) {
                  return null;
                }
                return BarTooltipItem(
                  '${subscriptionMonthLabels[index]} '
                  '${rod.toY.toInt()}',
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
                  if (index < 0 || index >= subscriptionMonthLabels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      subscriptionMonthLabels[index],
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
                    toY: values[i].toDouble(),
                    color: SuperAdminTheme.gold,
                    width: 22,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
