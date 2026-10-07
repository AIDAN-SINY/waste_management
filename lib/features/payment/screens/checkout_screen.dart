import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/config.dart';
import '../../../providers/user_provider.dart';
import '../../../services/payment_api.dart';
import '../controllers/checkout_controller.dart';
/// Écran de checkout — sélection du mode de paiement Mobile Money
/// (Orange Money / MTN Mobile Money) avec saisie de numéro et overlay de
/// progression pendant le traitement Campay.
///
/// The server prices, verifies and fulfills the payment; [onPaymentSuccess]
/// only runs after it reports `successful` and must stay UI-only.
///
/// Utilisation :
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => CheckoutScreen(
///     amount: 5500,
///     description: 'Weekly subscription',
///     purpose: PaymentPurpose.subscription,
///     plan: 'weekly',
///     onPaymentSuccess: (payment) => Navigator.pop(context),
///   ),
/// ));
/// ```
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.amount,
    required this.description,
    required this.purpose,
    this.plan = '',
    this.collectionDays = const [],
    this.pickupTime = '',
    this.zoneName = '',
    this.onPaymentSuccess,
  });

  /// Display price only.
  final num amount;
  final String description;
  final PaymentPurpose purpose;

  /// Plan id or title (`monthly` | `weekly` | `daily`) for subscriptions.
  final String plan;
  final List<String> collectionDays;
  final String pickupTime;
  final String zoneName;
  final void Function(StartedPayment payment)? onPaymentSuccess;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const Color _dGreen = Color(0xFF0B5A2A);
  static const Color _dGold = Color(0xFFF5B800);
  static const Color _dMuted = Color(0xFF6E8274);
  static const Color _dSurface = Color(0xFFFFFFFF);
  static const Color _dBg = Color(0xFFF5F7F6);
  static const Color _dBorder = Color(0xFFE8EBE9);
  static const Color _dText = Color(0xFF13261A);

  late final CheckoutController controller;
  late final String _tag;
  late final TextEditingController _phoneCtrl;
  bool _phonePrefillDone = false;

  @override
  void initState() {
    super.initState();
    _tag = 'checkout-${DateTime.now().microsecondsSinceEpoch}';
    controller = Get.put(
      CheckoutController(
        amount: widget.amount,
        description: widget.description,
        purpose: widget.purpose,
        plan: widget.plan,
        collectionDays: widget.collectionDays,
        pickupTime: widget.pickupTime,
        zoneName: widget.zoneName,
        onPaymentSuccess: widget.onPaymentSuccess,
      ),
      tag: _tag,
    );
    _phoneCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_phonePrefillDone) return;
    _phonePrefillDone = true;
    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      var initialPhone = user?.phoneNumber.trim() ?? '';
      if (initialPhone.startsWith('237') && initialPhone.length > 9) {
        initialPhone = initialPhone.substring(3);
      }
      if (initialPhone.isNotEmpty) {
        _phoneCtrl.text = initialPhone;
        controller.phoneNumber.value = initialPhone;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    if (Get.isRegistered<CheckoutController>(tag: _tag)) {
      Get.delete<CheckoutController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    controller.bindHost(context);
    return Scaffold(
      backgroundColor: _dBg,
      appBar: AppBar(
        title: Text(
          'Checkout',
          style: GoogleFonts.sora(
            fontWeight: FontWeight.w600,
            color: _dGreen,
            fontSize: 16,
          ),
        ),
        backgroundColor: _dSurface,
        elevation: 0,
        foregroundColor: _dGreen,
        centerTitle: false,
      ),
      body: Stack(
        children: [
          // Main content.
          Obx(() {
            if (controller.isProcessing.value) {
              return const SizedBox.shrink();
            }
            return _buildForm(context, controller);
          }),

          // Progress overlay (shown during payment processing).
          Obx(() {
            if (!controller.isProcessing.value) {
              return const SizedBox.shrink();
            }
            return _buildProgressOverlay(controller);
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Form
  // ---------------------------------------------------------------------------

  Widget _buildForm(BuildContext context, CheckoutController controller) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Amount summary ---
          _buildAmountCard(controller),
          const SizedBox(height: 24),

          // --- Section title ---
          Text(
            'Payment Method',
            style: GoogleFonts.sora(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _dText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose how you want to pay',
            style: GoogleFonts.inter(fontSize: 12, color: _dMuted),
          ),
          const SizedBox(height: 14),

          // --- Mobile Money methods ---
          Obx(() => _buildMethodCard(
                context: context,
                controller: controller,
                method: PaymentMethod.orangeMoney,
                title: 'Orange Money',
                subtitle: 'Pay with your Orange Money account',
                icon: Icons.phone_iphone,
                accentColor: const Color(0xFFED7D31),
              )),
          const SizedBox(height: 10),
          Obx(() => _buildMethodCard(
                context: context,
                controller: controller,
                method: PaymentMethod.mtnMomo,
                title: 'MTN Mobile Money',
                subtitle: 'Pay with your MTN MoMo account',
                icon: Icons.phone_iphone,
                accentColor: const Color(0xFFFFCC00),
              )),

          // --- Phone number input ---
          const SizedBox(height: 20),
          Text(
            'Phone Number',
            style: GoogleFonts.sora(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _dText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The payment request will be sent to this number',
            style: GoogleFonts.inter(fontSize: 11, color: _dMuted),
          ),
          const SizedBox(height: 10),
          _buildPhoneInput(controller),

          const SizedBox(height: 28),

          // --- Demo mode notice ---
          if (AppConfig.isCampayDemo) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _dGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Demo mode - CamPay charges '
                '${controller.chargeableAmount.toStringAsFixed(0)} XAF '
                '(plan ${controller.displayAmount.toStringAsFixed(0)} XAF shown above). '
                'Real prices apply in production.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: _dMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // --- Pay button ---
          SizedBox(
            width: double.infinity,
            child: Obx(() => ElevatedButton(
                  onPressed: controller.isProcessing.value
                      ? null
                      : () => controller.executePayment(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _dGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _payButtonText(controller),
                    style: GoogleFonts.sora(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                )),
          ),
          const SizedBox(height: 10),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 13, color: _dMuted),
                const SizedBox(width: 5),
                Text(
                  'Secure payment via Campay',
                  style: GoogleFonts.inter(color: _dMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Amount Card
  // ---------------------------------------------------------------------------

  Widget _buildAmountCard(CheckoutController controller) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _dSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _dGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: _dGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.description,
                  style: GoogleFonts.sora(
                    color: _dText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total amount',
                  style: GoogleFonts.inter(color: _dMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${widget.amount.toStringAsFixed(0)} XAF',
                style: GoogleFonts.sora(
                  color: _dGreen,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (AppConfig.isCampayDemo)
                Text(
                  'Demo: ${controller.chargeableAmount.toStringAsFixed(0)} XAF',
                  style: GoogleFonts.inter(
                    color: _dGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Payment Method Card
  // ---------------------------------------------------------------------------

  Widget _buildMethodCard({
    required BuildContext context,
    required CheckoutController controller,
    required PaymentMethod method,
    required String title,
    required String subtitle,
    required IconData icon,
    Color accentColor = _dGreen,
  }) {
    final isSelected = controller.selectedMethod.value == method;

    return GestureDetector(
      onTap: () => controller.selectedMethod.value = method,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _dSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accentColor : _dBorder,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Radio indicator.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? accentColor : _dMuted.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),

            // Icon.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.12)
                    : _dBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? accentColor : _dMuted,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),

            // Text.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? _dText : _dMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: _dMuted,
                    ),
                  ),
                ],
              ),
            ),

            // Check mark.
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: accentColor,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Phone Input
  // ---------------------------------------------------------------------------

  Widget _buildPhoneInput(CheckoutController controller) {
    return Container(
      decoration: BoxDecoration(
        color: _dSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _dBorder),
      ),
      child: Row(
        children: [
          // Fixed prefix.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _dBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              border: Border(
                right: BorderSide(color: _dBorder),
              ),
            ),
            child: Text(
              '+237',
              style: GoogleFonts.sora(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _dGreen,
              ),
            ),
          ),

          // Phone number field.
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: GoogleFonts.inter(fontSize: 14, color: _dText),
              decoration: InputDecoration(
                hintText: '6XX XXX XXX',
                hintStyle: GoogleFonts.inter(
                  color: _dMuted.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
              onChanged: (value) => controller.phoneNumber.value = value,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Progress Overlay
  // ---------------------------------------------------------------------------

  Widget _buildProgressOverlay(CheckoutController controller) {
    return Container(
      color: _dBg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon.
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _dGold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.smartphone,
                  color: _dGold,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),

              // Status text.
              Obx(() => Text(
                    controller.paymentStatus.value,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _dGreen,
                      height: 1.4,
                    ),
                  )),
              const SizedBox(height: 20),

              // Spinner while waiting for phone confirmation.
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: CircularProgressIndicator(color: _dGreen),
              ),

              const SizedBox(height: 8),

              // Warning.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Brand.goldSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.phone_android_rounded,
                      size: 16,
                      color: Brand.goldDim,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Confirm with your MoMo / Orange Money PIN on your phone',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Brand.goldDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pay Button
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _payButtonText(CheckoutController controller) => 'PAY';
}
