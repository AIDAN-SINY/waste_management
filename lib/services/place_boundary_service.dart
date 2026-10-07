import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// A place found in Cameroon, with its boundary when OpenStreetMap has one.
class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.displayName,
    required this.lat,
    required this.lng,
    required this.placeType,
    this.boundary = const [],
  });

  /// Short name (« Bastos »).
  final String name;

  /// Full name (« Bastos, Yaoundé I, Mfoundi, Centre, Cameroun »): tells
  /// apart places with the same name (two « Nkoabang »).
  final String displayName;
  final double lat;
  final double lng;

  /// OSM type: suburb, village, neighbourhood, quarter…
  final String placeType;

  /// Official outline (lat, lng); empty when OSM only has a point.
  final List<(double, double)> boundary;

  bool get hasBoundary => boundary.length >= 3;

  /// Circle radius used when there is no boundary, by kind of place.
  double get defaultRadiusMeters => switch (placeType) {
        'city' || 'town' => 4000,
        'village' || 'suburb' || 'quarter' => 1500,
        'neighbourhood' || 'hamlet' => 700,
        _ => 1000,
      };
}

/// Neighbourhood search + boundaries, from OpenStreetMap (Nominatim —
/// free, no key; max 1 request per second, so searches are explicit).
class PlaceBoundaryService {
  PlaceBoundaryService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Outlines are reduced to this many points (Firestore document size).
  static const maxPoints = 150;

  Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'countrycodes': 'cm',
      'limit': '6',
      'polygon_geojson': '1',
      'accept-language': 'fr',
      'q': q,
    });
    // Nominatim asks apps to identify themselves; browsers forbid setting
    // the User-Agent (they send their own).
    final res = await _client.get(uri, headers: {
      if (!kIsWeb) 'User-Agent': 'WastePro/1.0 (school project)',
    });
    if (res.statusCode != 200) {
      throw Exception('Map search unavailable (HTTP ${res.statusCode}).');
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return [
      for (final e in list.whereType<Map<String, dynamic>>()) _parse(e),
    ];
  }

  static PlaceResult _parse(Map<String, dynamic> e) {
    final display = e['display_name'] as String? ?? '';
    return PlaceResult(
      name: (e['name'] as String?)?.trim().isNotEmpty == true
          ? e['name'] as String
          : display.split(',').first.trim(),
      displayName: display,
      lat: double.tryParse('${e['lat']}') ?? 0,
      lng: double.tryParse('${e['lon']}') ?? 0,
      placeType: e['addresstype'] as String? ?? e['type'] as String? ?? '',
      boundary: simplify(_outline(e['geojson'])),
    );
  }

  /// Outer ring of a Polygon, or of the largest part of a MultiPolygon.
  static List<(double, double)> _outline(dynamic geojson) {
    if (geojson is! Map) return const [];
    List<(double, double)> ring(dynamic coords) => [
          for (final p in (coords as List))
            if (p is List && p.length >= 2)
              ((p[1] as num).toDouble(), (p[0] as num).toDouble()),
        ];
    switch (geojson['type']) {
      case 'Polygon':
        final rings = geojson['coordinates'] as List;
        return rings.isEmpty ? const [] : ring(rings.first);
      case 'MultiPolygon':
        var best = <(double, double)>[];
        for (final poly in geojson['coordinates'] as List) {
          if (poly is List && poly.isNotEmpty) {
            final r = ring(poly.first);
            if (r.length > best.length) best = r;
          }
        }
        return best;
      default:
        return const [];
    }
  }

  /// Keeps at most [maxPoints] evenly spread points of an outline.
  static List<(double, double)> simplify(List<(double, double)> points) {
    if (points.length <= maxPoints) return points;
    final step = points.length / maxPoints;
    return [
      for (var i = 0; i < maxPoints; i++) points[(i * step).floor()],
    ];
  }
}
