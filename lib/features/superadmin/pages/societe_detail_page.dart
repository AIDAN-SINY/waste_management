import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/agence_model.dart';
import '../../../models/platform_user_model.dart';
import '../../../models/societe_model.dart';
import '../../backoffice/models.dart';
import '../data/platform_store.dart';
import '../theme.dart';
import '../widgets/app_table.dart';
import '../widgets/cells.dart';
import '../widgets/kpi_card.dart';
import '../widgets/monthly_clients_bar.dart';
import '../widgets/status_badge.dart';

/// Fiche détaillée d'une société (compagnie) — page pleine grandeur de la
/// console super admin (le super admin voit TOUT sur la compagnie).
///
/// Centrée sur LA SOCIÉTÉ : identité + statut, cartes KPI (agences,
/// managers, clients, collecteurs, taux d'actifs), graphiques (clients par
/// statut / par formule) et tables des agences, managers, clients et
/// collecteurs de la compagnie.
class SocieteDetailPage extends StatelessWidget {
  const SocieteDetailPage({
    super.key,
    required this.societeId,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
  });

  final String societeId;
  final VoidCallback onBack;
  final ValueChanged<SocieteModel> onEdit;
  final ValueChanged<SocieteModel> onDelete;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlatformStore>();

    // Re-résout la société depuis le store à chaque build : si elle a été
    // éditée (statut, adresse…) la page se met à jour en direct.
    SocieteModel? societe;
    for (final s in store.societes) {
      if (s.id == societeId) {
        societe = s;
        break;
      }
    }
    // La page n'est montée que si la société existe (le parent bascule déjà
    // sur la liste sinon) — le garde-fou ci-dessous reste par défense.
    if (societe == null) return const SizedBox.shrink();
    final current = societe;

    final agences = store.agencesForSociete(current.id);
    final managers = store.managersForSociete(current.id);
    final clients = store.clientsForSociete(current.id);
    final collecteurs = store.collecteursForSociete(current.id);
    final activeClients = clients
        .where((c) => c.status == 'Active' || c.status == 'Actif')
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 880;

        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            _Header(
              societe: current,
              agencesCount: agences.length,
              onBack: onBack,
              onEdit: () => onEdit(current),
              onDelete: () => onDelete(current),
            ),
            const SizedBox(height: 16),

            // --- KPIs ---
            _buildKpis(
              wide,
              cardWidth: (constraints.maxWidth - 16) / 2,
              agencesCount: agences.length,
              managersCount: managers.length,
              clientsCount: clients.length,
              collecteursCount: collecteurs.length,
              activeClients: activeClients,
            ),
            const SizedBox(height: 16),

            // --- Charts ---
            _buildCharts(wide, clients),
            const SizedBox(height: 16),

            // --- Nouveaux clients abonnés par mois (cette société) ---
            _buildMonthlySubscriptions(clients),
            const SizedBox(height: 16),

            // --- Info société ---
            _buildInfoCard(current),
            const SizedBox(height: 22),

            // --- Tables ---
            _sectionTitle('Agencies', '${agences.length}'),
            const SizedBox(height: 10),
            AppTable<AgenceModel>(
              rows: agences,
              emptyText: 'No agencies under this company yet.',
              footer: '${agences.length} agenc${agences.length > 1 ? 'ies' : 'y'}',
              columns: [
                TableColumnSpec(
                  label: 'Agency',
                  sortValue: (a) => a.ville,
                  flex: 2,
                  cell: (a) => saNameCell(a.ville),
                ),
                TableColumnSpec(
                  label: 'Manager',
                  sortValue: (a) => a.responsable,
                  flex: 2,
                  cell: (a) => saTextCell(a.responsable),
                ),
                TableColumnSpec(
                  label: 'Phone',
                  sortValue: (a) => a.telephone,
                  flex: 2,
                  cell: (a) => saTextCell(a.telephone),
                ),
                TableColumnSpec(
                  label: 'Status',
                  sortValue: (a) => a.status,
                  flex: 1,
                  cell: (a) => StatusBadge(status: a.status),
                ),
              ],
            ),
            const SizedBox(height: 22),

            _sectionTitle('Managers', '${managers.length}'),
            const SizedBox(height: 10),
            AppTable<PlatformUserModel>(
              rows: managers,
              emptyText: 'No managers under this company yet.',
              footer:
                  '${managers.length} manager${managers.length > 1 ? 's' : ''}',
              columns: [
                TableColumnSpec(
                  label: 'Name',
                  sortValue: (u) => u.nom,
                  flex: 3,
                  cell: (u) => saNameCell(u.nom),
                ),
                TableColumnSpec(
                  label: 'Phone',
                  sortValue: (u) => u.telephone,
                  flex: 2,
                  cell: (u) => saTextCell(u.telephone),
                ),
                TableColumnSpec(
                  label: 'Role',
                  sortValue: (u) => u.role,
                  flex: 2,
                  cell: (u) => saTextCell(u.role),
                ),
                TableColumnSpec(
                  label: 'Status',
                  sortValue: (u) => u.status,
                  flex: 1,
                  cell: (u) => StatusBadge(status: u.status),
                ),
              ],
            ),
            const SizedBox(height: 22),

            _sectionTitle('Clients', '${clients.length}'),
            const SizedBox(height: 10),
            AppTable<ClientModel>(
              rows: clients,
              emptyText: 'No clients under this company yet.',
              footer: '${clients.length} client${clients.length > 1 ? 's' : ''}',
              columns: [
                TableColumnSpec(
                  label: 'Name',
                  sortValue: (c) => c.name,
                  flex: 3,
                  cell: (c) => saNameCell(c.name),
                ),
                TableColumnSpec(
                  label: 'Zone',
                  sortValue: (c) => c.zone,
                  flex: 2,
                  cell: (c) => saTextCell(c.zone),
                ),
                TableColumnSpec(
                  label: 'Plan',
                  sortValue: (c) => c.plan,
                  flex: 1,
                  cell: (c) => saTextCell(c.plan),
                ),
                TableColumnSpec(
                  label: 'Status',
                  sortValue: (c) => c.status,
                  flex: 1,
                  cell: (c) => StatusBadge(status: c.status),
                ),
              ],
            ),
            const SizedBox(height: 22),

            _sectionTitle('Collectors', '${collecteurs.length}'),
            const SizedBox(height: 10),
            AppTable<CollecteurModel>(
              rows: collecteurs,
              emptyText: 'No collectors under this company yet.',
              footer:
                  '${collecteurs.length} collector${collecteurs.length > 1 ? 's' : ''}',
              columns: [
                TableColumnSpec(
                  label: 'Name',
                  sortValue: (c) => c.name,
                  flex: 3,
                  cell: (c) => saNameCell(c.name),
                ),
                TableColumnSpec(
                  label: 'Zone',
                  sortValue: (c) => c.zone,
                  flex: 2,
                  cell: (c) => saTextCell(c.zone),
                ),
                TableColumnSpec(
                  label: 'Rating',
                  sortValue: (c) => c.rating,
                  flex: 1,
                  cell: (c) => _ratingCell(c.rating),
                ),
                TableColumnSpec(
                  label: 'Status',
                  sortValue: (c) => c.status,
                  flex: 1,
                  cell: (c) => StatusBadge(status: c.status),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // --- KPIs ---

  Widget _buildKpis(
    bool wide, {
    required double cardWidth,
    required int agencesCount,
    required int managersCount,
    required int clientsCount,
    required int collecteursCount,
    required int activeClients,
  }) {
    final totalClients = clientsCount;
    final activeRate = totalClients == 0
        ? 0.0
        : (activeClients / totalClients * 100);
    final kpis = <Widget>[
      KpiCard(
        icon: Icons.storefront_rounded,
        iconBg: SuperAdminTheme.goldSoft,
        iconColor: SuperAdminTheme.goldDim,
        value: agencesCount.toDouble(),
        label: 'Agencies',
      ),
      KpiCard(
        icon: Icons.people_rounded,
        iconBg: SuperAdminTheme.blueSoft,
        iconColor: SuperAdminTheme.blue,
        value: managersCount.toDouble(),
        label: 'Managers',
      ),
      KpiCard(
        icon: Icons.person_rounded,
        iconBg: SuperAdminTheme.greenSoft,
        iconColor: SuperAdminTheme.green,
        value: clientsCount.toDouble(),
        label: 'Clients',
      ),
      KpiCard(
        icon: Icons.engineering_rounded,
        iconBg: SuperAdminTheme.redSoft,
        iconColor: SuperAdminTheme.red,
        value: collecteursCount.toDouble(),
        label: 'Collectors',
      ),
      KpiCard(
        icon: Icons.verified_rounded,
        iconBg: SuperAdminTheme.blueSoft,
        iconColor: SuperAdminTheme.blue,
        value: activeRate,
        suffix: '%',
        decimals: 0,
        label: 'Active clients',
      ),
    ];

    if (wide) {
      return Row(
        children: [
          for (var i = 0; i < kpis.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i == kpis.length - 1 ? 0 : 16,
                ),
                child: kpis[i],
              ),
            ),
        ],
      );
    }
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final kpi in kpis)
          SizedBox(width: cardWidth, child: kpi),
      ],
    );
  }

  // --- Charts ---

  Widget _buildCharts(bool wide, List<ClientModel> clients) {
    final active = clients
        .where((c) => c.status == 'Active' || c.status == 'Actif')
        .length;
    final suspended = clients.length - active;

    final planCounts = <String, int>{};
    for (final c in clients) {
      planCounts[c.plan] = (planCounts[c.plan] ?? 0) + 1;
    }
    const planOrder = ['Monthly', 'Weekly', 'Daily', 'None'];

    final statusChart = _chartCard(
      title: 'Clients by status',
      tag: '${clients.length} total',
      child: clients.isEmpty
          ? _emptyChart('No clients to display yet')
          : PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 38,
                sections: [
                  PieChartSectionData(
                    value: active.toDouble(),
                    color: SuperAdminTheme.green,
                    radius: 46,
                    title: '$active',
                    titleStyle: SuperAdminTheme.inter(
                      11,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  PieChartSectionData(
                    value: suspended.toDouble(),
                    color: SuperAdminTheme.red,
                    radius: 46,
                    title: '$suspended',
                    titleStyle: SuperAdminTheme.inter(
                      11,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
      legend: const [
        (color: SuperAdminTheme.green, label: 'Active'),
        (color: SuperAdminTheme.red, label: 'Suspended'),
      ],
    );

    final planChart = _chartCard(
      title: 'Clients by plan',
      tag: planCounts.isEmpty ? '—' : '${planCounts.length} plans',
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: SuperAdminTheme.ink,
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                    '${planOrder[group.x]}\n${rod.toY.toInt()}',
                    SuperAdminTheme.inter(11, color: SuperAdminTheme.cream),
                  ),
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
                  if (index < 0 || index >= planOrder.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      planOrder[index].substring(0, 3),
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
            for (var i = 0; i < planOrder.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (planCounts[planOrder[i]] ?? 0).toDouble(),
                    color: SuperAdminTheme.gold,
                    width: 28,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ],
              ),
          ],
        ),
      ),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: statusChart),
          const SizedBox(width: 16),
          Expanded(flex: 7, child: planChart),
        ],
      );
    }
    return Column(
      children: [
        statusChart,
        const SizedBox(height: 16),
        planChart,
      ],
    );
  }

  Widget _chartCard({
    required String title,
    required String tag,
    required Widget child,
    List<({Color color, String label})> legend = const [],
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SuperAdminTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  style: SuperAdminTheme.inter(
                    11.5,
                    color: SuperAdminTheme.muted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(height: 170, child: child),
          if (legend.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final item in legend) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    item.label,
                    style: SuperAdminTheme.inter(
                      11,
                      color: SuperAdminTheme.muted,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyChart(String message) {
    return Center(
      child: Text(
        message,
        style: SuperAdminTheme.inter(12, color: SuperAdminTheme.muted),
      ),
    );
  }

  // --- Info card ---

  /// Carte « nouveaux clients abonnés par mois » — progression annuelle de
  /// la société (scope compagnie du super admin).
  Widget _buildMonthlySubscriptions(List<ClientModel> clients) {
    final year = DateTime.now().year;
    return _chartCard(
      title: 'New clients subscribed',
      tag: '${clients.length} client${clients.length > 1 ? 's' : ''} · $year',
      child: MonthlyClientsBar(
        values: monthlySubscriptions(clients, year),
        height: 170,
      ),
    );
  }

  Widget _buildInfoCard(SocieteModel societe) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SuperAdminTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: SuperAdminTheme.goldSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.business_rounded,
                  size: 15,
                  color: SuperAdminTheme.goldDim,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Company',
                style: SuperAdminTheme.sora(14.5, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final (label, value) in [
            ('Name', societe.raisonSociale),
            ('Address', societe.adresse),
            ('Email', societe.email),
            ('Phone', societe.telephone),
            ('Status', societe.status),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      label.toUpperCase(),
                      style: SuperAdminTheme.inter(
                        10,
                        weight: FontWeight.w600,
                        color: SuperAdminTheme.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value.isEmpty ? '—' : value,
                      style: SuperAdminTheme.inter(12.8),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String count) {
    return Row(
      children: [
        Text(title, style: SuperAdminTheme.sora(15, weight: FontWeight.w700)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: SuperAdminTheme.chip(SuperAdminTheme.goldSoft),
          child: Text(
            count,
            style: SuperAdminTheme.inter(
              11,
              weight: FontWeight.w700,
              color: SuperAdminTheme.goldDim,
            ),
          ),
        ),
      ],
    );
  }

  Widget _ratingCell(double rating) {
    if (rating <= 0) {
      return Text('—', style: SuperAdminTheme.inter(12.5, color: SuperAdminTheme.muted));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.star_rounded,
          size: 13,
          color: SuperAdminTheme.gold,
        ),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: SuperAdminTheme.inter(12.5, weight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// En-tête de la fiche : retour, identité de la société, badge de statut et
/// actions Éditer / Supprimer.
class _Header extends StatelessWidget {
  const _Header({
    required this.societe,
    required this.agencesCount,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
  });

  final SocieteModel societe;
  final int agencesCount;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SuperAdminTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Retour à la liste.
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_back_rounded,
                    size: 15,
                    color: SuperAdminTheme.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Back to companies',
                    style: SuperAdminTheme.inter(
                      12.5,
                      weight: FontWeight.w600,
                      color: SuperAdminTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: SuperAdminTheme.goldSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.business_rounded,
                  size: 24,
                  color: SuperAdminTheme.goldDim,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      societe.raisonSociale,
                      style: SuperAdminTheme.sora(19, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.storefront_rounded,
                          size: 13,
                          color: SuperAdminTheme.muted,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            agencesCount == 0
                                ? 'No agency yet'
                                : agencesCount == 1
                                    ? '1 agency'
                                    : '$agencesCount agencies',
                            overflow: TextOverflow.ellipsis,
                            style: SuperAdminTheme.inter(
                              12.5,
                              color: SuperAdminTheme.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusBadge(status: societe.status),
            ],
          ),
          const SizedBox(height: 16),
          // Rangée « meta + actions » : sur écran étroit, les chips passent
          // sur une ligne et les boutons d'action dessous (sinon tout est
          // écrasé dans une seule rangée → débordement).
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final chips = Row(
                children: [
                  Expanded(
                    child: _metaChip(
                      icon: Icons.place_outlined,
                      label: societe.adresse.isEmpty ? '—' : societe.adresse,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metaChip(
                      icon: Icons.phone_outlined,
                      label: societe.telephone.isEmpty ? '—' : societe.telephone,
                    ),
                  ),
                ],
              );
              final emailChip = _metaChip(
                icon: Icons.email_outlined,
                label: societe.email.isEmpty ? '—' : societe.email,
              );
              final actions = Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  _actionButton(
                    label: 'Edit',
                    icon: Icons.edit_rounded,
                    onTap: onEdit,
                    filled: false,
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    label: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    onTap: onDelete,
                    filled: true,
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    chips,
                    const SizedBox(height: 10),
                    emailChip,
                    const SizedBox(height: 10),
                    actions,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  chips,
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: emailChip),
                      const SizedBox(width: 10),
                      actions,
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _metaChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: SuperAdminTheme.rowHover,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SuperAdminTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: SuperAdminTheme.goldDim),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SuperAdminTheme.inter(12, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool filled,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: filled ? SuperAdminTheme.red : SuperAdminTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: filled ? null : Border.all(color: SuperAdminTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: filled ? Colors.white : SuperAdminTheme.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: SuperAdminTheme.inter(
                12,
                weight: FontWeight.w600,
                color: filled ? Colors.white : SuperAdminTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
