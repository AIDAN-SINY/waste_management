import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/navigation_provider.dart';
import '../../payment/screens/bills_screen.dart';
import '../../payment/screens/payment_receipt_screen.dart';
import '../../profile/screens/profile_screen.dart';
import 'subscription_screen.dart';

/// Historique des paiements (« My Bill ») — alimenté par la collection
/// `transactions` (écrite par [PaymentService] après chaque encaissement
/// CamPay). Plus jamais un écran vide : chaque paiement réussi
/// (abonnement, collecte supplémentaire…) apparaît ici.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Design System Colors
  final Color dBg = const Color(0xFFF5F7F6);
  final Color dSurface = const Color(0xFFFFFFFF);
  final Color dGreen = const Color(0xFF0B5A2A);
  final Color dGold = const Color(0xFFF5B800);
  final Color dMuted = const Color(0xFF6E8274);
  final Color dBorder = const Color(0xFFE8EBE9);
  final Color dRed = const Color(0xFFC1443D);

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user!;
    final navProvider = Provider.of<NavigationProvider>(context);

    return Scaffold(
      backgroundColor: dBg,
      appBar: AppBar(
        title: Text(
          "Payment History",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: dGreen),
        ),
        backgroundColor: dSurface,
        elevation: 0,
        foregroundColor: dGreen,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Transactions du client — sorted in Dart to avoid
        // requiring a composite Firestore index.
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('phone', isEqualTo: user.phoneNumber)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "Unable to load your payment history.\n${snapshot.error}",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: dMuted, fontSize: 14),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B5A2A)),
            );
          }

          // Sort in Dart to avoid needing a composite index.
          final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            snapshot.data!.docs,
          );
          docs.sort((a, b) {
            final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate();
            final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate();
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });
          if (docs.isEmpty) {
            return _buildEmptyState();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 100,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Payment History",
                  style: GoogleFonts.sora(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: dGreen,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Track your payments",
                  style: GoogleFonts.inter(fontSize: 14, color: dMuted),
                ),
                const SizedBox(height: 24),
                ...docs.map((doc) => _buildTransactionCard(doc)),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNav(navProvider),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 64,
              color: dMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              "No payments yet.",
              style: GoogleFonts.inter(
                color: dMuted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Subscribe to a plan to get started — every payment will "
              "appear here.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: dMuted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: dGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                "View Plans",
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final title = (data['description'] as String? ?? 'Payment').trim();
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final currency = data['currency'] as String? ?? 'XAF';
    final status = (data['status'] as String? ?? 'cancelled').toLowerCase();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    final isSuccess = status == 'successful';
    final statusLabel = isSuccess
        ? 'SUCCESS'
        : status == 'pending'
        ? 'PENDING'
        : 'FAILED';
    final statusColor = isSuccess ? dGreen : dRed;
    final statusBg = isSuccess
        ? dGreen.withValues(alpha: 0.1)
        : dRed.withValues(alpha: 0.1);
    final date = createdAt == null
        ? ''
        : '${createdAt.day}/${createdAt.month}/${createdAt.year}';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentReceiptScreen.fromMap(
              data,
              transactionId: doc.id,
            ),
          ),
        );
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.receipt_long,
              color: Color(0xFF0B5A2A),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sora(
                    color: dGreen,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Paid: ${amount.toStringAsFixed(0)} $currency",
                  style: GoogleFonts.inter(color: dMuted, fontSize: 13),
                ),
                if (date.isNotEmpty)
                  Text(
                    "Date: $date",
                    style: GoogleFonts.inter(color: dMuted, fontSize: 12),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Tap to open receipt',
                  style: GoogleFonts.inter(
                    color: dGreen.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusLabel,
              style: GoogleFonts.inter(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildBottomNav(NavigationProvider navProvider) {
    // Content-sized bar + outer SafeArea (same fix as ClientBottomNav):
    // a fixed height + inner SafeArea overflowed on devices with a
    // system navigation bar.
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
        top: false,
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
                    // Remplace l'écran courant : la pile reste
                    // [Dashboard, Onglet courant] et « retour » ramène à
                    // l'accueil au lieu de rejouer tous les onglets.
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
                color: isSelected ? dGreen.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: isSelected
                    ? Border.all(color: dGreen.withValues(alpha: 0.3), width: 1.5)
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
