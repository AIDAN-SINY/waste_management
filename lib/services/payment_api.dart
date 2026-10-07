import 'functions_client.dart';

/// Error raised by the payment backend (message is UI-ready).
class PaymentApiException implements Exception {
  const PaymentApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the client is paying for. The server sets the price from this —
/// the app never sends an amount.
enum PaymentPurpose { subscription, extraPickup }

/// A collection request accepted by CamPay (USSD prompt sent to the phone).
class StartedPayment {
  const StartedPayment({
    required this.txRef,
    required this.ussdCode,
    required this.amount,
    required this.displayAmount,
    required this.isDemo,
  });

  /// `transactions/{txRef}` — polled via [PaymentApi.checkPayment].
  final String txRef;
  final String ussdCode;

  /// Amount actually charged (capped in CamPay demo mode).
  final num amount;

  /// Plan / service price shown to the client.
  final num displayAmount;
  final bool isDemo;
}

/// Client for the payment Cloud Functions (`functions/index.js`).
///
/// CamPay credentials, prices and fulfillment (contract, subscription,
/// invoice, pickup) live on the server; the app only starts a payment and
/// polls its status. Calls are authenticated with the Firebase ID token.
class PaymentApi {
  PaymentApi({FunctionsClient? functions})
      : _functions = functions ?? FunctionsClient();

  final FunctionsClient _functions;

  Future<StartedPayment> startPayment({
    required PaymentPurpose purpose,
    required String momoPhone,
    String plan = '',
    List<String> collectionDays = const [],
    String pickupTime = '',
    String zoneName = '',
  }) async {
    final data = await _post('startPayment', {
      'purpose': switch (purpose) {
        PaymentPurpose.subscription => 'subscription',
        PaymentPurpose.extraPickup => 'extra_pickup',
      },
      'plan': plan,
      'momoPhone': momoPhone,
      'collectionDays': collectionDays,
      'pickupTime': pickupTime,
      'zoneName': zoneName,
    });
    return StartedPayment(
      txRef: data['txRef'] as String,
      ussdCode: data['ussdCode'] as String? ?? '',
      amount: data['amount'] as num? ?? 0,
      displayAmount: data['displayAmount'] as num? ?? 0,
      isDemo: data['demo'] as bool? ?? false,
    );
  }

  /// `pending` | `successful` | `failed`. A `successful` answer means the
  /// server has already activated what was paid for.
  Future<String> checkPayment(String txRef) async {
    final data = await _post('checkPayment', {'txRef': txRef});
    return data['status'] as String? ?? 'pending';
  }

  /// Polls [checkPayment] until a final status, or `timeout`.
  Future<String> waitForResult(
    String txRef, {
    Duration interval = const Duration(seconds: 4),
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      try {
        final status = await checkPayment(txRef);
        if (status != 'pending') return status;
      } on PaymentApiException {
        // Transient: retry on the next tick.
      }
    }
    return 'timeout';
  }

  Future<Map<String, dynamic>> _post(
    String function,
    Map<String, dynamic> body,
  ) async {
    try {
      return await _functions.post(function, body);
    } on FunctionsException catch (e) {
      throw PaymentApiException(e.message);
    }
  }
}
