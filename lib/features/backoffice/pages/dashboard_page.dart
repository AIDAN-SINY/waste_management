import 'package:flutter/material.dart';

import '../data/backoffice_store.dart';
import '../data/seed_data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/bar_chart.dart';
import '../widgets/kpi_card.dart';
import '../widgets/sheets.dart';

const List<double> _revenueValues = [3.2, 4.1, 3.8, 4.6, 5.2, 5.8];
const List<String> _revenueLabels = ['Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'];
const List<double> _weekValues = [3, 4, 5, 2, 6, 4, 5];
const List<String> _weekLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Dashboard page: KPI carousel, charts and the activity feed.
///
/// Web-first : sur desktop les KPIs s'affichent en ligne et les graphiques
/// côte à côte (au lieu du carrousel horizontal / empilement du mobile).
class BoDashboardPage extends StatelessWidget {
  const BoDashboardPage({super.key, required this.store, this.desktop = false});

  final BackofficeStore store;

  /// Layout desktop (web-first) : KPIs en ligne + graphiques côte à côte.
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(top: 6, bottom: desktop ? 24 : 110),
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final revenus = store.revenusMilliers.round();
          final kpis = [
            BoKpiCard(
              icon: Icons.group_outlined,
              iconColor: BackofficeTheme.green,
              iconBg: BackofficeTheme.greenSoft,
              trend: '↑4.2%',
              trendUp: true,
              value: '${store.clientsActifs}',
              label: 'Active clients',
              width: desktop ? null : 150,
            ),
            BoKpiCard(
              icon: Icons.event_available_outlined,
              iconColor: BackofficeTheme.goldDim,
              iconBg: BackofficeTheme.goldSoft,
              trend: '↑12',
              trendUp: true,
              value: '${store.collectesAujourdhui}',
              label: "Today's collections",
              width: desktop ? null : 150,
            ),
            BoKpiCard(
              icon: Icons.payments_outlined,
              iconColor: BackofficeTheme.blue,
              iconBg: BackofficeTheme.blueSoft,
              trend: '↑8.7%',
              trendUp: true,
              value: '₣$revenus',
              label: 'Revenue (thousands)',
              width: desktop ? null : 150,
            ),
            BoKpiCard(
              icon: Icons.trending_up_rounded,
              iconColor: BackofficeTheme.red,
              iconBg: BackofficeTheme.redSoft,
              trend: '↓1.1%',
              trendUp: false,
              value: '${store.tauxReussite.round()}%',
              label: 'Success rate',
              width: desktop ? null : 150,
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- KPI row / carousel ---
              if (desktop)
                IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < kpis.length; i++) ...[
                          if (i > 0) const SizedBox(width: 14),
                          Expanded(child: kpis[i]),
                        ],
                      ],
                    ),
                  ),
                )
              else
                IntrinsicHeight(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < kpis.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          kpis[i],
                        ],
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 6),
              if (desktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _chartCard(
                        'Revenue (6 months)',
                        'XAF, thousands',
                        BoBarChart(
                          values: _revenueValues,
                          labels: _revenueLabels,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _chartCard(
                        'Collections — last 7 days',
                        null,
                        BoBarChart(values: _weekValues, labels: _weekLabels),
                      ),
                    ),
                  ],
                )
              else ...[
                _chartCard(
                  'Revenue (6 months)',
                  'XAF, thousands',
                  BoBarChart(values: _revenueValues, labels: _revenueLabels),
                ),
                _chartCard(
                  'Collections — last 7 days',
                  null,
                  BoBarChart(values: _weekValues, labels: _weekLabels),
                ),
              ],

              // Nouveaux clients abonnés par mois (Jan → Déc de l'année
              // courante) — pleine largeur sur les deux layouts.
              _chartCard(
                'New clients subscribed',
                '${DateTime.now().year}',
                BoBarChart(
                  values: monthlySubscriptions(
                    store.clients,
                    DateTime.now().year,
                  ).map((e) => e.toDouble()).toList(),
                  labels: subscriptionMonthLabels,
                ),
              ),

              _SectionTitle(title: 'Pending applications'),
              if (store.pendingRegistrations.isEmpty)
                _PendingEmpty()
              else
                _PendingCard(
                  store: store,
                  desktop: desktop,
                ),

              _SectionTitle(title: 'Recent activity', trailing: 'Live'),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: desktop ? 18 : 16,
                  vertical: 4,
                ),
                decoration: BackofficeTheme.card(),
                child: Column(
                  children: [
                    for (var i = 0; i < seedActivity.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: BackofficeTheme.border),
                      _FeedItem(
                        color: _parseColor(seedActivity[i].color),
                        text: seedActivity[i].text,
                        time: seedActivity[i].time,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chartCard(String title, String? tag, Widget chart) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BackofficeTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(12.5, weight: FontWeight.w600),
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 8),
                Text(
                  tag,
                  style: BackofficeTheme.inter(10.5, color: BackofficeTheme.muted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          chart,
        ],
      ),
    );
  }

  Color _parseColor(String hex) => Color(int.parse(hex.replaceFirst('#', '0xFF')));
}

/// Section « Pending applications » : les candidatures clients en attente
/// d'approbation, avec un accès direct à la feuille de revue.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.store, required this.desktop});

  final BackofficeStore store;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final pending = store.pendingRegistrations.take(3).toList();
    return Container(
      padding: EdgeInsets.all(desktop ? 18 : 16),
      decoration: BackofficeTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: BackofficeTheme.goldSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.how_to_reg_rounded,
                  size: 16,
                  color: BackofficeTheme.goldDim,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pending applications',
                  style: BackofficeTheme.sora(13.5, weight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: BackofficeTheme.goldSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${store.pendingRegistrations.length} to review',
                  style: BackofficeTheme.inter(
                    10,
                    weight: FontWeight.w700,
                    color: BackofficeTheme.goldDim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < pending.length; i++) ...[
            if (i > 0) Divider(height: 1, color: BackofficeTheme.border),
            _PendingRow(
              reg: pending[i],
              onReview: () =>
                  showBoReviewSheet(context, store: store, reg: pending[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.reg, required this.onReview});

  final RegistrationModel reg;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: BackofficeTheme.greenSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              boInitials(reg.fullName),
              style: BackofficeTheme.inter(
                11,
                weight: FontWeight.w700,
                color: BackofficeTheme.green,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reg.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    12.5,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${reg.zone} · ${reg.agenceName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    10.5,
                    color: BackofficeTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: BackofficeTheme.green,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onReview,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text(
                  'Review',
                  style: BackofficeTheme.inter(
                    11,
                    weight: FontWeight.w600,
                    color: BackofficeTheme.cream,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BackofficeTheme.card(),
      child: Row(
        children: [
          const Icon(
            Icons.how_to_reg_rounded,
            size: 17,
            color: BackofficeTheme.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No pending applications. New client requests will appear here.',
              style: BackofficeTheme.inter(11.5, color: BackofficeTheme.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: BackofficeTheme.sora(14, weight: FontWeight.w700)),
          if (trailing != null)
            Text(
              trailing!,
              style: BackofficeTheme.inter(
                11,
                color: BackofficeTheme.muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedItem extends StatelessWidget {
  const _FeedItem({required this.color, required this.text, required this.time});

  final Color color;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: BackofficeTheme.inter(12, weight: FontWeight.w500)),
                const SizedBox(height: 1),
                Text(time, style: BackofficeTheme.inter(10.5, color: BackofficeTheme.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
