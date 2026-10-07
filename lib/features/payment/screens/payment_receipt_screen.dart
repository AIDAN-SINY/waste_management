/// Formal payment receipt shown after a successful CamPay charge
/// or when opening a transaction from Payment History.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class PaymentReceiptScreen extends StatelessWidget {
  const PaymentReceiptScreen({
    super.key,
    required this.description,
    required this.amount,
    this.displayAmount,
    this.currency = 'XAF',
    this.status = 'successful',
    this.method,
    this.reference,
    this.phone,
    this.customerName,
    this.createdAt,
    this.isDemoCharge = false,
    this.transactionId,
  });

  factory PaymentReceiptScreen.fromMap(
    Map<String, dynamic> data, {
    String? transactionId,
  }) {
    final createdAt = data['createdAt'];
    DateTime? date;
    if (createdAt is Timestamp) {
      date = createdAt.toDate();
    } else if (createdAt is DateTime) {
      date = createdAt;
    }

    return PaymentReceiptScreen(
      transactionId: transactionId,
      description: (data['description'] as String?)?.trim().isNotEmpty == true
          ? (data['description'] as String).trim()
          : 'WastePro payment',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      displayAmount: (data['displayAmount'] as num?)?.toDouble(),
      currency: data['currency'] as String? ?? 'XAF',
      status: (data['status'] as String?)?.toLowerCase() ?? 'successful',
      method: data['method'] as String? ?? data['paymentMethod'] as String?,
      reference: data['reference'] as String?,
      phone: data['phone'] as String? ?? data['userId'] as String?,
      customerName: data['customerName'] as String?,
      createdAt: date,
      isDemoCharge: data['isDemoCharge'] == true,
    );
  }

  final String description;
  final double amount;
  final double? displayAmount;
  final String currency;
  final String status;
  final String? method;
  final String? reference;
  final String? phone;
  final String? customerName;
  final DateTime? createdAt;
  final bool isDemoCharge;
  final String? transactionId;

  static const _bg = Color(0xFFF5F7F6);
  static const _surface = Color(0xFFFFFFFF);
  static const _green = Color(0xFF0B5A2A);
  static const _gold = Color(0xFFF5B800);
  static const _muted = Color(0xFF6E8274);
  static const _border = Color(0xFFE8EBE9);
  static const _text = Color(0xFF13261A);

  bool get _ok => status == 'successful' || status == 'success';

  @override
  Widget build(BuildContext context) {
    final shownPlan = displayAmount ?? amount;
    final paid = amount;
    final dateLabel = createdAt == null
        ? 'Just now'
        : '${createdAt!.day.toString().padLeft(2, '0')}/'
            '${createdAt!.month.toString().padLeft(2, '0')}/'
            '${createdAt!.year}  '
            '${createdAt!.hour.toString().padLeft(2, '0')}:'
            '${createdAt!.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          'Payment receipt',
          style: GoogleFonts.sora(
            fontWeight: FontWeight.w600,
            color: _green,
            fontSize: 16,
          ),
        ),
        backgroundColor: _surface,
        elevation: 0,
        foregroundColor: _green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: (_ok ? _green : Colors.red).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _ok ? Icons.check_circle_rounded : Icons.error_outline,
                      color: _ok ? _green : Colors.red,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _ok ? 'Payment successful' : 'Payment ${status.toUpperCase()}',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 13, color: _muted),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${shownPlan.toStringAsFixed(0)} $currency',
                    style: GoogleFonts.sora(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: _green,
                    ),
                  ),
                  if (isDemoCharge ||
                      (displayAmount != null && displayAmount != amount)) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Charged: ${paid.toStringAsFixed(0)} $currency'
                      '${isDemoCharge ? ' (demo)' : ''}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _gold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Divider(color: _border),
                  const SizedBox(height: 8),
                  _row('Date', dateLabel),
                  _row('Status', _ok ? 'SUCCESS' : status.toUpperCase()),
                  if (method != null && method!.trim().isNotEmpty)
                    _row('Method', method!),
                  if (customerName != null && customerName!.trim().isNotEmpty)
                    _row('Customer', customerName!),
                  if (phone != null && phone!.trim().isNotEmpty)
                    _row('Phone', '+237 $phone'),
                  if (reference != null && reference!.trim().isNotEmpty)
                    _row('Reference', reference!, copyable: true, context: context),
                  if (transactionId != null)
                    _row('Receipt ID', transactionId!, copyable: true, context: context),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Keep this receipt for your records. Support: +237 696 713 899',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: _muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Done',
                  style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool copyable = false,
    BuildContext? context,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: _muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
            ),
          ),
          if (copyable && context != null)
            InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
              child: const Icon(Icons.copy_rounded, size: 16, color: _muted),
            ),
        ],
      ),
    );
  }
}
