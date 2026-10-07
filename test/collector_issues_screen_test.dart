import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waste_pro/features/home/collector_issues_screen.dart';
import 'package:waste_pro/services/functions_client.dart';
import 'package:waste_pro/services/notification_service.dart';

void main() {
  const me = '+237678901122';

  Future<FakeFirebaseFirestore> seeded() async {
    final db = FakeFirebaseFirestore();
    await db.collection('issues').doc('i1').set({
      'id': 'i1',
      'client_id': '+237677123456',
      'client_name': 'Jean Dooh',
      'category': 'Overflowing bin',
      'description': 'Not emptied for a week.',
      'location': 'Bastos',
      'status': 'assigned',
      'created_at': '2026-10-07',
      'assignedCollecteurId': 'co1',
      'assignedCollectorName': 'Paul Mbarga',
      'assignedCollectorPhone': me,
    });
    // Someone else's issue and an already resolved one: not shown.
    await db.collection('issues').doc('i2').set({
      'id': 'i2', 'status': 'assigned', 'created_at': '2026-10-07',
      'category': 'Other', 'assignedCollectorPhone': '+237690000001',
    });
    await db.collection('issues').doc('i3').set({
      'id': 'i3', 'status': 'resolved', 'created_at': '2026-10-06',
      'category': 'Done', 'assignedCollectorPhone': me,
    });
    return db;
  }

  testWidgets('banner → list → start → resolve, client notified each step',
      (tester) async {
    final db = await seeded();
    final events = <Map<String, dynamic>>[];
    final notifications = NotificationService(
      db: db,
      functions: FunctionsClient(
        client: MockClient((request) async {
          events.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"ok":true}', 200);
        }),
        baseUrl: 'https://functions.test',
        idToken: () async => 'id-token',
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CollectorIssuesBanner(
          db: db,
          collectorPhone: me,
          notifications: notifications,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 issue assigned to you'), findsOneWidget);
    await tester.tap(find.byKey(const Key('collector_issues_banner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('collector_issue_i1')), findsOneWidget);
    expect(find.byKey(const Key('collector_issue_i2')), findsNothing);
    expect(find.byKey(const Key('collector_issue_i3')), findsNothing);

    await tester.tap(find.byKey(const Key('issue_start_i1')));
    await tester.pumpAndSettle();
    expect((await db.collection('issues').doc('i1').get()).data()!['status'],
        'in_progress');
    expect(find.byKey(const Key('issue_resolve_i1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('issue_resolve_i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolved'));
    await tester.pumpAndSettle();
    expect((await db.collection('issues').doc('i1').get()).data()!['status'],
        'resolved');
    expect(find.text('No issue assigned to you.'), findsOneWidget);

    expect(events, [
      {'event': 'issue_started', 'issueId': 'i1'},
      {'event': 'issue_resolved', 'issueId': 'i1'},
    ]);
  });
}
