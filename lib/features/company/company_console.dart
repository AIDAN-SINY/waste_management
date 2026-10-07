import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../models/agence_model.dart';
import '../../models/platform_user_model.dart';
import '../backoffice/models.dart';
import '../superadmin/widgets/monthly_clients_bar.dart';
import '../superadmin/theme.dart';
import '../superadmin/widgets/app_table.dart';
import '../superadmin/widgets/app_toast.dart';
import '../superadmin/widgets/cells.dart';
import '../superadmin/widgets/confirm_dialog.dart';
import '../superadmin/widgets/crud_drawer.dart';
import '../superadmin/widgets/form_fields.dart';
import '../superadmin/widgets/form_validation.dart';
import '../superadmin/widgets/primary_button.dart';
import '../superadmin/widgets/sa_search_field.dart';
import '../superadmin/widgets/status_badge.dart';
import 'data/company_store.dart';
import 'data/firestore_company_store.dart';
import 'widgets/company_charts.dart';
import 'widgets/create_agency_modal.dart';
import 'widgets/manager_credentials_dialog.dart';

/// Console entreprise — General Administrator.
///
/// Phase 2 : gestion des agences et des chefs d'agence de l'entreprise.
/// Les données sont scopées par [societeId] (l'id de l'entreprise
/// de l'administrateur, stocké dans `users/{phone}/societeId`).
///
/// Le General Administrator pilote toute son entreprise depuis ici :
/// un header avec un dropdown d'agences (zoom sur une agence → les stats
/// de l'Overview se filtrent), une Overview riche (KPIs + graphiques +
/// cartes d'agences) et la gestion des agences / chefs d'agence.
class CompanyConsole extends StatefulWidget {
  const CompanyConsole({super.key, this.societeId, this.store});

  /// Id of the connected administrator's company. '' in demo preview.
  final String? societeId;

  /// Injected store (tests); otherwise created lazily.
  final CompanyStore? store;

  @override
  State<CompanyConsole> createState() => _CompanyConsoleState();
}

class _CompanyConsoleState extends State<CompanyConsole> {
  late CompanyStore _store;
  late bool _ownsStore;
  int _page = 0;

  static const _navItems = [
    (icon: Icons.speed_rounded, label: 'Overview'),
    (icon: Icons.storefront_rounded, label: 'Agencies'),
    (icon: Icons.people_rounded, label: 'Managers'),
  ];
  static const _meta = [
    (title: 'Overview', sub: 'Your company at a glance'),
    (title: 'Agencies', sub: 'Manage your agencies'),
    (title: 'Managers', sub: 'Agency managers'),
  ];

  @override
  void initState() {
    super.initState();
    _bindStore();
    // Preview démo : un store mock créé ICI (jamais un store injecté par
    // les tests) est seedé pour que l'interface soit riche dès l'ouverture
    // (comme le backoffice et la console super admin).
    if (_ownsStore && _store is! FirestoreCompanyStore) {
      _store.seedPreviewData();
    }
    _store.load();
  }

  void _bindStore() {
    _ownsStore = widget.store == null;
    final sid = widget.societeId ?? '';
    _store = widget.store ??
        (sid.isNotEmpty
            ? FirestoreCompanyStore(societeId: sid)
            : CompanyStore());
  }

  @override
  void dispose() {
    if (_ownsStore) _store.dispose();
    super.dispose();
  }

  void _handleExit() {
    UserProvider? userProvider;
    try {
      userProvider = context.read<UserProvider>();
    } catch (_) {
      userProvider = null;
    }
    if (userProvider?.user != null) {
      userProvider!.logout();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Nom affiché dans le pied de sidebar : le nom du General Administrator
  /// connecté (UserProvider), avec repli sur le nom de l'entreprise quand le
  /// profil n'est pas disponible (preview démo / tests sans provider).
  String _adminDisplayName() {
    try {
      final user = context.read<UserProvider>().user;
      final name = user?.fullName.trim() ?? '';
      if (name.isNotEmpty) return name;
    } catch (_) {
      // Provider absent (preview / tests) → repli entreprise.
    }
    final societeNom = _store.societeNom;
    return societeNom.isNotEmpty ? societeNom : 'Administrator';
  }

  // --- Demo detection ---
  bool get _isDemo => _store is! FirestoreCompanyStore;

  /// Selects an agency from the header dropdown and switches to
  /// the Overview to show its stats.
  void _selectAgence(String id) {
    _store.selectAgence(id);
    setState(() => _page = 0);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _store,
      child: Material(
        color: SuperAdminTheme.bg,
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(),
                Expanded(child: _buildMain()),
              ],
            ),
            // Toasts (succès/erreur des actions) — obligatoire pour que
            // ToastService.show() soit visible.
            ToastService.host(),
          ],
        ),
      ),
    );
  }

  // --- Sidebar ---

  Widget _buildSidebar() {
    return Material(
      color: SuperAdminTheme.ink,
      child: SizedBox(
        width: 248,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: SuperAdminTheme.gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.business_rounded,
                      size: 17,
                      color: SuperAdminTheme.gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Company',
                        style: SuperAdminTheme.sora(
                          15,
                          weight: FontWeight.w700,
                          color: SuperAdminTheme.cream,
                        ),
                        children: [
                          TextSpan(
                            text: ' Console',
                            style: SuperAdminTheme.sora(
                              15,
                              weight: FontWeight.w700,
                              color: SuperAdminTheme.gold,
                            ),
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Company card
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Consumer<CompanyStore>(
                builder: (context, store, _) {
                  final nom = store.societeNom.isNotEmpty
                      ? store.societeNom
                      : 'My Company';
                  final initials = saInitials(nom);
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SuperAdminTheme.inkSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SuperAdminTheme.inkLine),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: SuperAdminTheme.gold.withValues(
                                  alpha: 0.18,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: SuperAdminTheme.inter(
                                    11,
                                    weight: FontWeight.w700,
                                    color: SuperAdminTheme.gold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                nom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SuperAdminTheme.inter(
                                  12.5,
                                  weight: FontWeight.w700,
                                  color: SuperAdminTheme.cream,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _sidebarStat(
                              icon: Icons.storefront_rounded,
                              value: '${store.agences.length}',
                              label: 'Agencies',
                            ),
                            const SizedBox(width: 8),
                            _sidebarStat(
                              icon: Icons.people_rounded,
                              value: '${store.managersCount}',
                              label: 'Managers',
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // Navigation
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _navItems.length; i++)
                      _navItem(i, _navItems[i].icon, _navItems[i].label),
                  ],
                ),
              ),
            ),
            // Footer — identité du General Administrator connecté.
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 18),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: SuperAdminTheme.inkLine),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: SuperAdminTheme.gold.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        saInitials(_adminDisplayName()),
                        style: const TextStyle(
                          color: SuperAdminTheme.gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _adminDisplayName(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SuperAdminTheme.inter(
                            11.5,
                            weight: FontWeight.w600,
                            color: SuperAdminTheme.cream,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'General Administrator',
                          style: SuperAdminTheme.inter(
                            10,
                            color: const Color(0x80F5F1E8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: _handleExit,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.logout_rounded,
                        size: 16,
                        color: const Color(0x80F5F1E8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarStat({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: SuperAdminTheme.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: SuperAdminTheme.gold),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: SuperAdminTheme.inter(
                      12,
                      weight: FontWeight.w700,
                      color: SuperAdminTheme.cream,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SuperAdminTheme.inter(
                      9,
                      color: const Color(0x80F5F1E8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final active = _page == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        key: Key('cc_nav_${label.toLowerCase()}'),
        onTap: () => setState(() => _page = index),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active
                ? SuperAdminTheme.gold.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: active
                ? Border.all(
                    color: SuperAdminTheme.gold.withValues(alpha: 0.32),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? SuperAdminTheme.gold
                    : SuperAdminTheme.cream.withValues(alpha: 0.62),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: SuperAdminTheme.inter(
                    13,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active
                        ? SuperAdminTheme.gold
                        : SuperAdminTheme.cream.withValues(alpha: 0.62),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Main ---

  Widget _buildMain() {
    return Column(
      children: [
        _buildTopbar(),
        if (_isDemo) const _DemoBanner(),
        Consumer<CompanyStore>(
          builder: (context, store, _) {
            if (store.isLoading) {
              return const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: SuperAdminTheme.gold,
              );
            }
            if (store.error != null) {
              return _ErrorBanner(
                message: store.error!,
                onRetry: store.load,
              );
            }
            return const SizedBox.shrink();
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: IndexedStack(
              index: _page,
              children: const [
                OverviewPage(),
                _AgenciesPage(),
                _ManagersPage(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: const BoxDecoration(
        color: SuperAdminTheme.bg,
        border: Border(bottom: BorderSide(color: SuperAdminTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _meta[_page].title,
                  style: SuperAdminTheme.sora(19, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _meta[_page].sub,
                  style: SuperAdminTheme.inter(
                    12,
                    color: SuperAdminTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          // Dropdown d'agences : zoom sur une agence = les stats de
          // l'Overview se filtrent à cette agence.
          _buildAgencyDropdown(),
          const SizedBox(width: 12),
          _TopbarIconButton(
            icon: Icons.notifications_none_rounded,
            dot: true,
            onTap: () => ToastService.show('No new notifications'),
          ),
        ],
      ),
    );
  }

  /// Header dropdown: "All agencies" + one entry per agency.
  Widget _buildAgencyDropdown() {
    return Consumer<CompanyStore>(
      builder: (context, store, _) {
        final selected = store.selectedAgence;
        final label = selected?.ville ?? 'All agencies';
        return PopupMenuButton<String>(
          key: const Key('cc_agency_dropdown'),
          initialValue: store.selectedAgenceId,
          onOpened: () {},
          onSelected: _selectAgence,
          color: SuperAdminTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          itemBuilder: (context) => [
            PopupMenuItem(
              key: const Key('cc_dd_all'),
              value: '',
              child: _dropdownItem(
                icon: Icons.apartment_rounded,
                label: 'All agencies',
                selected: store.selectedAgenceId.isEmpty,
              ),
            ),
            for (final a in store.agences)
              PopupMenuItem(
                key: Key('cc_dd_${a.id}'),
                value: a.id,
                child: _dropdownItem(
                  icon: Icons.storefront_rounded,
                  label: a.ville,
                  selected: store.selectedAgenceId == a.id,
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: SuperAdminTheme.surface,
              border: Border.all(color: SuperAdminTheme.border),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  size: 16,
                  color: SuperAdminTheme.goldDim,
                ),
                const SizedBox(width: 9),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SuperAdminTheme.inter(
                      12.5,
                      weight: FontWeight.w600,
                      color: SuperAdminTheme.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: SuperAdminTheme.muted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dropdownItem({
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: SuperAdminTheme.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SuperAdminTheme.inter(
              12.5,
              weight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? SuperAdminTheme.text : SuperAdminTheme.muted,
            ),
          ),
        ),
        if (selected) ...[
          const SizedBox(width: 8),
          const Icon(
            Icons.check_rounded,
            size: 16,
            color: SuperAdminTheme.gold,
          ),
        ],
      ],
    );
  }
}

// --- Bandeau démo ---

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: SuperAdminTheme.gold.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.science_outlined,
            size: 15,
            color: SuperAdminTheme.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Demo preview — changes are not saved. Log in as a '
              'General Administrator to manage your company.',
              style: SuperAdminTheme.inter(12, color: SuperAdminTheme.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Bannière d'erreur ---

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: SuperAdminTheme.redSoft,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 15,
            color: SuperAdminTheme.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: SuperAdminTheme.inter(12, color: SuperAdminTheme.red),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: SuperAdminTheme.red,
              textStyle: SuperAdminTheme.inter(12, weight: FontWeight.w600),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// --- Bouton icône topbar ---

class _TopbarIconButton extends StatelessWidget {
  const _TopbarIconButton({
    required this.icon,
    required this.onTap,
    this.dot = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: SuperAdminTheme.bg,
          border: Border.all(color: SuperAdminTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 18, color: SuperAdminTheme.muted),
            if (dot)
              Positioned(
                top: 9,
                right: 10,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: SuperAdminTheme.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// Pages
// ====================================================================

// --- Overview ---

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  static const _statusColors = [
    SuperAdminTheme.green,
    SuperAdminTheme.red,
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CompanyStore>();
    final sel = store.selectedAgence;
    final nom = store.societeNom.isNotEmpty ? store.societeNom : 'Your Company';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 880;
        final padding = constraints.maxWidth - 56;
        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            // Bandeau contexte
            _ScopeHeader(store: store, nom: nom),
            const SizedBox(height: 16),
            // KPIs
            _buildKpis(store, wide, padding),
            const SizedBox(height: 16),
            // Charts
            _buildCharts(store, wide),
            const SizedBox(height: 16),
            // Progression annuelle des abonnements (scope entreprise ou
            // agence zoomée).
            _buildAnnualSubscriptions(store),
            const SizedBox(height: 16),
            // Agences (ou agence sélectionnée) + managers
            if (sel == null)
              _AgenciesOverview(store: store)
            else
              _AgencyDetail(store: store, agence: sel),
          ],
        );
      },
    );
  }

  Widget _buildKpis(CompanyStore store, bool wide, double paddingWidth) {
    final sel = store.selectedAgence;
    final kpis = <Widget>[
      _KpiCard(
        icon: Icons.storefront_rounded,
        iconBg: SuperAdminTheme.goldSoft,
        iconColor: SuperAdminTheme.goldDim,
        value: '${store.scopedAgences.length}',
        label: sel == null ? 'Total agencies' : 'Agency',
      ),
      _KpiCard(
        icon: Icons.people_rounded,
        iconBg: SuperAdminTheme.greenSoft,
        iconColor: SuperAdminTheme.green,
        value: '${store.scopedManagersCount}',
        label: 'Managers',
      ),
      _KpiCard(
        icon: Icons.check_circle_rounded,
        iconBg: SuperAdminTheme.blueSoft,
        iconColor: SuperAdminTheme.blue,
        value: '${store.activeAgencies}',
        label: 'Active agencies',
      ),
      _KpiCard(
        icon: Icons.leaderboard_rounded,
        iconBg: SuperAdminTheme.redSoft,
        iconColor: SuperAdminTheme.red,
        value: sel != null
            ? '${store.managersForAgence(sel.id)}'
            : '${store.agences.isEmpty ? 0 : (store.managersCount / store.agences.length).toStringAsFixed(1)}',
        label: sel != null ? 'Managers / agency' : 'Managers per agency',
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
          SizedBox(
            width: (paddingWidth - 16) / 2,
            child: kpi,
          ),
      ],
    );
  }

  Widget _buildCharts(CompanyStore store, bool wide) {
    final sel = store.selectedAgence;
    // Bar chart : managers par agence (ou par manager pour une agence).
    final barValues = sel == null
        ? store.agences
              .map((a) => store.managersForAgence(a.id).toDouble())
              .toList()
        : store.scopedUtilisateurs
              .map((_) => 1.0)
              .toList();
    final barLabels = sel == null
        ? store.agences.map((a) => a.ville).toList()
        : store.scopedUtilisateurs.map((u) => u.nom).toList();

    // Donut : statut des agences (ou des managers).
    final donutValues = sel == null
        ? [
            store.activeAgencies.toDouble(),
            (store.scopedAgences.length - store.activeAgencies).toDouble(),
          ]
        : _statusCounts(store.scopedUtilisateurs);
    final donutLabels = sel == null
        ? ['Active', 'Suspended']
        : _statusLabels();
    final donutColors = sel == null
        ? [SuperAdminTheme.green, SuperAdminTheme.red]
        : _statusColors;

    final barChart = _chartCard(
      title: sel == null ? 'Managers per agency' : 'Managers',
      tag: sel?.ville ?? 'All agencies',
      child: CcBarChart(values: barValues, labels: barLabels),
    );
    final donutChart = _chartCard(
      title: sel == null ? 'Agency status' : 'Manager status',
      tag: sel?.status ?? '',
      child: CcDonutChart(
        values: donutValues,
        labels: donutLabels,
        colors: donutColors,
        centerValue:
            '${donutValues.fold<double>(0, (a, b) => a + b).round()}',
        centerLabel: sel == null ? 'agencies' : 'managers',
      ),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: barChart),
          const SizedBox(width: 16),
          Expanded(flex: 5, child: donutChart),
        ],
      );
    }
    return Column(
      children: [
        barChart,
        const SizedBox(height: 16),
        donutChart,
      ],
    );
  }

  /// Carte « nouveaux clients abonnés par mois » (Jan → Déc de l'année
  /// courante), scopée à l'entreprise — ou à l'agence zoomée.
  Widget _buildAnnualSubscriptions(CompanyStore store) {
    final sel = store.selectedAgence;
    final year = DateTime.now().year;
    final counts = monthlySubscriptions(store.scopedClients, year);
    return _chartCard(
      title: 'New clients subscribed',
      tag: '${sel?.ville ?? 'All agencies'} · $year',
      child: MonthlyClientsBar(values: counts),
    );
  }

  List<double> _statusCounts(List<PlatformUserModel> users) {
    var activeCount = 0;
    for (final u in users) {
      if (u.status == 'Active' || u.status == 'Actif') activeCount++;
    }
    return [activeCount.toDouble(), (users.length - activeCount).toDouble()];
  }

  List<String> _statusLabels() {
    return ['Active', 'Suspended'];
  }
}

Widget _chartCard({
  required String title,
  required String tag,
  required Widget child,
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
                overflow: TextOverflow.ellipsis,
                style: SuperAdminTheme.inter(11.5, color: SuperAdminTheme.muted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

/// Bandeau d'en-tête de l'Overview : nom de l'entreprise + agence filtrée.
class _ScopeHeader extends StatelessWidget {
  const _ScopeHeader({required this.store, required this.nom});

  final CompanyStore store;
  final String nom;

  @override
  Widget build(BuildContext context) {
    final sel = store.selectedAgence;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: SuperAdminTheme.card(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: SuperAdminTheme.goldSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.apartment_rounded,
              size: 22,
              color: SuperAdminTheme.goldDim,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nom,
                  style: SuperAdminTheme.sora(17, weight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  sel != null
                      ? 'Viewing ${sel.ville} — ${sel.responsable}'
                      : 'Viewing all your agencies',
                  style: SuperAdminTheme.inter(
                    12,
                    color: SuperAdminTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          if (store.societes.isNotEmpty)
            StatusBadge(status: store.societes.first.status),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: SuperAdminTheme.sora(26, weight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: SuperAdminTheme.inter(12, color: SuperAdminTheme.muted),
          ),
        ],
      ),
    );
  }
}

// --- Grille d'agences (vue « toutes ») ---

class _AgenciesOverview extends StatelessWidget {
  const _AgenciesOverview({required this.store});

  final CompanyStore store;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Your agencies',
            style: SuperAdminTheme.sora(15, weight: FontWeight.w700),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 16) / 2;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final a in store.agences)
                  SizedBox(
                    width: cardWidth,
                    child: _AgencyCard(
                      agence: a,
                      managerCount: store.managersForAgence(a.id),
                      onView: () => store.selectAgence(a.id),
                    ),
                  ),
              ],
            );
          },
        ),
        if (store.agences.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: SuperAdminTheme.card(),
            child: Center(
              child: Text(
                'No agencies yet. Create your first agency to get started.',
                textAlign: TextAlign.center,
                style: SuperAdminTheme.inter(12.5, color: SuperAdminTheme.muted),
              ),
            ),
          ),
      ],
    );
  }
}

class _AgencyCard extends StatelessWidget {
  const _AgencyCard({
    required this.agence,
    required this.managerCount,
    required this.onView,
  });

  final AgenceModel agence;
  final int managerCount;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                  Icons.storefront_rounded,
                  size: 16,
                  color: SuperAdminTheme.goldDim,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  agence.ville,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SuperAdminTheme.inter(
                    13,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              StatusBadge(status: agence.status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _cardMeta(icon: Icons.person_rounded, text: agence.responsable),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _cardMeta(icon: Icons.groups_rounded, text: '$managerCount managers'),
              const SizedBox(width: 14),
              _cardMeta(icon: Icons.phone_rounded, text: agence.telephone),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onView,
              style: TextButton.styleFrom(
                foregroundColor: SuperAdminTheme.goldDim,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: SuperAdminTheme.inter(
                  12,
                  weight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.visibility_rounded, size: 15),
              label: const Text('View stats'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardMeta({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: SuperAdminTheme.muted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SuperAdminTheme.inter(11.5, color: SuperAdminTheme.muted),
          ),
        ),
      ],
    );
  }
}

// --- Détail d'une agence (vue « zoom ») ---

class _AgencyDetail extends StatelessWidget {
  const _AgencyDetail({required this.store, required this.agence});

  final CompanyStore store;
  final AgenceModel agence;

  @override
  Widget build(BuildContext context) {
    final managers =
        store.managers
            .where((u) => u.agenceId == agence.id || u.agence == agence.ville)
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Managers — ${agence.ville}',
                style: SuperAdminTheme.sora(15, weight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: () => store.selectAgence(''),
              style: TextButton.styleFrom(
                foregroundColor: SuperAdminTheme.goldDim,
                textStyle: SuperAdminTheme.inter(
                  12,
                  weight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 15),
              label: const Text('All agencies'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppTable<PlatformUserModel>(
          rows: managers,
          emptyText: 'No managers in this agency',
          footer: '${managers.length} manager${managers.length > 1 ? 's' : ''}',
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
              label: 'Status',
              sortValue: (u) => u.status,
              flex: 1,
              cell: (u) => StatusBadge(status: u.status),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Agences ---

class _AgenciesPage extends StatefulWidget {
  const _AgenciesPage();

  @override
  State<_AgenciesPage> createState() => _AgenciesPageState();
}

class _AgenciesPageState extends State<_AgenciesPage> {
  final Map<String, dynamic> _form = {};

  /// Recherche live sur la page courante (nom, manager, téléphone).
  final _searchCtrl = TextEditingController();
  String _search = '';

  /// Opens the "New agency" modal: a centered dialog whose non-editable
  /// top badge shows the logged-in General Administrator's company, then
  /// asks for the agency name, location, manager, manager phone, city and
  /// agency phone. When a manager name is entered, the Agency Manager
  /// account is created right away with a generated numeric login password
  /// (shown once afterwards) — the admin doesn't have to open the Managers
  /// page again.
  void openCreate() async {
    final societeNom = context.read<CompanyStore>().societeNom;
    String? createdManagerName;
    String? createdManagerPhone;
    String? createdManagerPassword;
    await showCreateAgencyModal(
      context,
      companyName:
          societeNom.isNotEmpty ? societeNom : 'Your Company',
      onSave: (form) async {
        try {
          final store = context.read<CompanyStore>();
          final nom = form['nom']?.toString().trim() ?? '';
          final villePart = form['ville']?.toString().trim() ?? '';
          // The agency is named after its city (e.g. "Yaoundé — Bastos"):
          // City and Agency name are combined into the existing ville field.
          // If the name already includes the city, keep it as-is to avoid
          // duplication ("Yaoundé — Yaoundé — Bastos").
          final ville = villePart.isEmpty
              ? nom
              : nom.isEmpty || villePart.contains(nom)
                    ? villePart
                    : '$villePart — $nom';
          if (ville.isEmpty) {
            throw const ValidationError(
              'Please enter an agency name or a city.',
            );
          }
          final managerName =
              form['responsable']?.toString().trim() ?? '';
          final managerPhone =
              form['managerPhone']?.toString().trim() ?? '';
          if (managerName.isNotEmpty && managerPhone.isEmpty) {
            throw const ValidationError(
              'Please enter the manager phone number.',
            );
          }
          if (managerName.isEmpty && managerPhone.isNotEmpty) {
            throw const ValidationError(
              'Please enter the manager name.',
            );
          }
          final agence = await store.addAgence(
            ville: ville,
            location: form['location']?.toString().trim() ?? '',
            responsable: managerName,
            telephone: form['telephone']?.toString().trim() ?? '',
            status: 'Active',
          );
          // Sync with the managers: the name entered here becomes the
          // Agency Manager of the new agency, so it shows up in the
          // Managers page without being re-created there.
          if (managerName.isNotEmpty) {
            final password = _numericPassword();
            try {
              await store.addUtilisateur(
                nom: managerName,
                telephone: managerPhone,
                role: 'Agency Manager',
                agence: agence.ville,
                agenceId: agence.id,
                status: 'Active',
                password: password,
              );
            } catch (e) {
              // Best-effort rollback: keep agency + manager creation
              // atomic so a retry doesn't leave/duplicate an orphan agency.
              try {
                await store.deleteAgence(agence.id);
              } catch (_) {}
              rethrow;
            }
            createdManagerName = managerName;
            createdManagerPhone = managerPhone;
            createdManagerPassword = password;
          }
          // When a manager was created, the credentials dialog right after
          // is the confirmation — a toast would be hidden behind it.
          if (managerName.isEmpty) {
            ToastService.show('Agency created successfully.');
          }
        } catch (e) {
          ToastService.show(e.toString(), isError: true);
          rethrow;
        }
      },
    );
    // Reveal the generated credentials once, after the modal closes.
    if (mounted &&
        createdManagerName != null &&
        createdManagerPhone != null &&
        createdManagerPassword != null) {
      await showManagerCredentialsDialog(
        context,
        managerName: createdManagerName!,
        managerPhone: createdManagerPhone!,
        password: createdManagerPassword!,
      );
    }
  }

  void openEdit(AgenceModel agence) {
    _form
      ..clear()
      ..addAll(agence.toMap());
    showCrudDrawer(
      context,
      title: 'Edit agency',
      body: _buildForm(),
      onSave: () async {
        try {
          final ville = requireField(_form, 'ville', 'City');
          await context.read<CompanyStore>().updateAgence(
                agence.copyWith(
                  ville: ville,
                  responsable:
                      _form['responsable']?.toString().trim(),
                  telephone:
                      _form['telephone']?.toString().trim(),
                  status: _form['status']?.toString(),
                ),
              );
          ToastService.show('Changes saved.');
        } catch (e) {
          ToastService.show(e.toString(), isError: true);
          rethrow;
        }
      },
    );
  }

  Future<void> confirmDelete(AgenceModel agence) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this agency?',
      message:
          '"${agence.ville}" will be permanently deleted. This action is irreversible.',
    );
    if (confirmed == true && mounted) {
      try {
        await context.read<CompanyStore>().deleteAgence(agence.id);
        if (mounted) ToastService.show('Item deleted.');
      } catch (e) {
        if (mounted) ToastService.show(e.toString(), isError: true);
      }
    }
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SaTextField(
          label: 'City',
          initial: _form['ville']?.toString(),
          hint: 'Ex. Yaoundé — Bastos',
          onChanged: (v) => _form['ville'] = v,
        ),
        const SizedBox(height: 16),
        SaTextField(
          label: 'Manager',
          initial: _form['responsable']?.toString(),
          hint: 'Manager name',
          onChanged: (v) => _form['responsable'] = v,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SaTextField(
                label: 'Phone',
                initial: _form['telephone']?.toString(),
                hint: '+237 6XX XX XX XX',
                keyboardType: TextInputType.phone,
                onChanged: (v) => _form['telephone'] = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SaSelectField(
                label: 'Status',
                options: const ['Active', 'Suspended'],
                initial: _form['status']?.toString() ?? 'Active',
                onChanged: (v) => _form['status'] = v,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CompanyStore>();
    final filteredAgences = store.agences.where((a) {
      if (_search.isEmpty) return true;
      return a.ville.toLowerCase().contains(_search) ||
          a.responsable.toLowerCase().contains(_search) ||
          a.telephone.toLowerCase().contains(_search);
    }).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Row(
          children: [
            Expanded(
              child: SaSearchField(
                key: const Key('cc_search_agences'),
                controller: _searchCtrl,
                hint: 'Search agencies...',
                onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 12),
            PrimaryButton(
              label: 'New agency',
              icon: Icons.add_rounded,
              onTap: openCreate,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppTable<AgenceModel>(
          rows: filteredAgences,
          emptyText: 'No agencies yet',
          footer: '${filteredAgences.length} agenc${filteredAgences.length > 1 ? 'ies' : 'y'}',
          columns: [
            TableColumnSpec(
              label: 'Agency',
              sortValue: (a) => a.ville,
              flex: 3,
              cell: (a) => saNameCell(a.ville),
            ),
            TableColumnSpec(
              label: 'Manager',
              sortValue: (a) => a.responsable,
              flex: 2,
              cell: (a) => saTextCell(a.responsable),
            ),
            TableColumnSpec(
              label: 'Status',
              sortValue: (a) => a.status,
              flex: 1,
              cell: (a) => StatusBadge(status: a.status),
            ),
          ],
          actions: (a) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RowActionButton(
                icon: Icons.edit_rounded,
                onTap: () => openEdit(a),
              ),
              RowActionButton(
                icon: Icons.delete_outline_rounded,
                onTap: () => confirmDelete(a),
                danger: true,
              ),
            ],
          ),
          onRowTap: openEdit,
        ),
      ],
    );
  }
}

// --- Managers ---

class _ManagersPage extends StatefulWidget {
  const _ManagersPage();

  @override
  State<_ManagersPage> createState() => _ManagersPageState();
}

class _ManagersPageState extends State<_ManagersPage> {
  final Map<String, dynamic> _form = {};

  /// Recherche live sur la page courante (nom, agence, téléphone).
  final _searchCtrl = TextEditingController();
  String _search = '';

  List<String> get _agenceOptions {
    final agences = context.read<CompanyStore>().agences.map((a) => a.ville).toList();
    return ['—', ...agences];
  }

  String _agenceIdFor(String ville) {
    for (final a in context.read<CompanyStore>().agences) {
      if (a.ville == ville) return a.id;
    }
    return '';
  }

  void openEdit(PlatformUserModel user) {
    _form
      ..clear()
      ..addAll(user.toMap())
      ..remove('password');
    showCrudDrawer(
      context,
      title: 'Edit manager',
      body: _buildForm(),
      onSave: () async {
        try {
          final nom = requireField(_form, 'nom', 'Full name');
          final telephone = requireField(_form, 'telephone', 'Phone');
          final password = _form['password']?.toString().trim() ?? '';
          final agenceVille = _form['agence']?.toString() ?? '—';
          if (agenceVille == '—') {
            throw 'Please assign this manager to an agency.';
          }
          await context.read<CompanyStore>().updateUtilisateur(
                user.copyWith(
                  nom: nom,
                  telephone: telephone,
                  agence: agenceVille,
                  agenceId: _agenceIdFor(agenceVille),
                  status: _form['status']?.toString(),
                  password: password.isEmpty ? user.password : password,
                ),
              );
          ToastService.show('Changes saved.');
        } catch (e) {
          ToastService.show(e.toString(), isError: true);
          rethrow;
        }
      },
    );
  }

  Future<void> confirmDelete(PlatformUserModel user) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this manager?',
      message:
          '"${user.nom}" will be permanently deleted. This action is irreversible.',
    );
    if (confirmed == true && mounted) {
      try {
        await context.read<CompanyStore>().deleteUtilisateur(user.id);
        if (mounted) ToastService.show('Item deleted.');
      } catch (e) {
        if (mounted) ToastService.show(e.toString(), isError: true);
      }
    }
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SaTextField(
          label: 'Full name',
          initial: _form['nom']?.toString(),
          hint: 'Ex. Jean Dooh',
          onChanged: (v) => _form['nom'] = v,
        ),
        const SizedBox(height: 16),
        SaTextField(
          label: 'Phone',
          initial: _form['telephone']?.toString(),
          hint: '+237 6XX XX XX XX',
          keyboardType: TextInputType.phone,
          onChanged: (v) => _form['telephone'] = v,
        ),
        const SizedBox(height: 16),
        SaSelectField(
          label: 'Agency',
          options: _agenceOptions,
          initial: _form['agence']?.toString(),
          onChanged: (v) => _form['agence'] = v,
        ),
        const SizedBox(height: 16),
        SaTextField(
          label: 'Password',
          initial: _form['password']?.toString(),
          hint: 'Login password',
          obscureText: true,
          onChanged: (v) => _form['password'] = v,
        ),
        const SizedBox(height: 16),
        SaSelectField(
          label: 'Status',
          options: const ['Active', 'Suspended'],
          initial: _form['status']?.toString() ?? 'Active',
          onChanged: (v) => _form['status'] = v,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CompanyStore>();
    // Le General Administrator connecté n'est pas un manager : il ne doit
    // jamais apparaître dans la liste des chefs d'agence.
    final filteredManagers = store.managers.where((u) {
      if (_search.isEmpty) return true;
      return u.nom.toLowerCase().contains(_search) ||
          u.telephone.toLowerCase().contains(_search) ||
          u.agence.toLowerCase().contains(_search);
    }).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Row(
          children: [
            Expanded(
              child: SaSearchField(
                key: const Key('cc_search_managers'),
                controller: _searchCtrl,
                hint: 'Search managers...',
                onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 12),
            // Managers are created together with their agency (agency
            // modal) — no separate creation flow here.
            Text(
              'Managers are created with their agency.',
              style: SuperAdminTheme.inter(
                12,
                color: SuperAdminTheme.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppTable<PlatformUserModel>(
          rows: filteredManagers,
          emptyText: 'No managers yet',
          footer: '${filteredManagers.length} manager${filteredManagers.length > 1 ? 's' : ''}',
          columns: [
            TableColumnSpec(
              label: 'Name',
              sortValue: (u) => u.nom,
              flex: 3,
              cell: (u) => saNameCell(u.nom),
            ),
            TableColumnSpec(
              label: 'Agency',
              sortValue: (u) => u.agence,
              flex: 2,
              cell: (u) => saTextCell(u.agence),
            ),
            TableColumnSpec(
              label: 'Status',
              sortValue: (u) => u.status,
              flex: 1,
              cell: (u) => StatusBadge(status: u.status),
            ),
          ],
          actions: (u) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RowActionButton(
                icon: Icons.edit_rounded,
                onTap: () => openEdit(u),
              ),
              RowActionButton(
                icon: Icons.delete_outline_rounded,
                onTap: () => confirmDelete(u),
                danger: true,
              ),
            ],
          ),
          onRowTap: openEdit,
        ),
      ],
    );
  }
}

/// Generates a short numeric login password (digits only) for
/// auto-created managers.
String _numericPassword([int length = 6]) {
  final rand = Random.secure();
  return List.generate(length, (_) => rand.nextInt(10)).join();
}