import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:waste_pro/services/navigation_service.dart';

void main() {
  group('NavigationService.formatDuration', () {
    test('formats minutes under 60', () {
      expect(NavigationService.formatDuration(300), '5 min'); // 300s = 5min
      expect(NavigationService.formatDuration(60), '1 min');
      expect(NavigationService.formatDuration(3540), '59 min'); // 59min
    });

    test('formats hours and minutes', () {
      expect(NavigationService.formatDuration(3600), '1h 0m');
      expect(NavigationService.formatDuration(5400), '1h 30m');
      expect(NavigationService.formatDuration(7200), '2h 0m');
    });

    test('rounds to nearest minute', () {
      expect(NavigationService.formatDuration(90), '2 min'); // 1.5min rounds to 2
      expect(NavigationService.formatDuration(30), '1 min'); // 0.5min rounds to 1
    });
  });

  group('NavigationService.formatDistance', () {
    test('formats meters under 1000', () {
      expect(NavigationService.formatDistance(500), '500 m');
      expect(NavigationService.formatDistance(1), '1 m');
      expect(NavigationService.formatDistance(999), '999 m');
    });

    test('formats kilometers', () {
      expect(NavigationService.formatDistance(1000), '1.0 km');
      expect(NavigationService.formatDistance(2350), '2.4 km');
      expect(NavigationService.formatDistance(15000), '15.0 km');
    });
  });

  group('RouteResult', () {
    test('formatted getters work correctly', () {
      final result = RouteResult(
        points: const [LatLng(3.85, 11.51), LatLng(3.86, 11.52)],
        distanceMeters: 1500,
        durationSeconds: 900,
      );

      expect(result.distanceFormatted, '1.5 km');
      expect(result.durationFormatted, '15 min');
      expect(result.points.length, 2);
    });

    test('short distance formats as meters', () {
      final result = RouteResult(
        points: const [],
        distanceMeters: 450,
        durationSeconds: 120,
      );

      expect(result.distanceFormatted, '450 m');
      expect(result.durationFormatted, '2 min');
    });
  });

  group('NavigationService.getRoute', () {
    test('returns fallback straight-line route when API fails', () async {
      final service = NavigationService();

      final result = await service.getRoute(
        origin: const LatLng(3.8665, 11.5155),
        destination: const LatLng(3.8480, 11.5021),
      );

      expect(result.points.length, greaterThanOrEqualTo(2));
      expect(result.distanceMeters, greaterThan(0));
      expect(result.durationSeconds, greaterThan(0));
    });
  });
}
