import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart';
import '../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/navigation_provider.dart';
import '../subscription/screens/subscription_screen.dart';
import '../payment/screens/extra_pickup_screen.dart';
import '../payment/screens/bills_screen.dart';
import '../auth/screens/welcome_screen.dart';
import 'notifications_screen.dart';
import 'pickup_confirmation_screen.dart';
import 'support_screen.dart';
import 'chatbot_screen.dart';
import 'chatbot_robot_icon.dart';
import 'collector_tracking_screen.dart';
import 'client_bottom_nav.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key, FirebaseFirestore? db}) : _db = db;

  /// Optional Firestore instance for testing.
  final FirebaseFirestore? _db;

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard>
    with TickerProviderStateMixin {
  AnimationController? _animationController;
  Animation<double>? _progressAnimation;

  // Pulse animation for the chatbot FAB.
  AnimationController? _pulseController;
  Animation<double>? _pulseScale;
  Animation<double>? _pulseGlow;

  // --- Design System Colors ---
  final Color bgDark = const Color(0xFF0B5A2A);
  final Color bgDarker = const Color(0xFF073A1B);
  final Color accentGold = const Color(0xFFF5B800);
  final Color accentRed = const Color(0xFFC1443D);
  final Color cream = const Color(0xFFF5F1E8);
  final Color muted = const Color(0xFFAEC0B7);
  final Color dBg = const Color(0xFFF4F7F2);
  final Color dSurface = const Color(0xFFFFFFFF);
  final Color dBorder = const Color(0xFFE1E9DD);
  final Color dText = const Color(0xFF13261A);
  final Color dMuted = const Color(0xFF6E8274);
  final Color dGreen = const Color(0xFF0B5A2A);
  final Color dGreenSoft = const Color(0xFFE6F2E4);
  final Color dGold = const Color(0xFFF5B800);
  final Color dGoldSoft = const Color(0xFFFFF4CC);
  final Color dRed = const Color(0xFFC1443D);
  final Color dRedSoft = const Color(0xFFF8E4E2);

  FirebaseFirestore get _db => widget._db ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _progressAnimation = Tween<double>(begin: 0, end: 0.375).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeOut),
    );

    _animationController!.repeat(reverse: true);
    _animationController!.forward();

    // Chatbot FAB pulse animation.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _pulseController!,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );
    _pulseGlow = Tween<double>(begin: 0.35, end: 0.6).animate(
      CurvedAnimation(
        parent: _pulseController!,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );
    _pulseController!.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;
    final navProvider = Provider.of<NavigationProvider>(context);

    // Redirect to login if user is null (after logout).
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
      backgroundColor: dBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: 20,
            right: 20,
            top: 10,
            bottom: 100,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(user),
              const SizedBox(height: 6),

              _buildContractCard(user),
              const SizedBox(height: 22),

              _buildWeeklySchedule(user),
              const SizedBox(height: 22),

              _sectionTitle("Quick Access"),
              const SizedBox(height: 12),
              _buildQuickActions(),

              const SizedBox(height: 12),

              // QR validation: opens the pickup confirmation screen (QR +
              // “Scan” button) where the client validates a pickup the
              // collector has marked as done.
              _buildMyQrCard(user),

              const SizedBox(height: 22),

              _buildMonthlyStats(),

              const SizedBox(height: 22),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionTitle("Tracking"),
                  Text(
                    "Details",
                    style: TextStyle(
                      color: dGold,
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildChartSection(),
              const SizedBox(height: 12),
              _buildCollectorTracking(user),

              const SizedBox(height: 22),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionTitle("Recent Activity"),
                  Text(
                    "View All",
                    style: TextStyle(
                      color: dGold,
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildRecentActivity(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(navProvider),
      floatingActionButton: _buildChatFab(),
    );
  }

  // --- UI Building Blocks ---

  Widget _buildHeader(UserModel user) {
    final initials =
        user.fullName.split(' ').map((name) => name[0]).take(2).join();
    final firstName = user.fullName.split(' ')[0];
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour < 12) {
      greeting = "Good morning";
    } else if (hour < 18) {
      greeting = "Good afternoon";
    } else {
      greeting = "Good evening";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: dGreen,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: GoogleFonts.sora(
                      color: cream,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "$greeting, $firstName",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        color: dText,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: dMuted,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            _formatLocation(user),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: dMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _buildNotificationBell(user),
      ],
    );
  }

  /// Notification bell with unread count badge from Firestore stream.
  Widget _buildNotificationBell(UserModel user) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NotificationsScreen(
              db: widget._db,
              phone: user.phoneNumber,
            ),
          ),
        );
      },
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: dSurface,
          shape: BoxShape.circle,
          border: Border.all(color: dBorder),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.notifications_none_outlined,
              color: dGreen,
              size: 18,
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('notifications')
                  .where('phone', isEqualTo: user.phoneNumber)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                final unread = docs
                    .where(
                        (d) => (d.data()['read'] as bool? ?? false) != true)
                    .length;
                if (unread == 0) return const SizedBox.shrink();
                return Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 15),
                    height: 15,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: dRed,
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: dSurface, width: 1.2),
                    ),
                    child: Center(
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: TextStyle(
                          color: cream,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContractCard(UserModel user) {
    // Read the user's contract data from Firestore in real time.
    // Stream subscription price from Firestore.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('subscriptions').doc(user.phoneNumber).snapshots(),
      builder: (context, subSnap) {
        final subData = subSnap.data?.data();
        final price = (subData?['price'] as num?)?.toDouble() ?? 0;
        final subStatus = subData?['status'] as String? ?? 'inactive';
        final isActive = subStatus == 'active';

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db.collection('users').doc(user.phoneNumber).snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data();
            final plan = data?['subscription_plan'] as String? ?? '';
            final collectionDays =
                (data?['collection_days'] as List<dynamic>?)?.cast<String>() ?? [];
            final pickupTime = data?['pickup_time'] as String? ?? '';
            final isSubscribed = data?['isSubscribed'] as bool? ?? false;

            // Compute next pickup from zone calendar.
            final nextPickup = _computeNextPickup(collectionDays);
            final hoursUntil = nextPickup != null
                ? nextPickup.difference(DateTime.now()).inHours
                : 0;

            // Format plan label: "Weekly · 2x/week" etc.
            final planLabel = _formatPlanLabel(plan, collectionDays.length);

            // Format next pickup line.
            final nextPickupText = _formatNextPickupText(
              nextPickup,
              pickupTime,
              user,
              data?['zone_name'] as String? ?? '',
            );

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
                    children: [
                      // Circular countdown ring
                      AnimatedBuilder(
                        animation: _progressAnimation!,
                        builder: (context, child) {
                          return SizedBox(
                            width: 76,
                            height: 76,
                            child: CustomPaint(
                              painter: _RingPainter(
                                progress: isSubscribed ? _progressAnimation!.value : 0,
                                backgroundColor: cream.withValues(alpha: 0.15),
                                foregroundColor: dGold,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "$hoursUntil",
                                      style: GoogleFonts.sora(
                                        color: cream,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      "h",
                                      style: GoogleFonts.sora(
                                        color: cream,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      "remaining",
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 8.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: dGold.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                planLabel,
                                style: TextStyle(
                                  color: dGold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.03,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Next pickup",
                              style: GoogleFonts.sora(
                                color: cream,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              nextPickupText,
                              style: TextStyle(
                                color: muted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Bill amount row (tap to view bills)
                  if (isActive && price > 0) ...[
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BillsScreen()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: cream.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.receipt_long_rounded,
                              color: dGold,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Current Bill",
                                style: TextStyle(
                                  color: cream.withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              "${price.toStringAsFixed(0)} XAF",
                              style: GoogleFonts.sora(
                                color: dGold,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: cream.withValues(alpha: 0.5),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Weekly schedule card — the client's own collection days
  /// (`collection_days` + `pickup_time` from their `users` doc), shown as a
  /// Monday→Sunday strip with today's day highlighted.
  Widget _buildWeeklySchedule(UserModel user) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('users').doc(user.phoneNumber).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final collectionDays =
            (data?['collection_days'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const [];
        final pickupTime = data?['pickup_time'] as String? ?? '';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dSurface,
            border: Border.all(color: dBorder),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: dGreenSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.calendar_month_outlined,
                      color: dGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Weekly Schedule",
                          style: GoogleFonts.sora(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: dText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          collectionDays.isEmpty
                              ? 'No collection days yet'
                              : 'Your collection days',
                          style: TextStyle(color: dMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (pickupTime.isNotEmpty)
                    Text(
                      pickupTime,
                      style: GoogleFonts.sora(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: dGold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (collectionDays.isEmpty)
                Text(
                  'Subscribe to a plan to get scheduled pickups.',
                  style: TextStyle(color: dMuted, fontSize: 11.5),
                )
              else
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(child: _dayCell(i, collectionDays)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  /// One cell of the weekly strip: [weekdayIndex] is 0=Monday … 6=Sunday.
  Widget _dayCell(int weekdayIndex, List<String> collectionDays) {
    const shortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const fullNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final isPickup = collectionDays.contains(fullNames[weekdayIndex]);
    final isToday = DateTime.now().weekday == weekdayIndex + 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isPickup ? dGreen : dSurface,
            shape: BoxShape.circle,
            border: Border.all(
              color: isPickup ? dGreen : dBorder,
              width: isToday ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              shortNames[weekdayIndex],
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: isPickup ? cream : dMuted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Petit repère « aujourd'hui » sous la pastille du jour courant.
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: isToday ? dGold : Colors.transparent,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _actionItem(
          Icons.add,
          "Request Pickup",
          dGoldSoft,
          dGold,
        ),
        _actionItem(
          Icons.receipt_long_outlined,
          "My Bill",
          dGreenSoft,
          dGreen,
        ),
        _actionItem(
          Icons.chat_bubble_outline,
          "Support",
          const Color(0xFFE7EEFB),
          const Color(0xFF3D6BE8),
        ),
      ],
    );
  }

  /// “My QR code” card: opens the pickup validation screen showing the QR
  /// code with the collection info and a “Scan” button. A live badge is
  /// displayed while a pickup awaits the client's validation.
  Widget _buildMyQrCard(UserModel user) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('pickups')
          .where('client_id', isEqualTo: user.phoneNumber)
          .where('status', isEqualTo: 'pending_client_confirmation')
          .snapshots(),
      builder: (context, snap) {
        final pendingCount = snap.data?.docs.length ?? 0;
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PickupConfirmationScreen(
                  db: widget._db,
                  // Empty id: the screen resolves the client's latest
                  // pending pickup itself.
                  pickupId: '',
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dSurface,
              border: Border.all(
                color: pendingCount > 0 ? dGold : dBorder,
                width: pendingCount > 0 ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: dGreenSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: dGreen,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "My QR code",
                        style: GoogleFonts.sora(
                          color: dText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pendingCount > 0
                            ? '$pendingCount pickup${pendingCount > 1 ? 's' : ''} '
                                'awaiting your validation'
                            : 'Validate a pickup by scanning your code',
                        style: TextStyle(
                          color: pendingCount > 0 ? dGold : dMuted,
                          fontSize: 11.5,
                          fontWeight: pendingCount > 0
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (pendingCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: dGoldSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$pendingCount',
                      style: GoogleFonts.sora(
                        color: dGold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  color: dMuted,
                  size: 22,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Subscription / Monthly Stats ---

  Widget _buildMonthlyStats() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dSurface,
          border: Border.all(color: dBorder),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: dGoldSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                color: dGold,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Subscription Plan",
                    style: GoogleFonts.sora(
                      color: dText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "View available plans & upgrade",
                    style: TextStyle(
                      color: dMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: dMuted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // --- Waste Chart ---

  Widget _buildChartSection() {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dSurface,
        border: Border.all(color: dBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Waste Collected",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Last 6 months",
                style: TextStyle(
                  fontSize: 10,
                  color: dMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: BarChart(
              BarChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const months = [
                          'Feb',
                          'Mar',
                          'Apr',
                          'May',
                          'Jun',
                          'Jul'
                        ];
                        if (value.toInt() >= 0 &&
                            value.toInt() < months.length) {
                          return Text(
                            months[value.toInt()],
                            style: TextStyle(
                              color: dMuted,
                              fontSize: 10,
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(
                    x: 0,
                    barRods: [
                      BarChartRodData(
                        toY: 18,
                        color: dGreen,
                        width: 22,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 1,
                    barRods: [
                      BarChartRodData(
                        toY: 22,
                        color: dGreen,
                        width: 22,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 2,
                    barRods: [
                      BarChartRodData(
                        toY: 19,
                        color: dGreen,
                        width: 22,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 3,
                    barRods: [
                      BarChartRodData(
                        toY: 25,
                        color: dGreen,
                        width: 22,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 4,
                    barRods: [
                      BarChartRodData(
                        toY: 21,
                        color: dGreen,
                        width: 22,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
                  BarChartGroupData(
                    x: 5,
                    barRods: [
                      BarChartRodData(
                        toY: 24,
                        color: dGreen,
                        width: 22,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Collector Tracking (with mini-map) ---

  Widget _buildCollectorTracking(UserModel user) {
    final collecteurId = user.collecteurId;
    if (collecteurId.isEmpty) {
      return _collectorCard(
        initials: "?",
        name: "No collector assigned yet",
        sub: "Your agency will assign one after approval",
        icon: Icons.person_search_outlined,
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('collecteurs').doc(collecteurId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData || !snap.data!.exists) {
          return _collectorCard(
            initials: "?",
            name: "Collector unavailable",
            sub: "Contact your agency for details",
            icon: Icons.person_off_outlined,
          );
        }
        final data = snap.data!.data()!;
        final name = (data['name'] as String? ?? '').trim();
        final rating = (data['rating'] as num?)?.toDouble() ?? 0;
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        if (name.isEmpty) {
          return _collectorCard(
            initials: "?",
            name: "Collector unavailable",
            sub: "Contact your agency for details",
            icon: Icons.person_off_outlined,
          );
        }
        final initials = name
            .split(' ')
            .where((p) => p.isNotEmpty)
            .map((p) => p[0])
            .take(2)
            .join()
            .toUpperCase();
        final stars = rating >= 4.5
            ? ""
            : rating >= 3.5
                ? ""
                : rating >= 2.5
                    ? ""
                    : "";
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CollectorTrackingScreen(
                  collecteurId: collecteurId,
                  collecteurName: name,
                  collecteurInitials: initials,
                  db: _db,
                ),
              ),
            );
          },
          child: Column(
            children: [
              _collectorCard(
                initials: initials,
                name: name,
                sub: '$stars ${rating.toStringAsFixed(1)}',
                icon: Icons.person_pin_circle_outlined,
              ),
              // Mini-map showing collector location
              if (lat != null && lng != null) ...[
                const SizedBox(height: 12),
                _buildCollectorMiniMap(lat, lng, name),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Compact mini-map showing the collector's position on an OSM tile.
  Widget _buildCollectorMiniMap(double lat, double lng, String name) {
    final collectorPos = LatLng(lat, lng);
    // Center slightly offset so marker isn't dead center.
    final center = LatLng(lat + 0.002, lng);
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.proprie237.waste_pro',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: collectorPos,
                    width: 32,
                    height: 32,
                    child: Container(
                      decoration: BoxDecoration(
                        color: dGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_shipping,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Overlay label
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: dSurface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Brand.leaf,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: dText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Common collector card body (assigned or not).
  Widget _collectorCard({
    required String initials,
    required String name,
    required String sub,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dSurface,
        border: Border.all(color: dBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: dGoldSoft,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: GoogleFonts.sora(
                  color: dGold,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: dText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: dMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 20, color: dGreen),
        ],
      ),
    );
  }

  // --- Recent Activity ---

  Widget _buildRecentActivity() {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    final phone = user?.phoneNumber ?? '';
    if (phone.isEmpty) return _buildEmptyActivity();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('pickups')
          .where('client_id', isEqualTo: phone)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _buildEmptyActivity();
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: CircularProgressIndicator(color: dGreen),
            ),
          );
        }

        final pickups = (snap.data?.docs ?? const [])
            .map((d) => d.data())
            .where((p) => p['status'] != null)
            .toList()
          ..sort((a, b) {
            final ta = a['timestamp'];
            final tb = b['timestamp'];
            return _pickupTime(tb).compareTo(_pickupTime(ta));
          });
        final latest = pickups.take(3).toList();
        if (latest.isEmpty) return _buildEmptyActivity();

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: dSurface,
            border: Border.all(color: dBorder),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              for (final p in latest) _pickupItem(p),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyActivity() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dSurface,
        border: Border.all(color: dBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _activityItem(
            Icons.inventory_2_outlined,
            "No pickups yet",
            "Your validated collections will appear here",
            "—",
            dGoldSoft,
            dGold,
          ),
        ],
      ),
    );
  }

  /// Millisecond timestamp of a pickup doc (null-safe for tests writing
  /// plain DateTime or nothing at all).
  static int _pickupTime(dynamic v) {
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    return 0;
  }

  /// One activity row for a real pickup document.
  Widget _pickupItem(Map<String, dynamic> p) {
    final status = p['status'] as String? ?? '';
    final date = p['date'] as String? ?? '';
    final heure = p['heure_depart'] as String? ??
        (p['heure_arrivee'] as String? ?? '');
    final poids = (p['poids'] as num?)?.toDouble() ?? 0;
    final poidsLabel = poids > 0 ? '${poids.toStringAsFixed(1)} kg' : '—';
    final collector = p['collector_name'] as String? ?? '';

    final verified = status == 'verified';
    final pending = status == 'pending_client_confirmation';
    final missed = status == 'missed';
    final disputed = status == 'disputed';

    final (icon, title, subtitle, bg, ic) = verified
        ? (
            Icons.check_rounded,
            'Pickup completed',
            '${date.isEmpty ? '' : '$date · '}$heure · validated',
            dGreenSoft,
            dGreen,
          )
        : pending
            ? (
                Icons.qr_code_scanner,
                'Pickup to confirm',
                '${date.isEmpty ? '' : '$date · '}waiting for your QR scan',
                dGoldSoft,
                dGold,
              )
            : disputed
                ? (
                    Icons.report_outlined,
                    'Pickup reported',
                    '${date.isEmpty ? '' : '$date · '}under review',
                    dRedSoft,
                    dRed,
                  )
                : missed
                    ? (
                        Icons.close,
                        'Pickup missed',
                        '${date.isEmpty ? '' : '$date · '}${p['miss_reason'] as String? ?? 'rescheduled'}',
                        dRedSoft,
                        dRed,
                      )
                    : (
                        Icons.schedule,
                        'Pickup scheduled',
                        date,
                        dGreenSoft,
                        dGreen,
                      );

    return Column(
      children: [
        _activityItem(icon, title, subtitle, poidsLabel, bg, ic),
        if (pending && collector.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Collected by $collector — tap “My QR code” to validate.',
              style: TextStyle(fontSize: 10.5, color: dMuted),
            ),
          ),
      ],
    );
  }

  Widget _activityItem(
    IconData icon,
    String title,
    String subtitle,
    String weight,
    Color bgColor,
    Color iconColor,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: dText,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: dMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              weight,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: dMuted,
              ),
            ),
          ],
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          height: 1,
          color: dBorder,
        ),
      ],
    );
  }

  // --- Helpers ---

  /// The client's collection zone (set with the paid plan), else the
  /// agency's area — never an invented street address.
  String _userZoneAddress(UserModel user, String zoneName) {
    if (zoneName.trim().isNotEmpty) return zoneName.trim();
    final raw = user.agenceName.trim();
    if (raw.isEmpty) return 'your address';
    final parts = raw.split(RegExp(r'[—–-]'));
    return parts.length >= 2 ? parts.last.trim() : raw;
  }

  /// Parses the user's agenceName (e.g. "Yaoundé — Bastos") into
  /// "Quartier, Ville" format for the header.
  String _formatLocation(UserModel user) {
    final raw = user.agenceName.trim();
    if (raw.isEmpty) return 'Location not set';
    // Format is typically "Ville — Quartier" or "Ville - Quartier"
    final parts = raw.split(RegExp(r'[—–-]'));
    if (parts.length >= 2) {
      final ville = parts[0].trim();
      final quartier = parts.sublist(1).join(' — ').trim();
      return '$quartier, $ville';
    }
    return raw;
  }

  Widget _buildChatFab() {
    if (_pulseController == null || _pulseScale == null || _pulseGlow == null) {
      return GestureDetector(
        onTap: () => ChatbotScreen.open(context),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: dGreen,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: dGreen.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const ChatbotRobotIcon(size: 56),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _pulseController!,
      builder: (context, child) {
        final scale = _pulseScale!.value;
        final glowAlpha = _pulseGlow!.value;
        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            onTap: () => ChatbotScreen.open(context),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: dGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dGreen.withValues(alpha: glowAlpha),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const ChatbotRobotIcon(size: 56),
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: GoogleFonts.sora(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: dText,
        ),
      );

  Widget _actionItem(IconData i, String l, Color bg, Color ic) {
    return InkWell(
      onTap: () {
        switch (l) {
          case "My Bill":
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BillsScreen()),
            );
          case "Request Pickup":
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExtraPickupScreen()),
            );
          case "Support":
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupportScreen()),
            );
        }
      },
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(i, color: ic, size: 19),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 70,
            child: Text(
              l,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: dText,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(NavigationProvider navProvider) {
    // Shared bottom bar — identical on the dashboard, bills, history and
    // profile screens, so tab switching is stack-safe (no screen pile-up).
    return const ClientBottomNav();
  }

  // --- Utility helpers ---

  /// Computes the next pickup date from a list of collection day names.
  DateTime? _computeNextPickup(List<String> collectionDays) {
    if (collectionDays.isEmpty) return null;
    final now = DateTime.now();
    // Search up to 14 days ahead.
    for (int i = 1; i <= 14; i++) {
      final date = now.add(Duration(days: i));
      final dayName = _weekdayLabel(date);
      if (collectionDays.contains(dayName)) return date;
    }
    return null;
  }

  /// Formats plan label: "Weekly · 2x/week".
  String _formatPlanLabel(String plan, int dayCount) {
    if (plan.isEmpty) return 'No subscription';
    // Capitalize first letter.
    final tier = plan[0].toUpperCase() + plan.substring(1);
    if (dayCount > 0) return '$tier · ${dayCount}x/week';
    return tier;
  }

  /// Formats the next pickup text for the contract card.
  String _formatNextPickupText(
      DateTime? nextPickup, String pickupTime, UserModel user,
      String zoneName) {
    if (nextPickup == null) return 'No upcoming pickup scheduled';
    final day = _weekdayLabel(nextPickup);
    final month = _monthShort(nextPickup.month);
    final time = pickupTime.isNotEmpty ? pickupTime : '07:00';
    final addr = _userZoneAddress(user, zoneName);
    return '$day, $month ${nextPickup.day} · $time — $addr';
  }

  String _weekdayLabel(DateTime d) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[d.weekday - 1];
  }

  String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

// --- Data models for schedule and payments ---



// Custom painter for the circular countdown ring.
class _RingPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color foregroundColor;

  _RingPainter({
    required this.progress,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final strokeWidth = 6.0;

    // Background ring
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Foreground ring (progress)
    if (progress > 0) {
      final foregroundPaint = Paint()
        ..color = foregroundColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final rect = Rect.fromCircle(center: center, radius: radius);
      final startAngle = -math.pi / 2; // Start from top
      final sweepAngle = 2 * math.pi * progress;

      canvas.drawArc(rect, startAngle, sweepAngle, false, foregroundPaint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
