import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/notification_model.dart';
import 'pickup_confirmation_screen.dart';

/// Client dashboard Notifications screen — lists in-app notifications
/// received (agency manager decisions on applications, future product
/// notifications...).
///
/// Opened from the dashboard bell: notifications are marked as read on
/// open (the bell badge disappears).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    FirebaseFirestore? db,
    required this.phone,
  }) : _db = db;

  /// Optional Firestore instance for testing; otherwise the default.
  final FirebaseFirestore? _db;

  /// Numéro de téléphone du client connecté (canonique).
  final String phone;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  FirebaseFirestore get _db => widget._db ?? FirebaseFirestore.instance;

  // Palette du dashboard client (fond clair).
  static const Color dBg = Color(0xFFF4F7F2);
  static const Color dSurface = Color(0xFFFFFFFF);
  static const Color dBorder = Color(0xFFE1E9DD);
  static const Color dText = Color(0xFF13261A);
  static const Color dMuted = Color(0xFF6E8274);
  static const Color dGreen = Color(0xFF0B5A2A);
  static const Color dGreenSoft = Color(0xFFE6F2E4);
  static const Color dGold = Color(0xFFF5B800);
  static const Color dGoldSoft = Color(0xFFFFF4CC);
  static const Color dRed = Color(0xFFC1443D);

  @override
  void initState() {
    super.initState();
    // Mark all as read on open (fire-and-forget).
    _markAllRead();
  }

  /// Opens the pickup confirmation screen when the user taps a
  /// pickup_to_confirm notification.
  Future<void> _onTapNotification(NotificationModel n) async {
    if (n.type == 'pickup_to_confirm') {
      // Mark as read.
      await _db.collection('notifications').doc(n.id).update({'read': true});
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PickupConfirmationScreen(
            db: _db,
            // Real pickup document id carried by the notification payload —
            // falls back to the latest pending pickup when empty (legacy
            // notifications written before the payload existed).
            pickupId: n.pickupId,
          ),
        ),
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      final snap = await _db
          .collection('notifications')
          .where('phone', isEqualTo: widget.phone)
          .get();
      final unread = snap.docs.where(
        (d) => (d.data()['read'] as bool? ?? false) != true,
      );
      if (unread.isEmpty) return;
      final batch = _db.batch();
      for (final doc in unread) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {
      // Silent: a read failure should not block the screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dBg,
      appBar: AppBar(
        backgroundColor: dBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: dGreen),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.sora(
            color: dText,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('notifications')
              .where('phone', isEqualTo: widget.phone)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(
                child: Text(
                  'Could not load notifications.',
                  style: TextStyle(color: dMuted),
                ),
              );
            }
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? const [];
            if (docs.isEmpty) return _emptyState();
            final items = docs.map(
              (d) => NotificationModel.fromMap(d.id, d.data()),
            ).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
              final n = items[index];
              // Tap on a pickup_to_confirm notification opens the confirmation screen.
              return GestureDetector(
                onTap: () => _onTapNotification(n),
                child: _item(n),
              );
            },
            );
          },
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: dGreenSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 32,
              color: dGreen,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: GoogleFonts.sora(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: dText,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'You will be notified here when something needs your attention.',
            textAlign: TextAlign.center,
            style: TextStyle(color: dMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _item(NotificationModel n) {
    final pickupRequest = n.type == 'pickup_to_confirm';
    final pickupConfirmed = n.type == 'pickup_confirmed';
    final pickupDisputed = n.type == 'pickup_disputed';
    final approved = n.type == 'approved';
    final iconColor = pickupConfirmed
        ? dGreen
        : pickupDisputed
            ? dRed
            : pickupRequest
                ? dGold
                : approved
                    ? dGreen
                    : dRed;
    final iconBg = pickupConfirmed
        ? dGreenSoft
        : pickupDisputed
            ? dRed.withValues(alpha: 0.1)
            : pickupRequest
                ? const Color(0xFFFFF4CC)
                : approved
                    ? dGreenSoft
                    : dRed.withValues(alpha: 0.1);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dSurface,
        border: Border.all(color: dBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(
              pickupConfirmed
                  ? Icons.check_circle_rounded
                  : pickupDisputed
                      ? Icons.report_rounded
                      : pickupRequest
                          ? Icons.notifications_active_rounded
                          : approved
                              ? Icons.check_rounded
                              : Icons.close_rounded,
              color: iconColor,
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
                    Expanded(
                      child: Text(
                        n.title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: dText,
                        ),
                      ),
                    ),
                    Text(
                      n.createdAt,
                      style: const TextStyle(fontSize: 10.5, color: dMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  n.message,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: dMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
