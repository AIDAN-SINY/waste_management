import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backoffice/models.dart';
import '../data/platform_store.dart';
import '../theme.dart';
import '../widgets/kpi_card.dart';
import '../widgets/monthly_clients_bar.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  static const _growthLabels = ['Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlatformStore>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 880;
        final chartHeight = 190.0;
        final kpis = _kpis(store);

        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            // --- KPIs ---
            if (wide)
              Row(
                children: [
                  for (var i = 0; i < kpis.length; i++)
                    Expanded(
                      child: Padding(
                        // Espacement régulier entre les cartes : pas de
                        // marge droite sur la dernière (elle s'aligne déjà
                        // sur le bord du contenu).
                        padding: EdgeInsets.only(
                          right: i == kpis.length - 1 ? 0 : 16,
                        ),
                        child: kpis[i],
                      ),
                    ),
                ],
              )
            else
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final kpi in kpis)
                    SizedBox(
                      width: (constraints.maxWidth - 16) / 2,
                      child: kpi,
                    ),
                ],
              ),

            const SizedBox(height: 16),

            // --- Charts ---
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: _chartCard(
                      title: 'New companies',
                      tag: 'Last 6 months',
                      height: chartHeight,
                      child: _GrowthChart(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: _chartCard(
                      title: 'Agencies per company',
                      tag: '',
                      height: chartHeight,
                      child: _AgencyChart(store: store),
                    ),
                  ),
                ],
              )
            else ...[
              _chartCard(
                title: 'New companies',
                tag: 'Last 6 months',
                height: chartHeight,
                child: _GrowthChart(),
              ),
              const SizedBox(height: 16),
              _chartCard(
                title: 'Agencies per company',
                tag: '',
                height: chartHeight,
                child: _AgencyChart(store: store),
              ),
            ],

            const SizedBox(height: 16),

            // --- Nouveaux clients abonnés par mois (toute la plateforme) ---
            _chartCard(
              title: 'New clients subscribed',
              tag: '${DateTime.now().year} · all companies',
              height: chartHeight,
              child: MonthlyClientsBar(
                values: monthlySubscriptions(store.clients, DateTime.now().year),
              ),
            ),

            const SizedBox(height: 16),

            // --- Activity feed ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: SuperAdminTheme.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cardHead('Platform activity', 'Live'),
                  const SizedBox(height: 12),
                  const _ActivityItem(
                    color: SuperAdminTheme.gold,
                    text: 'New company registered: EcoCollecte Kribi',
                    time: '2 h ago',
                  ),
                  const _ActivityItem(
                    color: SuperAdminTheme.green,                     text: 'Agency "Yaoundé — Nlongkak" activated',
                    time: 'yesterday',
                  ),
                  const _ActivityItem(
                    color: SuperAdminTheme.blue,
                    text: 'New Agency Manager created: Marie Ekwalla',
                    time: '2 d ago',
                  ),
                  const _ActivityItem(
                    color: SuperAdminTheme.red,
                    text: 'Company "EcoCollecte Kribi" suspended (unpaid)',
                    time: '3 d ago',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _kpis(PlatformStore store) {
    return [
      KpiCard(
        icon: Icons.business_rounded,
        iconBg: SuperAdminTheme.goldSoft,
        iconColor: SuperAdminTheme.goldDim,
        value: store.societesActives.toDouble(),
        label: 'Active companies',
        trend: '2',
        trendUp: true,
      ),
      KpiCard(
        icon: Icons.storefront_rounded,
        iconBg: SuperAdminTheme.greenSoft,
        iconColor: SuperAdminTheme.green,
        value: store.agencesCount.toDouble(),
        label: 'Agencies',
        trend: '3',
        trendUp: true,
      ),
      KpiCard(
        icon: Icons.people_rounded,
        iconBg: SuperAdminTheme.blueSoft,
        iconColor: SuperAdminTheme.blue,
        value: store.utilisateursCount.toDouble(),
        label: 'Users',
        trend: '6.4%',
        trendUp: true,
      ),
      KpiCard(
        icon: Icons.signal_cellular_alt_rounded,
        iconBg: SuperAdminTheme.redSoft,
        iconColor: SuperAdminTheme.red,
        value: 99.9,
        suffix: '%',
        label: 'Platform availability',
        trend: '0.1%',
        trendUp: false,
        decimals: 1,
      ),
    ];
  }
}

Widget _cardHead(String title, String tag) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Flexible(
        child: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
        ),
      ),
      if (tag.isNotEmpty) ...[
        const SizedBox(width: 8),
        Text(
          tag,
          style: SuperAdminTheme.inter(11.5, color: SuperAdminTheme.muted),
        ),
      ],
    ],
  );
}

Widget _chartCard({
  required String title,
  required String tag,
  required double height,
  required Widget child,
}) {
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: SuperAdminTheme.card(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHead(title, tag),
        const SizedBox(height: 14),
        SizedBox(height: height, child: child),
      ],
    ),
  );
}

// --- Charts (fl_chart equivalents of the design's Chart.js charts) ---

class _GrowthChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= OverviewPage._growthLabels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    OverviewPage._growthLabels[index],
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
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 1),
              FlSpot(1, 1),
              FlSpot(2, 2),
              FlSpot(3, 2),
              FlSpot(4, 3),
              FlSpot(5, 3),
            ],
            isCurved: true,
            curveSmoothness: 0.35,
            color: SuperAdminTheme.ink,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: SuperAdminTheme.ink.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgencyChart extends StatelessWidget {
  const _AgencyChart({required this.store});

  final PlatformStore store;

  @override
  Widget build(BuildContext context) {
    final labels = store.societes.map((s) => s.raisonSociale.split(' ').first).toList();
    final counts = store.societes
        .map((s) => store.agences.where((a) => a.societe == s.raisonSociale).length)
        .toList();

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: SuperAdminTheme.ink,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${labels[group.x]}\n${rod.toY.toInt()}',
              SuperAdminTheme.inter(11, color: SuperAdminTheme.cream),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    labels[index],
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
          for (var i = 0; i < counts.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: counts[i].toDouble(),
                  color: SuperAdminTheme.gold,
                  width: 26,
                  borderRadius: BorderRadius.circular(5),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({required this.color, required this.text, required this.time});

  final Color color;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SuperAdminTheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: SuperAdminTheme.inter(12.5, weight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: SuperAdminTheme.inter(11, color: SuperAdminTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
