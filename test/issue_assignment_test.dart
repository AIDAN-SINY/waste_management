import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/backoffice/data/backoffice_store.dart';
import 'package:waste_pro/features/backoffice/data/firestore_backoffice_store.dart';
import 'package:waste_pro/features/backoffice/models.dart';
import 'package:waste_pro/features/backoffice/pages/issues_page.dart';

import 'fakes/fake_auth_backend.dart';

/// Same collector, sharing his live position [minutesAgo] minutes ago.
CollecteurModel tracked(CollecteurModel c, {int minutesAgo = 2}) =>
    CollecteurModel(
      id: c.id,
      name: c.name,
      phone: c.phone,
      zone: c.zone,
      rating: c.rating,
      status: c.status,
      isTracking: true,
      lastPositionUpdate:
          DateTime.now().subtract(Duration(minutes: minutesAgo)),
    );

const issue = IssueModel(
  id: 'i1',
  clientId: '+237677123456', // Jean Dooh — his collector is co1
  clientName: 'Jean Dooh',
  category: 'Overflowing bin',
  description: 'The bin has not been emptied for a week.',
  location: 'Bastos, near the bakery',
  status: 'open',
  createdAt: '2026-10-07',
);

/// Seed store: Paul (co1) and Vincent (co2) on duty, Serge (co4) off
/// duty, André (co3) inactive.
BackofficeStore seededStore() {
  final store = BackofficeStore();
  for (final id in ['co1', 'co2']) {
    final i = store.collecteurs.indexWhere((c) => c.id == id);
    store.collecteurs[i] = tracked(store.collecteurs[i]);
  }
  store.issues.add(issue);
  return store;
}

void main() {
  group('collector availability', () {
    final now = DateTime(2026, 10, 7, 10);
    CollecteurModel collector({
      String status = 'Active',
      bool tracking = true,
      int minutesAgo = 2,
    }) =>
        CollecteurModel(
          id: 'c',
          name: 'C',
          phone: '+237600000000',
          zone: 'Bastos',
          rating: 4,
          status: status,
          isTracking: tracking,
          lastPositionUpdate: now.subtract(Duration(minutes: minutesAgo)),
        );

    test('on duty with few issues → available, many → busy', () {
      expect(collectorAvailability(collector(), openIssues: 0, now: now),
          CollectorAvailability.available);
      expect(
          collectorAvailability(collector(),
              openIssues: kBusyIssueCount, now: now),
          CollectorAvailability.busy);
    });

    test('not sharing his position, or for too long → off duty', () {
      expect(
          collectorAvailability(collector(tracking: false),
              openIssues: 0, now: now),
          CollectorAvailability.offDuty);
      expect(
          collectorAvailability(collector(minutesAgo: 20),
              openIssues: 0, now: now),
          CollectorAvailability.offDuty);
    });

    test('suspended / inactive → cannot be assigned', () {
      expect(
          collectorAvailability(collector(status: 'Suspended'),
              openIssues: 0, now: now),
          CollectorAvailability.inactive);
    });
  });

  group('ranking', () {
    test("available first, the client's own collector on top", () {
      final ranked = rankCollectorsForIssue(seededStore(), issue);
      expect(ranked.map((c) => c.collecteur.id), ['co1', 'co2', 'co4', 'co3']);
      expect(ranked.first.isClientsCollector, isTrue);
      expect(ranked.map((c) => c.availability), [
        CollectorAvailability.available,
        CollectorAvailability.available,
        CollectorAvailability.offDuty,
        CollectorAvailability.inactive,
      ]);
    });

    test("a collector whose circled zone contains the client comes next", () {
      final store = seededStore();
      // Vincent (co2) gets a zone around Jean Dooh's address (3.8665,
      // 11.5155); Paul (co1) stays the client's own collector.
      final i = store.collecteurs.indexWhere((c) => c.id == 'co2');
      final v = store.collecteurs[i];
      store.collecteurs[i] = CollecteurModel(
        id: v.id,
        name: v.name,
        phone: v.phone,
        zone: 'Elsewhere',
        rating: 1, // lowest rating: only the zone puts him ahead
        status: v.status,
        isTracking: true,
        lastPositionUpdate: DateTime.now(),
        zoneArea: const ZoneArea(
          name: 'Bastos',
          kind: 'circle',
          centerLat: 3.8665,
          centerLng: 11.5155,
          radiusMeters: 800,
        ),
      );
      // Paul unavailable (off duty) → Vincent first, marked as covering.
      final p = store.collecteurs.indexWhere((c) => c.id == 'co1');
      final paul = store.collecteurs[p];
      store.collecteurs[p] = CollecteurModel(
        id: paul.id,
        name: paul.name,
        phone: paul.phone,
        zone: paul.zone,
        rating: paul.rating,
        status: paul.status,
      );
      final ranked = rankCollectorsForIssue(store, issue);
      expect(ranked.first.collecteur.id, 'co2');
      expect(ranked.first.coversClient, isTrue);
    });

    test('a collector with too many issues in progress becomes busy', () {
      final store = seededStore();
      for (var i = 0; i < kBusyIssueCount; i++) {
        store.issues.add(issue.copyWith(
            status: 'in_progress', assignedCollecteurId: 'co1'));
      }
      final ranked = rankCollectorsForIssue(store, issue);
      expect(ranked.first.collecteur.id, 'co2');
      expect(ranked.firstWhere((c) => c.collecteur.id == 'co1').availability,
          CollectorAvailability.busy);
    });
  });

  testWidgets('the manager assigns an issue from the issues page',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = seededStore();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BoIssuesPage(store: store)),
    ));

    await tester.tap(find.byKey(const Key('issue_assign_i1')));
    await tester.pumpAndSettle();
    expect(find.text('Assign this issue'), findsOneWidget);
    expect(find.text('Available'), findsNWidgets(2));
    expect(find.text('Off duty'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);

    // The inactive collector cannot be picked; choose Vincent instead of
    // the pre-selected Paul.
    await tester.tap(find.byKey(const Key('assign_option_co3')));
    await tester.tap(find.byKey(const Key('assign_option_co2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('issue_assign_confirm')));
    await tester.pumpAndSettle();

    final assigned = store.issues.single;
    expect(assigned.status, 'assigned');
    expect(assigned.assignedCollecteurId, 'co2');
    expect(find.text('Assigned to Vincent Onana'), findsOneWidget);
    expect(find.text('Reassign'), findsOneWidget);
  });

  test('Firestore store: assignment saved + collector notified', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('issues').doc('i1').set(issue.toMap());
    final notified = <String>[];
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
      notifyIssueAssigned: (id) async => notified.add(id),
    );
    await store.initialLoad;

    await store.assignIssue(issue, tracked(seededStore().collecteurs.first));

    final saved = (await db.collection('issues').doc('i1').get()).data()!;
    expect(saved['status'], 'assigned');
    expect(saved['assignedCollecteurId'], 'co1');
    expect(saved['assignedCollectorPhone'], '+237678901122');
    expect(notified, ['i1']);
    store.dispose();
  });
}
