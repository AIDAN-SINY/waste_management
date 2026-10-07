import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/subscription_billing.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/navigation_provider.dart';
import '../../subscription/screens/subscription_screen.dart';
import '../../profile/screens/profile_screen.dart';
import 'checkout_screen.dart';
import '../../subscription/screens/history_screen.dart';
import 'payment_receipt_screen.dart';
import '../../../services/payment_api.dart';
import '../../../core/subscription_plans.dart';
/// Bills screen — shows the client's current active subscription bill
/// and payment status. This is distinct from Payment History which
/// shows all past transactions.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  // Design System Colors
  final Color dBg = const Color(0xFFF4F7F2);
  final Color dSurface = const Color(0xFFFFFFFF);
  final Color dGreen = const Color(0xFF0B5A2A);
  final Color dGold = const Color(0xFFF5B800);
  final Color dMuted = const Color(0xFF6E8274);
  final Color dBorder = const Color(0xFFE1E9DD);
  final Color dText = const Color(0xFF13261A);
  final Color dRed = const Color(0xFFC1443D);
  final Color dGreenSoft = const Color(0xFFE6F2E4);
  final Color dGoldSoft = const Color(0xFFFFF4CC);
  final Color dRedSoft = const Color(0xFFF8E4E2);

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user!;
    final navProvider = Provider.of<NavigationProvider>(context);

    return Scaffold(
      backgroundColor: dBg,
      appBar: AppBar(
        title: Text(
          "My Bills",
          style: GoogleFonts.sora(
            fontWeight: FontWeight.w600,
            color: dGreen,
            fontSize: 16,
          ),
        ),
        backgroundColor: dSurface,
        elevation: 0,
        foregroundColor: dGreen,
        centerTitle: false,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(user.phoneNumber)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B5A2A)),
            );
          }

          final subDoc = snapshot.data!;
          if (!subDoc.exists) {
            return _buildNoSubscription();
          }

          final data = subDoc.data()!;
          final planName = data['planName'] as String? ?? '';
          final price = (data['price'] as num?)?.toDouble() ?? 0;
          final status = data['status'] as String? ?? 'inactive';
          final startDate = (data['startDate'] as Timestamp?)?.toDate();
          final lastPayment =
              SubscriptionBilling.asDate(data['lastPaymentDate']) ?? startDate;
          final nextPayment =
              SubscriptionBilling.asDate(data['nextPaymentDate']) ??
                  SubscriptionBilling.asDate(data['expiryDate']) ??
                  (lastPayment != null
                      ? SubscriptionBilling.nextPaymentDate(lastPayment)
                      : null);
          final hoursLeft = SubscriptionBilling.hoursRemaining(nextPayment);
          final collectionDays =
              (data['collection_days'] as List<dynamic>?)?.cast<String>() ?? [];
          final pickupTime = data['pickup_time'] as String? ?? '';
          final zoneName = data['zone_name'] as String? ?? '';

          final isActive = status == 'active';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCurrentBillCard(
                  planName: planName,
                  price: price,
                  status: status,
                  startDate: startDate,
                  lastPayment: lastPayment,
                  nextPayment: nextPayment,
                  hoursLeft: hoursLeft,
                  isActive: isActive,
                ),
                const SizedBox(height: 18),
                if (planName.isNotEmpty) ...[
                  _buildDetailsCard(
                    collectionDays: collectionDays,
                    pickupTime: pickupTime,
                    zoneName: zoneName,
                    startDate: startDate,
                    lastPayment: lastPayment,
                    nextPayment: nextPayment,
                    hoursLeft: hoursLeft,
                  ),
                  const SizedBox(height: 18),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _payFromBills(
                      planName: planName.isNotEmpty ? planName : 'Monthly',
                      price: price > 0
                          ? price
                          : (SubscriptionPlans.byTitle(planName)?.price ??
                              3000),
                    ),
                    icon: const Icon(Icons.payments_rounded, size: 18),
                    label: Text(
                      isActive ? 'Pay / Renew now' : 'Pay now',
                      style: GoogleFonts.sora(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: dGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _buildRecentPayments(user.phoneNumber),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNav(navProvider),
    );
  }

  Future<void> _payFromBills({
    required String planName,
    required double price,
  }) async {
    final user = Provider.of<UserProvider>(context, listen: false).user!;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          amount: price,
          description: 'WastePro $planName subscription',
          purpose: PaymentPurpose.subscription,
          plan: planName,
          // Server has already renewed contract + subscription + invoice.
          onPaymentSuccess: (payment) async {
            try {
              await context.read<UserProvider>().refreshUser(user.phoneNumber);
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => PaymentReceiptScreen(
                    description: 'WastePro $planName subscription',
                    amount: payment.amount.toDouble(),
                    displayAmount: payment.displayAmount.toDouble(),
                    currency: 'XAF',
                    status: 'successful',
                    method: 'Notch Pay',
                    phone: user.phoneNumber,
                    customerName: user.fullName,
                    createdAt: DateTime.now(),
                    isDemoCharge: payment.isDemo,
                  ),
                ),
                (route) => route.isFirst,
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sync error: $e')),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildCurrentBillCard({
    required String planName,
    required double price,
    required String status,
    required DateTime? startDate,
    required DateTime? lastPayment,
    required DateTime? nextPayment,
    required int hoursLeft,
    required bool isActive,
  }) {
    final statusColor = isActive ? dGreen : dRed;
    final statusBg = isActive ? dGreenSoft : dRedSoft;
    final statusLabel = isActive ? 'ACTIVE' : 'INACTIVE';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                planName.isNotEmpty ? '$planName Plan' : 'No Active Plan',
                style: GoogleFonts.sora(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            price > 0 ? '${price.toStringAsFixed(0)} XAF / cycle' : '—',
            style: GoogleFonts.sora(
              color: dGold,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$hoursLeft h remaining',
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'until next payment',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Last: ${SubscriptionBilling.formatDate(lastPayment)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Next: ${SubscriptionBilling.formatDate(nextPayment)}',
                    style: GoogleFonts.inter(
                      color: dGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard({
    required List<String> collectionDays,
    required String pickupTime,
    required String zoneName,
    required DateTime? startDate,
    required DateTime? lastPayment,
    required DateTime? nextPayment,
    required int hoursLeft,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Subscription Details",
            style: GoogleFonts.sora(
              color: dText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _detailRow(
            Icons.hourglass_bottom_rounded,
            "Hours until next payment",
            SubscriptionBilling.formatHours(hoursLeft),
          ),
          const SizedBox(height: 10),
          _detailRow(
            Icons.event_available_outlined,
            "Last payment date",
            SubscriptionBilling.formatDate(lastPayment ?? startDate),
          ),
          const SizedBox(height: 10),
          _detailRow(
            Icons.event_outlined,
            "Next payment date",
            SubscriptionBilling.formatDate(nextPayment),
          ),
          const SizedBox(height: 10),
          _detailRow(
            Icons.calendar_today_outlined,
            "Collection Days",
            collectionDays.isNotEmpty ? collectionDays.join(', ') : 'Not set',
          ),
          const SizedBox(height: 10),
          _detailRow(
            Icons.schedule_outlined,
            "Pickup Time",
            pickupTime.isNotEmpty ? pickupTime : 'Not set',
          ),
          const SizedBox(height: 10),
          _detailRow(
            Icons.location_on_outlined,
            "Zone",
            zoneName.isNotEmpty ? zoneName : 'Not set',
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: dMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: dMuted, fontSize: 11),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  color: dText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentPayments(String phone) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Recent Payments",
          style: GoogleFonts.sora(
            color: dText,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('transactions')
              .where('phone', isEqualTo: phone)
              .limit(5)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError || !snapshot.hasData) {
              return const SizedBox.shrink();
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: dSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: dBorder),
                ),
                child: Center(
                  child: Text(
                    "No payments recorded yet.",
                    style: TextStyle(color: dMuted, fontSize: 13),
                  ),
                ),
              );
            }
            // Sort in Dart to avoid needing a composite index.
            docs.sort((a, b) {
              final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate();
              final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate();
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
            return Column(
              children: docs.map((doc) => _buildPaymentTile(doc)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPaymentTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final desc = (data['description'] as String? ?? 'Payment').trim();
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final currency = data['currency'] as String? ?? 'XAF';
    final status = (data['status'] as String? ?? 'cancelled').toLowerCase();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    final isSuccess = status == 'successful';
    final statusLabel = isSuccess ? 'PAID' : status == 'pending' ? 'PENDING' : 'FAILED';
    final statusColor = isSuccess ? dGreen : dRed;

    final dateStr = createdAt != null
        ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isSuccess ? dGreenSoft : dRedSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isSuccess ? Icons.check_rounded : Icons.close_rounded,
              color: statusColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(color: dMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${amount.toStringAsFixed(0)} $currency',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: dText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoSubscription() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: dGoldSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                color: dGold,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Active Subscription',
              style: GoogleFonts.sora(
                color: dText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Subscribe to a plan to see your bills and manage payments.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: dGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'View Plans',
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: dRed.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: GoogleFonts.sora(
                color: dText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Please try again later.',
              style: TextStyle(color: dMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // --- Bottom Navigation ---

  Widget _buildBottomNav(NavigationProvider navProvider) {
    return Container(
      decoration: BoxDecoration(
        color: dSurface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: _buildNavItem(
                  navProvider: navProvider,
                  icon: Icons.home_rounded,
                  label: "Home",
                  index: 0,
                  onTap: () {
                    navProvider.setIndex(0);
                    Navigator.pop(context);
                  },
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  navProvider: navProvider,
                  icon: Icons.history_rounded,
                  label: "History",
                  index: 1,
                  onTap: () {
                    navProvider.setIndex(1);
                    // Ouvre réellement l'écran Historique (l'ancien code
                    // faisait un pop qui ne menait nulle part).
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    );
                  },
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  navProvider: navProvider,
                  icon: Icons.description_rounded,
                  label: "Bill",
                  index: 2,
                  onTap: () {
                    navProvider.setIndex(2);
                  },
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  navProvider: navProvider,
                  icon: Icons.person_rounded,
                  label: "Profile",
                  index: 3,
                  onTap: () {
                    navProvider.setIndex(3);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfileScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required NavigationProvider navProvider,
    required IconData icon,
    required String label,
    required int index,
    required VoidCallback onTap,
  }) {
    final isSelected = navProvider.currentIndex == index;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      splashColor: dGreen.withValues(alpha: 0.1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? dGreen.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: isSelected
                    ? Border.all(
                        color: dGreen.withValues(alpha: 0.3), width: 1.5)
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected ? dGreen : dMuted,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? dGreen : dMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
