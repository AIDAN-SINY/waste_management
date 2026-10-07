import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waste_pro/features/backoffice/backoffice_screen.dart';
import 'package:waste_pro/features/backoffice/data/backoffice_store.dart';
import 'package:waste_pro/features/superadmin/data/platform_store.dart';
import 'package:waste_pro/main.dart';
import 'package:waste_pro/providers/user_provider.dart';
import 'package:waste_pro/services/auth_service.dart';

import 'fakes/fake_auth_backend.dart';
import 'fakes/fake_notification_provider.dart';
import 'package:waste_pro/providers/notification_provider.dart';

import 'helpers/setup_firebase.dart';

/// Backend whose signOut NEVER completes (simulates a stuck Firebase signOut
/// (web/desktop plugin, network...): the logout must still clear
/// the app-side session, otherwise the user stays trapped in the backoffice
/// and cannot log in with a different account.
class _HangingSignOutBackend extends FakeAuthBackend {
  @override
  Future<void> signOut() => Completer<void>().future; // never resolves
}

void main() {
  setUpAll(() => setupFirebaseMocks());

  Future<(FakeFirebaseFirestore, FakeAuthBackend, UserProvider)> pumpApp(
    WidgetTester tester,
    FakeAuthBackend backend,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('+237656778990').set({
      'phoneNumber': '+237656778990',
      'fullName': 'Chef A',
      'role': 'agency_manager',
      'agenceId': 'ag1',
    });
    await db.collection('users').doc('+237674738258').set({
      'phoneNumber': '+237674738258',
      'fullName': 'Chef B',
      'role': 'agency_manager',
      'agenceId': 'ag2',
    });

    final userProvider = UserProvider(backend: backend);
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: userProvider,
        child: ChangeNotifierProvider<NotificationProvider>.value(
          value: FakeNotificationProvider(),
          child: WasteProApp(
            consoleStore: PlatformStore(),
            backofficeStore: BackofficeStore(),
            db: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (db, backend, userProvider);
  }

  Future<void> loginAs(
    WidgetTester tester,
    FakeFirebaseFirestore db,
    FakeAuthBackend backend,
    UserProvider userProvider,
    String phone,
    String password,
  ) async {
    final auth = AuthService(db: db, backend: backend);
    final user = await auth.login(phone, password);
    expect(user, isNotNull);
    await userProvider.setUser(user!);
    await tester.pumpAndSettle();
  }

  testWidgets('login A → logout → login B (real flow)', (tester) async {
    final backend = FakeAuthBackend()
      ..seedAccount('237656778990@wastepro.cm', 'mdpA')
      ..seedAccount('237674738258@wastepro.cm', 'mdpB');
    final (db, _, userProvider) = await pumpApp(tester, backend);

    // Login A → backoffice.
    await loginAs(tester, db, backend, userProvider, '+237656778990', 'mdpA');
    expect(find.byType(BackofficeScreen), findsOneWidget);

    // Logout (normal backend signOut) → back to home.
    await userProvider.logout();
    await tester.pumpAndSettle();
    expect(find.byType(BackofficeScreen), findsNothing);
    expect(find.text('Log In'), findsOneWidget);
    expect(userProvider.user, isNull);

    // Login B → backoffice de B.
    await loginAs(tester, db, backend, userProvider, '+237674738258', 'mdpB');
    expect(find.byType(BackofficeScreen), findsOneWidget);
    expect(userProvider.user!.fullName, 'Chef B');
  });

  testWidgets(
    'logout clears the session even if the backend signOut never completes',
    (tester) async {
      final backend = _HangingSignOutBackend()
        ..seedAccount('237656778990@wastepro.cm', 'mdpA')
        ..seedAccount('237674738258@wastepro.cm', 'mdpB');
      final (db, _, userProvider) = await pumpApp(tester, backend);

      // Login A (via AuthService, like the login screen).
      await loginAs(tester, db, backend, userProvider, '+237656778990', 'mdpA');
      expect(find.byType(BackofficeScreen), findsOneWidget);

      // Logout: the backend signOut is stuck, but the app session MUST
      // be cleared (back to home + ability to log in again).
      unawaited(userProvider.logout());
      await tester.pumpAndSettle();

      expect(find.byType(BackofficeScreen), findsNothing);
      expect(find.text('Log In'), findsOneWidget);
      expect(userProvider.user, isNull);

      // Login B: possible despite the stuck signOut (signIn replaces
      // the session).
      await loginAs(tester, db, backend, userProvider, '+237674738258', 'mdpB');
      expect(find.byType(BackofficeScreen), findsOneWidget);
      expect(userProvider.user!.fullName, 'Chef B');
    },
  );
}
