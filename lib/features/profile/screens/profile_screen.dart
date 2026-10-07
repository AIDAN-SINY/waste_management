import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/subscription_billing.dart';
import '../../../core/subscription_plans.dart';
import '../../../models/user_model.dart';
import '../../../providers/navigation_provider.dart';
import '../../../providers/user_provider.dart';
import '../../auth/screens/welcome_screen.dart';
import '../../home/support_screen.dart';
import '../../payment/screens/bills_screen.dart';
import '../../payment/screens/checkout_screen.dart';
import '../../subscription/screens/history_screen.dart';
import '../../subscription/screens/subscription_screen.dart';
import '../../../services/payment_api.dart';
import '../../payment/screens/payment_receipt_screen.dart';
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _bg = Color(0xFFF5F7F6);
  static const _surface = Color(0xFFFFFFFF);
  static const _green = Color(0xFF0B5A2A);
  static const _gold = Color(0xFFF5B800);
  static const _muted = Color(0xFF6E8274);
  static const _border = Color(0xFFE8EBE9);
  static const _text = Color(0xFF13261A);

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final navProvider = Provider.of<NavigationProvider>(context);
    final user = userProvider.user;

    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (GoRouter.maybeOf(context) != null) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          'My Account',
          style: GoogleFonts.sora(
            fontWeight: FontWeight.w600,
            color: _green,
            fontSize: 16,
          ),
        ),
        backgroundColor: _surface,
        foregroundColor: _green,
        elevation: 0,
        centerTitle: false,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(user.phoneNumber)
            .snapshots(),
        builder: (context, subSnap) {
          final subData = subSnap.data?.data();
          final planFromSub = subData?['planName'] as String?;
          final planTitle = planFromSub ?? user.subscriptionPlan;
          final planInfo = SubscriptionPlans.byTitle(planTitle);
          final isActive = user.isSubscribed == true ||
              (subData?['status'] as String?)?.toLowerCase() == 'active';
          final upgrades = SubscriptionPlans.upgradesFrom(
            planInfo?.title ?? planTitle,
          );
          final lastPayment = SubscriptionBilling.asDate(
                subData?['lastPaymentDate'],
              ) ??
              SubscriptionBilling.asDate(subData?['startDate']);
          final nextPayment = SubscriptionBilling.asDate(
                subData?['nextPaymentDate'],
              ) ??
              SubscriptionBilling.asDate(subData?['expiryDate']) ??
              (lastPayment != null
                  ? SubscriptionBilling.nextPaymentDate(lastPayment)
                  : null);
          final hoursLeft = SubscriptionBilling.hoursRemaining(nextPayment);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(user),
                const SizedBox(height: 20),
                _subscriptionCard(
                  user: user,
                  planInfo: planInfo,
                  planLabel: planTitle,
                  isActive: isActive,
                  upgrades: upgrades,
                  price: (subData?['price'] as num?)?.toDouble(),
                  lastPayment: lastPayment,
                  nextPayment: nextPayment,
                  hoursLeft: hoursLeft,
                ),
                const SizedBox(height: 20),
                Text(
                  'Personal information',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 10),
                _infoCard(user),
                const SizedBox(height: 20),
                Text(
                  'Services',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 10),
                _actionCard(
                  icon: Icons.receipt_long_rounded,
                  title: 'Payment receipts',
                  subtitle: 'View history and open a receipt',
                  onTap: () {
                    navProvider.setIndex(1);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    );
                  },
                ),
                _actionCard(
                  icon: Icons.description_outlined,
                  title: 'My bill',
                  subtitle: 'Current subscription invoice',
                  onTap: () {
                    navProvider.setIndex(2);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BillsScreen()),
                    );
                  },
                ),
                _actionCard(
                  icon: Icons.workspace_premium_outlined,
                  title: 'All plans',
                  subtitle: 'Compare Monthly, Weekly and Daily',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionScreen(),
                      ),
                    );
                  },
                ),
                _actionCard(
                  icon: Icons.support_agent_rounded,
                  title: 'Contact support',
                  subtitle: 'Talk to WastePro agents',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SupportScreen()),
                    );
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => userProvider.logout(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC1443D),
                      side: const BorderSide(color: Color(0xFFE8C0BC)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Logout',
                      style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNav(navProvider),
    );
  }

  Widget _header(UserModel user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: _green.withValues(alpha: 0.12),
            child: Text(
              user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
              style: GoogleFonts.sora(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: _green,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '+237 ${user.phoneNumber}',
                  style: GoogleFonts.inter(fontSize: 13, color: _muted),
                ),
                if (user.agenceName.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.agenceName,
                    style: GoogleFonts.inter(fontSize: 12, color: _muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscriptionCard({
    required UserModel user,
    required SubscriptionPlanInfo? planInfo,
    required String? planLabel,
    required bool isActive,
    required List<SubscriptionPlanInfo> upgrades,
    required double? price,
    required DateTime? lastPayment,
    required DateTime? nextPayment,
    required int hoursLeft,
  }) {
    final label = planInfo?.title ?? planLabel ?? 'No plan';
    final priceLabel = price != null
        ? '${price.toStringAsFixed(0)} XAF'
        : planInfo != null
            ? '${planInfo.price.toStringAsFixed(0)} XAF'
            : null;
    final renewAmount = price ?? planInfo?.price ?? 3000;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: _gold,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current plan',
                      style: GoogleFonts.inter(fontSize: 12, color: _muted),
                    ),
                    Text(
                      label,
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isActive ? _green : _muted).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isActive ? 'ACTIVE' : 'INACTIVE',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isActive ? _green : _muted,
                  ),
                ),
              ),
            ],
          ),
          if (planInfo != null || priceLabel != null) ...[
            const SizedBox(height: 12),
            Text(
              [
                if (planInfo != null) planInfo.subtitle,
                ?priceLabel,
              ].join(' · '),
              style: GoogleFonts.inter(fontSize: 13, color: _muted),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$hoursLeft',
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _green,
                        ),
                      ),
                      Text(
                        'hours left',
                        style: GoogleFonts.inter(fontSize: 11, color: _muted),
                      ),
                      Text(
                        'until next payment',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 10, color: _muted),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 48, color: _border),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last payment',
                          style:
                              GoogleFonts.inter(fontSize: 11, color: _muted),
                        ),
                        Text(
                          SubscriptionBilling.formatDate(lastPayment),
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Next payment',
                          style:
                              GoogleFonts.inter(fontSize: 11, color: _muted),
                        ),
                        Text(
                          SubscriptionBilling.formatDate(nextPayment),
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openCheckoutForPlan(
                user: user,
                cycleName: planInfo?.title ?? planLabel ?? 'Monthly',
                amount: renewAmount.toDouble(),
              ),
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: Text(
                isActive ? 'Pay / Renew now' : 'Pay now',
                style: GoogleFonts.sora(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (upgrades.isEmpty && isActive)
            Text(
              'You are on the highest plan (Daily).',
              style: GoogleFonts.inter(fontSize: 13, color: _muted),
            )
          else if (!isActive)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'Choose a plan',
                  style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  side: const BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else ...[
            Text(
              'Upgrade to a higher plan',
              style: GoogleFonts.sora(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
            ),
            const SizedBox(height: 10),
            ...upgrades.map((plan) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openCheckoutForPlan(
                      user: user,
                      cycleName: plan.title,
                      amount: plan.price,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  plan.title,
                                  style: GoogleFonts.sora(
                                    fontWeight: FontWeight.w700,
                                    color: _green,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '${plan.subtitle} · ${plan.price.toStringAsFixed(0)} XAF',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Upgrade & pay',
                            style: GoogleFonts.sora(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _gold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: _gold,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _openCheckoutForPlan({
    required UserModel user,
    required String cycleName,
    required double amount,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          amount: amount,
          description: 'WastePro $cycleName subscription',
          purpose: PaymentPurpose.subscription,
          plan: cycleName,
          onPaymentSuccess: (payment) => _finalizeFromProfile(
            user: user,
            cycleName: cycleName,
            payment: payment,
          ),
        ),
      ),
    );
  }

  /// UI-only: the server has already activated the plan.
  Future<void> _finalizeFromProfile({
    required UserModel user,
    required String cycleName,
    required StartedPayment payment,
  }) async {
    final phone = user.phoneNumber;
    await context.read<UserProvider>().refreshUser(phone);
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => PaymentReceiptScreen(
          description: 'WastePro $cycleName subscription',
          amount: payment.amount.toDouble(),
          displayAmount: payment.displayAmount.toDouble(),
          currency: 'XAF',
          status: 'successful',
          method: 'Notch Pay',
          phone: phone,
          customerName: user.fullName,
          createdAt: DateTime.now(),
          isDemoCharge: payment.isDemo,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  Widget _infoCard(UserModel user) {
    final location = user.latitude != null && user.longitude != null
        ? 'Pinned at ${user.latitude!.toStringAsFixed(4)}, ${user.longitude!.toStringAsFixed(4)}'
        : 'No location set yet';

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          _infoRow(Icons.phone_outlined, 'Phone', '+237 ${user.phoneNumber}'),
          const Divider(height: 1, color: _border),
          _infoRow(Icons.badge_outlined, 'Role', user.role.toUpperCase()),
          const Divider(height: 1, color: _border),
          _infoRow(Icons.home_outlined, 'Collection point', location),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String value) {
    return ListTile(
      leading: Icon(icon, color: _green, size: 22),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 12, color: _muted),
      ),
      subtitle: Text(
        value,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _text,
        ),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: _green.withValues(alpha: 0.1),
          child: Icon(icon, color: _green, size: 20),
        ),
        title: Text(
          title,
          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.inter(fontSize: 12, color: _muted),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: _muted),
      ),
    );
  }

  Widget _buildBottomNav(NavigationProvider navProvider) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
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
                  label: 'Home',
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
                  label: 'History',
                  index: 1,
                  onTap: () {
                    navProvider.setIndex(1);
                    // Remplace l'écran courant : la pile reste
                    // [Dashboard, Onglet courant] et « retour » ramène à
                    // l'accueil au lieu de rejouer tous les onglets.
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
                  label: 'Bill',
                  index: 2,
                  onTap: () {
                    navProvider.setIndex(2);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const BillsScreen()),
                    );
                  },
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  navProvider: navProvider,
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  index: 3,
                  onTap: () => navProvider.setIndex(3),
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
      splashColor: _green.withValues(alpha: 0.1),
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
                    ? _green.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: isSelected
                    ? Border.all(
                        color: _green.withValues(alpha: 0.3),
                        width: 1.5,
                      )
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected ? _green : _muted,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? _green : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
