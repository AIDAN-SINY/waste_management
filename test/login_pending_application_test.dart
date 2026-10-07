import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/auth/screens/login_screen.dart';

import 'fakes/fake_auth_backend.dart';

/// An application submitted BEFORE the Auth migration has no login account
/// (neither users/{phone} nor Auth account): the login must guide the
/// client according to their application status instead of the generic
/// "User not found".
void main() {
  Future<void> pumpLogin(WidgetTester tester, FakeFirebaseFirestore db) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(db: db, backend: FakeAuthBackend())),
    );
    // Fixed pump: the login logo has an infinite animation (no
    // pumpAndSettle).
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tryLogin(WidgetTester tester, String phone) async {
    await tester.enterText(find.byType(TextField).at(0), phone);
    await tester.enterText(find.byType(TextField).at(1), 'whatever');
    await tester.tap(find.text('Log In'));
    await tester.pump(); // lance _handleAuth
    await tester.pump(const Duration(milliseconds: 500)); // async requests
    await tester.pump(const Duration(milliseconds: 500)); // snackbar slide-in
  }

  testWidgets(
    'login with PENDING application → clear message (not "User not found")',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('registrations').doc('reg1').set({
        'id': 'reg1',
        'fullName': 'Carine Mbappe',
        'phone': '+237698224466',
        'status': 'pending',
        'agenceId': 'ag1',
        'agenceName': 'Yaoundé — Bastos',
      });

      await pumpLogin(tester, db);
      await tryLogin(tester, '698 22 44 66');

      expect(find.textContaining('pending approval'), findsOneWidget);
      expect(find.textContaining('User not found'), findsNothing);
    },
  );

  testWidgets('login with REJECTED application → dedicated message', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('registrations').doc('reg1').set({
      'id': 'reg1',
      'fullName': 'Carine Mbappe',
      'phone': '+237698224466',
      'status': 'rejected',
      'agenceId': 'ag1',
    });

    await pumpLogin(tester, db);
    await tryLogin(tester, '698 22 44 66');

    expect(find.textContaining('was rejected'), findsOneWidget);
  });

  testWidgets(
    'login with no account or application → "User not found" preserved',
    (tester) async {
      final db = FakeFirebaseFirestore();

      await pumpLogin(tester, db);
      await tryLogin(tester, '698 22 44 66');

      expect(
        find.text('User not found. Please sign up first.'),
        findsOneWidget,
      );
    },
  );
}
