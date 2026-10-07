import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/superadmin/data/firestore_platform_store.dart';
import 'package:waste_pro/features/superadmin/data/platform_store.dart';
import 'package:waste_pro/features/superadmin/super_admin_console.dart';

import 'fakes/fake_auth_backend.dart';

import 'helpers/setup_firebase.dart';

/// Regression: "A FirestorePlatformStore was used after being disposed".
///
/// Real scenario that triggered the error:
///   1. Super admin session → console mounted with the SHARED Firestore store
///      (ConsoleStoreScope).
///   2. Debug logout → router rebuilds the console WITHOUT a store
///      (mock preview) before unmounting it.
///   3. On unmount, dispose() saw widget.store == null and disposed the
///      shared store it had NOT created.
///   4. On next login, the disposed store was reused → the error.
void main() {
  setUpAll(() => setupFirebaseMocks());

  testWidgets(
      'the shared Firestore store survives console unmount and '
      'can be reused', (tester) async {
    final db = FakeFirebaseFirestore();
    final store = FirestorePlatformStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
      isSignedOut: () => false,
    );
    await store.initialLoad;

    // 1. Real session: console mounted with the shared store.
    await tester.pumpWidget(
      MaterialApp(home: SuperAdminConsole(store: store, db: FakeFirebaseFirestore())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 2. Debug logout: router rebuilds the console WITHOUT a store.
    await tester.pumpWidget(
      MaterialApp(home: SuperAdminConsole(db: FakeFirebaseFirestore())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 3. Full unmount (return to home screen).
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 4. The shared store must remain usable (not "used after
    //    disposed") and reusable by the next login.
    expect(() => store.load(), returnsNormally);
    await store.initialLoad;
    expect(store.error, isNull);

    // Effective reuse by a new console.
    await tester.pumpWidget(
      MaterialApp(home: SuperAdminConsole(store: store, db: FakeFirebaseFirestore())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    store.dispose();
  });

  testWidgets('the console never disposes an injected store', (tester) async {
    // A provided store (even a mock) belongs to its creator: the console's
    // unmount must not dispose it (notifyListeners would throw if so).
    final injected = PlatformStore();
    await tester.pumpWidget(
      MaterialApp(home: SuperAdminConsole(store: injected, db: FakeFirebaseFirestore())),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pumpAndSettle();

    expect(() => injected.notifyListeners(), returnsNormally,
        reason: 'the injected store must remain usable after unmount');
  });
}
