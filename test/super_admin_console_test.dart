import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/superadmin/super_admin_console.dart';

import 'helpers/setup_firebase.dart';

void main() {
  setUpAll(() => setupFirebaseMocks());

  Future<void> pumpConsole(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: SuperAdminConsole(db: FakeFirebaseFirestore())));
    // Let the KPI skeleton timers fire.
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('console renders brand, navigation and dashboard KPIs', (
    tester,
  ) async {
    await pumpConsole(tester);

    // Brand appears as a rich text (also present in the agency chart labels,
    // so we only assert the sidebar-specific texts here).
    expect(find.text('PLATFORM CONSOLE'), findsOneWidget);
    expect(find.text('Super Admin'), findsOneWidget);

    // Navigation items (labels also appear as KPI labels, hence findsWidgets)
    expect(find.text('Companies'), findsOneWidget);
    expect(find.text('Agencies'), findsWidgets);
    expect(find.text('Users'), findsWidgets);

    // Dashboard KPIs
    expect(find.text('Active companies'), findsOneWidget);
    expect(find.text('Platform availability'), findsOneWidget);

    // Mock data appears in the activity feed
    expect(find.text('Platform activity'), findsOneWidget);
  });

  testWidgets('creates a company through the drawer and shows it in the table', (
    tester,
  ) async {
    await pumpConsole(tester);

    // Navigate to Companies
    await tester.tap(find.text('Companies'));
    await tester.pumpAndSettle();
    expect(find.text('New company'), findsOneWidget);

    // Open the create drawer
    await tester.tap(find.text('New company'));
    await tester.pumpAndSettle();
    expect(find.text('Company name'), findsOneWidget);

    // Fill the form and save
    await tester.enterText(find.byType(TextFormField).at(0), 'Test SARL');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The new company is visible in the table + toast shown
    expect(find.text('Test SARL'), findsOneWidget);

    // Flush the toast auto-dismiss timer.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('blocks saving a company with an empty required field', (
    tester,
  ) async {
    await pumpConsole(tester);

    await tester.tap(find.text('Companies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New company'));
    await tester.pumpAndSettle();

    // Save without filling the "Company name" field.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // An error toast is shown and the drawer stays open for a retry.
    expect(
      find.text('The field "Company name" is required.'),
      findsOneWidget,
    );
    expect(find.text('Company name'), findsOneWidget);

    // Flush the toast auto-dismiss timer.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('blocks deleting a company that still has agencies', (
    tester,
  ) async {
    await pumpConsole(tester);

    await tester.tap(find.text('Companies'));
    await tester.pumpAndSettle();

    // 'WastePro Yaoundé SARL' has 2 attached agencies (seed data): its
    // delete action is blocked with an explanatory toast, no confirm dialog.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('Delete this company?'), findsNothing);
    expect(find.textContaining('Cannot delete'), findsOneWidget);
    expect(find.text('WastePro Yaoundé SARL'), findsWidgets);

    // Flush the toast auto-dismiss timer.
    await tester.pump(const Duration(seconds: 4));
  });

  Future<void> pumpConsoleMobile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: SuperAdminConsole(db: FakeFirebaseFirestore())));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('mobile: hamburger drawer navigation and card rows', (
    tester,
  ) async {
    await pumpConsoleMobile(tester);

    // Sidebar is hidden (drawer closed) - nav items are not hit-testable.
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    expect(find.text('Companies').hitTestable(), findsNothing);

    // Open the drawer via the hamburger.
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Companies').hitTestable(), findsOneWidget);

    // Navigate: drawer closes and the companies page shows cards.
    await tester.tap(find.text('Companies').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Bastos, Yaoundé'), findsWidgets);
    expect(find.text('New company'), findsOneWidget);
  });

  testWidgets('mobile: tapping a company card opens the company detail page',
      (tester) async {
    await pumpConsoleMobile(tester);

    // Open the drawer and go to the companies page (cards layout).
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Companies').hitTestable());
    await tester.pumpAndSettle();

    // Tapping the first card opens the full company detail page (parity
    // with desktop rows).
    await tester.tap(find.text('WastePro Yaoundé SARL').first);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Back to companies'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('mobile: system back closes the drawer before popping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Push the console as a route so the second back actually pops it.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SuperAdminConsole(db: FakeFirebaseFirestore())),
                ),
                child: const Text('Open console'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open console'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    // Open the drawer.
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Companies').hitTestable(), findsOneWidget);

    // First back: the drawer closes, the console is NOT popped.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Companies').hitTestable(), findsNothing);
    expect(find.text('Open console'), findsNothing);

    // Second back: the console pops back to the previous screen.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open console'), findsOneWidget);
  });

  testWidgets('demo preview banner is shown when using the mock store', (
    tester,
  ) async {
    await pumpConsole(tester);

    // Without an injected Firestore store, the console runs on the in-memory
    // mock: a banner must warn that nothing is saved.
    expect(find.textContaining('Demo preview'), findsOneWidget);
  });

  testWidgets('creating a user is blocked in demo preview', (tester) async {
    await pumpConsole(tester);

    await tester.tap(find.text('Users').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New user'));
    await tester.pumpAndSettle();

    // No creation drawer: a toast explains you need to log in as super admin
    // ("to create real users" only appears in the toast, not the banner).
    expect(find.text('Full name'), findsNothing);
    expect(find.textContaining('to create real users'), findsOneWidget);

    // Flush le timer du toast (3 s).
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('clicking a company row opens the full company detail page', (
    tester,
  ) async {
    await pumpConsole(tester);

    // Navigate to Companies (sidebar nav item).
    await tester.tap(find.text('Companies').first);
    await tester.pumpAndSettle();
    expect(find.text('New company'), findsOneWidget);

    // Click the first company row: "WastePro Yaoundé SARL" (seed data).
    await tester.tap(find.text('WastePro Yaoundé SARL').first);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    // Full page detail: back to the list + company identity.
    expect(find.text('Back to companies'), findsOneWidget);
    expect(find.text('WastePro Yaoundé SARL'), findsWidgets);

    // KPI cards + charts specific to the detail page.
    expect(find.text('Agencies'), findsWidgets);
    expect(find.text('Managers'), findsWidgets);
    expect(find.text('Clients'), findsWidgets);
    expect(find.text('Collectors'), findsWidgets);
    expect(find.text('Clients by status'), findsOneWidget);
    expect(find.text('Clients by plan'), findsOneWidget);

    // Actions in the header.
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Scroll down to the agences table: the company's agencies + managers.
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -1000),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Yaoundé — Bastos'), findsWidgets);
    expect(find.text('Jean Dooh'), findsWidgets);

    await tester.pumpAndSettle();
  });

  testWidgets('command palette opens and closes with Escape', (tester) async {
    await pumpConsole(tester);

    await tester.tap(find.text('Search or take action...'));
    await tester.pumpAndSettle();

    // Group labels are uppercased by the palette UI.
    expect(find.text('NAVIGATION'), findsOneWidget);
    expect(find.text('ACTIONS'), findsOneWidget);
    expect(find.text('New company'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('NAVIGATION'), findsNothing);
  });
}
