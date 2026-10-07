import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../services/live_tracking_service.dart';
import '../data/backoffice_store.dart';
import '../models.dart';
import '../theme.dart';

/// Colours of the collectors' operating zones (one per collector).
const _zoneColors = <Color>[
  Color(0xFF0B5A2A), // brand green
  Color(0xFFB88A00), // brand gold (dim, readable)
  Color(0xFF3D6BE8),
  Color(0xFF8E44AD),
  Color(0xFF00897B),
  Color(0xFFD35400),
  Color(0xFF6CB82E),
  Color(0xFFC1443D),
];

/// Full-screen Leaflet map showing all active collectors in real time,
/// with the operating zone of each collector circled.
/// Accessible from the Agency Manager backoffice sidebar.
class BoTrackingPage extends StatefulWidget {
  const BoTrackingPage({
    super.key,
    this.store,
    this.agenceId = '',
    this.trackingService,
    this.showTiles = true,
  });

  /// The agency's collectors (their operating zones).
  final BackofficeStore? store;

  /// The manager's agency: only its collectors are shown.
  final String agenceId;

  /// Live positions (tests inject one).
  final LiveTrackingService? trackingService;

  /// Map background (off in tests: no network).
  final bool showTiles;

  @override
  State<BoTrackingPage> createState() => _BoTrackingPageState();
}

class _BoTrackingPageState extends State<BoTrackingPage> {
  late final LiveTrackingService _trackingService =
      widget.trackingService ?? LiveTrackingService();
  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _collectors = [];
  bool _loading = true;
  String? _selectedCollectorId;
  bool _showZones = true;

  /// Collectors of the agency that have an operating zone.
  List<CollecteurModel> get _zoned => (widget.store?.collecteurs ?? const [])
      .where((c) => c.zoneArea != null)
      .toList();

  Color _zoneColor(String collecteurId) {
    final all = widget.store?.collecteurs ?? const <CollecteurModel>[];
    final i = all.indexWhere((c) => c.id == collecteurId);
    return _zoneColors[(i < 0 ? 0 : i) % _zoneColors.length];
  }

  CollecteurModel? _model(String id) {
    for (final c in widget.store?.collecteurs ?? const <CollecteurModel>[]) {
      if (c.id == id) return c;
    }
    return null;
  }

  // Default center: Yaoundé
  static const LatLng _defaultCenter = LatLng(3.8480, 11.5021);

  @override
  void initState() {
    super.initState();
    _listenToCollectors();
  }

  void _listenToCollectors() {
    _trackingService.watchAllCollectors(agenceId: widget.agenceId).listen((
      collectors,
    ) {
      if (!mounted) return;
      setState(() {
        _collectors = collectors;
        _loading = false;
      });

      // Auto-fit map bounds when we have collectors.
      if (collectors.isNotEmpty) {
        _fitBounds(collectors);
      }
    });
  }

  /// True once the FlutterMap is built (its controller usable).
  bool _mapReady = false;

  void _fitBounds(List<Map<String, dynamic>> collectors) {
    if (collectors.isEmpty) return;
    // The first positions can arrive while the spinner is still shown:
    // fit once the map exists.
    if (!_mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) _fitBounds(_collectors);
      });
      return;
    }
    final points = collectors
        .map((c) => LatLng(c['latitude'] as double, c['longitude'] as double))
        .toList();
    if (points.length == 1) {
      _mapController.move(points.first, 15);
    } else {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
      );
    }
  }

  @override
  void dispose() {
    if (widget.trackingService == null) _trackingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    Widget page(BuildContext context) => Scaffold(
      backgroundColor: BackofficeTheme.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: BackofficeTheme.green,
                    ),
                  )
                : _buildMap(),
          ),
        ],
      ),
    );
    // Zones follow the store (a collector's zone edited elsewhere).
    return store == null
        ? page(context)
        : ListenableBuilder(listenable: store, builder: (c, _) => page(c));
  }

  /// Fits the map on [c]'s zone (used for a collector with no position).
  void _focusZone(CollecteurModel c) {
    final a = c.zoneArea;
    if (a == null) return;
    final points = a.isPolygon
        ? a.points.map((p) => LatLng(p.$1, p.$2)).toList()
        : [
            LatLng(
              a.centerLat - a.radiusMeters / 111320,
              a.centerLng - a.radiusMeters / 111320,
            ),
            LatLng(
              a.centerLat + a.radiusMeters / 111320,
              a.centerLng + a.radiusMeters / 111320,
            ),
          ];
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  /// Transparent area of every collector's zone (the selected one stronger).
  List<Widget> _zoneLayers() {
    if (!_showZones) return const [];
    final polygons = <Polygon>[];
    final circles = <CircleMarker>[];
    for (final c in _zoned) {
      final a = c.zoneArea!;
      final color = _zoneColor(c.id);
      final selected = c.id == _selectedCollectorId;
      final fill = color.withValues(alpha: selected ? 0.28 : 0.13);
      final width = selected ? 3.5 : 2.0;
      if (a.isPolygon) {
        polygons.add(
          Polygon(
            points: a.points.map((p) => LatLng(p.$1, p.$2)).toList(),
            color: fill,
            borderColor: color,
            borderStrokeWidth: width,
            isFilled: true,
          ),
        );
      } else if (a.radiusMeters > 0) {
        circles.add(
          CircleMarker(
            point: LatLng(a.centerLat, a.centerLng),
            radius: a.radiusMeters,
            useRadiusInMeter: true,
            color: fill,
            borderColor: color,
            borderStrokeWidth: width,
          ),
        );
      }
    }
    return [
      if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
      if (circles.isNotEmpty) CircleLayer(circles: circles),
      // Label in each zone: « Paul · Nkoabang » (tap = select).
      MarkerLayer(
        markers: [
          for (final c in _zoned)
            Marker(
              point: LatLng(c.zoneArea!.centerLat, c.zoneArea!.centerLng),
              width: 150,
              height: 26,
              child: GestureDetector(
                key: Key('zone_label_${c.id}'),
                onTap: () {
                  setState(() => _selectedCollectorId = c.id);
                  _focusZone(c);
                },
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _zoneColor(c.id)),
                    ),
                    child: Text(
                      '${c.name} · ${c.zoneArea!.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BackofficeTheme.inter(
                        10,
                        weight: FontWeight.w700,
                        color: _zoneColor(c.id),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
  }

  Widget _buildHeader() {
    final activeCount = _collectors
        .where((c) => c['isTracking'] == true)
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
        color: BackofficeTheme.surface,
        border: Border(bottom: BorderSide(color: BackofficeTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: BackofficeTheme.greenSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.map_outlined,
              color: BackofficeTheme.green,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live Collector Tracking',
                  style: BackofficeTheme.sora(16, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '$activeCount of ${_collectors.length} collectors active',
                  style: BackofficeTheme.inter(
                    12,
                    color: BackofficeTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          // Show / hide the collectors' operating zones.
          if (_zoned.isNotEmpty) ...[
            FilterChip(
              key: const Key('tracking_zones_toggle'),
              label: Text('Zones (${_zoned.length})'),
              selected: _showZones,
              showCheckmark: true,
              selectedColor: BackofficeTheme.greenSoft,
              onSelected: (v) => setState(() => _showZones = v),
            ),
            const SizedBox(width: 8),
          ],
          // Refresh button
          Material(
            color: BackofficeTheme.bg,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => _fitBounds(_collectors),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.center_focus_strong,
                  size: 20,
                  color: BackofficeTheme.green,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final center = _collectors.isNotEmpty
        ? LatLng(
            _collectors.first['latitude'] as double,
            _collectors.first['longitude'] as double,
          )
        : _defaultCenter;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
            onMapReady: () => _mapReady = true,
          ),
          children: [
            if (widget.showTiles)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.proprie237.waste_pro',
              ),
            ..._zoneLayers(),
            MarkerLayer(
              markers: [for (final c in _collectors) _buildCollectorMarker(c)],
            ),
          ],
        ),
        // Collector list panel
        Positioned(left: 12, bottom: 12, child: _buildCollectorList()),
        // Selected collector detail card
        if (_selectedCollectorId != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildCollectorDetail(),
          ),
      ],
    );
  }

  Marker _buildCollectorMarker(Map<String, dynamic> collector) {
    final lat = collector['latitude'] as double;
    final lng = collector['longitude'] as double;
    final name = collector['name'] as String;
    final isActive = collector['isTracking'] as bool;
    final id = collector['id'] as String;
    final isSelected = _selectedCollectorId == id;

    final initials = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .take(2)
        .join()
        .toUpperCase();

    return Marker(
      point: LatLng(lat, lng),
      width: isSelected ? 52 : 44,
      height: isSelected ? 52 : 44,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedCollectorId = isSelected ? null : id);
          _mapController.move(LatLng(lat, lng), 16);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: isActive ? BackofficeTheme.green : BackofficeTheme.muted,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: isSelected ? 3 : 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: isSelected ? 10 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(
              initials.isNotEmpty ? initials : '?',
              style: BackofficeTheme.sora(
                isSelected ? 16 : 14,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollectorList() {
    if (_collectors.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 180,
      constraints: BoxConstraints(
        maxHeight: math.min(200.0, _collectors.length * 48.0 + 40),
      ),
      decoration: BoxDecoration(
        color: BackofficeTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BackofficeTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              'Collectors (${_collectors.length})',
              style: BackofficeTheme.sora(12, weight: FontWeight.w700),
            ),
          ),
          Flexible(
            child: Material(
              type: MaterialType.transparency,
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _collectors.length,
                itemBuilder: (context, index) {
                  final c = _collectors[index];
                  final name = c['name'] as String;
                  final isActive = c['isTracking'] as bool;
                  final id = c['id'] as String;
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? BackofficeTheme.success
                            : BackofficeTheme.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BackofficeTheme.inter(11, weight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      isActive ? 'Active' : 'Offline',
                      style: BackofficeTheme.inter(
                        9,
                        color: BackofficeTheme.muted,
                      ),
                    ),
                    onTap: () {
                      final lat = c['latitude'] as double;
                      final lng = c['longitude'] as double;
                      setState(() => _selectedCollectorId = id);
                      _mapController.move(LatLng(lat, lng), 16);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectorDetail() {
    final collector = _collectors.firstWhere(
      (c) => c['id'] == _selectedCollectorId,
      orElse: () => {},
    );
    final model = _model(_selectedCollectorId ?? '');
    if (collector.isEmpty && model == null) return const SizedBox.shrink();

    final name = collector['name'] as String? ?? model!.name;
    final isActive = collector['isTracking'] as bool? ?? false;
    final speed = collector['speed'] as double? ?? 0;
    final lastUpdate = collector['lastPositionUpdate'];

    // His operating zone, and whether he is in it right now.
    final zone = model?.zoneArea;
    String? zoneText;
    Color zoneColor = BackofficeTheme.muted;
    if (zone != null) {
      final lat = collector['latitude'] as double?;
      final lng = collector['longitude'] as double?;
      if (lat == null || lng == null) {
        zoneText = 'Zone: ${zone.name} · no position yet';
      } else if (zone.contains(lat, lng)) {
        zoneText = 'Inside his zone (${zone.name})';
        zoneColor = BackofficeTheme.success;
      } else {
        zoneText = 'Outside his zone (${zone.name})';
        zoneColor = BackofficeTheme.red;
      }
    }

    String lastUpdateText = 'Unknown';
    if (lastUpdate != null && lastUpdate is DateTime) {
      final diff = DateTime.now().difference(lastUpdate);
      if (diff.inMinutes < 1) {
        lastUpdateText = 'Just now';
      } else if (diff.inMinutes < 60) {
        lastUpdateText = '${diff.inMinutes} min ago';
      } else {
        lastUpdateText = '${diff.inHours}h ago';
      }
    } else if (lastUpdate != null && lastUpdate is Timestamp) {
      final diff = DateTime.now().difference(lastUpdate.toDate());
      if (diff.inMinutes < 1) {
        lastUpdateText = 'Just now';
      } else if (diff.inMinutes < 60) {
        lastUpdateText = '${diff.inMinutes} min ago';
      } else {
        lastUpdateText = '${diff.inHours}h ago';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BackofficeTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BackofficeTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isActive
                      ? BackofficeTheme.greenSoft
                      : BackofficeTheme.graySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person,
                  size: 18,
                  color: isActive
                      ? BackofficeTheme.green
                      : BackofficeTheme.muted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: BackofficeTheme.sora(13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive ? 'Active · $lastUpdateText' : 'Offline',
                      style: BackofficeTheme.inter(
                        11,
                        color: isActive
                            ? BackofficeTheme.success
                            : BackofficeTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (speed > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: BackofficeTheme.greenSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(speed * 3.6).toStringAsFixed(0)} km/h',
                    style: BackofficeTheme.inter(
                      10,
                      weight: FontWeight.w600,
                      color: BackofficeTheme.green,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _selectedCollectorId = null),
                child: const Icon(
                  Icons.close,
                  size: 18,
                  color: BackofficeTheme.muted,
                ),
              ),
            ],
          ),
          if (zoneText != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.layers_outlined, size: 15, color: zoneColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    zoneText,
                    key: const Key('tracking_zone_status'),
                    style: BackofficeTheme.inter(
                      11.5,
                      weight: FontWeight.w600,
                      color: zoneColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
