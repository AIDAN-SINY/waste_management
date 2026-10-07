import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/brand.dart';
import '../../../services/place_boundary_service.dart';
import '../models.dart';
import '../theme.dart';

/// Cameroon's bounding box (the map stays around it).
final _cameroon = LatLngBounds(const LatLng(1.65, 8.45), const LatLng(13.10, 16.20));
const _cameroonCenter = LatLng(5.7, 12.35);

/// Transparent fill + outline of an operating zone.
const _fill = Color(0x332E9E3A); // Brand.leaf @ 20 %
const _outline = Brand.green;

LatLng _ll((double, double) p) => LatLng(p.$1, p.$2);

/// Bounds of an area (circle: its enclosing square).
LatLngBounds _boundsOf(ZoneArea a) {
  if (a.isPolygon) return LatLngBounds.fromPoints(a.points.map(_ll).toList());
  final dLat = a.radiusMeters / 111320;
  final dLng = a.radiusMeters / (111320 * math.cos(a.centerLat * math.pi / 180));
  return LatLngBounds(
    LatLng(a.centerLat - dLat, a.centerLng - dLng),
    LatLng(a.centerLat + dLat, a.centerLng + dLng),
  );
}

/// Map layers drawing [area] (polygon or circle), transparently filled.
List<Widget> zoneAreaLayers(ZoneArea area) => [
      if (area.isPolygon)
        PolygonLayer(polygons: [
          Polygon(
            points: area.points.map(_ll).toList(),
            color: _fill,
            borderColor: _outline,
            borderStrokeWidth: 2.5,
            isFilled: true,
          ),
        ])
      else if (area.radiusMeters > 0)
        CircleLayer(circles: [
          CircleMarker(
            point: LatLng(area.centerLat, area.centerLng),
            radius: area.radiusMeters,
            useRadiusInMeter: true,
            color: _fill,
            borderColor: _outline,
            borderStrokeWidth: 2.5,
          ),
        ]),
    ];

Widget _tiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.wastepro.app',
    );

/// Small, non-interactive map showing a collector's operating zone.
class ZoneAreaPreview extends StatelessWidget {
  const ZoneAreaPreview({
    super.key,
    required this.area,
    this.height = 150,
    this.showTiles = true,
  });

  final ZoneArea area;
  final double height;

  /// Map background (off in tests: no network).
  final bool showTiles;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          key: ValueKey(area.toMap().toString()),
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: _boundsOf(area),
              padding: const EdgeInsets.all(18),
            ),
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [if (showTiles) _tiles(), ...zoneAreaLayers(area)],
        ),
      ),
    );
  }
}

/// How the zone is defined on the picker.
enum _Mode { official, circle, draw }

/// Full-screen map where the agency manager defines a collector's
/// operating zone: search the neighbourhood (OpenStreetMap), then
///  - its official boundary is circled when OSM has it (e.g. Bastos);
///  - otherwise an adjustable circle around the place (e.g. Nkoabang);
///  - or he draws the exact zone by tapping its limits on the map.
/// Returns the [ZoneArea] (null when cancelled).
class ZoneAreaPickerScreen extends StatefulWidget {
  const ZoneAreaPickerScreen({
    super.key,
    this.initial,
    this.initialQuery = '',
    this.service,
    this.showTiles = true,
  });

  final ZoneArea? initial;
  final String initialQuery;
  final PlaceBoundaryService? service;
  final bool showTiles;

  @override
  State<ZoneAreaPickerScreen> createState() => _ZoneAreaPickerScreenState();
}

class _ZoneAreaPickerScreenState extends State<ZoneAreaPickerScreen> {
  late final PlaceBoundaryService _service =
      widget.service ?? PlaceBoundaryService();
  late final TextEditingController _query =
      TextEditingController(text: widget.initial?.name ?? widget.initialQuery);
  final _map = MapController();
  bool _mapReady = false;

  List<PlaceResult> _results = const [];
  bool _searching = false;
  String? _error;

  PlaceResult? _place;
  _Mode _mode = _Mode.circle;
  double _radius = 1000;
  final List<LatLng> _drawn = [];

  /// The zone loaded from [ZoneAreaPickerScreen.initial] (no place).
  ZoneArea? _existing;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _existing = initial;
      _radius = initial.radiusMeters > 0 ? initial.radiusMeters : 1000;
      if (initial.source == 'drawn' && initial.isPolygon) {
        _mode = _Mode.draw;
        _drawn.addAll(initial.points.map(_ll));
      } else {
        _mode = initial.isPolygon ? _Mode.official : _Mode.circle;
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  // --- Search ---

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _service.search(_query.text);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        if (results.isEmpty) {
          _error = 'No place called “${_query.text.trim()}” found in '
              'Cameroon. Check the spelling, or draw the zone yourself.';
        }
      });
      if (results.length == 1) _choose(results.single);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Map search unavailable — check the internet connection, '
            'or draw the zone yourself.';
      });
    }
  }

  void _choose(PlaceResult p) {
    setState(() {
      _place = p;
      _existing = null;
      _results = const [];
      _drawn.clear();
      _radius = p.defaultRadiusMeters;
      _mode = p.hasBoundary ? _Mode.official : _Mode.circle;
    });
    _fit();
  }

  // --- Current area ---

  String get _name => _place?.name ?? _existing?.name ?? _query.text.trim();

  ZoneArea? get _area {
    final place = _place;
    final existing = _existing;
    switch (_mode) {
      case _Mode.official:
        if (place != null && place.hasBoundary) {
          return ZoneArea(
            name: place.name,
            kind: 'polygon',
            points: place.boundary,
            centerLat: place.lat,
            centerLng: place.lng,
            source: 'osm',
          );
        }
        if (existing != null && existing.isPolygon) return existing;
        return null;
      case _Mode.circle:
        final lat = place?.lat ?? existing?.centerLat;
        final lng = place?.lng ?? existing?.centerLng;
        if (lat == null || lng == null) return null;
        return ZoneArea(
          name: _name,
          kind: 'circle',
          centerLat: lat,
          centerLng: lng,
          radiusMeters: _radius,
          source: 'circle',
        );
      case _Mode.draw:
        if (_drawn.length < 3) return null;
        final lat = _drawn.map((p) => p.latitude).reduce((a, b) => a + b) /
            _drawn.length;
        final lng = _drawn.map((p) => p.longitude).reduce((a, b) => a + b) /
            _drawn.length;
        return ZoneArea(
          name: _name,
          kind: 'polygon',
          points: [for (final p in _drawn) (p.latitude, p.longitude)],
          centerLat: lat,
          centerLng: lng,
          source: 'drawn',
        );
    }
  }

  void _fit() {
    final area = _area;
    if (!_mapReady || area == null) return;
    _map.fitCamera(CameraFit.bounds(
      bounds: _boundsOf(area),
      padding: const EdgeInsets.all(40),
    ));
  }

  void _setMode(_Mode mode) {
    setState(() => _mode = mode);
    if (mode != _Mode.draw) _fit();
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final area = _area;
    return Scaffold(
      backgroundColor: BackofficeTheme.bg,
      appBar: AppBar(
        title: Text('Operating zone',
            style: BackofficeTheme.sora(16, weight: FontWeight.w600)),
        backgroundColor: BackofficeTheme.surface,
        foregroundColor: BackofficeTheme.green,
        elevation: 0,
        actions: [
          TextButton(
            key: const Key('zone_area_confirm'),
            onPressed: area == null || area.name.isEmpty
                ? null
                : () => Navigator.of(context).pop(area),
            child: const Text('Confirm'),
          ),
        ],
      ),
      body: Column(
        children: [
          _searchBar(),
          if (_results.isNotEmpty) _resultsList(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(_error!,
                  key: const Key('zone_area_error'),
                  style: BackofficeTheme.inter(12, color: BackofficeTheme.red)),
            ),
          Expanded(child: _mapView(area)),
          _panel(area),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('zone_area_query'),
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Neighbourhood, e.g. Nkoabang, Bastos…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: BackofficeTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: BackofficeTheme.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('zone_area_search'),
            onPressed: _searching ? null : _search,
            style: FilledButton.styleFrom(
              backgroundColor: BackofficeTheme.green,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            child: _searching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Search'),
          ),
        ],
      ),
    );
  }

  Widget _resultsList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BackofficeTheme.card(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: _resultsTiles(),
      ),
    );
  }

  Widget _resultsTiles() {
    return ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              '${_results.length} places found — choose the right one:',
              style: BackofficeTheme.inter(11.5, color: BackofficeTheme.muted),
            ),
          ),
          for (var i = 0; i < _results.length; i++)
            ListTile(
              key: Key('zone_area_result_$i'),
              dense: true,
              leading: Icon(
                _results[i].hasBoundary
                    ? Icons.crop_square_rounded
                    : Icons.place_outlined,
                color: BackofficeTheme.green,
              ),
              title: Text(_results[i].name,
                  style: BackofficeTheme.inter(13, weight: FontWeight.w600)),
              subtitle: Text(
                _results[i].displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
              ),
              trailing: Text(
                _results[i].hasBoundary ? 'Exact limits' : 'Approximate',
                style: BackofficeTheme.inter(10.5,
                    weight: FontWeight.w700,
                    color: _results[i].hasBoundary
                        ? BackofficeTheme.green
                        : BackofficeTheme.goldDim),
              ),
              onTap: () => _choose(_results[i]),
            ),
        ],
    );
  }

  Widget _mapView(ZoneArea? area) {
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _cameroonCenter,
        initialZoom: 6,
        initialCameraFit: area == null
            ? null
            : CameraFit.bounds(
                bounds: _boundsOf(area),
                padding: const EdgeInsets.all(40),
              ),
        minZoom: 5,
        cameraConstraint: CameraConstraint.containCenter(bounds: _cameroon),
        onMapReady: () => _mapReady = true,
        onTap: (_, point) {
          if (_mode != _Mode.draw) return;
          setState(() => _drawn.add(point));
        },
      ),
      children: [
        if (widget.showTiles) _tiles(),
        if (area != null) ...zoneAreaLayers(area),
        if (_mode == _Mode.draw && _drawn.isNotEmpty) ...[
          if (_drawn.length >= 2 && _drawn.length < 3)
            PolylineLayer(polylines: [
              Polyline(points: _drawn, color: _outline, strokeWidth: 2.5),
            ]),
          MarkerLayer(markers: [
            for (final p in _drawn)
              Marker(
                point: p,
                width: 14,
                height: 14,
                child: Container(
                  decoration: BoxDecoration(
                    color: Brand.gold,
                    shape: BoxShape.circle,
                    border: Border.all(color: Brand.greenDark, width: 2),
                  ),
                ),
              ),
          ]),
        ],
      ],
    );
  }

  Widget _panel(ZoneArea? area) {
    final place = _place;
    final hasOfficial = (place?.hasBoundary ?? false) ||
        (_existing?.isPolygon == true && _existing?.source == 'osm');
    final canCircle = place != null || _existing != null;

    final Widget body;
    switch (_mode) {
      case _Mode.official:
        body = Text(
          'Official limits of ${area?.name ?? _name} (OpenStreetMap). '
          'The collector operates inside the green area.',
          key: const Key('zone_area_info'),
          style: BackofficeTheme.inter(12.5),
        );
      case _Mode.circle:
        body = canCircle
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place != null && !place.hasBoundary
                        ? 'The exact limits of ${place.name} are not on the '
                            'map yet: adjust the circle, or draw the exact zone.'
                        : 'Area: ${(_radius / 1000).toStringAsFixed(1)} km '
                            'around $_name.',
                    key: const Key('zone_area_info'),
                    style: BackofficeTheme.inter(12.5),
                  ),
                  Slider(
                    key: const Key('zone_area_radius'),
                    value: _radius.clamp(200, 6000),
                    min: 200,
                    max: 6000,
                    divisions: 58,
                    activeColor: BackofficeTheme.green,
                    label: '${(_radius / 1000).toStringAsFixed(1)} km',
                    onChanged: (v) => setState(() => _radius = v),
                    onChangeEnd: (_) => _fit(),
                  ),
                ],
              )
            : Text(
                'Search the neighbourhood above, or draw the zone on the map.',
                key: const Key('zone_area_info'),
                style: BackofficeTheme.inter(12.5, color: BackofficeTheme.muted),
              );
      case _Mode.draw:
        body = Text(
          _drawn.length < 3
              ? 'Tap on the map along the limits of the zone '
                  '(${_drawn.length}/3 points minimum).'
              : 'Zone drawn with ${_drawn.length} points. Keep tapping to '
                  'refine it.',
          key: const Key('zone_area_info'),
          style: BackofficeTheme.inter(12.5),
        );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: BackofficeTheme.surface,
        border: Border(top: BorderSide(color: BackofficeTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (hasOfficial && _mode != _Mode.official)
                  OutlinedButton(
                    onPressed: () => _setMode(_Mode.official),
                    child: const Text('Official limits'),
                  ),
                if (canCircle && _mode != _Mode.circle)
                  OutlinedButton(
                    onPressed: () => _setMode(_Mode.circle),
                    child: const Text('Use a circle'),
                  ),
                if (_mode != _Mode.draw)
                  OutlinedButton.icon(
                    key: const Key('zone_area_draw'),
                    onPressed: () => _setMode(_Mode.draw),
                    icon: const Icon(Icons.draw_outlined, size: 16),
                    label: const Text('Draw the exact zone'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: _drawn.isEmpty
                        ? null
                        : () => setState(() => _drawn.removeLast()),
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: const Text('Undo'),
                  ),
                  OutlinedButton(
                    onPressed: _drawn.isEmpty
                        ? null
                        : () => setState(_drawn.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
