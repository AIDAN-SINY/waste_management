import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:get/get.dart';

import '../../../core/config.dart';
import '../../../services/payment_api.dart';

enum PaymentMethod {
  orangeMoney,
  mtnMomo,
}

extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.orangeMoney => 'Orange Money',
        PaymentMethod.mtnMomo => 'MTN Mobile Money',
      };
}

/// Checkout via CamPay, driven by the payment Cloud Functions.
///
/// The server sets the price, sends the USSD prompt, verifies the result
/// with CamPay and activates what was paid for. [onPaymentSuccess] is only
/// called once the server reports `successful` — it is UI-only (receipt,
/// refresh), it must not write payment or subscription data.
class CheckoutController extends GetxController {
  CheckoutController({
    required this.amount,
    required this.description,
    required this.purpose,
    this.plan = '',
    this.collectionDays = const [],
    this.pickupTime = '',
    this.zoneName = '',
    PaymentApi? api,
    this.onPaymentSuccess,
  }) : _api = api ?? PaymentApi();

  /// Display price; the server decides what is actually charged.
  final num amount;
  final String description;
  final PaymentPurpose purpose;
  final String plan;
  final List<String> collectionDays;
  final String pickupTime;
  final String zoneName;
  final void Function(StartedPayment payment)? onPaymentSuccess;
  final PaymentApi _api;

  final isProcessing = false.obs;
  final paymentStatus = ''.obs;
  final selectedMethod = PaymentMethod.orangeMoney.obs;
  final phoneNumber = ''.obs;

  /// Bound from [CheckoutScreen] — required because the app uses
  /// MaterialApp (not GetMaterialApp), so Get.snackbar / Get.context crash.
  BuildContext? hostContext;

  void bindHost(BuildContext context) {
    hostContext = context;
  }

  /// Expected charge, for display before the server answers.
  num get chargeableAmount =>
      AppConfig.isCampayDemo ? AppConfig.campayDemoMaxAmount : amount;

  num get displayAmount => amount;

  void _notify(String title, String message, {bool error = false}) {
    final ctx = hostContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('$title: $message')),
          ],
        ),
        backgroundColor: error ? Colors.red.shade700 : Brand.leaf,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> executePayment() async {
    if (phoneNumber.value.trim().isEmpty) {
      _notify(
        'Phone number required',
        'Please enter your mobile money phone number.',
        error: true,
      );
      return;
    }

    isProcessing.value = true;
    try {
      paymentStatus.value = 'Sending payment request...\n'
          'Check your phone for the MTN / Orange Money prompt.';
      final payment = await _api.startPayment(
        purpose: purpose,
        momoPhone: phoneNumber.value,
        plan: plan,
        collectionDays: collectionDays,
        pickupTime: pickupTime,
        zoneName: zoneName,
      );

      paymentStatus.value = payment.ussdCode.isNotEmpty
          ? 'Approve on your phone now.\nUSSD: ${payment.ussdCode}\n'
              'Waiting for confirmation...'
          : 'Approve the payment on your phone (MoMo / Orange Money PIN).\n'
              'Do not close this screen...';

      final status = await _api.waitForResult(payment.txRef);
      if (status != 'successful') {
        _showError(
          'Payment Issue',
          status == 'timeout'
              ? 'No confirmation received in time. If you approved it, it '
                  'will appear in your payment history shortly.'
              : 'Payment was declined or failed on your phone.',
        );
        return;
      }

      paymentStatus.value = 'Payment confirmed!';
      await Future<void>.delayed(const Duration(milliseconds: 800));
      onPaymentSuccess?.call(payment);
    } on PaymentApiException catch (e) {
      _showError('Payment Error', e.message);
    } catch (e) {
      _showError('Error', 'An unexpected error occurred: $e');
    } finally {
      isProcessing.value = false;
    }
  }

  void _showError(String title, String message) {
    _notify(title, message, error: true);
    paymentStatus.value = '';
  }
}
