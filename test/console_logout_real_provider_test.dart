import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waste_pro/features/superadmin/data/platform_store.dart';
import 'package:waste_pro/features/superadmin/super_admin_console.dart';
import 'package:waste_pro/main.dart';
import 'package:waste_pro/providers/user_provider.dart';
import 'package:waste_pro/services/auth_service.dart';

import 'fakes/fake_auth_backend.dart';

import 'helpers/setup_firebase.dart';

/// Logout from the super admin console with the REAL `UserProvider.logout()`
/// (session cleared before the backend signOut) — not the mutable fake provider
/// used in routing tests. This is the real user flow.
void main() {
  setUpAll(() => setupFirebaseMocks());

  testWidgets(
    'super admin: logout from console → home screen (real provider)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend()
        ..seedAccount('237640996787@wastepro.cm', 'admin123');
      await db.collection('users').doc('+237640996787').set({
        'phoneNumber': '+237640996787',
        'fullName': 'Super Admin',
        'role': 'super_admin',
      });

      final userProvider = UserProvider(backend: backend);
      final auth = AuthService(db: db, backend: backend);
      final user = await auth.login('+237640996787', 'admin123');
      expect(user, isNotNull);
      await userProvider.setUser(user!);

      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value: userProvider,
          child: WasteProApp(consoleStore: PlatformStore(), db: db),
        ),
      );
      await tester.pumpAndSettle();

      // The super admin is redirected to the console.
      expect(find.byType(SuperAdminConsole), findsOneWidget);

      // Logout via the sidebar icon (footer).
      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pumpAndSettle();

      // Back to the home screen (Log In button of the CTA).
      expect(find.byType(SuperAdminConsole), findsNothing);
      expect(find.text('Log In'), findsOneWidget);
      expect(userProvider.user, isNull);
    },
  );
}
