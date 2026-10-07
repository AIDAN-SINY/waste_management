import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waste_pro/services/functions_client.dart';
import 'package:waste_pro/services/payment_api.dart';

void main() {
  late List<http.Request> requests;

  PaymentApi apiReturning(int status, Map<String, dynamic> body) {
    requests = [];
    return PaymentApi(
      functions: FunctionsClient(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(body), status);
        }),
        baseUrl: 'https://functions.test',
        idToken: () async => 'id-token',
      ),
    );
  }

  test('startPayment sends the plan, never an amount', () async {
    final api = apiReturning(200, {
      'txRef': 'WP-1',
      'ussdCode': '*126#',
      'amount': 25,
      'displayAmount': 3000,
      'demo': true,
    });

    final payment = await api.startPayment(
      purpose: PaymentPurpose.subscription,
      momoPhone: '670000000',
      plan: 'monthly',
    );

    final sent = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(requests.single.url.path, endsWith('/startPayment'));
    expect(sent['purpose'], 'subscription');
    expect(sent['plan'], 'monthly');
    expect(sent.containsKey('amount'), isFalse);

    expect(payment.txRef, 'WP-1');
    expect(payment.ussdCode, '*126#');
    expect(payment.amount, 25);
    expect(payment.displayAmount, 3000);
    expect(payment.isDemo, isTrue);
  });

  test('a refused payment surfaces the server message', () async {
    final api = apiReturning(502, {'error': 'Number refused'});

    expect(
      () => api.startPayment(
        purpose: PaymentPurpose.extraPickup,
        momoPhone: '670000002',
      ),
      throwsA(isA<PaymentApiException>()
          .having((e) => e.message, 'message', 'Number refused')),
    );
  });
}
