import 'dart:async';
import 'dart:convert';
import 'dart:io' as io show File;
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/navigation_service.dart';
import '../../services/offline_sync_service.dart';
import '../../services/live_tracking_service.dart';
import '../../services/tournee_service.dart';
import '../../services/notification_service.dart';
import '../backoffice/theme.dart';
import 'collector_issues_screen.dart';
import 'notifications_screen.dart';

/// Collector mobile app — ported 1:1 from the `collecteur-mobile.html`
/// design (Propre237 — Collector), reusing the [BackofficeTheme] palette.
///
/// On wide screens (web) the app displays inside the phone frame from the
/// design (centered on shell background #DEDBD1); on mobile it fills the
/// screen. The screen has three tabs:
///  - **Route**: today's route, filterable (To Do / Done / Missed), with
///    client detail, live route map (pausable) and the simplified pickup
///    flow (proof photo → Done → client QR validation).
///  - **History**: past collections by day.
///  - **Profile**: collector stats + contact info + logout.
class CollectorDashboard extends StatefulWidget {
  const CollectorDashboard({super.key, this.db});

  /// Optional Firestore instance for dependency injection in tests.
  final FirebaseFirestore? db;

  @override
  State<CollectorDashboard> createState() => _CollectorDashboardState();
}

/// A history entry.
class _HistoryEntry {
  _HistoryEntry({
    required this.name,
    required this.heure,
    required this.poids,
    required this.status,
  });

  final String name;
  final String heure; // '—' when not visited
  final double poids;
  final String status; // 'Completed' | 'Missed'
}

/// A day of history.
class _HistoryDay {
  _HistoryDay({required this.date, required this.entries});

  final DateTime date;
  final List<_HistoryEntry> entries;
}

/// A toast displayed at the top of the screen.
class _ToastMsg {
  _ToastMsg(this.message, {this.error = false});
  final String message;
  final bool error;
}

// ====================================================================
// State
// ====================================================================

class _CollectorDashboardState extends State<CollectorDashboard>
    with WidgetsBindingObserver {
  // --- Tour data (loaded from Firestore) ---
  late List<TourneeStop> _tournee;
  List<_HistoryDay> _historique = [];
  bool _tourLoading = true;
  String? _collectorId;
  String _collectorName = '';
  late final TourneeService _tourneeService;
  final OfflineSyncService _offlineService = OfflineSyncService.instance;
  final LiveTrackingService _trackingService = LiveTrackingService();
  late final NotificationService _notificationService;
  bool _isOnline = true;
  int _pendingSyncCount = 0;
  bool _locationPermissionDenied = false;
  StreamSubscription<bool>? _onlineSub;
  StreamSubscription<int>? _pendingSub;

  // --- Live client-validation feedback ---
  // Watches today's pickups so that when a client scans the QR code and
  // validates, the stop flips to Done (tick) and the collector sees
  // “Pickup validated from client …” immediately.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _validationsSub;
  final Set<String> _validatedPickupIds = <String>{};

  // --- Navigation ---
  int _tab = 0; // 0 Route · 1 History · 2 Profile
  String _filter = 'all'; // 'all' | 'To Do' | 'Done' | 'Missed'

  // --- Client sheet ---
  String? _sheetId;
  bool _sheetOpen = false;
  String _flow = 'detail'; // 'detail' | 'miss' | 'photo'

  // --- Collection flow ---
  XFile? _photoFile; // proof-of-visit photo captured by the camera
  bool _capturingPhoto = false;
  String? _missSelected;

  // --- Toasts ---
  final List<_ToastMsg> _toasts = [];
  final List<Timer> _toastTimers = [];

  static const List<(String, IconData)> _missReasons = [
    ('Client absent', Icons.person_off_outlined),
    ('Bin damaged', Icons.delete_outline),
    ('Access blocked', Icons.lock_outline),
    ('Other', Icons.more_horiz),
  ];

  /// Firestore docs cap at ~1 MiB; keep the base64 photo well under it
  /// (~700 KB raw → ~950 KB base64).
  static const int _maxPhotoBytes = 700 * 1024;

  FirebaseFirestore get _db => widget.db ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tourneeService = TourneeService(db: widget.db);
    // Same db injection as the tour service: without it, notifications
    // would go to FirebaseFirestore.instance instead of the (test/injected)
    // db this screen was built with.
    _notificationService = NotificationService(db: widget.db);
    _tournee = [];
    _loadTourFromFirestore();
    _initOfflineListeners();
    _initLiveTracking();
  }

  void _initOfflineListeners() {
    _onlineSub = _offlineService.onlineStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _pendingSub = _offlineService.pendingCountStream.listen((count) {
      if (mounted) setState(() => _pendingSyncCount = count);
    });
    _isOnline = _offlineService.isOnline;
    _pendingSyncCount = _offlineService.pendingCount;
  }

  /// Start uploading GPS position to Firestore for real-time tracking.
  void _initLiveTracking() {
    // Use a post-frame callback to ensure the user provider is available.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Check location permission first.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationPermissionDenied = true);
        return;
      }
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) return;
      final collectorId = user.collecteurId.isNotEmpty
          ? user.collecteurId
          : user.phoneNumber;
      _trackingService.startTracking(
        collectorId: collectorId,
        collectorName: user.fullName,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _locationPermissionDenied) {
      _recheckLocationPermission();
    }
  }

  /// Re-check location permission when the user returns from app settings.
  Future<void> _recheckLocationPermission() async {
    if (!mounted) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      if (!mounted) return;
      setState(() => _locationPermissionDenied = false);
      // Start live tracking now that permission is granted.
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) return;
      final collectorId = user.collecteurId.isNotEmpty
          ? user.collecteurId
          : user.phoneNumber;
      _trackingService.startTracking(
        collectorId: collectorId,
        collectorName: user.fullName,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _toastTimers) {
      t.cancel();
    }
    _onlineSub?.cancel();
    _pendingSub?.cancel();
    _validationsSub?.cancel();
    _trackingService.dispose();
    super.dispose();
  }

  /// Loads today's tour from Firestore (clients assigned to this collector
  /// with active contracts and today as a collection day).
  Future<void> _loadTourFromFirestore() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) {
      setState(() => _tourLoading = false);
      return;
    }

    _collectorId = user.collecteurId.isNotEmpty
        ? user.collecteurId
        : user.phoneNumber;
    _collectorName = user.fullName;

    _watchPickupValidations();

    try {
      final stops = await _tourneeService.generateTodayTour(
        _collectorId!,
        agenceId: user.agenceId,
      );
      final historyData = await _tourneeService.fetchHistory(_collectorId!);

      if (!mounted) return;
      setState(() {
        _tournee = stops;
        _tourLoading = false;
        _historique = _buildHistoryFromPickups(historyData);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _tourLoading = false);
    }
  }

  /// Listens to this collector's pickups. When a pickup that is still
  /// awaiting client validation (stop In Progress / To Do) becomes
  /// `verified`, the client has scanned the QR code and validated it — mark
  /// the stop Done (tick) and show the in-app notification with the client's
  /// name.
  void _watchPickupValidations() {
    final collectorId = _collectorId;
    if (collectorId == null || collectorId.isEmpty) return;
    if (_validationsSub != null) return;
    final todayDate = DateTime.now().toString().split(' ').first;

    _validationsSub = _db
        .collection('pickups')
        .where('collector_id', isEqualTo: collectorId)
        .snapshots()
        .listen((snap) {
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['status'] != 'verified') continue;
        if (data['date'] != todayDate) continue;
        if (!_validatedPickupIds.add(doc.id)) continue;

        final clientPhone = data['client_id'] as String? ?? '';
        TourneeStop? stop;
        for (final t in _tournee) {
          if (t.clientPhone == clientPhone) {
            stop = t;
            break;
          }
        }
        // Stops already shown as Done (seeded before the dashboard opened)
        // are ignored: we only announce pickups that get validated while the
        // collector is looking at today's route.
        if (stop == null || stop.status == 'Done') continue;
        final s = stop;

        if (!mounted) return;
        setState(() {
          s.status = 'Done';
          s.poids = (data['poids'] as num?)?.toDouble() ?? s.poids;
          s.heureArrivee =
              data['heure_arrivee'] as String? ?? s.heureArrivee;
          s.heureDepart =
              data['heure_depart'] as String? ?? s.heureDepart;
          s.commentaire =
              data['commentaire'] as String? ?? s.commentaire;
        });
        _showToast('Pickup validated from client ${s.clientName} ');
      }
    }, onError: (e) {
      debugPrint('[CollectorDashboard] Pickup validation watch failed: $e');
    });
  }

  /// Converts raw pickup documents into grouped history days.
  List<_HistoryDay> _buildHistoryFromPickups(List<Map<String, dynamic>> pickups) {
    final map = <String, List<_HistoryEntry>>{};
    for (final p in pickups) {
      final date = p['date'] as String? ?? '';
      if (date.isEmpty) continue;
      final name = p['client_id'] as String? ?? '';
      final heure = p['heure_arrivee'] as String? ?? '—';
      final poids = (p['poids'] as num?)?.toDouble() ?? 0;
      final status = p['status'] as String? ?? 'completed';
      map.putIfAbsent(date, () => []).add(_HistoryEntry(
        name: name,
        heure: heure,
        poids: poids,
        status: status == 'completed' ? 'Completed' : 'Missed',
      ));
    }
    final days = map.entries.map((e) {
      final parts = e.key.split('-');
      final date = parts.length == 3
          ? DateTime(
              int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]))
          : DateTime.now();
      return _HistoryDay(date: date, entries: e.value);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return days;
  }

  TourneeStop? get _currentClient {
    if (_sheetId == null) return null;
    for (final t in _tournee) {
      if (t.clientId == _sheetId) return t;
    }
    return null;
  }

  int get _doneCount => _tournee.where((t) => t.status == 'Done').length;

  String _now() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  // ====================================================================
  // Build
  // ====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BackofficeTheme.shell,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 520;
          if (!wide) return _buildPhoneScreen(context);
          final frameHeight = math.min(844.0, constraints.maxHeight);
          return Center(
            child: Container(
              width: 390,
              height: frameHeight,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(46),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 40,
                    offset: Offset(0, 24),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: _buildPhoneScreen(context),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhoneScreen(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;
    final userName = user?.fullName.isNotEmpty == true
        ? user!.fullName
        : 'Paul Mbarga';
    return LayoutBuilder(
      builder: (context, c) {
        final sheetHeight = c.maxHeight * 0.88;
        return Stack(
          children: [
            Column(
              children: [
                _buildTopbar(context, userName),
                Expanded(child: _buildContent(context)),
              ],
            ),
            // Tab bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildTabBar(),
            ),
            // Scrim
            if (_sheetOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeSheet,
                  child: AnimatedOpacity(
                    opacity: _sheetOpen ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const ColoredBox(color: Color(0x66073A1B)),
                  ),
                ),
              ),
            // Client sheet
            AnimatedPositioned(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: _sheetOpen ? 0 : -sheetHeight,
              height: sheetHeight,
              child: _buildSheet(context),
            ),
            // Toasts
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  for (final t in _toasts) _ToastView(toast: t),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Topbar
  // ------------------------------------------------------------------

  Widget _buildTopbar(BuildContext context, String userName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: const BoxDecoration(
        color: BackofficeTheme.green,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(initials: boInitials(userName), size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BackofficeTheme.sora(
                          15,
                          weight: FontWeight.w700,
                          color: BackofficeTheme.cream,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Bastos / Nlongkak Zone',
                        style: BackofficeTheme.inter(
                          10.5,
                          color: BackofficeTheme.cream.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _isOnline
                            ? BackofficeTheme.cream.withValues(alpha: 0.08)
                            : BackofficeTheme.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isOnline
                              ? BackofficeTheme.cream.withValues(alpha: 0.12)
                              : BackofficeTheme.red.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isOnline ? Icons.cloud_done : Icons.cloud_off,
                            size: 12,
                            color: _isOnline
                                ? const Color(0xFFA8D88A)
                                : BackofficeTheme.red,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _isOnline
                                ? (_pendingSyncCount > 0
                                    ? 'Syncing ($_pendingSyncCount)'
                                    : 'Synced')
                                : 'Offline',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _isOnline
                                  ? const Color(0xFFA8D88A)
                                  : BackofficeTheme.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _IconBtn(
                      icon: Icons.notifications_none,
                      // Ouvre l'écran Notifications (même écran que le
                      // client), filtré sur le numéro du collecteur.
                      onTap: () {
                        final user =
                            Provider.of<UserProvider>(context, listen: false)
                                .user;
                        if (user == null) {
                          _showToast('New notification');
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotificationsScreen(
                              db: widget.db,
                              phone: user.phoneNumber,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ProgressCard(done: _doneCount, total: _tournee.length),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Content (3 pages)
  // ------------------------------------------------------------------

  Widget _buildContent(BuildContext context) {
    if (_tab == 0) return _buildTourneePage();
    if (_tab == 1) return _buildHistoriquePage();
    return _buildProfilPage(context);
  }

  Widget _buildTourneePage() {
    if (_tourLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: BackofficeTheme.green),
              SizedBox(height: 12),
              Text('Loading today\'s route...', style: TextStyle(color: BackofficeTheme.muted)),
            ],
          ),
        ),
      );
    }
    final rows = _filter == 'all'
        ? _tournee
        : _tournee.where((t) => t.status == _filter).toList();
    final phone =
        Provider.of<UserProvider>(context, listen: false).user?.phoneNumber ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Issues the agency manager assigned to this collector.
          if (phone.isNotEmpty)
            CollectorIssuesBanner(
              db: _db,
              collectorPhone: phone,
              notifications: _notificationService,
            ),
          // Location permission banner
          if (_locationPermissionDenied) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BackofficeTheme.redSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BackofficeTheme.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_off_outlined, color: BackofficeTheme.red, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Location access denied',
                          style: BackofficeTheme.sora(12.5, weight: FontWeight.w600, color: BackofficeTheme.red),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Enable location in settings to track your route',
                          style: BackofficeTheme.inter(10.5, color: BackofficeTheme.muted),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      await Geolocator.openAppSettings();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: BackofficeTheme.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Settings',
                        style: BackofficeTheme.inter(11, weight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _buildFilterChips(),
          const SizedBox(height: 14),
          // View full route on map
          if (_tournee.isNotEmpty) ...[
            GestureDetector(
              onTap: _openItineraryMap,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BackofficeTheme.green,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.map_outlined, color: BackofficeTheme.cream, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'View Route on Map',
                            style: BackofficeTheme.sora(13, weight: FontWeight.w600, color: BackofficeTheme.cream),
                          ),
                          Text(
                            '${_tournee.length} stops · $_doneCount completed',
                            style: BackofficeTheme.inter(10.5, color: BackofficeTheme.cream.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: BackofficeTheme.cream, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (rows.isEmpty)
            _tournee.isEmpty
                ? const _EmptyState(text: 'No collections scheduled today')
                : const _EmptyState(text: 'No clients in this filter')
          else
            for (final t in rows) ...[
              _ClientCard(client: t, onTap: () => _openClient(t.clientId), index: rows.indexOf(t)),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    const chips = [
      ('all', 'All'),
      ('To Do', 'To Do'),
      ('Done', 'Done'),
      ('Missed', 'Missed'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label) in chips) ...[
            _FilterChip(
              label: label,
              active: _filter == value,
              onTap: () => setState(() => _filter = value),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoriquePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final day in _historique) ...[
            Text(
              _dayLabel(day.date),
              style: BackofficeTheme.inter(
                11,
                weight: FontWeight.w700,
                color: BackofficeTheme.muted,
              ),
            ),
            const SizedBox(height: 8),
            for (final e in day.entries) ...[
              _HistoryCard(entry: e),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildProfilPage(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;
    final userName =
        user?.fullName.isNotEmpty == true ? user!.fullName : 'Paul Mbarga';
    final phone = user?.phoneNumber.isNotEmpty == true
        ? user!.phoneNumber
        : '+237 678 90 11 22';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BackofficeTheme.card(),
            child: Column(
              children: [
                _Avatar(initials: boInitials(userName), size: 64),
                const SizedBox(height: 10),
                Text(
                  userName,
                  style: BackofficeTheme.sora(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Collector · Bastos / Nlongkak Zone',
                  style: BackofficeTheme.inter(
                    11.5,
                    color: BackofficeTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(
                child: _StatBox(value: '312', label: 'Total Collections'),
              ),
              SizedBox(width: 10),
              Expanded(child: _StatBox(value: '4.8', label: 'Avg. Rating')),
              SizedBox(width: 10),
              Expanded(child: _StatBox(value: '96%', label: 'Success Rate')),
            ],
          ),
          const SizedBox(height: 14),
          _ProfileRow(icon: Icons.phone_outlined, text: phone),
          const _ProfileRow(
            icon: Icons.local_shipping_outlined,
            text: 'Tricycle — MB-2024-CM',
          ),
          const _ProfileRow(
            icon: Icons.business_outlined,
            text: 'Propre237 Yaoundé SARL — Bastos Branch',
          ),
          const _ProfileRow(
            icon: Icons.info_outline,
            text: 'App version 1.0.0',
          ),
          const SizedBox(height: 6),
          Material(
            color: BackofficeTheme.redSoft,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () async {
                // Mark the collector as no longer tracking before the
                // session ends, so the client map shows the truck offline.
                try {
                  if (_collectorId?.isNotEmpty == true) {
                    await _trackingService
                        .stopTrackingFirestore(_collectorId!);
                  }
                } catch (_) {}
                await userProvider.logout();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.logout,
                      size: 15,
                      color: BackofficeTheme.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Log Out',
                      style: BackofficeTheme.inter(
                        12.5,
                        weight: FontWeight.w700,
                        color: BackofficeTheme.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Tab bar
  // ------------------------------------------------------------------

  Widget _buildTabBar() {
    const tabs = [
      (0, Icons.checklist, 'Route'),
      (1, Icons.history, 'History'),
      (2, Icons.person_outline, 'Profile'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF0FFFFFF),
        border: Border(top: BorderSide(color: BackofficeTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
        children: [
          for (final (index, icon, label) in tabs)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = index),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 17,
                      color: _tab == index
                          ? BackofficeTheme.green
                          : BackofficeTheme.muted,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: BackofficeTheme.inter(
                        9.5,
                        weight: FontWeight.w600,
                        color: _tab == index
                            ? BackofficeTheme.green
                            : BackofficeTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Client sheet
  // ------------------------------------------------------------------

  void _openClient(String clientId) {
    setState(() {
      _sheetId = clientId;
      _sheetOpen = true;
      _flow = 'detail';
    });
  }

  void _closeSheet() {
    setState(() => _sheetOpen = false);
  }

  Widget _buildSheet(BuildContext context) {
    final client = _currentClient;
    return Material(
      color: BackofficeTheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: BackofficeTheme.border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              child: client == null
                  ? const SizedBox.shrink()
                  : switch (_flow) {
                      'detail' => _buildDetail(client),
                      'miss' => _buildMissFlow(),
                      _ => _buildPhotoStep(client),
                    },
            ),
          ),
        ],
      ),
    );
  }

  // ---- Client detail ----

  Widget _buildDetail(TourneeStop client) {
    if (client.status == 'Done') return _buildDone(client);
    if (client.status == 'Missed') return _buildMissed(client);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClientHeader(client: client, showTime: true),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.phone_outlined,
                label: 'Call',
                onTap: () => _showToast('Opening call...'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionTile(
                icon: Icons.map_outlined,
                label: 'Start Route',
                onTap: () => _openRouteMap(client),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionTile(
                icon: Icons.flag_outlined,
                label: 'Report',
                onTap: () => setState(() => _flow = 'miss'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: BackofficeTheme.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _InfoRow(label: 'Plan', value: client.plan),
              _InfoRow(label: 'Phone', value: client.clientPhone),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Pickup already recorded (pending client validation): the collector
        // can capture/redo the proof photo and tap Done again to re-notify.
        _PrimaryBtn(
          icon: Icons.check_circle_outline,
          label: 'Done',
          onTap: () => _startPhotoStep(client),
        ),
      ],
    );
  }

  Widget _buildDone(TourneeStop client) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClientHeader(client: client),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BackofficeTheme.greenSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle,
                size: 26,
                color: BackofficeTheme.success,
              ),
              const SizedBox(height: 8),
              Text(
                'Collection Completed',
                style: BackofficeTheme.sora(14, weight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Recorded successfully',
                style: BackofficeTheme.inter(
                  11.5,
                  color: BackofficeTheme.muted,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DoneCell(
                      label: 'Arrival',
                      value: client.heureArrivee.isEmpty
                          ? '—'
                          : client.heureArrivee,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DoneCell(
                      label: 'Departure',
                      value: client.heureDepart.isEmpty
                          ? '—'
                          : client.heureDepart,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DoneCell(
                      label: 'Weight',
                      value: client.poids > 0 ? '${client.poids} kg' : '—',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DoneCell(
                      label: 'Comment',
                      value: client.commentaire.isEmpty
                          ? 'None'
                          : client.commentaire,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMissed(TourneeStop client) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClientHeader(client: client),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BackofficeTheme.redSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 26,
                color: BackofficeTheme.red,
              ),
              const SizedBox(height: 8),
              Text(
                'Collection Missed',
                style: BackofficeTheme.sora(14, weight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Reason: ${client.missReason ?? 'Not specified'}',
                style: BackofficeTheme.inter(
                  11.5,
                  color: BackofficeTheme.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PrimaryBtn(
          icon: Icons.refresh,
          label: 'Retry Now',
          onTap: () => setState(() {
            client.status = 'To Do';
            client.missReason = null;
            _flow = 'detail';
          }),
        ),
      ],
    );
  }

  // ---- "Missed" flow ----

  Widget _buildMissFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Report a Problem',
          textAlign: TextAlign.center,
          style: BackofficeTheme.sora(14.5, weight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Why can\'t this collection be made?',
          textAlign: TextAlign.center,
          style: BackofficeTheme.inter(11.5, color: BackofficeTheme.muted),
        ),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            for (final (label, icon) in _missReasons)
              _ReasonChip(
                label: label,
                icon: icon,
                selected: _missSelected == label,
                onTap: () => setState(() => _missSelected = label),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _BackBtn(
              onTap: () {
                setState(() => _flow = 'detail');
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NextBtn(
                label: 'Confirm',
                enabled: _missSelected != null,
                onTap: _confirmMiss,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmMiss() {
    final client = _currentClient;
    if (client == null || _missSelected == null) return;
    final reason = _missSelected!;
    setState(() {
      client.status = 'Missed';
      client.missReason = reason;
      _sheetOpen = false;
      _flow = 'detail';
      _missSelected = null;
    });
    // Persist to Firestore (fire-and-forget).
    _tourneeService.recordMissed(
      collectorId: _collectorId ?? '',
      collectorName: _collectorName,
      stop: client,
      reason: reason,
    ).catchError((e) {
      debugPrint('[CollectorDashboard] Failed to record miss: $e');
    });
    _showToast('Collection marked as missed.', error: true);
  }

  // ---- Pickup flow (proof photo → Done) ----

  /// Opens the proof-photo step reached from the “Done” button. The pickup
  /// itself is recorded when the collector taps the step's Done button.
  void _startPhotoStep(TourneeStop client) {
    setState(() {
      if (client.status == 'To Do') client.status = 'In Progress';
      _flow = 'photo';
      _photoFile = null;
    });
  }
  /// Final confirmation step: proof photo of the collected deposit, then
  /// “Done” records the pickup (no weight entry — the weight stays 0) and
  /// asks the client to validate it via their QR code.
  Widget _buildPhotoStep(TourneeStop client) {
    final hasPhoto = _photoFile != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Take a Photo',
          textAlign: TextAlign.center,
          style: BackofficeTheme.sora(14.5, weight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Photo of the deposit as proof of visit',
          textAlign: TextAlign.center,
          style: BackofficeTheme.inter(11.5, color: BackofficeTheme.muted),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _capturingPhoto ? null : _capturePhoto,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: hasPhoto ? BackofficeTheme.greenSoft : BackofficeTheme.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    hasPhoto ? BackofficeTheme.success : BackofficeTheme.border,
                width: 2,
              ),
            ),
            child: _capturingPhoto
                ? const Center(
                    child: CircularProgressIndicator(
                      color: BackofficeTheme.green,
                    ),
                  )
                : hasPhoto
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // Real camera capture preview (kIsWeb-safe via
                          // Image.network; native uses the file path).
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: _photoPreview(),
                          ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Material(
                              color: const Color(0x99151515),
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                onTap: () => setState(() => _photoFile = null),
                                borderRadius: BorderRadius.circular(20),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.refresh,
                                          size: 12, color: Colors.white),
                                      SizedBox(width: 5),
                                      Text(
                                        'Retake',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.photo_camera_outlined,
                            size: 26,
                            color: BackofficeTheme.muted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to take photo',
                            style: BackofficeTheme.inter(
                              12,
                              weight: FontWeight.w600,
                              color: BackofficeTheme.muted,
                            ),
                          ),
                        ],
                      ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _BackBtn(
              onTap: () {
                setState(() => _flow = 'detail');
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NextBtn(
                label: 'Done',
                icon: Icons.check,
                enabled: hasPhoto,
                onTap: _validateCollecte,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Opens the device camera and stores the captured photo (proof of
  /// visit). The image is compressed (85% quality, ≤1920px wide) to keep
  /// the base64 payload small for Firestore.
  Future<void> _capturePhoto() async {
    if (_capturingPhoto) return;
    // Declaring android.permission.CAMERA in the manifest without requesting
    // it at runtime makes Android silently block the camera intent and
    // image_picker fall back to the gallery — so always request first.
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      debugPrint('[CollectorDashboard] camera permission: $cameraStatus');
      if (mounted) {
        _showToast(
          cameraStatus.isPermanentlyDenied
              ? 'Camera blocked. Enable it in Settings → Apps → WastePro → Permissions.'
              : 'Camera permission is required to take a photo.',
          error: true,
        );
      }
      return;
    }
    setState(() => _capturingPhoto = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (photo != null && mounted) {
        setState(() => _photoFile = photo);
      }
    } catch (e) {
      debugPrint('[CollectorDashboard] camera error: $e');
      if (mounted) {
        _showToast('Camera unavailable: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _capturingPhoto = false);
    }
  }

  /// Preview widget for the captured photo. `kIsWeb` needs network
  /// rendering from bytes; native platforms use the file path directly.
  Widget _photoPreview() {
    final file = _photoFile;
    if (file == null) return const SizedBox.shrink();
    return Image.network(
      file.path,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Image.file(
        io.File(file.path),
        fit: BoxFit.cover,
      ),
    );
  }

  Future<void> _validateCollecte() async {
    final client = _currentClient;
    if (client == null) return;
    // No weight entry anymore: the weight stays 0 until the agency weighs
    // the load; no collector comment is attached either.
    const poids = 0.0;
    const commentaire = '';
    final now = _now();
    final heureArrivee = client.heureArrivee.isEmpty ? now : client.heureArrivee;

    // Close the sheet first (UI responsiveness), then persist async.
    setState(() {
      client.status = 'In Progress';
      client.heureArrivee = heureArrivee;
      client.heureDepart = now;
      client.poids = poids;
      client.commentaire = commentaire;
      _sheetOpen = false;
      _flow = 'detail';
    });
    _showPickupDonePopup(client);

    // 1. Automatic location pin: capture the collector's GPS at validation
    //    time as proof the visit happened at the client's address.
    double? lat;
    double? lng;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      lat = position.latitude;
      lng = position.longitude;
    } catch (e) {
      debugPrint('[CollectorDashboard] GPS capture failed: $e');
    }

    // 2. Encode the proof-of-visit photo (base64) so it is stored with the
    //    pickup document — visible to the client and the agency.
    String photoBase64 = '';
    final photoFile = _photoFile;
    if (photoFile != null) {
      try {
        final bytes = await photoFile.readAsBytes();
        if (bytes.length <= _maxPhotoBytes) {
          photoBase64 = base64Encode(bytes);
        } else {
          debugPrint(
            '[CollectorDashboard] photo too large '
            '(${bytes.length} B) — skipped',
          );
        }
      } catch (e) {
        debugPrint('[CollectorDashboard] photo encode failed: $e');
      }
    }

    if (mounted) {
      setState(() => _photoFile = null);
    }

    try {
      final pickupId = await _tourneeService.recordPickup(
        collectorId: _collectorId ?? '',
        collectorName: _collectorName,
        stop: client,
        poids: poids,
        commentaire: commentaire,
        heureArrivee: heureArrivee,
        heureDepart: now,
        photoBase64: photoBase64,
        latitude: lat,
        longitude: lng,
      );
      // The server asks the client to validate (bell, push, SMS).
      await _notificationService.notifyPickupEvent(
        PickupEvent.confirmationRequest,
        pickupId: pickupId,
      );
    } catch (e) {
      debugPrint(
        '[CollectorDashboard] Failed to record pickup / notify: $e',
      );
    }
  }

  /// Green-tick popup shown right after the collector taps Done: the pickup
  /// is recorded but only fully completed once the client validates it by
  /// scanning the QR code on their phone.
  void _showPickupDonePopup(TourneeStop client) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: BackofficeTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: BackofficeTheme.greenSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 46,
                  color: BackofficeTheme.success,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Pickup recorded!',
                textAlign: TextAlign.center,
                style: BackofficeTheme.sora(15.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'The collection with ${client.clientName} will be totally '
                'completed when the client validates the pickup by scanning '
                'your QR code.',
                textAlign: TextAlign.center,
                style: BackofficeTheme.inter(
                  12,
                  color: BackofficeTheme.muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: _PrimaryBtn(
                  icon: Icons.check,
                  label: 'Got it',
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Route Map
  // ------------------------------------------------------------------

  void _openRouteMap(TourneeStop client) {
    if (client.latitude == null || client.longitude == null) {
      _showToast('No location data for this client.', error: true);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RouteMapScreen(
          clientName: client.clientName,
          clientAddress: client.address,
          clientLatitude: client.latitude!,
          clientLongitude: client.longitude!,
        ),
      ),
    );
  }

  void _openItineraryMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ItineraryMapScreen(
          tournee: _tournee,
          collectorId: _collectorId ?? '',
          collectorName: _collectorName,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Toasts
  // ------------------------------------------------------------------

  void _showToast(String message, {bool error = false}) {
    final toast = _ToastMsg(message, error: error);
    setState(() => _toasts.add(toast));
    late final Timer timer;
    timer = Timer(const Duration(milliseconds: 2800), () {
      _toastTimers.remove(timer);
      if (mounted) setState(() => _toasts.remove(toast));
    });
    _toastTimers.add(timer);
  }
}

// ====================================================================
// Route Map Screen
// ====================================================================

class _RouteMapScreen extends StatefulWidget {
  const _RouteMapScreen({
    required this.clientName,
    required this.clientAddress,
    required this.clientLatitude,
    required this.clientLongitude,
  });

  final String clientName;
  final String clientAddress;
  final double clientLatitude;
  final double clientLongitude;

  @override
  State<_RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<_RouteMapScreen> {
  LatLng? _collectorPosition;
  StreamSubscription<Position>? _positionSubscription;
  bool _loading = true;
  bool _routeLoading = true;
  bool _permissionDenied = false;
  final NavigationService _navService = NavigationService();
  RouteResult? _routeResult;

  // --- Pause / Resume + elapsed collection timer ---
  bool _paused = false;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _segmentStart;

  // Default to Yaoundé center if GPS unavailable
  static const LatLng _defaultYaounde = LatLng(3.8480, 11.5021);

  @override
  void initState() {
    super.initState();
    _initLocation();
    _startElapsedSegment();
  }

  /// Starts counting the current driving segment (called on init and on
  /// Resume).
  void _startElapsedSegment() {
    _segmentStart = DateTime.now();
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused) return;
      setState(() {
        _elapsed = _elapsed + const Duration(seconds: 1);
      });
    });
  }

  /// Pauses the collection: stops the GPS stream and freezes the elapsed
  /// timer. The route is kept on screen.
  void _pauseCollection() {
    if (_paused) return;
    setState(() {
      _paused = true;
      _elapsed = _segmentStart == null
          ? _elapsed
          : _elapsed + DateTime.now().difference(_segmentStart!);
      _segmentStart = null;
    });
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _elapsedTimer?.cancel();
  }

  /// Resumes the collection: restarts the GPS stream and the timer.
  void _resumeCollection() {
    if (!_paused) return;
    setState(() => _paused = false);
    _startElapsedSegment();
    _subscribeToPosition();
  }

  /// Live GPS subscription (separated from [_initLocation] so Resume can
  /// restart it after a Pause).
  Future<void> _subscribeToPosition() async {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() {
          _collectorPosition = LatLng(pos.latitude, pos.longitude);
        });
        // Re-fetch route when position changes significantly.
        _fetchRoute();
      }
    });
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _useDefaultPosition();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _permissionDenied = true);
        _useDefaultPosition();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _collectorPosition = LatLng(position.latitude, position.longitude);
        _loading = false;
      });

      // Fetch the real road-based route.
      _fetchRoute();

      // Stream live updates
      await _subscribeToPosition();
    } catch (_) {
      _useDefaultPosition();
    }
  }

  String get _elapsedLabel {
    final total = _elapsed.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Fetches the real road-based route from OSRM.
  Future<void> _fetchRoute() async {
    if (_collectorPosition == null) return;
    setState(() => _routeLoading = true);

    try {
      final result = await _navService.getRoute(
        origin: _collectorPosition!,
        destination: _clientPos,
      );
      if (mounted) {
        setState(() {
          _routeResult = result;
          _routeLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _routeLoading = false);
      }
    }
  }

  void _useDefaultPosition() {
    if (!mounted) return;
    setState(() {
      _collectorPosition = _defaultYaounde;
      _loading = false;
    });
  }

  /// Open device settings so the collector can enable location permission.
  Future<void> _openSettings() async {
    await Geolocator.openAppSettings();
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: BackofficeTheme.redSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_outlined,
                size: 40,
                color: BackofficeTheme.red,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Location Permission Required',
              textAlign: TextAlign.center,
              style: BackofficeTheme.sora(16, weight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'This app needs access to your location to show your route and track collections. Please enable location access in your device settings.',
              textAlign: TextAlign.center,
              style: BackofficeTheme.inter(12.5, color: BackofficeTheme.muted),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings, size: 18),
                label: Text(
                  'Open Settings',
                  style: BackofficeTheme.inter(13, weight: FontWeight.w700, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BackofficeTheme.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() => _permissionDenied = false);
                _initLocation();
              },
              child: Text(
                'Try Again',
                style: BackofficeTheme.inter(12.5, weight: FontWeight.w600, color: BackofficeTheme.green),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  LatLng get _clientPos =>
      LatLng(widget.clientLatitude, widget.clientLongitude);

  LatLng get _startPos => _collectorPosition ?? _defaultYaounde;

  /// Distance and duration from real road route (or fallback to straight-line).
  double get _distanceKm {
    if (_routeResult != null) {
      return _routeResult!.distanceMeters / 1000;
    }
    return const Distance().as(LengthUnit.Kilometer, _startPos, _clientPos);
  }

  double get _durationMinutes {
    if (_routeResult != null) {
      return _routeResult!.durationSeconds / 60;
    }
    return _distanceKm * 3; // Fallback: ~20 km/h
  }

  List<LatLng> get _routePoints {
    if (_routeResult != null && _routeResult!.points.isNotEmpty) {
      return _routeResult!.points;
    }
    return [_startPos, _clientPos];
  }

  @override
  Widget build(BuildContext context) {
    final clientMarker = _clientPos;
    final startMarker = _startPos;

    // Compute bounds to fit both markers
    final bounds = LatLngBounds.fromPoints([startMarker, clientMarker]);
    final center = bounds.center;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BackofficeTheme.green,
        foregroundColor: BackofficeTheme.cream,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.clientName,
              style: BackofficeTheme.sora(15, weight: FontWeight.w600, color: BackofficeTheme.cream),
            ),
            Text(
              widget.clientAddress,
              style: BackofficeTheme.inter(11, color: BackofficeTheme.cream.withValues(alpha: 0.7)),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: BackofficeTheme.cream.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_distanceKm.toStringAsFixed(1)} km',
                  style: BackofficeTheme.inter(11, weight: FontWeight.w700, color: BackofficeTheme.cream),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _permissionDenied
              ? _buildPermissionDeniedView()
          : Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.proprie237.waste_pro',
                    ),
                    // Route polyline (real road-based route from OSRM)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          color: _routeResult != null ? BackofficeTheme.green : BackofficeTheme.muted,
                          strokeWidth: 4,
                          isDotted: _routeResult == null,
                        ),
                      ],
                    ),
                    // Client marker
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: clientMarker,
                          width: 44,
                          height: 44,
                          child: Container(
                            decoration: BoxDecoration(
                              color: BackofficeTheme.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                              ],
                            ),
                            child: const Icon(Icons.home, color: Colors.white, size: 20),
                          ),
                        ),
                        // Collector marker
                        Marker(
                          point: startMarker,
                          width: 44,
                          height: 44,
                          child: Container(
                            decoration: BoxDecoration(
                              color: BackofficeTheme.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                              ],
                            ),
                            child: const Icon(Icons.my_location, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Bottom info card
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: BackofficeTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: BackofficeTheme.border),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: BackofficeTheme.greenSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.home, size: 18, color: BackofficeTheme.green),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.clientName,
                                    style: BackofficeTheme.sora(13, weight: FontWeight.w600),
                                  ),
                                  Text(
                                    widget.clientAddress,
                                    style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Horizontally scrollable: the distance/duration/timer
                        // chip row overflows on narrow screens (e.g. 320dp-wide
                        // devices) when the route + Paused chips are shown.
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _MapInfoChip(
                                icon: Icons.straighten,
                                label: _routeResult != null
                                    ? _routeResult!.distanceFormatted
                                    : '${_distanceKm.toStringAsFixed(1)} km',
                              ),
                              const SizedBox(width: 8),
                              _MapInfoChip(
                                icon: Icons.access_time,
                                label: _routeResult != null
                                    ? _routeResult!.durationFormatted
                                    : '~${_durationMinutes.round()} min',
                              ),
                              const SizedBox(width: 8),
                              _MapInfoChip(
                                icon: Icons.timer_outlined,
                                label: _elapsedLabel,
                                active: !_paused,
                              ),
                              if (_routeLoading) ...[
                                const SizedBox(width: 8),
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ],
                              if (_paused) ...[
                                const SizedBox(width: 8),
                                _MapInfoChip(
                                  icon: Icons.pause_circle_outline,
                                  label: 'Paused',
                                  active: false,
                                ),
                              ] else if (_collectorPosition != null) ...[
                                const SizedBox(width: 8),
                                _MapInfoChip(
                                  icon: Icons.gps_fixed,
                                  label: 'Live',
                                  active: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Pause / Resume the collection (GPS + timer).
                        Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: ElevatedButton(
                                onPressed:
                                    _paused ? _resumeCollection : _pauseCollection,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _paused
                                      ? BackofficeTheme.green
                                      : BackofficeTheme.gold,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Icon(
                                  _paused ? Icons.play_arrow : Icons.pause,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Navigate button
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _navService.openNavigation(
                                  origin: _startPos,
                                  destination: _clientPos,
                                  destinationName: widget.clientName,
                                ),
                                icon: const Icon(Icons.navigation, size: 18),
                                label: Text(
                                  'Navigate with GPS',
                                  style: BackofficeTheme.inter(
                                    13,
                                    weight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: BackofficeTheme.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ====================================================================
// Itinerary Map Screen (collector's full route overview)
// ====================================================================

class _ItineraryMapScreen extends StatefulWidget {
  const _ItineraryMapScreen({
    required this.tournee,
    required this.collectorId,
    required this.collectorName,
  });

  final List<TourneeStop> tournee;
  final String collectorId;
  final String collectorName;

  @override
  State<_ItineraryMapScreen> createState() => _ItineraryMapScreenState();
}

class _ItineraryMapScreenState extends State<_ItineraryMapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng? _collectorPos;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _posSub;

  // Pulse animation.
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;

  static const LatLng _defaultCenter = LatLng(3.8480, 11.5021);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _subscribeToPosition();
    // Auto-center on stops after the first frame so the map doesn't show
    // a default view far from the actual route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitAllStops();
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _subscribeToPosition() {
    _posSub = FirebaseFirestore.instance
        .collection('collecteurs')
        .doc(widget.collectorId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      if (data == null) return;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      // Treat 0,0 or coordinates outside Cameroon as invalid.
      final valid = lat != null && lng != null &&
          !(lat == 0 && lng == 0) &&
          (lat > 1 && lat < 14) && (lng > 8 && lng < 17);
      setState(() {
        _collectorPos = valid ? LatLng(lat, lng) : null;
        _fitAllStops();
      });
    });
  }

  void _fitAllStops() {
    final points = <LatLng>[];
    if (_collectorPos != null) points.add(_collectorPos!);
    for (final s in widget.tournee) {
      if (s.latitude != null && s.longitude != null) {
        points.add(LatLng(s.latitude!, s.longitude!));
      }
    }
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Collect stop points for polylines.
    final stopPoints = widget.tournee
        .where((s) => s.latitude != null && s.longitude != null)
        .map((s) => LatLng(s.latitude!, s.longitude!))
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _collectorPos ?? _defaultCenter,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.proprie237.waste_pro',
              ),
              // Route polylines
              if (stopPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: stopPoints,
                      color: BackofficeTheme.gold.withValues(alpha: 0.5),
                      strokeWidth: 3,
                      isDotted: true,
                    ),
                  ],
                ),
              // Collector → first pending stop
              if (_collectorPos != null)
                _buildCollectorRouteLine(),
              // Stop markers
              MarkerLayer(markers: _buildStopMarkers()),
              // Collector marker
              if (_collectorPos != null)
                MarkerLayer(markers: [_buildCollectorMarker()]),
            ],
          ),
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),
          // Bottom info card
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _buildInfoCard(),
          ),
          // My Location button (right side, above info card)
          Positioned(
            right: 16,
            bottom: 180,
            child: _buildMyLocationButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildMyLocationButton() {
    return GestureDetector(
      onTap: _centerOnMyLocation,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: BackofficeTheme.surface,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(
          _collectorPos != null ? Icons.my_location : Icons.location_searching,
          color: BackofficeTheme.green,
          size: 20,
        ),
      ),
    );
  }

  void _centerOnMyLocation() {
    if (_collectorPos != null) {
      _mapController.move(_collectorPos!, 16);
    } else {
      _fetchAndCenterPosition();
    }
  }

  Future<void> _fetchAndCenterPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final pos = LatLng(position.latitude, position.longitude);
      setState(() => _collectorPos = pos);
      _mapController.move(pos, 16);
    } catch (_) {}
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: BackofficeTheme.surface,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: const Icon(Icons.arrow_back_rounded, color: BackofficeTheme.green, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Today's Route",
                  style: BackofficeTheme.sora(15, weight: FontWeight.w600, color: Colors.white),
                ),
                Text(
                  '${widget.tournee.length} stops · ${widget.collectorName}',
                  style: BackofficeTheme.inter(11, color: Colors.white.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          // Fit-all button
          GestureDetector(
            onTap: _fitAllStops,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: BackofficeTheme.surface,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: Icon(Icons.zoom_out_map, color: BackofficeTheme.green, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Marker _buildCollectorMarker() {
    return Marker(
      point: _collectorPos!,
      width: 44,
      height: 44,
      child: AnimatedBuilder(
        animation: _pulseScale,
        builder: (context, _) {
          final s = _pulseScale.value;
          return Transform.scale(
            scale: s,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: BackofficeTheme.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: BackofficeTheme.green.withValues(alpha: 0.4 * (2 - s)),
                    blurRadius: 12 * s,
                    spreadRadius: 2 * (s - 1),
                  ),
                ],
              ),
              child: const Icon(Icons.my_location, color: Colors.white, size: 18),
            ),
          );
        },
      ),
    );
  }

  List<Marker> _buildStopMarkers() {
    return widget.tournee.asMap().entries.map((entry) {
      final i = entry.key;
      final stop = entry.value;
      if (stop.latitude == null || stop.longitude == null) return null;
      final done = stop.status == 'Done';
      final missed = stop.status == 'Missed';
      final color = done
          ? Brand.leaf
          : missed
              ? BackofficeTheme.red
              : BackofficeTheme.gold;
      return Marker(
        point: LatLng(stop.latitude!, stop.longitude!),
        width: 34,
        height: 42,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : missed
                        ? const Icon(Icons.close, color: Colors.white, size: 14)
                        : Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 12, color: color),
          ],
        ),
      );
    }).whereType<Marker>().toList();
  }

  Widget _buildCollectorRouteLine() {
    if (_collectorPos == null) return const SizedBox.shrink();
    final pending = widget.tournee.where((s) => s.status == 'To Do' || s.status == 'In Progress').toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    // Find the first pending stop that has GPS coordinates.
    final destStop = pending.firstWhere(
      (s) => s.latitude != null && s.longitude != null,
      orElse: () => pending.first,
    );
    if (destStop.latitude == null || destStop.longitude == null) return const SizedBox.shrink();
    final dest = LatLng(destStop.latitude!, destStop.longitude!);
    return PolylineLayer(
      polylines: [
        Polyline(
          points: [_collectorPos!, dest],
          color: BackofficeTheme.green,
          strokeWidth: 4,
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    final pending = widget.tournee.where((t) => t.status == 'To Do' || t.status == 'In Progress').length;
    final done = widget.tournee.where((t) => t.status == 'Done').length;
    final missed = widget.tournee.where((t) => t.status == 'Missed').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BackofficeTheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's Progress",
            style: BackofficeTheme.sora(14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ItineraryStat(label: 'Pending', value: '$pending', color: BackofficeTheme.gold),
              const SizedBox(width: 8),
              _ItineraryStat(label: 'Done', value: '$done', color: BackofficeTheme.success),
              const SizedBox(width: 8),
              _ItineraryStat(label: 'Missed', value: '$missed', color: BackofficeTheme.red),
            ],
          ),
          // Show stops list
          const SizedBox(height: 10),
          ...widget.tournee.take(5).toList().asMap().entries.map((entry) {
            final i = entry.key;
            final stop = entry.value;
            final done = stop.status == 'Done';
            final missed = stop.status == 'Missed';
            final color = done ? Brand.leaf : missed ? BackofficeTheme.red : BackofficeTheme.gold;
            return GestureDetector(
              onTap: () {
                if (stop.latitude != null && stop.longitude != null) {
                  _mapController.move(
                    LatLng(stop.latitude!, stop.longitude!),
                    16,
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: done
                            ? const Icon(Icons.check, size: 10, color: Brand.leaf)
                            : missed
                                ? const Icon(Icons.close, size: 10, color: BackofficeTheme.red)
                                : Text(
                                    '${i + 1}',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: BackofficeTheme.gold),
                                  ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stop.clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: done ? BackofficeTheme.muted : BackofficeTheme.text,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    Text(
                      stop.pickupTime.split('\u2013').first.trim(),
                      style: BackofficeTheme.inter(10, color: BackofficeTheme.muted),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (widget.tournee.length > 5)
            Text(
              '+${widget.tournee.length - 5} more stops',
              style: BackofficeTheme.inter(10, color: BackofficeTheme.muted),
            ),
        ],
      ),
    );
  }
}

/// Small stat box for the itinerary card.
class _ItineraryStat extends StatelessWidget {
  const _ItineraryStat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: BackofficeTheme.sora(16, weight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label, style: BackofficeTheme.inter(9.5, color: BackofficeTheme.muted)),
          ],
        ),
      ),
    );
  }
}

class _MapInfoChip extends StatelessWidget {
  const _MapInfoChip({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: active ? BackofficeTheme.greenSoft : BackofficeTheme.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: active ? BackofficeTheme.green : BackofficeTheme.muted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: BackofficeTheme.inter(
              10.5,
              weight: FontWeight.w600,
              color: active ? BackofficeTheme.green : BackofficeTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================

String _dayLabel(DateTime d) {
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${days[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')} '
      '${months[d.month - 1]}';
}

// ====================================================================
// Small widgets
// ====================================================================

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.size});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BackofficeTheme.gold.withValues(alpha: 0.22),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: BackofficeTheme.sora(
          size * 0.34,
          weight: FontWeight.w700,
          color: BackofficeTheme.gold,
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BackofficeTheme.cream.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: Icon(icon, size: 13, color: BackofficeTheme.cream),
        ),
      ),
    );
  }
}

/// Progress card with ring indicator.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    final remaining = total - done;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BackofficeTheme.cream.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BackofficeTheme.cream.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CustomPaint(
              painter: _RingPainter(progress: progress),
              child: Center(
                child: Text(
                  '$done/$total',
                  style: BackofficeTheme.sora(
                    13,
                    weight: FontWeight.w700,
                    color: BackofficeTheme.cream,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today\'s Route',
                  style: BackofficeTheme.sora(
                    13,
                    weight: FontWeight.w600,
                    color: BackofficeTheme.cream,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_dayLabel(DateTime.now())} — '
                  '$remaining client${remaining > 1 ? 's' : ''} '
                  'remaining',
                  style: BackofficeTheme.inter(
                    10.5,
                    color: BackofficeTheme.cream.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    // Background
    canvas.drawCircle(
      center,
      radius,
      stroke..color = BackofficeTheme.cream.withValues(alpha: 0.15),
    );
    // Progress
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      stroke
        ..color = BackofficeTheme.gold
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? BackofficeTheme.green : BackofficeTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? BackofficeTheme.green : BackofficeTheme.border,
          ),
        ),
        child: Text(
          label,
          style: BackofficeTheme.inter(
            11.5,
            weight: FontWeight.w600,
            color: active ? BackofficeTheme.cream : BackofficeTheme.muted,
          ),
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.onTap, required this.index});

  final TourneeStop client;
  final VoidCallback onTap;
  final int index;

  Color get _accent => switch (client.status) {
        'Done' => BackofficeTheme.success,
        'Missed' => BackofficeTheme.red,
        'In Progress' => BackofficeTheme.gold,
        _ => BackofficeTheme.border,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: BackofficeTheme.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: BackofficeTheme.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Color bar based on status
              Container(width: 4, color: _accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: BackofficeTheme.greenSoft,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: BackofficeTheme.sora(
                            12,
                            weight: FontWeight.w700,
                            color: BackofficeTheme.green,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              client.clientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BackofficeTheme.inter(
                                13.5,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 9,
                                  color: BackofficeTheme.muted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    client.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: BackofficeTheme.inter(
                                      11,
                                      color: BackofficeTheme.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            client.pickupTime.split('–').first.trim(),
                            style: BackofficeTheme.inter(
                              11,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          _StatusBadge(status: client.status),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'Done' => (BackofficeTheme.greenSoft, BackofficeTheme.success),
      'Missed' => (BackofficeTheme.redSoft, BackofficeTheme.red),
      'In Progress' => (BackofficeTheme.goldSoft, BackofficeTheme.goldDim),
      _ => (BackofficeTheme.graySoft, BackofficeTheme.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: BackofficeTheme.inter(9.5, weight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: BackofficeTheme.inter(12.5, color: BackofficeTheme.muted),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final _HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final done = entry.status == 'Completed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: BackofficeTheme.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: BackofficeTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? BackofficeTheme.greenSoft : BackofficeTheme.redSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              done ? Icons.check : Icons.close,
              size: 14,
              color: done ? BackofficeTheme.success : BackofficeTheme.red,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: BackofficeTheme.inter(13.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.heure == '—' ? 'Not visited' : 'Arrival ${entry.heure}',
                  style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (entry.poids > 0)
                Text(
                  '${entry.poids} kg',
                  style: BackofficeTheme.inter(
                    11,
                    weight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 5),
              _StatusBadge(status: done ? 'Done' : 'Missed'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BackofficeTheme.card(),
      child: Column(
        children: [
          Text(
            value,
            style: BackofficeTheme.sora(
              18,
              weight: FontWeight.w700,
              color: BackofficeTheme.green,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: BackofficeTheme.inter(9.5, color: BackofficeTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BackofficeTheme.card(),
      child: Row(
        children: [
          Icon(icon, size: 16, color: BackofficeTheme.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BackofficeTheme.inter(12.5, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Client sheet header.
class _ClientHeader extends StatelessWidget {
  const _ClientHeader({required this.client, this.showTime = false});

  final TourneeStop client;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BackofficeTheme.greenSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              boInitials(client.clientName),
              style: BackofficeTheme.sora(
                16,
                weight: FontWeight.w700,
                color: BackofficeTheme.green,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.clientName,
                  style: BackofficeTheme.sora(15.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  showTime ? '${client.pickupTime} · ${client.address}' : client.address,
                  style: BackofficeTheme.inter(
                    11.5,
                    color: BackofficeTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BackofficeTheme.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, size: 15, color: BackofficeTheme.green),
              const SizedBox(height: 5),
              Text(
                label,
                style: BackofficeTheme.inter(
                  10.5,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: BackofficeTheme.inter(12, color: BackofficeTheme.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BackofficeTheme.inter(12, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneCell extends StatelessWidget {
  const _DoneCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: BackofficeTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: BackofficeTheme.inter(9.5, color: BackofficeTheme.muted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BackofficeTheme.inter(12.5, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BackofficeTheme.green,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(15),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: BackofficeTheme.cream),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    14,
                    weight: FontWeight.w700,
                    color: BackofficeTheme.cream,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? BackofficeTheme.redSoft : BackofficeTheme.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? BackofficeTheme.red : BackofficeTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? BackofficeTheme.red : BackofficeTheme.muted,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: BackofficeTheme.inter(
                11.5,
                weight: FontWeight.w600,
                color: selected ? BackofficeTheme.red : BackofficeTheme.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackBtn extends StatelessWidget {
  const _BackBtn({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BackofficeTheme.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: const Icon(
            Icons.arrow_back,
            size: 16,
            color: BackofficeTheme.muted,
          ),
        ),
      ),
    );
  }
}

class _NextBtn extends StatelessWidget {
  const _NextBtn({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? BackofficeTheme.green
          : BackofficeTheme.green.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: BackofficeTheme.cream),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: BackofficeTheme.inter(
                  14,
                  weight: FontWeight.w700,
                  color: BackofficeTheme.cream,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToastView extends StatelessWidget {
  const _ToastView({required this.toast});

  final _ToastMsg toast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: toast.error ? BackofficeTheme.red : BackofficeTheme.green,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 26,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            toast.error ? Icons.error_outline : Icons.check_circle_outline,
            size: 14,
            color: BackofficeTheme.gold,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              toast.message,
              style: BackofficeTheme.inter(
                12,
                weight: FontWeight.w500,
                color: BackofficeTheme.cream,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
