import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../providers/user_provider.dart';
import '../../../services/auth_service.dart';
import 'login_screen.dart';
import 'pre_register_screen.dart';

/// Écran « Application status » — suivi de candidature client (pré-inscription).
///
/// Le client saisit son numéro et voit l'état de SA candidature en temps
/// réel : la carte se met à jour toute seule quand le chef d'agence prend
/// une décision (approuvé / rejeté). C'est la notification « in-app » de la
/// décision — sans infrastructure push, l'écran est le canal de suivi.
///
/// États affichés :
///   • en attente → « Under review » (pas encore de compte de connexion) ;
///   • approuvé → « Approved! » + bouton vers le login (le compte existe) ;
///   • rejeté → « Rejected » + bouton « Re-apply » (nouvelle candidature,
///     formulaire pré-rempli avec les infos de la candidature rejetée) ;
///   • aucune candidature → « No application found » + bouton « Apply ».
class ApplicationStatusScreen extends StatefulWidget {
  const ApplicationStatusScreen({
    super.key,
    FirebaseFirestore? db,
    this.initialPhone = '',
  }) : _db = db;

  /// Base injectée par les tests ; sinon l'instance par défaut.
  final FirebaseFirestore? _db;

  /// Numéro pré-rempli (arrivée depuis la carte de succès d'une candidature).
  final String initialPhone;

  @override
  State<ApplicationStatusScreen> createState() =>
      _ApplicationStatusScreenState();
}

class _ApplicationStatusScreenState extends State<ApplicationStatusScreen> {
  final _phoneCtrl = TextEditingController();
  bool _checked = false;
  bool _loading = false;

  FirebaseFirestore get _db => widget._db ?? FirebaseFirestore.instance;

  // Palette de marque (cohérente avec LoginScreen / PreRegisterScreen).
  static const Color bgDarker = Color(0xFF073A1B);
  static const Color accentGold = Color(0xFFF5B800);
  static const Color cream = Color(0xFFF5F1E8);
  static const Color muted = Color(0xFFAEC0B7);
  static const Color glass = Color(0x12F5F1E8);
  static const Color glassBorder = Color(0x29F5F1E8);

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = widget.initialPhone;
    // Arrivée depuis le dashboard (candidat connecté, rôle pending_client) :
    // le suivi démarre directement, sans saisie.
    if (widget.initialPhone.isNotEmpty) {
      _checked = true;
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  String get _canonicalPhone =>
      AuthService.canonicalPhone(_phoneCtrl.text.trim());

  Future<void> _check() async {
    if (_canonicalPhone.isEmpty) {
      _toast('Enter your phone number');
      return;
    }
    setState(() {
      _loading = true;
      _checked = true;
    });
    // Laisse le StreamBuilder prendre le relais ; un petit délai évite un
    // flash de chargement quand la réponse est immédiate.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Navigation (mêmes règles que PreRegisterScreen : routeur si présent) ---

  void _goToLogin() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      //  L'écran de statut est poussé IMPÉRATIVEMENT au-dessus du routeur
      // (depuis le login ou la carte de succès). Il faut le retirer avant de
      // laisser le routeur naviguer — sinon il resterait empilé au-dessus de
      // la destination et bloquerait la navigation (piège documenté dans
      // welcome_screen.dart).
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      router.go('/login');
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  /// Approuvé : on déconnecte la session pending_client puis on redirige
  /// vers l'écran de login pour que le client se reconnecte avec son nouveau
  /// rôle `client`.
  Future<void> _handleApproved() async {
    final provider = context.read<UserProvider>();
    // Déconnecte la session pending_client (rôle obsolète après approbation).
    if (provider.user != null) {
      await provider.logout();
    }
    if (!mounted) return;
    _goToLogin();
  }

  void _goToApply({String name = '', String phone = '', String zone = ''}) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      // Même règle que [_goToLogin] : retirer la route impérative d'abord.
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      router.go('/register');
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PreRegisterScreen(
            initialName: name,
            initialPhone: phone,
            initialZone: zone,
          ),
        ),
      );
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDarker,
      body: Stack(
        children: [
          _background(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: cream,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Application status',
                              style: GoogleFonts.sora(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: cream,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Enter the phone number you used to apply. This page '
                        'updates automatically when the agency manager '
                        'reviews your application.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _buildPhoneField(),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _check,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentGold,
                            foregroundColor: const Color(0xFF073A1B),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF073A1B),
                                  ),
                                )
                              : Text(
                                  'Check status',
                                  style: GoogleFonts.sora(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_checked) _buildStatusCard(),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton(
                          onPressed: () =>
                              context.read<UserProvider>().logout(),
                          child: const Text(
                            'Log out',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned(
          top: -60,
          left: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              color: const Color(0xFF0B4A24),
              borderRadius: BorderRadius.circular(140),
            ),
          ),
        ),
        Positioned(
          bottom: 60,
          right: -60,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: accentGold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(110),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Container(
      decoration: BoxDecoration(
        color: bgDarker.withValues(alpha: 0.35),
        border: Border.all(color: glassBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Text(
              '+237',
              style: TextStyle(color: muted, fontSize: 14),
            ),
          ),
          Container(width: 1, height: 20, color: glassBorder),
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: cream, fontSize: 14.5),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _check(),
              decoration: InputDecoration(
                hintText: '6 XX XX XX XX',
                hintStyle: TextStyle(color: muted.withValues(alpha: 0.5)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Carte de statut (mise à jour en direct via Firestore) ---

  Widget _buildStatusCard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('registrations')
          .where('phone', isEqualTo: _canonicalPhone)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _baseCard(
            icon: Icons.cloud_off_rounded,
            iconColor: const Color(0xFFE0605A),
            iconBg: const Color(0xFFE0605A).withValues(alpha: 0.14),
            title: 'Unable to load',
            message: 'Could not load your application status. Check your '
                'connection and try again.',
          );
        }
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(color: accentGold),
            ),
          );
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return _baseCard(
            icon: Icons.search_off_rounded,
            iconColor: muted,
            iconBg: muted.withValues(alpha: 0.12),
            title: 'No application found',
            message: 'We could not find any application for '
                '$_canonicalPhone. You can apply now to get started.',
            actionLabel: 'Apply now',
            onAction: () => _goToApply(phone: _phoneCtrl.text.trim()),
          );
        }
        // La candidature la plus récente fait foi (ids : reg<microsecondes>).
        final docsSorted = docs.toList()
          ..sort((a, b) => b.id.compareTo(a.id));
        final data = docsSorted.first.data();
        final status = (data['status'] as String? ?? '').toLowerCase();
        switch (status) {
          case 'approved':
            return _approvedCard(data);
          case 'rejected':
            return _rejectedCard(data);
          default:
            return _pendingCard(data);
        }
      },
    );
  }

  Widget _pendingCard(Map<String, dynamic> data) {
    return _baseCard(
      icon: Icons.hourglass_top_rounded,
      iconColor: accentGold,
      iconBg: accentGold.withValues(alpha: 0.16),
      title: 'Under review',
      message:
          'Your application${data['agenceName'] != null && (data['agenceName'] as String).isNotEmpty ? ' to ${data['agenceName']}' : ''} '
          'is pending approval. The agency manager is reviewing it and will '
          'assign you a collector. You will be able to log in once it is '
          'approved — this page updates automatically.',
      extra: _stepsIndicator(step: 1),
    );
  }

  Widget _approvedCard(Map<String, dynamic> data) {
    return _baseCard(
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF6CB82E),
      iconBg: const Color(0xFF6CB82E).withValues(alpha: 0.16),
      title: 'Approved!',
      message:
          'Your application was approved and a collector has been assigned '
          'to you. Log in, then choose and pay your plan to start your '
          'pickups.',
      actionLabel: 'Log in',
      onAction: _handleApproved,
      extra: _stepsIndicator(step: 2),
    );
  }

  Widget _rejectedCard(Map<String, dynamic> data) {
    return _baseCard(
      icon: Icons.cancel_rounded,
      iconColor: const Color(0xFFE0605A),
      iconBg: const Color(0xFFE0605A).withValues(alpha: 0.16),
      title: 'Application rejected',
      message:
          'Unfortunately, your application was rejected. You can submit a '
          'new one — your details are kept so you only have to adjust what '
          'changed.',
      actionLabel: 'Re-apply',
      onAction: () => _goToApply(
        name: data['fullName'] as String? ?? '',
        phone: data['phone'] as String? ?? '',
        zone: data['zone'] as String? ?? '',
      ),
      extra: _stepsIndicator(step: -1),
    );
  }

  Widget _baseCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Widget? extra,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: glass,
        border: Border.all(color: glassBorder),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cream,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13, height: 1.55),
          ),
          if (extra != null) ...[
            const SizedBox(height: 18),
            extra,
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentGold,
                  foregroundColor: const Color(0xFF073A1B),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Petit fil d'avancement (soumission → revue → décision).
  /// [step] : 0 = soumise, 1 = en revue, 2 = décidée ; -1 = rejetée.
  Widget _stepsIndicator({required int step}) {
    // Une étape est « faite » quand elle est AVANT la position courante
    // (jamais l'étape en cours — elle reste en surbrillance or) ; rejeté :
    // la soumission et la revue ont bien eu lieu, seule la décision échoue.
    Widget dot(int i) {
      final isDone = step == 2 ? true : (step == -1 ? i < 2 : i < step);
      final rejected = step == -1 && i == 2;
      final active = step == i && !rejected;
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: isDone
              ? (rejected ? const Color(0xFFE0605A) : const Color(0xFF6CB82E))
              : (active
                    ? accentGold.withValues(alpha: 0.25)
                    : Colors.transparent),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDone
                ? (rejected
                      ? const Color(0xFFE0605A)
                      : const Color(0xFF6CB82E))
                : glassBorder,
          ),
        ),
        child: Icon(
          rejected
              ? Icons.close_rounded
              : (isDone ? Icons.check_rounded : Icons.circle),
          size: 14,
          color: isDone
              ? cream
              : (active ? accentGold : muted.withValues(alpha: 0.5)),
        ),
      );
    }

    Widget label(int i, String text) {
      final highlighted = step == i || (step == -1 && i == 2);
      return Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: highlighted ? cream : muted,
          fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [dot(0), dot(1), dot(2)],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            label(0, 'Submitted'),
            label(1, 'Review'),
            label(2, step == -1 ? 'Rejected' : 'Decision'),
          ],
        ),
      ],
    );
  }
}
