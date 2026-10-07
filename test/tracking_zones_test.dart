import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/backoffice/data/backoffice_store.dart';
import 'package:waste_pro/features/backoffice/models.dart';
import 'package:waste_pro/features/backoffice/pages/tracking_page.dart';
import 'package:waste_pro/services/live_tracking_service.dart';

const _square = ZoneArea(
  name: 'Bastos',
  kind: 'polygon',
  points: [(3.88, 11.49), (3.88, 11.53), (3.91, 11.53), (3.91, 11.49)],
  centerLat: 3.895,
  centerLng: 11.51,
  source: 'osm',
);

void main() {
  Future<void> pump(WidgetTester tester, {required double lat}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = BackofficeStore();
    final i = store.collecteurs.indexWhere((c) => c.id == 'co1');
    store.collecteurs[i] = store.collecteurs[i].copyWith(zoneArea: _square);

    // Live position of Paul (co1).
    final db = FakeFirebaseFirestore();
    await db.collection('collecteurs').doc('co1').set({
      'name': 'Paul Mbarga',
      'latitude': lat,
      'longitude': 11.51,
      'isTracking': true,
    });

    await tester.pumpWidget(MaterialApp(
      home: BoTrackingPage(
        store: store,
        trackingService: LiveTrackingService(db: db),
        showTiles: false,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("each collector's zone is shown with his name", (tester) async {
    await pump(tester, lat: 3.895);
    expect(find.text('Zones (1)'), findsOneWidget);
    expect(find.text('Paul Mbarga · Bastos'), findsOneWidget);

    // Hide / show.
    await tester.tap(find.byKey(const Key('tracking_zones_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Paul Mbarga · Bastos'), findsNothing);
  });

  testWidgets('selecting a collector says if he is inside his zone',
      (tester) async {
    await pump(tester, lat: 3.895); // inside the square
    await tester.tap(find.byKey(const Key('zone_label_co1')));
    await tester.pumpAndSettle();
    expect(find.text('Inside his zone (Bastos)'), findsOneWidget);
  });

  testWidgets('…or outside it', (tester) async {
    await pump(tester, lat: 3.95); // north of the square
    await tester.tap(find.byKey(const Key('zone_label_co1')));
    await tester.pumpAndSettle();
    expect(find.text('Outside his zone (Bastos)'), findsOneWidget);
  });
}
