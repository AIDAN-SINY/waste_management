// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:waste_pro/main.dart';
import 'package:waste_pro/models/user_model.dart';
import 'package:waste_pro/providers/user_provider.dart';

import 'fakes/fake_auth_backend.dart';
import 'helpers/setup_firebase.dart';

class FakeUserProvider extends UserProvider {
  FakeUserProvider({this.fakeUser, this.fakeIsLoading = false})
      : super(backend: FakeAuthBackend());

  final UserModel? fakeUser;
  final bool fakeIsLoading;

  @override
  UserModel? get user => fakeUser;

  @override
  bool get isLoading => fakeIsLoading;
}

void main() {
  setUpAll(() => setupFirebaseMocks());

  testWidgets('app shows welcome screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => UserProvider(backend: FakeAuthBackend()),
        child: const WasteProApp(),
      ),
    );

    // The new welcome screen shows the CTA card with its "Log In" button
    // (the "Welcome to WastePro" text was replaced by a responsive product
    // promise).
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('auth wrapper shows loading while auth check is in progress', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: FakeUserProvider(fakeUser: null, fakeIsLoading: true),
        child: const WasteProApp(),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
