import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/config.dart';
import '../../../core/subscription_billing.dart';
import '../../../core/subscription_plans.dart';
import '../../../services/payment_api.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/navigation_provider.dart';
import '../../payment/screens/checkout_screen.dart';
import '../../payment/screens/payment_receipt_screen.dart';
import '../../payment/screens/bills_screen.dart';
import '../../profile/screens/profile_screen.dart';
import 'history_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.upgradeToPlan});

  /// When set (e.g. "Weekly"), opens focused on upgrading to that plan.
  final String? upgradeToPlan;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  // Design System Colors
  final Color dBg = const Color(0xFFF5F7F6);
  final Color dSurface = const Color(0xFFFFFFFF);
  final Color dGreen = const Color(0xFF0B5A2A);
  final Color dGold = const Color(0xFFF5B800);
  final Color dMuted = const Color(0xFF6E8274);
  final Color dBorder = const Color(0xFFE8EBE9);

  // Zone calendar data fetched from Firestore.
  List<String> _zoneDays = [];
  String _zonePickupTime = '';
  String _zoneName = '';
  bool _zoneLoaded = false;

  /// End of the running subscription: a plan paid now starts then.
  DateTime? _currentEnd;

  /// Collection days offered when the agency defined no zone calendar
  /// (mirrors WEEK_DAYS in functions/index.js).
  static const _weekDays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadZoneCalendar();
    final target = widget.upgradeToPlan;
    if (target == null || !mounted) return;
    // Let the plans UI paint, then open checkout so the user can enter payment.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    final plan = SubscriptionPlans.byTitle(target);
    if (plan == null) return;
    await _handleSubscription(plan.title, plan.price);
  }



  /// Loads the client's zone calendar (the agency's zone matching the
  /// client's own zone — the same rule as the server, which re-checks the
  /// days at payment) and the end of the running subscription.
  Future<void> _loadZoneCalendar() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;
    final db = FirebaseFirestore.instance;

    try {
      final me = (await db.collection('users').doc(user.phoneNumber).get())
          .data();
      final end = SubscriptionBilling.asDate(me?['subscription_end']);
      if (me?['isSubscribed'] == true && end != null &&
          end.isAfter(DateTime.now())) {
        _currentEnd = end;
      }

      // The client's own record carries their zone.
      final mine = await db
          .collection('clients')
          .where('phone', isEqualTo: user.phoneNumber)
          .limit(1)
          .get();
      final clientZone = mine.docs.isEmpty
          ? ''
          : mine.docs.first.data()['zone'] as String? ?? '';
      if (clientZone.isNotEmpty && user.agenceId.isNotEmpty) {
        final zones = await db
            .collection('zones')
            .where('agenceId', isEqualTo: user.agenceId)
            .get();
        for (final z in zones.docs) {
          final data = z.data();
          final name = data['name'] as String? ?? '';
          if (!_zonesMatch(clientZone, name)) continue;
          _zoneDays = (data['collectionDays'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          _zonePickupTime =
              data['standardPickupTime'] as String? ?? '07:00 — 08:00';
          _zoneName = name;
          break;
        }
      }
    } catch (_) {
      // Server-side fallback: the payment always gets valid days.
    }
    if (mounted) setState(() => _zoneLoaded = true);
  }

  /// "Yaoundé: Bastos" matches the zone "Bastos" (accents / case ignored)
  /// — mirrors zonesMatch() in functions/index.js.
  static bool _zonesMatch(String clientZone, String zoneName) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[àâä]'), 'a')
        .replaceAll(RegExp('[îï]'), 'i')
        .replaceAll(RegExp('[ôö]'), 'o')
        .replaceAll(RegExp('[ùûü]'), 'u')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final full = norm(clientZone);
    final last = full.contains(':') ? full.split(':').last.trim() : full;
    final z = norm(zoneName);
    if (z.isEmpty) return false;
    return [full, last].any(
      (k) => k.isNotEmpty && (k == z || k.contains(z) || z.contains(k)),
    );
  }

  /// Collection days per week sold with each plan (Daily = every day).
  static int _daysPerWeek(String plan) => switch (plan.toLowerCase()) {
        'monthly' => 1,
        'weekly' => 2,
        _ => 0,
      };

  // Professional Payment Handshake Logic
  Future<void> _handleSubscription(String cycleName, double amount) async {
    // --- Step 0: collection days, from the zone calendar (or any working
    // day when the agency has none). Daily = all of them, no choice.
    final options = _zoneDays.isNotEmpty ? _zoneDays : _weekDays;
    final perWeek = _daysPerWeek(cycleName);
    List<String> resolvedDays = List.of(options);
    if (perWeek > 0 && perWeek < options.length) {
      final chosen = await _showDayPickerDialog(cycleName, perWeek, options);
      if (chosen == null || !mounted) return; // user cancelled
      resolvedDays = chosen;
    }

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user!;
    final phone = user.phoneNumber;

    // Always open Checkout so the user can choose a method and enter phone/PIN.
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          amount: amount,
          description: 'WastePro $cycleName subscription',
          purpose: PaymentPurpose.subscription,
          plan: cycleName,
          collectionDays: resolvedDays,
          pickupTime: _zonePickupTime,
          zoneName: _zoneName,
          onPaymentSuccess: (payment) => _finalizeSubscription(
            cycleName: cycleName,
            payment: payment,
            phone: phone,
            resolvedDays: resolvedDays,
            userProvider: userProvider,
          ),
        ),
      ),
    );
  }

  /// Shows the confirmation after the server has activated the contract,
  /// subscription and invoice (see `settle` in functions/index.js).
  Future<void> _finalizeSubscription({
    required String cycleName,
    required StartedPayment payment,
    required String phone,
    required List<String> resolvedDays,
    required UserProvider userProvider,
  }) async {
    try {
      if (mounted) {
        final daySummary = resolvedDays.isNotEmpty
            ? ' on ${resolvedDays.join(', ')}'
            : '';
        // A plan paid while another runs starts when that one ends.
        final startsLater = _currentEnd;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(startsLater != null
                ? 'Paid! Your $cycleName plan starts on '
                    '${SubscriptionBilling.formatDate(startsLater)}'
                    '$daySummary.'
                : 'Success! Your $cycleName contract is now active'
                    '$daySummary.'),
            backgroundColor: dGreen,
          ),
        );
        await userProvider.refreshUser(phone);
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
              customerName: userProvider.user?.fullName,
              createdAt: DateTime.now(),
              isDemoCharge: payment.isDemo,
            ),
          ),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  /// Shows a dialog for the client to pick exactly [maxPick] collection
  /// day(s) among [options]. Returns null if cancelled.
  Future<List<String>?> _showDayPickerDialog(
    String plan,
    int maxPick,
    List<String> options,
  ) async {
    final selected = <String>[];

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            'Choose your collection day${maxPick > 1 ? 's' : ''}',
            style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: dGreen),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$plan plan — pick $maxPick collection day${maxPick > 1 ? 's' : ''} '
                'per week${_zoneName.isNotEmpty ? ' (zone $_zoneName)' : ''}.',
                style: GoogleFonts.inter(fontSize: 12, color: dMuted, height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options.map((day) {
                  final isSelected = selected.contains(day);
                  return GestureDetector(
                    onTap: () {
                      setDialogState(() {
                        if (isSelected) {
                          selected.remove(day);
                        } else if (selected.length < maxPick) {
                          selected.add(day);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? dGreen : dSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? dGreen : dBorder,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        day,
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : dGreen,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_zonePickupTime.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.schedule_outlined, size: 14, color: dMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Pickup window: $_zonePickupTime',
                      style: GoogleFonts.inter(fontSize: 11, color: dMuted),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: GoogleFonts.inter(fontSize: 13, color: dMuted)),
            ),
            TextButton(
              onPressed: selected.length != maxPick
                  ? null
                  : () => Navigator.of(ctx).pop(selected.toList()),
              child: Text(
                'Confirm',
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected.length != maxPick ? dMuted : dGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navProvider = Provider.of<NavigationProvider>(context);
    final user = Provider.of<UserProvider>(context).user;
    final currentRank = SubscriptionPlans.rankOf(user?.subscriptionPlan);
    final upgradeFocus = widget.upgradeToPlan;
    
    return Scaffold(
      backgroundColor: dBg,
      appBar: AppBar(
        title: Text(
          upgradeFocus != null ? "Upgrade plan" : "Service Plans",
          style: GoogleFonts.sora(fontWeight: FontWeight.w600, color: dGreen, fontSize: 16),
        ),
        backgroundColor: dSurface,
        elevation: 0,
        foregroundColor: dGreen,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  upgradeFocus != null
                      ? "Upgrade to $upgradeFocus"
                      : "Choose Your Plan",
                  style: GoogleFonts.sora(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: dGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  upgradeFocus != null
                      ? "Pay to switch to a higher collection frequency"
                      : "Select a collection frequency — you can change it "
                          "every month",
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: dMuted,
                  ),
                ),
                if (_currentEnd != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: dGreen.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_repeat, size: 18, color: dGreen),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your current plan runs until '
                            '${SubscriptionBilling.formatDate(_currentEnd)}. '
                            'Renew or switch plan now: the new plan starts '
                            'that day — no day lost.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: dGreen,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                _buildPlanCard(
                  "Monthly",
                  3000,
                  "1 Collection per week",
                  Icons.calendar_month,
                  false,
                  currentRank: currentRank,
                ),
                _buildPlanCard(
                  "Weekly",
                  5500,
                  "2 Collections per week",
                  Icons.view_week,
                  true,
                  currentRank: currentRank,
                ),
                _buildPlanCard(
                  "Daily",
                  15000,
                  "Collection every single day",
                  Icons.wb_sunny,
                  false,
                  currentRank: currentRank,
                ),
                
                const SizedBox(height: 14),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 13, color: dMuted),
                      const SizedBox(width: 6),
                      Text(
                        "Secure payment via CamPay",
                        style: TextStyle(color: dMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (AppConfig.isCampayDemo) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: dGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "Demo mode - CamPay charges "
                      "${AppConfig.campayDemoMaxAmount.toStringAsFixed(0)} XAF "
                      "even if the plan shows 3000 / 5500 / 15000 XAF. "
                      "Real prices apply in production.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: dMuted, fontSize: 11, height: 1.4),
                    ),
                  ),
                ]
              ],
            ),
          ),
      bottomNavigationBar: _buildBottomNav(navProvider),
    );
  }

  Widget _buildPlanCard(
    String title,
    double price,
    String subtitle,
    IconData icon,
    bool isPopular, {
    required int currentRank,
  }) {
    // Any plan can be chosen each month: renew the current one, move up or
    // down. Paid while a plan runs, it starts when that one ends.
    final planRank = SubscriptionPlans.rankOf(title);
    final isCurrent = currentRank > 0 && planRank == currentRank;
    final isUpgrade = planRank > currentRank && currentRank > 0;
    final isLower = currentRank > 0 && planRank < currentRank;
    final ctaLabel = isCurrent
        ? 'RENEW'
        : isUpgrade
            ? 'UPGRADE'
            : isLower
                ? 'SWITCH'
                : 'SUBSCRIBE';
    // Waits for the zone calendar (collection days) before paying.
    final enabled = _zoneLoaded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPopular ? dGold.withValues(alpha: 0.3) : dBorder,
          width: isPopular ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isPopular ? dGold.withValues(alpha: 0.15) : dGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon, 
                  color: isPopular ? dGold : dGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title, 
                          style: GoogleFonts.sora(
                            color: dGreen, 
                            fontSize: 14, 
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isPopular) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: dGold,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "POPULAR",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: dGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "YOURS",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle, 
                      style: TextStyle(
                        color: dMuted, 
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${price.toInt()} XAF", 
                    style: GoogleFonts.sora(
                      color: dGreen, 
                      fontSize: 18, 
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    "per cycle",
                    style: TextStyle(
                      color: dMuted, 
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: enabled
                      ? (isUpgrade || isPopular ? dGold : dGreen)
                      : dMuted.withValues(alpha: 0.35),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  elevation: 0,
                ),
                onPressed: enabled ? () => _handleSubscription(title, price) : null,
                child: Text(
                  ctaLabel,
                  style: GoogleFonts.sora(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

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
              _buildNavItem(
                navProvider: navProvider,
                icon: Icons.home_rounded,
                label: "Home",
                index: 0,
                onTap: () {
                  navProvider.setIndex(0);
                  Navigator.pop(context);
                },
              ),
              _buildNavItem(
                navProvider: navProvider,
                icon: Icons.history_rounded,
                label: "History",
                index: 1,
                onTap: () {
                  navProvider.setIndex(1);
                  // Remplace l'écran courant : la pile reste
                  // [Dashboard, Onglet courant] et « retour » ramène à
                  // l'accueil au lieu de rejouer tous les onglets.
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HistoryScreen(),
                    ),
                  );
                },
              ),
              _buildNavItem(
                navProvider: navProvider,
                icon: Icons.description_rounded,
                label: "Bill",
                index: 2,
                onTap: () {
                  navProvider.setIndex(2);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const BillsScreen()),
                  );
                },
              ),
              _buildNavItem(
                navProvider: navProvider,
                icon: Icons.person_rounded,
                label: "Profile",
                index: 3,
                onTap: () {
                  navProvider.setIndex(3);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
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
      splashColor: dGreen.withValues(alpha: 0.1),              child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isSelected ? dGreen.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: isSelected 
                    ? Border.all(color: dGreen.withValues(alpha: 0.3), width: 1.5)
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected ? dGreen : dMuted,
                size: 21,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
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