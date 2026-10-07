import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:waste_pro/features/home/chatbot_screen.dart';
import 'package:waste_pro/providers/user_provider.dart';

import 'helpers/setup_firebase.dart';

void main() {
  setUpAll(() => setupFirebaseMocks());

  Future<void> pumpChatbot(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChatbotScreen()),
        ),
      ),
    );
    // The typing-dots animation loops forever: fixed pumps only.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('chatbot opens with the WasteBot greeting', (tester) async {
    await pumpChatbot(tester);

    expect(find.textContaining("I'm WasteBot", findRichText: true), findsOneWidget);
    expect(find.text('WasteBot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending a message gets a bot reply', (tester) async {
    await pumpChatbot(tester);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.send_rounded));
    // Typing delay (500ms) + reply.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // The user bubble + the bot's greeting reply are both present.
    expect(find.text('hello'), findsOneWidget);
    expect(find.textContaining('How can I help', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}