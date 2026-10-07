import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import 'data/backoffice_store.dart';
import 'data/firestore_backoffice_store.dart';
import 'models.dart';
import 'pages/applications_page.dart';
import 'pages/assignments_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/issues_page.dart';
import 'pages/tracking_page.dart';
import 'pages/zones_page.dart';
import 'pages/list_page.dart';
import 'pages/settings_page.dart';
import '../../features/home/pickup_schedule_screen.dart';
import 'theme.dart';
import 'widgets/sheets.dart';
import 'widgets/toast.dart';

const List<String> _tabPages = [
  'dashboard',
  'clients',
  'collectes',
  'contrats',
];
const Set<String> _searchablePages = {
  'applications',
  'clients',
  'collecteurs',
  'contrats',
  'collectes',
  'facturation',
  'vehicles',
};

/// Backoffice de l'agence (Agency Manager) — web-first.
///
/// Sur desktop (≥ 900px) : sidebar fixe + topbar + zone de contenu, comme la
/// console entreprise — l'interface de gestion se travaille au bureau. Sur
/// mobile, le layout d'origine (`backoffice-mobile.html`) est conservé :
/// topbar, FAB, tab bar en bas et menu latéral en drawer.
class BackofficeScreen extends StatefulWidget {
  const BackofficeScreen({super.key, this.store, this.agenceId = '', this.societeId = ''});

  /// Injectable store (used by tests); a Firestore-backed store is created
  /// otherwise.
  final BackofficeStore? store;

  /// Id de l'agence du chef connecté (Phase 3 : scoping).
  final String agenceId;

  /// Id de l'entreprise (facultatif).
  final String societeId;

  @override
  State<BackofficeScreen> createState() => _BackofficeScreenState();
}

class _BackofficeScreenState extends State<BackofficeScreen> {
  late BackofficeStore _store;

  /// Vrai quand l'écran a lui-même créé le store : seul ce cas dispose.
  /// Un store injecté (tests) appartient à son créateur.
  late bool _ownsStore;
  final _searchCtrl = TextEditingController();
  String _page = 'dashboard';
  bool _menuOpen = false;
  bool _searchOpen = false;
  String _search = '';
  bool _toastInit = false;

  static const _titles = <String, String>{
    'dashboard': 'Overview',
    'applications': 'Applications',
    'clients': 'Clients',
    'collecteurs': 'Collectors',
    'contrats': 'Contracts',
    'collectes': 'Collections',
    'schedule': 'Weekly Schedule',
    'issues': 'Issues',
    'zones': 'Zones',
    'assignments': 'Assignments',
    'vehicles': 'Vehicles',
    'facturation': 'Billing',
    'tracking': 'Live Tracking',
    'parametres': 'Settings',
  };

  /// Entrées de la sidebar desktop : (page, icône, label).
  static const List<(String, IconData, String)> _desktopNav = [
    ('dashboard', Icons.home_rounded, 'Overview'),
    ('applications', Icons.how_to_reg_rounded, 'Applications'),
    ('clients', Icons.people_outline_rounded, 'Clients'),
    ('collecteurs', Icons.person_search_rounded, 'Collectors'),
    ('contrats', Icons.description_outlined, 'Contracts'),
    ('collectes', Icons.event_note_rounded, 'Collections'),
    ('schedule', Icons.calendar_month_outlined, 'Schedule'),
    ('issues', Icons.report_outlined, 'Issues'),
    ('zones', Icons.map_outlined, 'Zones'),
    ('assignments', Icons.assignment_ind_outlined, 'Assignments'),
    ('vehicles', Icons.local_shipping_outlined, 'Vehicles'),
    ('facturation', Icons.payments_outlined, 'Billing'),
    ('tracking', Icons.map_outlined, 'Tracking'),
    ('parametres', Icons.settings_outlined, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    // The Firestore store starts loading in its constructor; load() also
    // re-arms the listeners here (same pattern as the super admin console).
    _ownsStore = widget.store == null;
    _store = widget.store ?? FirestoreBackofficeStore(
      agenceId: widget.agenceId,
      societeId: widget.societeId,
    );
    _store.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_toastInit) {
      _toastInit = true;
      BoToastService.init(context);
    }
  }

  @override
  void dispose() {
    // Only dispose the store we created ourselves; an injected store is
    // owned by its creator (e.g. tests).
    if (_ownsStore) _store.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // --- navigation ---

  void _goTo(String page) {
    setState(() {
      _page = page;
      _menuOpen = false;
      _searchOpen = false;
      _search = '';
      _searchCtrl.clear();
    });
  }

  String get _subtitle {
    switch (_page) {
      case 'applications':
        return '${_store.pendingRegistrations.length} pending';
      case 'clients':
        return '${_store.clients.length} registered';
      case 'collecteurs':
        return '${_store.collecteurs.length} agents';
      case 'contrats':
        return '${_store.contrats.length} total';
      case 'schedule':
        return 'Weekly pickup calendar';
      case 'issues':
        return '${_store.issues.length} reported';
      case 'zones':
        return '${_store.zones.length} zones';
      case 'assignments':
        return '${_store.assignments.length} active';
      case 'vehicles':
        return '${_store.vehicles.length} registered';
      case 'facturation':
        return '${_store.factures.length} invoices';
      case 'tracking':
        return 'Real-time positions';
      case 'parametres':
        return 'Company settings';
      default:
        return 'Today';
    }
  }

  BoEntity? get _fabEntity => switch (_page) {
    'clients' => BoEntity.client,
    'collecteurs' => BoEntity.collecteur,
    'contrats' => BoEntity.contrat,
    'collectes' => BoEntity.collecte,
    'vehicles' => BoEntity.vehicle,
    'facturation' => BoEntity.facture,
    _ => null,
  };

  String get _newLabel => switch (_fabEntity) {
    BoEntity.client => 'New client',
    BoEntity.collecteur => 'New collector',
    BoEntity.contrat => 'New contract',
    BoEntity.collecte => 'New collection',
    BoEntity.vehicle => 'New vehicle',
    BoEntity.facture => 'New invoice',
    _ => 'New',
  };

  void _openCreate() {
    final type = _fabEntity;
    if (type == null) return;
    showBoFormSheet(context, store: _store, type: type);
  }

  // --- build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BackofficeTheme.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          return desktop ? _buildDesktop() : _buildMobile();
        },
      ),
    );
  }

  /// Layout mobile (porté 1:1 de `backoffice-mobile.html`) : topbar, FAB,
  /// tab bar en bas et menu latéral en drawer.
  Widget _buildMobile() {
    return Stack(
      children: [
        Column(
          children: [
            _topbar(),
            _searchRow(),
            _statusBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(_page),
                  child: _pageContent(desktop: false),
                ),
              ),
            ),
          ],
        ),
        // FAB
        if (_fabEntity != null)
          Positioned(right: 18, bottom: 100, child: _fab()),
        // Tab bar
        Positioned(left: 0, right: 0, bottom: 0, child: _tabbar()),
        // Side menu overlay + panel
        _menuOverlay(),
        _sideMenu(),
      ],
    );
  }

  // --- Layout desktop (web-first) ---

  Widget _buildDesktop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDesktopSidebar(),
        Expanded(child: _buildDesktopMain()),
      ],
    );
  }

  Widget _buildDesktopSidebar() {
    return Material(
      color: BackofficeTheme.green,
      child: SizedBox(
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
              child: Row(
                children: [
                  const WasteProLogo(size: 30, radius: 8),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Waste',
                        style: BackofficeTheme.sora(
                          15,
                          weight: FontWeight.w700,
                          color: BackofficeTheme.cream,
                        ),
                        children: [
                          TextSpan(
                            text: 'Pro',
                            style: BackofficeTheme.sora(
                              15,
                              weight: FontWeight.w700,
                              color: BackofficeTheme.gold,
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
            // Tag plateforme
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: BackofficeTheme.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        size: 10,
                        color: BackofficeTheme.gold,
                      ),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'AGENCY BACKOFFICE',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: BackofficeTheme.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Navigation
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListenableBuilder(
                  listenable: _store,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in _desktopNav)
                        _desktopNavItem(
                          entry.$1,
                          entry.$2,
                          entry.$3,
                          badge: entry.$1 == 'applications'
                              ? _pendingBadge
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Footer
            _desktopSidebarFooter(),
          ],
        ),
      ),
    );
  }

  /// Badge « N à revoir » des candidatures en attente (null si rien).
  String? get _pendingBadge {
    final n = _store.pendingRegistrations.length;
    return n > 0 ? '$n' : null;
  }

  Widget _desktopNavItem(
    String page,
    IconData icon,
    String label, {
    String? badge,
  }) {
    final active = _page == page;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: () => _goTo(page),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active
                ? BackofficeTheme.gold.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: active
                ? Border.all(
                    color: BackofficeTheme.gold.withValues(alpha: 0.32),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: active
                    ? BackofficeTheme.gold
                    : const Color(0xBFE9F2ED),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    13,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active
                        ? BackofficeTheme.gold
                        : const Color(0xBFE9F2ED),
                  ),
                ),
              ),
              _navBadge(badge),
            ],
          ),
        ),
      ),
    );
  }

  /// Badge de navigation nullable : `SizedBox.shrink` quand il n'y a rien à
  /// afficher (évite les problèmes de promotion de type dans les collections).
  static Widget _navBadge(String? text) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: BackofficeTheme.gold,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: BackofficeTheme.inter(
            9.5,
            weight: FontWeight.w700,
            color: const Color(0xFF073A1B),
          ),
        ),
      ),
    );
  }

  Widget _desktopSidebarFooter() {
    // UserProvider lives above the backoffice in main.dart; in standalone
    // widget tests it may be absent, so we read it defensively.
    UserProvider? userProvider;
    try {
      userProvider = Provider.of<UserProvider>(context, listen: false);
    } catch (_) {
      userProvider = null;
    }
    final user = userProvider?.user;
    final label = user != null ? user.fullName : 'Agency Manager';
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 18),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x1FE9F2ED))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BackofficeTheme.inter(
                      12,
                      weight: FontWeight.w600,
                      color: BackofficeTheme.cream,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Nom de l'agence quand il est chargé (store scopé) —
                  // sinon le rôle.
                  Text(
                    _store.agenceName.isEmpty
                        ? 'Agency Manager'
                        : _store.agenceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BackofficeTheme.inter(
                      10.5,
                      color: const Color(0x80E9F2ED),
                    ),
                  ),
                ],
              ),
            ),
            if (user != null)
              IconButton(
                key: const Key('bo_bo_logout'),
                tooltip: 'Log out',
                onPressed: () =>
                    Provider.of<UserProvider>(context, listen: false).logout(),
                icon: const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: Color(0x80E9F2ED),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopMain() {
    return Column(
      children: [
        _buildDesktopTopbar(),
        _searchRow(),
        _statusBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_page),
                child: _pageContent(desktop: true),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopTopbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
      decoration: const BoxDecoration(
        color: BackofficeTheme.surface,
        border: Border(bottom: BorderSide(color: BackofficeTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titles[_page]!,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.sora(19, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    12,
                    color: BackofficeTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          if (_fabEntity != null) ...[
            // Action de création web-first (remplace le FAB du mobile).
            Material(
              color: BackofficeTheme.green,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _openCreate,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: BackofficeTheme.cream,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _newLabel,
                        style: BackofficeTheme.inter(
                          12.5,
                          weight: FontWeight.w600,
                          color: BackofficeTheme.cream,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (_searchablePages.contains(_page)) ...[
            _desktopIconButton(
              key: const Key('bo_bo_search_toggle'),
              icon: Icons.search_rounded,
              onTap: () => setState(() => _searchOpen = !_searchOpen),
            ),
            const SizedBox(width: 10),
          ],
          _desktopIconButton(
            key: const Key('bo_bo_bell'),
            icon: Icons.notifications_none_rounded,
            dot: true,
            onTap: () => BoToastService.show('No new notifications'),
          ),
        ],
      ),
    );
  }

  /// Bouton icône de la topbar desktop (variante du bouton mobile, taille
  /// légèrement plus grande pour le web).
  Widget _desktopIconButton({
    required Key key,
    required IconData icon,
    required VoidCallback onTap,
    bool dot = false,
  }) {
    return _iconButton(
      key: key,
      icon: icon,
      onTap: onTap,
      dot: dot,
      size: 38,
    );
  }

  // --- contenu (partagé desktop / mobile) ---

  Widget _pageContent({bool desktop = false}) {
    switch (_page) {
      case 'applications':
        return BoApplicationsPage(
          store: _store,
          desktop: desktop,
          search: _search,
        );
      case 'clients':
        return BoListPage(
          store: _store,
          type: BoEntity.client,
          search: _search,
          desktop: desktop,
        );
      case 'collecteurs':
        return BoListPage(
          store: _store,
          type: BoEntity.collecteur,
          search: _search,
          desktop: desktop,
        );
      case 'contrats':
        return BoListPage(
          store: _store,
          type: BoEntity.contrat,
          search: _search,
          desktop: desktop,
        );
      case 'collectes':
        return BoListPage(
          store: _store,
          type: BoEntity.collecte,
          search: _search,
          desktop: desktop,
        );
      case 'schedule':
        return PickupScheduleScreen(store: _store);
      case 'issues':
        return BoIssuesPage(store: _store, desktop: desktop);
      case 'zones':
        return BoZonesPage(store: _store, desktop: desktop);
      case 'assignments':
        return BoAssignmentsPage(store: _store, desktop: desktop);
      case 'vehicles':
        return BoListPage(
          store: _store,
          type: BoEntity.vehicle,
          search: _search,
          desktop: desktop,
        );
      case 'facturation':
        return BoListPage(
          store: _store,
          type: BoEntity.facture,
          search: _search,
          desktop: desktop,
        );
      case 'tracking':
        return BoTrackingPage(store: _store, agenceId: widget.agenceId);
      case 'parametres':
        return BoSettingsPage(
          store: _store,
          desktop: desktop,
          agenceId: widget.agenceId,
          societeId: widget.societeId,
        );
      default:
        return BoDashboardPage(store: _store, desktop: desktop);
    }
  }

  // --- topbar ---

  Widget _topbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        children: [
          _iconButton(
            key: const Key('bo_menu'),
            icon: Icons.menu_rounded,
            onTap: () => setState(() => _menuOpen = true),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ListenableBuilder(
              listenable: _store,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titles[_page]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BackofficeTheme.sora(17, weight: FontWeight.w700),
                  ),
                  Text(
                    _subtitle,
                    style: BackofficeTheme.inter(
                      11,
                      color: BackofficeTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_searchablePages.contains(_page)) ...[
            _iconButton(
              key: const Key('bo_search_toggle'),
              icon: Icons.search_rounded,
              onTap: () => setState(() => _searchOpen = !_searchOpen),
            ),
            const SizedBox(width: 8),
          ],
          _iconButton(
            key: const Key('bo_bell'),
            icon: Icons.notifications_none_rounded,
            dot: true,
            onTap: () => BoToastService.show('No new notifications'),
          ),
        ],
      ),
    );
  }

  Widget _iconButton({
    required Key key,
    required IconData icon,
    required VoidCallback onTap,
    bool dot = false,
    double size = 36,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: BackofficeTheme.surface,
          border: Border.all(color: BackofficeTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: size * 0.47, color: BackofficeTheme.green),
            if (dot)
              Positioned(
                top: size * 0.19,
                right: size * 0.22,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: BackofficeTheme.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- load status / error banner ---

  Widget _statusBar() {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        if (_store.isLoading) {
          return const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: BackofficeTheme.gold,
          );
        }
        if (_store.error != null) {
          return Container(
            width: double.infinity,
            color: BackofficeTheme.redSoft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 15,
                  color: BackofficeTheme.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _store.error!,
                    style: BackofficeTheme.inter(
                      11.5,
                      color: BackofficeTheme.red,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _store.load,
                  style: TextButton.styleFrom(
                    foregroundColor: BackofficeTheme.red,
                    textStyle: BackofficeTheme.inter(
                      11.5,
                      weight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  // --- search row ---

  Widget _searchRow() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: _searchOpen
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: BackofficeTheme.surface,
                  border: Border.all(color: BackofficeTheme.border),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: BackofficeTheme.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('bo_search'),
                        controller: _searchCtrl,
                        autofocus: true,
                        style: BackofficeTheme.inter(13),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Search...',
                          hintStyle: TextStyle(
                            color: BackofficeTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                        onChanged: (v) =>
                            setState(() => _search = v.trim().toLowerCase()),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  // --- FAB ---

  Widget _fab() {
    return FloatingActionButton(
      key: const Key('bo_fab'),
      onPressed: _openCreate,
      elevation: 6,
      backgroundColor: BackofficeTheme.gold,
      shape: const CircleBorder(),
      child: const Icon(Icons.add_rounded, size: 24, color: Color(0xFF073A1B)),
    );
  }

  // --- tab bar ---

  Widget _tabbar() {
    final moreActive = !_tabPages.contains(_page);
    return Container(
      decoration: BoxDecoration(
        color: BackofficeTheme.surface.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: BackofficeTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: Row(
            children: [
              _tabItem('dashboard', Icons.home_rounded, 'Home'),
              _tabItem('clients', Icons.people_outline_rounded, 'Clients'),
              _tabItem('collectes', Icons.event_note_rounded, 'Collections'),
              _tabItem('contrats', Icons.description_outlined, 'Contracts'),
              _tabItem(
                'more',
                Icons.more_horiz_rounded,
                'More',
                forceActive: moreActive,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabItem(
    String page,
    IconData icon,
    String label, {
    bool forceActive = false,
  }) {
    final active = forceActive || _page == page;
    return Expanded(
      child: InkWell(
        key: Key('bo_tab_$page'),
        onTap: () {
          if (page == 'more') {
            setState(() => _menuOpen = true);
          } else {
            _goTo(page);
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 19,
                color: active ? BackofficeTheme.green : BackofficeTheme.muted,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: BackofficeTheme.inter(
                  9,
                  weight: FontWeight.w600,
                  color: active ? BackofficeTheme.green : BackofficeTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- side menu ---

  Widget _menuOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_menuOpen,
        child: AnimatedOpacity(
          opacity: _menuOpen ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: GestureDetector(
            onTap: () => setState(() => _menuOpen = false),
            child: const ColoredBox(color: Color(0x66073A1B)),
          ),
        ),
      ),
    );
  }

  Widget _sideMenu() {
    final width = math.min(MediaQuery.of(context).size.width * 0.78, 300.0);
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: width,
      child: AnimatedSlide(
        offset: _menuOpen ? Offset.zero : const Offset(-1, 0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: Container(
          color: BackofficeTheme.green,
          child: SafeArea(
            right: false,
            child: ListenableBuilder(
              listenable: _store,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 22),
                    child: Row(
                      children: [
                        WasteProLogo(size: 32, radius: 8),
                        SizedBox(width: 9),
                        Text.rich(
                          TextSpan(
                            text: 'Waste',
                            style: TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: BackofficeTheme.cream,
                            ),
                            children: [
                              TextSpan(
                                text: 'Pro',
                                style: TextStyle(
                                  fontFamily: 'Sora',
                                  fontWeight: FontWeight.w700,
                                  color: BackofficeTheme.gold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _menuItem('dashboard', Icons.home_rounded, 'Overview'),
                  _menuItem(
                    'applications',
                    Icons.how_to_reg_rounded,
                    'Applications',
                    badge: _pendingBadge,
                  ),
                  _menuItem('clients', Icons.people_outline_rounded, 'Clients'),
                  _menuItem(
                    'collecteurs',
                    Icons.person_search_rounded,
                    'Collectors',
                  ),
                  _menuItem(
                    'contrats',
                    Icons.description_outlined,
                    'Contracts',
                  ),
                  _menuItem(
                    'collectes',
                    Icons.event_note_rounded,
                    'Collections',
                  ),
                  _menuItem(
                    'schedule',
                    Icons.calendar_month_outlined,
                    'Schedule',
                  ),
                  _menuItem(
                    'issues',
                    Icons.report_outlined,
                    'Issues',
                  ),
                  _menuItem(
                    'zones',
                    Icons.map_outlined,
                    'Zones',
                  ),
                  _menuItem(
                    'assignments',
                    Icons.assignment_ind_outlined,
                    'Assignments',
                  ),
                  _menuItem(
                    'vehicles',
                    Icons.local_shipping_outlined,
                    'Vehicles',
                  ),
                  _menuItem(
                    'facturation',
                    Icons.payments_outlined,
                    'Billing',
                  ),
                  _menuItem(
                    'tracking',
                    Icons.map_outlined,
                    'Live Tracking',
                  ),
                  _menuItem('parametres', Icons.settings_outlined, 'Settings'),
                  const Spacer(),
                  _menuFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(
    String page,
    IconData icon,
    String label, {
    String? badge,
  }) {
    final active = _page == page;
    return InkWell(
      key: Key('bo_menu_$page'),
      onTap: () => _goTo(page),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: active
            ? BackofficeTheme.gold.withValues(alpha: 0.1)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: active ? BackofficeTheme.gold : const Color(0xBFE9F2ED),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: BackofficeTheme.inter(
                  13.5,
                  weight: FontWeight.w500,
                  color:
                      active ? BackofficeTheme.gold : const Color(0xBFE9F2ED),
                ),
              ),
            ),
            _navBadge(badge),
          ],
        ),
      ),
    );
  }

  Widget _menuFooter() {
    // UserProvider lives above the backoffice in main.dart; in standalone
    // widget tests it may be absent, so we read it defensively.
    UserProvider? userProvider;
    try {
      userProvider = Provider.of<UserProvider>(context, listen: false);
    } catch (_) {
      userProvider = null;
    }
    final user = userProvider?.user;
    final label = user != null ? user.fullName : 'Admin';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1FE9F2ED))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    12,
                    weight: FontWeight.w600,
                    color: BackofficeTheme.cream,
                  ),
                ),
                const SizedBox(height: 2),
                // Nom de l'agence quand il est chargé (store scopé) —
                // sinon le rôle.
                Text(
                  _store.agenceName.isEmpty ? 'Admin' : _store.agenceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    10.5,
                    color: const Color(0x80E9F2ED),
                  ),
                ),
              ],
            ),
          ),
          if (user != null)
            IconButton(
              key: const Key('bo_logout'),
              tooltip: 'Log out',
              onPressed: () =>
                  Provider.of<UserProvider>(context, listen: false).logout(),
              icon: const Icon(
                Icons.logout_rounded,
                size: 18,
                color: Color(0x80E9F2ED),
              ),
            ),
        ],
      ),
    );
  }
}
