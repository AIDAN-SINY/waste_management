import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:waste_pro/firebase_options.dart';
import 'package:waste_pro/features/superadmin/data/firestore_platform_store.dart';
import 'package:waste_pro/features/superadmin/super_admin_console.dart';

/// Lets real-time snapshot listeners propagate (real Firestore round-trips).
Future<void> _settle(WidgetTester tester, [int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'admin console E2E: creating a company persisted in Firestore',
    (tester) async {
      // Desktop viewport so the console renders the table layout.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Real Firebase (production project waste-pro-f67a5).
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // The exact store the super admin login uses.
      final store = FirestorePlatformStore();
      await store.initialLoad;
      await _settle(tester);
      expect(
        store.error,
        isNull,
        reason: 'Firestore rules — ${store.error ?? 'ok'}',
      );

      await tester.pumpWidget(
        MaterialApp(home: SuperAdminConsole(store: store)),
      );
      await _settle(tester, 10);

      // 1) Navigate to the Companies page.
      await tester.tap(find.text('Companies'));
      await _settle(tester, 10);

      // 2) Open the "New company" drawer.
      await tester.tap(find.text('New company'));
      await _settle(tester, 10);
      expect(find.text('Company name'), findsOneWidget);

      // 3) Fill in the form (unique name for this run).
      final name = 'Test E2E ${DateTime.now().millisecondsSinceEpoch}';
      await tester.enterText(find.byType(TextFormField).at(0), name);
      await tester.enterText(find.byType(TextFormField).at(1), 'Yaoundé E2E');
      await tester.pump();

      // 4) Save → Firestore write + table update.
      await tester.tap(find.text('Save'));
      await _settle(tester, 15);

      expect(
        find.text(name),
        findsOneWidget,
        reason: 'The company must appear in the console table',
      );

      // 5) Proof of persistence: read directly from Firestore.
      final snapshot = await FirebaseFirestore.instance
          .collection('societes')
          .where('raisonSociale', isEqualTo: name)
          .get();
      expect(
        snapshot.docs,
        isNotEmpty,
        reason: 'The company must be actually persisted in Firestore',
      );

      // 6) Cleanup: delete the test company and verify real-time sync.
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
      await _settle(tester, 15);
      expect(
        find.text(name),
        findsNothing,
        reason: 'After Firestore deletion, the row must disappear',
      );

      // Flush les toasts automatiques.
      await tester.pump(const Duration(seconds: 4));
      store.dispose();
    },
  );
}
