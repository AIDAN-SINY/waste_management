import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/auth/screens/application_status_screen.dart';
import 'package:waste_pro/features/auth/screens/pre_register_screen.dart';

/// "Application status" screen: the client tracks their application live
/// (pending → approved/rejected) and can resubmit after a rejection.
void main() {
  Future<FakeFirebaseFirestore> seedDb({String status = 'pending'}) async {
    final db = FakeFirebaseFirestore();
    await db.collection('registrations').doc('reg1').set({
      'id': 'reg1',
      'fullName': 'Carine Mbappe',
      'phone': '+237698224466',
      'zone': 'Bonanjo',
      'agenceId': 'ag1',
      'agenceName': 'Yaoundé — Bastos',
      'societeId': 'so1',
      'status': status,
      'collecteurId': '',
      'password': 'secret123',
      'createdAt': '2026-08-10',
    });
    return db;
  }

  Future<void> pumpStatus(
    WidgetTester tester,
    FakeFirebaseFirestore db, {
    String initialPhone = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApplicationStatusScreen(db: db, initialPhone: initialPhone),
      ),
    );
    await tester.pump();
  }

  Future<void> checkStatus(WidgetTester tester, String phone) async {
    await tester.enterText(find.byType(TextField), phone);
    await tester.tap(find.text('Check status'));
    // The 150 ms button delay + the stream.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  testWidgets('candidature en attente → carte « Under review »', (tester) async {
    final db = await seedDb();
    await pumpStatus(tester, db);
    await checkStatus(tester, '698 22 44 66');

    expect(find.text('Under review'), findsOneWidget);
    expect(find.text('Application rejected'), findsNothing);
    expect(find.text('Approved!'), findsNothing);
  });

  testWidgets('approved application → green card + login button', (
    tester,
  ) async {
    final db = await seedDb(status: 'approved');
    await pumpStatus(tester, db);
    await checkStatus(tester, '698 22 44 66');

    expect(find.text('Approved!'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Re-apply'), findsNothing);
  });

  testWidgets('rejected application → red card + Re-apply button', (
    tester,
  ) async {
    final db = await seedDb(status: 'rejected');
    await pumpStatus(tester, db);
    await checkStatus(tester, '698 22 44 66');

    expect(find.text('Application rejected'), findsOneWidget);
    expect(find.text('Re-apply'), findsOneWidget);
    expect(find.text('Go to login'), findsNothing);
  });

  testWidgets('aucune candidature → « No application found » + Apply now', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await pumpStatus(tester, db);
    await checkStatus(tester, '698 22 44 66');

    expect(find.text('No application found'), findsOneWidget);
    expect(find.text('Apply now'), findsOneWidget);
  });

  testWidgets(
    'the card updates LIVE when the agency manager decides',
    (tester) async {
      final db = await seedDb(status: 'pending');
      await pumpStatus(tester, db);
      await checkStatus(tester, '698 22 44 66');
      expect(find.text('Under review'), findsOneWidget);

      // The agency manager approves → the screen switches on its own (stream).
      await db.collection('registrations').doc('reg1').update({
        'status': 'approved',
        'collecteurId': 'co1',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Approved!'), findsOneWidget);
      expect(find.text('Under review'), findsNothing);
    },
  );

  testWidgets(
    'Re-apply after rejection → form pre-filled with preserved info',
    (tester) async {
      final db = await seedDb(status: 'rejected');
      await pumpStatus(tester, db);
      await checkStatus(tester, '698 22 44 66');

      await tester.ensureVisible(find.text('Re-apply'));
      await tester.tap(find.text('Re-apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PreRegisterScreen), findsOneWidget);
      // The form is pre-filled with the name / phone / zone of the
      // rejected application.
      final fields = find.byType(TextFormField);
      expect(fields, findsWidgets);
      final nameField = tester.widget<TextFormField>(fields.at(0));
      expect((nameField.controller?.text ?? '').trim(), 'Carine Mbappe');
      final phoneField = tester.widget<TextFormField>(fields.at(1));
      expect(phoneField.controller?.text, '+237698224466');
      final zoneField = tester.widget<TextFormField>(fields.at(2));
      expect(zoneField.controller?.text, 'Bonanjo');
    },
  );

  testWidgets('empty number → toast instead of searching', (tester) async {
    final db = FakeFirebaseFirestore();
    await pumpStatus(tester, db);

    await tester.tap(find.text('Check status'));
    await tester.pump();

    expect(find.text('Enter your phone number'), findsOneWidget);
  });
}
