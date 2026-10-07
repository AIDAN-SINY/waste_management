/// Tests for the simplified ChatbotService.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:waste_pro/features/home/chatbot_service.dart';
import 'package:waste_pro/models/user_model.dart';

void main() {
  final testUser = UserModel(phoneNumber: '+237699999999', fullName: 'Test User', role: 'client');

  group('ChatbotService — FAQ', () {
    late ChatbotService bot;

    setUp(() {
      bot = ChatbotService(db: FakeFirebaseFirestore());
    });

    test('greeting', () async {
      final reply = await bot.process('hello');
      expect(reply.text, contains('Hey'));
      expect(reply.intent, 'greeting');
    });

    test('thanks', () async {
      final reply = await bot.process('thanks');
      expect(reply.text, contains('welcome'));
    });

    test('plans', () async {
      final reply = await bot.process('what plans do you have?');
      expect(reply.text, contains('Essential'));
      expect(reply.text, contains('Standard'));
      expect(reply.text, contains('Premium'));
    });

    test('plan difference', () async {
      final reply = await bot.process("what's the difference between plans?");
      expect(reply.text, contains('Essential'));
      expect(reply.text, contains('Premium'));
    });

    test('how it works', () async {
      final reply = await bot.process('how does this work?');
      expect(reply.intent, 'how_it_works');
      expect(reply.text, contains('collector'));
      expect(reply.text, contains('confirm'));
    });

    test('how it works — briefing phrasing', () async {
      final reply = await bot.process('can you give me a briefing of how this app works?');
      expect(reply.intent, 'how_it_works');
      expect(reply.text, contains('confirm'));
      expect(reply.text, contains('dispute'));
    });

    test('how it works — explain phrasing', () async {
      final reply = await bot.process('explain how the app works');
      expect(reply.intent, 'how_it_works');
    });

    test('payment methods', () async {
      final reply = await bot.process('how can I pay?');
      expect(reply.text, contains('MTN MoMo'));
    });

    test('support contact', () async {
      final reply = await bot.process('how do I contact support?');
      expect(reply.text, contains('+237 696 713 899'));
    });

    test('missed pickup FAQ', () async {
      final reply = await bot.process('what happens if a pickup is missed?');
      expect(reply.text, contains('extra pickup'));
    });

    test('track collector', () async {
      final reply = await bot.process('where is my collector?');
      expect(reply.text, contains('mini-map'));
    });

    test('upgrade plan', () async {
      final reply = await bot.process('how do I upgrade my plan?');
      expect(reply.text, contains('Subscription Plan'));
    });

    test('password help', () async {
      final reply = await bot.process('I forgot my password');
      // Points to the SMS reset on the login screen.
      expect(reply.text, contains('Forgot password?'));
    });

    test('fallback', () async {
      final reply = await bot.process('what is the weather today?');
      expect(reply.intent, 'unknown');
    });
  });

  group('ChatbotService — Backend queries', () {
    late ChatbotService bot;
    late FakeFirebaseFirestore fakeDb;

    setUp(() async {
      fakeDb = FakeFirebaseFirestore();
      bot = ChatbotService(db: fakeDb);

      final now = DateTime.now();
      final dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      await fakeDb.collection('users').doc('+237699999999').set({
        'phoneNumber': '+237699999999',
        'fullName': 'Test User',
        'role': 'client',
        'isSubscribed': true,
        'subscription_plan': 'Standard',
        'collection_days': [dayNames[now.weekday % 7]],
        'pickup_time': '07:00 — 08:00',
        'agenceName': 'Yaoundé — Bastos',
      });
    });

    test('next pickup', () async {
      final reply = await bot.process('when is my next pickup?', user: testUser);
      expect(reply.intent, 'next_pickup');
      expect(reply.text, contains('pickup'));
    });

    test('subscription status', () async {
      final reply = await bot.process('is my subscription active?', user: testUser);
      expect(reply.intent, 'subscription_active');
      expect(reply.text, contains('active'));
    });

    test('payment history empty', () async {
      final reply = await bot.process('show me my payment history', user: testUser);
      expect(reply.intent, 'no_payments');
    });

    test('notifications empty', () async {
      final reply = await bot.process('do I have any notifications?', user: testUser);
      expect(reply.intent, 'no_notifications');
    });

    test('unauthenticated gets login prompt', () async {
      final reply = await bot.process('when is my next pickup?');
      expect(reply.text, contains('logged in'));
    });
  });

  group('ChatbotService — Complaint flow', () {
    late ChatbotService bot;

    setUp(() {
      bot = ChatbotService(db: FakeFirebaseFirestore());
    });

    test('complaint with clear category', () async {
      final reply = await bot.process('my bin was not collected yesterday');
      expect(reply.intent, 'complaint_flow');
      expect(reply.text, contains('Missed collection'));
    });

    test('complaint flow: category then description then confirmation', () async {
      final r1 = await bot.process('my bin was not collected');
      expect(r1.intent, 'complaint_flow');

      final r2 = await bot.process('The collector never came on Tuesday morning');
      expect(r2.intent, 'complaint_confirm');
      expect(r2.needsConfirmation, true);
    });

    test('complaint flow can be cancelled', () async {
      await bot.process('my bin was not collected');
      final reply = await bot.process('cancel');
      expect(reply.intent, 'cancelled');
    });

    test('complaint without category hint asks 1-5, then proceeds', () async {
      final r1 = await bot.process('submit complaint');
      expect(r1.intent, 'complaint_flow');
      expect(r1.text, contains('1'));

      // L'état « choisir la catégorie » est géré : « 1 » avance, ne reset
      // plus la conversation (ancien bug → « Something went wrong »).
      final r2 = await bot.process('1');
      expect(r2.intent, 'complaint_flow');
      expect(r2.text, contains('Missed collection'));

      final r3 = await bot.process('The bin was never emptied');
      expect(r3.intent, 'complaint_confirm');
      expect(r3.needsConfirmation, true);
    });

    test('complaint category select → submit writes the issue', () async {
      final fakeDb = FakeFirebaseFirestore();
      final flowBot = ChatbotService(db: fakeDb);
      await flowBot.process('submit complaint');
      await flowBot.process('2');
      await flowBot.process('The bin is overflowing since Tuesday');
      final reply = await flowBot.process('yes', user: testUser);
      expect(reply.intent, 'complaint_submitted');

      final issues = await fakeDb.collection('issues').get();
      expect(issues.docs.single.data()['category'], 'Overflowing bin');
      expect(issues.docs.single.data()['client_id'], '+237699999999');
    });
  });

  group('ChatbotService — Pickup request flow', () {
    late ChatbotService bot;

    setUp(() {
      bot = ChatbotService(db: FakeFirebaseFirestore());
    });

    test('asks for date', () async {
      final reply = await bot.process('I need an extra pickup');
      expect(reply.intent, 'pickup_flow');
      expect(reply.text, contains('date'));
    });

    test('with date shows confirmation', () async {
      await bot.process('I need an extra pickup');
      final reply = await bot.process('tomorrow');
      expect(reply.intent, 'pickup_confirm');
      expect(reply.needsConfirmation, true);
    });

    test('can be cancelled', () async {
      await bot.process('I need an extra pickup');
      final reply = await bot.process('no');
      expect(reply.intent, 'cancelled');
    });

    test('natural « yes please » confirms the request', () async {
      final fakeDb = FakeFirebaseFirestore();
      await fakeDb.collection('users').doc('+237699999999').set({
        'phoneNumber': '+237699999999',
      });
      final flowBot = ChatbotService(db: fakeDb);
      await flowBot.process('I need an extra pickup', user: testUser);
      await flowBot.process('tomorrow', user: testUser);
      final reply = await flowBot.process('yes please', user: testUser);
      expect(reply.intent, 'pickup_submitted');

      final pickups = await fakeDb.collection('pickups').get();
      expect(pickups.docs, isNotEmpty);
      // La date choisie (« demain ») est bien enregistrée (ancien bug :
      // le buffer était vidé avant la soumission).
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final expected =
          '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-'
          '${tomorrow.day.toString().padLeft(2, '0')}';
      expect(pickups.docs.single.data()['requested_date'], expected);
    });
  });

  group('ChatbotService — Payment flow', () {
    late ChatbotService bot;

    setUp(() {
      bot = ChatbotService(db: FakeFirebaseFirestore());
    });

    test('pay subscription asks for confirmation', () async {
      final reply = await bot.process('pay my subscription');
      expect(reply.needsConfirmation, true);
    });

    test('pay subscription can be confirmed', () async {
      await bot.process('pay my subscription', user: testUser);
      final reply = await bot.process('yes', user: testUser);
      expect(reply.intent, 'payment_initiated');
    });
  });

  group('ChatbotService — Security', () {
    test('no data leakage between users', () async {
      final fakeDb = FakeFirebaseFirestore();
      await fakeDb.collection('users').doc('+237600000001').set({
        'phoneNumber': '+237600000001',
        'fullName': 'User A',
        'isSubscribed': true,
        'subscription_plan': 'Premium',
        'collection_days': ['Monday'],
        'pickup_time': '07:00',
      });

      final botA = ChatbotService(db: fakeDb);
      final userA = UserModel(phoneNumber: '+237600000001', fullName: 'User A', role: 'client');
      final reply = await botA.process('is my subscription active?', user: userA);
      expect(reply.text, contains('Premium'));
    });
  });
}
