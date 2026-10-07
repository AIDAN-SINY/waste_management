import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../services/functions_client.dart';

/// Full-screen Leaflet map that shows the collector's live GPS position
/// and today's itinerary for the household.
///
/// The collector's position is streamed in real-time from the
/// `collecteurs/{collectorId}` Firestore document (written by
/// [LiveTrackingService]). The itinerary comes from the `collectorRoute`
/// Cloud Function: the client's own stop in full, the other stops as
/// anonymous points.
class CollectorTrackingScreen extends StatefulWidget {
  const CollectorTrackingScreen({
    super.key,
    required this.collecteurId,
    required this.collecteurName,
    required this.collecteurInitials,
    this.db,
    this.functions,
  });

  final String collecteurId;
  final String collecteurName;
  final String collecteurInitials;
  final FirebaseFirestore? db;

  /// Injected in tests (mocked `collectorRoute`).
  final FunctionsClient? functions;

  @override
  State<CollectorTrackingScreen> createState() =>
      _CollectorTrackingScreenState();
}

class _CollectorTrackingScreenState extends State<CollectorTrackingScreen>
    with SingleTickerProviderStateMixin {
  // ── Map ──────────────────────────────────────────────────────────
  final MapController _mapController = MapController();

  // ── Live position ────────────────────────────────────────────────
  LatLng? _collectorPos;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _posSub;
  bool _isTracking = false;

  // ── Itinerary stops ──────────────────────────────────────────────
  List<_ItineraryStop> _stops = [];
  bool _loadingStops = true;

  /// Pending stops of other clients before the household's own stop.
  int _stopsBeforeMe = 0;

  // ── Follow-collector mode ──────────────────────────────────────
  bool _followCollector = true;
  Timer? _periodicRefit;
  LatLng? _lastCollectorPos;

  // ── Pulse animation for collector marker ─────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;

  // ── Design ───────────────────────────────────────────────────────
  final Color _dGreen = const Color(0xFF0B5A2A);
  final Color _dGold = const Color(0xFFF5B800);
  final Color _dSurface = const Color(0xFFFFFFFF);
  final Color _dText = const Color(0xFF13261A);
  final Color _dMuted = const Color(0xFF6E8274);

  FirebaseFirestore get _db => widget.db ?? FirebaseFirestore.instance;

  static const LatLng _defaultCenter = LatLng(3.8480, 11.5021); // Yaoundé

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
    _loadItinerary();
    // Re-fit bounds every 30 s as a safety net.
    _periodicRefit = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_followCollector && _collectorPos != null && mounted) {
        _panToCollector(instant: true);
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _periodicRefit?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Firestore streams ────────────────────────────────────────────

  void _subscribeToPosition() {
    _posSub = _db
        .collection('collecteurs')
        .doc(widget.collecteurId)
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
        _isTracking = data['isTracking'] as bool? ?? false;
      });
      // Auto-pan if following and collector moved > 15 m.
      if (_followCollector && _collectorPos != null) {
        final moved = _lastCollectorPos == null ||
            const Distance().as(
              LengthUnit.Meter,
              _lastCollectorPos!,
              _collectorPos!,
            ) > 15;
        if (moved) _panToCollector();
      }
    });
  }

  /// Smoothly move camera to the collector's position.
  void _panToCollector({bool instant = false}) {
    if (_collectorPos == null) return;
    _lastCollectorPos = _collectorPos;
    if (instant) {
      _mapController.move(_collectorPos!, _mapController.camera.zoom);
    } else {
      _mapController.move(_collectorPos!, _mapController.camera.zoom);
    }
  }

  /// Loads today's route from the `collectorRoute` Cloud Function.
  ///
  /// The server returns the client's own stop in full, and the other stops
  /// of the collector's tour as anonymous points (no name / address,
  /// position rounded to ~100 m) — other clients' identity never reaches
  /// this device.
  Future<void> _loadItinerary() async {
    try {
      final data = await (widget.functions ?? FunctionsClient())
          .post('collectorRoute', const {});
      final stops = (data['stops'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (s) => _ItineraryStop(
              name: s['name'] as String? ?? '',
              address: s['address'] as String? ?? '',
              latitude: (s['lat'] as num).toDouble(),
              longitude: (s['lng'] as num).toDouble(),
              isDone: s['isDone'] as bool? ?? false,
              isMine: s['isMine'] as bool? ?? false,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _stops = stops;
        _stopsBeforeMe = (data['stopsBeforeMe'] as num?)?.toInt() ?? 0;
        _loadingStops = false;
      });

      // Fit bounds to include all stops + collector.
      _fitBounds();
    } catch (e) {
      debugPrint('[CollectorTracking] Error loading itinerary: $e');
      if (mounted) setState(() => _loadingStops = false);
    }
  }

  void _fitBounds() {
    final points = <LatLng>[];
    if (_collectorPos != null) points.add(_collectorPos!);
    for (final s in _stops) {
      points.add(LatLng(s.latitude, s.longitude));
    }
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _collectorPos ?? _defaultCenter,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.proprie237.waste_pro',
              ),
              // Itinerary polylines
              if (_stops.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _stops
                          .map((s) => LatLng(s.latitude, s.longitude))
                          .toList(),
                      color: _dGold.withValues(alpha: 0.5),
                      strokeWidth: 3,
                      isDotted: true,
                    ),
                  ],
                ),
              // Collector → first pending stop polyline
              if (_collectorPos != null && _stops.isNotEmpty)
                _buildCollectorRouteLine(),
              // Stop markers
              MarkerLayer(markers: _buildStopMarkers()),
              // Collector live marker
              if (_collectorPos != null)
                MarkerLayer(markers: [_buildCollectorMarker()]),
            ],
          ),

          // ── Top bar ─────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),

          // ── Bottom info card ────────────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _buildInfoCard(),
          ),
        ],
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────

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
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _dSurface,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF13261A),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Collector info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.collecteurName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sora(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _isTracking ? Brand.leaf : Brand.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isTracking ? 'Live tracking' : 'Position updating…',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Recenter / follow toggle button
          GestureDetector(
            onTap: () {
              setState(() => _followCollector = !_followCollector);
              if (_followCollector) _panToCollector();
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _followCollector ? _dGreen : _dSurface,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                _followCollector
                    ? Icons.gps_fixed
                    : Icons.gps_not_fixed,
                color: _followCollector ? Colors.white : _dGreen,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Markers ──────────────────────────────────────────────────────

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
                color: _dGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: _dGreen.withValues(alpha: 0.4 * (2 - s)),
                    blurRadius: 12 * s,
                    spreadRadius: 2 * (s - 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_shipping,
                color: Colors.white,
                size: 18,
              ),
            ),
          );
        },
      ),
    );
  }

  List<Marker> _buildStopMarkers() {
    return _stops.asMap().entries.map((entry) {
      final i = entry.key;
      final stop = entry.value;
      final done = stop.isDone;
      if (stop.isMine) return _buildMyStopMarker(stop);
      return Marker(
        point: LatLng(stop.latitude, stop.longitude),
        width: 34,
        height: 42,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: done ? Brand.leaf : _dGold,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
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
            // Triangle pointer
            Icon(
              Icons.arrow_drop_down,
              size: 12,
              color: done ? Brand.leaf : _dGold,
            ),
          ],
        ),
      );
    }).toList();
  }

  /// The household's own stop: a home pin, distinct from the anonymous
  /// stops of other clients.
  Marker _buildMyStopMarker(_ItineraryStop stop) {
    final color = stop.isDone ? Brand.leaf : _dGreen;
    return Marker(
      point: LatLng(stop.latitude, stop.longitude),
      width: 40,
      height: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              stop.isDone ? Icons.check : Icons.home_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          Icon(Icons.arrow_drop_down, size: 12, color: color),
        ],
      ),
    );
  }

  /// Draws a polyline from the collector to the nearest pending stop.
  Widget _buildCollectorRouteLine() {
    // Find the first pending stop.
    final pending = _stops.where((s) => !s.isDone).toList();
    if (pending.isEmpty) return const SizedBox.shrink();

    final dest = LatLng(pending.first.latitude, pending.first.longitude);
    return PolylineLayer(
      polylines: [
        Polyline(
          points: [_collectorPos!, dest],
          color: _dGreen,
          strokeWidth: 4,
        ),
      ],
    );
  }

  // ── Bottom info card ─────────────────────────────────────────────

  Widget _buildInfoCard() {
    final pending = _stops.where((s) => !s.isDone).length;
    final done = _stops.where((s) => s.isDone).length;

    // Estimate distance to nearest pending stop.
    String etaText = 'N/A';
    if (_collectorPos != null && pending > 0) {
      final nearest = _stops
          .where((s) => !s.isDone)
          .map((s) {
            final dist = const Distance().as(
              LengthUnit.Meter,
              _collectorPos!,
              LatLng(s.latitude, s.longitude),
            );
            return (s, dist);
          })
          .toList()
        ..sort((a, b) => a.$2.compareTo(b.$2));
      final distM = nearest.first.$2;
      final distKm = distM / 1000;
      final estMin = (distKm / 0.4).round(); // ~24 km/h avg
      if (estMin < 60) {
        etaText = '$estMin min';
      } else {
        etaText = '${estMin ~/ 60}h ${estMin % 60}m';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dSurface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Collector avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _dGold.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.collecteurInitials,
                    style: GoogleFonts.sora(
                      color: _dGold,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Collector',
                      style: TextStyle(
                        fontSize: 11,
                        color: _dMuted,
                      ),
                    ),
                    Text(
                      widget.collecteurName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        color: _dText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // ETA badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _dGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      'ETA',
                      style: TextStyle(
                        fontSize: 9,
                        color: _dMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      etaText,
                      style: GoogleFonts.sora(
                        color: _dGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Itinerary progress
          Row(
            children: [
              _ItineraryStat(
                label: 'Total stops',
                value: '${_stops.length}',
                color: _dText,
              ),
              const SizedBox(width: 12),
              _ItineraryStat(
                label: 'Completed',
                value: '$done',
                color: Brand.leaf,
              ),
              const SizedBox(width: 12),
              _ItineraryStat(
                label: 'Remaining',
                value: '$pending',
                color: _dGold,
              ),
            ],
          ),
          if (_loadingStops) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _dGold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Loading itinerary…',
                  style: TextStyle(fontSize: 10, color: _dMuted),
                ),
              ],
            ),
          ],
          // The household's own stop + its place in the queue (other
          // clients' stops stay anonymous).
          if (!_loadingStops) ..._buildMyStopSummary(),
        ],
      ),
    );
  }
}

extension on _CollectorTrackingScreenState {
  List<Widget> _buildMyStopSummary() {
    final mine = _stops.where((s) => s.isMine).firstOrNull;
    if (mine == null) return const [];
    final String status;
    if (mine.isDone) {
      status = 'Your pickup is done today.';
    } else if (_stopsBeforeMe == 0) {
      status = 'You are the next stop.';
    } else {
      status = '$_stopsBeforeMe stop${_stopsBeforeMe == 1 ? '' : 's'} '
          'before you.';
    }
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          Icon(
            mine.isDone ? Icons.check_circle : Icons.home_rounded,
            size: 18,
            color: mine.isDone ? Brand.leaf : _dGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _dText,
                  ),
                ),
                if (mine.address.isNotEmpty)
                  Text(
                    mine.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: _dMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    ];
  }
}

// ── Models ───────────────────────────────────────────────────────────

class _ItineraryStop {
  const _ItineraryStop({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.isDone,
    this.isMine = false,
  });

  /// Only known for the household's own stop ([isMine]).
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final bool isDone;
  final bool isMine;
}

// ── Small widgets ────────────────────────────────────────────────────

class _ItineraryStat extends StatelessWidget {
  const _ItineraryStat({
    required this.label,
    required this.value,
    required this.color,
  });

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
            Text(
              value,
              style: GoogleFonts.sora(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: const Color(0xFF6E8274),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
