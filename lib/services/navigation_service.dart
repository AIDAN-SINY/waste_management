import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Navigation service providing real road-based routing and GPS navigation.
///
/// Uses:
///   - **OSRM (Open Source Routing Machine)** for route calculation
///     via the public demo server (no API key needed).
///   - **Google Maps** for turn-by-turn GPS navigation on the device.
///
/// OSRM provides the route geometry (polyline) and road distance/duration.
/// Google Maps provides the actual turn-by-turn navigation experience.
class NavigationService {
  NavigationService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  // OSRM public demo server (for development/testing).
  // In production, consider self-hosting or using a paid OSRM instance.
  static const String _osrmBase = 'https://router.project-osrm.org';

  /// Fetches a real road-based route between [origin] and [destination].
  ///
  /// Returns a [RouteResult] with the route geometry (list of LatLng points),
  /// road distance in meters, and estimated duration in seconds.
  /// Falls back to a straight line if the API call fails.
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      // OSRM expects coordinates as lng,lat (note the reversed order).
      final url = '$_osrmBase/route/v1/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=geojson&steps=true';

      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = body['routes'] as List<dynamic>?;

        if (routes != null && routes.isNotEmpty) {
          final route = routes[0] as Map<String, dynamic>;
          final distance = (route['distance'] as num?)?.toDouble() ?? 0;
          final duration = (route['duration'] as num?)?.toDouble() ?? 0;
          final geometry = route['geometry'] as Map<String, dynamic>?;

          final points = _decodeGeoJson(geometry);

          debugPrint('[Navigation] Route: ${(distance / 1000).toStringAsFixed(1)} km, '
              '${(duration / 60).round()} min, ${points.length} points');

          return RouteResult(
            points: points,
            distanceMeters: distance,
            durationSeconds: duration,
          );
        }
      }
    } catch (e) {
      debugPrint('[Navigation] OSRM error: $e');
    }

    // Fallback: straight line.
    return RouteResult(
      points: [origin, destination],
      distanceMeters: _haversineMeters(origin, destination),
      durationSeconds: _haversineMeters(origin, destination) / 500, // ~18 km/h avg
    );
  }

  /// Decodes a GeoJSON geometry from OSRM into a list of LatLng points.
  List<LatLng> _decodeGeoJson(Map<String, dynamic>? geometry) {
    if (geometry == null) return [];
    final coords = geometry['coordinates'] as List<dynamic>? ?? [];
    return coords.map((coord) {
      final c = coord as List<dynamic>;
      return LatLng(c[1] as double, c[0] as double); // GeoJSON is [lng, lat]
    }).toList();
  }

  /// Haversine distance in meters between two points.
  double _haversineMeters(LatLng a, LatLng b) {
    return const Distance().as(LengthUnit.Meter, a, b);
  }

  /// Opens Google Maps for turn-by-turn navigation from [origin] to [destination].
  ///
  /// Uses the Google Maps intent URL which works on both Android and iOS.
  /// Falls back to Apple Maps on iOS if Google Maps is not installed.
  Future<bool> openNavigation({
    required LatLng origin,
    required LatLng destination,
    String? destinationName,
  }) async {
    final destName = destinationName ?? 'Destination';

    // Google Maps URL for navigation:
    // https://www.google.com/maps/dir/?api=1&origin=lat,lng&destination=lat,lng&travelmode=driving
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&travelmode=driving',
    );

    // Apple Maps URL (iOS fallback):
    // https://maps.apple.com/?sll=lat,lng&daddr=lat,lng&dirflg=d
    final appleMapsUrl = Uri.parse(
      'https://maps.apple.com/?'
      'sll=${destination.latitude},${destination.longitude}'
      '&daddr=${destination.latitude},${destination.longitude}'
      '&dirflg=d',
    );

    try {
      // Try Google Maps first.
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
        return true;
      }

      // Fallback to Apple Maps (iOS).
      if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint('[Navigation] Failed to launch maps: $e');
    }

    // Last resort: open in browser.
    try {
      await launchUrl(googleMapsUrl, mode: LaunchMode.inAppWebView);
      return true;
    } catch (_) {
      debugPrint('[Navigation] Could not open any navigation app');
      return false;
    }
  }

  /// Formats a duration in seconds to a human-readable string.
  static String formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final hours = mins ~/ 60;
    final remainMins = mins % 60;
    return '${hours}h ${remainMins}m';
  }

  /// Formats a distance in meters to a human-readable string.
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

/// Result of a route calculation.
class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  /// The route geometry as a list of LatLng points.
  final List<LatLng> points;

  /// Total road distance in meters.
  final double distanceMeters;

  /// Estimated travel duration in seconds.
  final double durationSeconds;

  /// Distance formatted for display (e.g. '2.3 km').
  String get distanceFormatted => NavigationService.formatDistance(distanceMeters);

  /// Duration formatted for display (e.g. '12 min').
  String get durationFormatted => NavigationService.formatDuration(durationSeconds);
}
