import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/auth/screens/welcome_screen.dart';
import 'package:waste_pro/features/auth/screens/login_screen.dart';

void main() {
  // Renders a screen at a given size and checks that there are no exceptions
  // (overflow) or errors during layout.
  Future<void> pumpAt(
    WidgetTester tester,
    Widget screen,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: screen),
    );
    // Fixed pump (not pumpAndSettle: the login logo has an infinite animation
    // that would prevent settling).
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull,
        reason: 'exception during render at $size');
  }

  testWidgets('welcome: desktop and mobile without overflow', (tester) async {
    // Desktop (web / Windows)
    await pumpAt(tester, const WelcomeScreen(), const Size(1440, 900));
    expect(find.text('Log In'), findsOneWidget);
    // The 3 hero product promises
    expect(find.text('Scheduled pickups'), findsOneWidget);
    expect(find.text('Simple payments'), findsOneWidget);

    // Mobile
    await pumpAt(tester, const WelcomeScreen(), const Size(390, 844));
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('login: desktop and mobile without overflow', (tester) async {
    // Desktop (web / Windows) — brand panel + login card
    await pumpAt(tester, const LoginScreen(), const Size(1440, 900));
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    // Trust points of the brand panel
    expect(find.text('Your data and payments are protected.'), findsOneWidget);

    // Mobile — the card stays usable
    await pumpAt(tester, const LoginScreen(), const Size(390, 844));
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
  });
}
