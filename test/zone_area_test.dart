import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waste_pro/features/backoffice/models.dart';
import 'package:waste_pro/features/backoffice/widgets/zone_area_picker.dart';
import 'package:waste_pro/services/place_boundary_service.dart';

/// Nominatim-like answers: Bastos has its boundary, Nkoabang (two
/// villages) only a point — as in OpenStreetMap today.
const _bastos = {
  'name': 'Bastos',
  'display_name': 'Bastos, Yaoundé I, Mfoundi, Centre, Cameroun',
  'lat': '3.894',
  'lon': '11.510',
  'addresstype': 'suburb',
  'geojson': {
    'type': 'Polygon',
    'coordinates': [
      [
        [11.499, 3.883], [11.522, 3.883], [11.522, 3.905], [11.499, 3.905],
        [11.499, 3.883],
      ],
    ],
  },
};
const _nkoabang = [
  {
    'name': 'Nkoabang',
    'display_name': 'Nkoabang, Nkolafamba, Méfou-et-Afamba, Centre, Cameroun',
    'lat': '3.864',
    'lon': '11.587',
    'addresstype': 'village',
    'geojson': {'type': 'Point', 'coordinates': [11.587, 3.864]},
  },
  {
    'name': 'Nkoabang',
    'display_name': 'Nkoabang, Mbankomo, Méfou-et-Akono, Centre, Cameroun',
    'lat': '3.662',
    'lon': '11.421',
    'addresstype': 'village',
    'geojson': {'type': 'Point', 'coordinates': [11.421, 3.662]},
  },
];

PlaceBoundaryService fakeService() => PlaceBoundaryService(
      client: MockClient((request) async {
        final q = request.url.queryParameters['q']!.toLowerCase();
        final body = q.contains('bastos')
            ? [_bastos]
            : q.contains('nkoabang')
                ? _nkoabang
                : <Object>[];
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );

void main() {
  group('ZoneArea', () {
    const square = ZoneArea(
      name: 'Bastos',
      kind: 'polygon',
      points: [(3.883, 11.499), (3.883, 11.522), (3.905, 11.522), (3.905, 11.499)],
      centerLat: 3.894,
      centerLng: 11.510,
      source: 'osm',
    );

    test('saved and read back (points as maps, Firestore-safe)', () {
      final map = square.toMap();
      expect(map['points'], isA<List>());
      expect((map['points'] as List).first, {'lat': 3.883, 'lng': 11.499});
      final back = ZoneArea.fromMap(map)!;
      expect(back.points, square.points);
      expect(back.source, 'osm');
      expect(back.isPolygon, isTrue);
    });

    test('contains: polygon and circle', () {
      expect(square.contains(3.894, 11.510), isTrue);
      expect(square.contains(3.95, 11.510), isFalse);
      const circle = ZoneArea(
        name: 'Nkoabang',
        kind: 'circle',
        centerLat: 3.864,
        centerLng: 11.587,
        radiusMeters: 1500,
      );
      expect(circle.contains(3.870, 11.590), isTrue); // ~760 m
      expect(circle.contains(3.900, 11.587), isFalse); // ~4 km
    });

    test('a collector keeps his zone through toMap / fromMap', () {
      const c = CollecteurModel(
        id: 'co9',
        name: 'Paul',
        phone: '+237600000000',
        zone: 'Bastos',
        rating: 0,
        status: 'Active',
        zoneArea: square,
      );
      final back = CollecteurModel.fromMap(c.toMap());
      expect(back.zoneArea?.name, 'Bastos');
      expect(back.zoneArea?.points.length, 4);
    });
  });

  group('PlaceBoundaryService', () {
    test('official boundary when OSM has it, point otherwise', () async {
      final service = fakeService();
      final bastos = await service.search('Bastos');
      expect(bastos.single.hasBoundary, isTrue);
      expect(bastos.single.boundary.first, (3.883, 11.499)); // (lat, lng)

      final nkoabang = await service.search('Nkoabang');
      expect(nkoabang, hasLength(2));
      expect(nkoabang.every((p) => !p.hasBoundary), isTrue);
      expect(nkoabang.first.defaultRadiusMeters, 1500);
    });

    test('long outlines are reduced', () {
      final long = [for (var i = 0; i < 600; i++) (i.toDouble(), 0.0)];
      expect(PlaceBoundaryService.simplify(long),
          hasLength(PlaceBoundaryService.maxPoints));
    });
  });

  group('ZoneAreaPickerScreen', () {
    Future<List<ZoneArea?>> open(WidgetTester tester) async {
      final results = <ZoneArea?>[];
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => results.add(
                  await Navigator.of(context).push<ZoneArea>(
                    MaterialPageRoute(
                      builder: (_) => ZoneAreaPickerScreen(
                        service: fakeService(),
                        showTiles: false,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    Future<void> search(WidgetTester tester, String q) async {
      await tester.enterText(find.byKey(const Key('zone_area_query')), q);
      await tester.tap(find.byKey(const Key('zone_area_search')));
      await tester.pumpAndSettle();
    }

    testWidgets('Bastos: its official limits are circled', (tester) async {
      final results = await open(tester);
      await search(tester, 'Bastos');

      expect(find.textContaining('Official limits of Bastos'), findsOneWidget);
      await tester.tap(find.byKey(const Key('zone_area_confirm')));
      await tester.pumpAndSettle();

      final area = results.single!;
      expect(area.source, 'osm');
      expect(area.isPolygon, isTrue);
      expect(area.name, 'Bastos');
    });

    testWidgets(
        'Nkoabang: pick the right one, circle by default, or draw it exactly',
        (tester) async {
      final results = await open(tester);
      await search(tester, 'Nkoabang');

      // Two places share the name: the manager picks one.
      expect(find.text('2 places found — choose the right one:'),
          findsOneWidget);
      expect(find.text('Approximate'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('zone_area_result_0')));
      await tester.pumpAndSettle();
      expect(find.textContaining('exact limits of Nkoabang are not on the map'),
          findsOneWidget);
      expect(find.byKey(const Key('zone_area_radius')), findsOneWidget);

      // Draw the exact zone: 4 taps on the map.
      await tester.tap(find.byKey(const Key('zone_area_draw')));
      await tester.pumpAndSettle();
      final map = tester.getRect(find.byType(ZoneAreaPickerScreen));
      final c = map.center;
      for (final o in const [Offset(-60, -60), Offset(60, -60),
          Offset(60, 40), Offset(-60, 40)]) {
        await tester.tapAt(c + o);
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('Zone drawn with 4 points'), findsOneWidget);

      await tester.tap(find.byKey(const Key('zone_area_confirm')));
      await tester.pumpAndSettle();
      final area = results.single!;
      expect(area.source, 'drawn');
      expect(area.points, hasLength(4));
      expect(area.name, 'Nkoabang');
    });

    testWidgets('unknown place → message, confirm stays disabled',
        (tester) async {
      await open(tester);
      await search(tester, 'Zzzz');
      expect(find.byKey(const Key('zone_area_error')), findsOneWidget);
      final confirm = tester.widget<TextButton>(
          find.byKey(const Key('zone_area_confirm')));
      expect(confirm.onPressed, isNull);
    });
  });
}
