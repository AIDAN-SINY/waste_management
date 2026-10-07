import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../superadmin/super_admin_console.dart';
import 'login_screen.dart';
import 'pre_register_screen.dart';

/// Écran d'accueil — responsive.
///
/// Sur grand écran (web / Windows) : un panneau héro à gauche (marque,
/// promesses produit) et une carte CTA vitrée à droite. Sur mobile : la même
/// marque empilée verticalement. La palette (vert profond / or / crème) est
/// partagée avec l'écran de connexion pour une identité cohérente.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  /// Navigue vers un écran d'auth via le routeur quand il est présent
  /// (app web : /login, /register) — sinon repli sur une push impérative
  /// (tests / contextes sans routeur).
  ///
  ///  La push impérative est le piège qui force à actualiser la page : un
  /// écran poussé avec Navigator.push reste empilé AU-DESSUS du routeur, et
  /// router.go('/') après le login ne le retire pas. Le routeur, lui,
  /// remplace proprement la pile (/login → /).
  void _goToAuth(BuildContext context, String path, Widget fallback) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(path);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => fallback));
    }
  }

  // Palette de marque (cohérente avec LoginScreen).
  static const Color bgDarker = Color(0xFF073A1B);
  static const Color accentGold = Color(0xFFF5B800);
  static const Color cream = Color(0xFFF5F1E8);
  static const Color muted = Color(0xFFAEC0B7);
  static const Color glass = Color(0x12F5F1E8); // crème à 7%
  static const Color glassBorder = Color(0x29F5F1E8); // crème à 16%

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Image de fond
          Positioned.fill(
            child: Image.asset('assets/images/waste_bg.jpg', fit: BoxFit.cover),
          ),

          // 2. Voile dégradé pour la lisibilité
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    bgDarker.withValues(alpha: 0.92),
                    const Color(0xFF0B5A2A).withValues(alpha: 0.72),
                    bgDarker.withValues(alpha: 0.94),
                  ],
                ),
              ),
            ),
          ),

          // 3. Contenu responsive
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 900;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: desktop
                          ? _buildDesktop(context)
                          : _buildMobile(context),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Desktop (web / Windows) ----------

  Widget _buildDesktop(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Panneau héro
        Expanded(flex: 6, child: _buildHero(context)),
        const SizedBox(width: 56),
        // Carte CTA
        Expanded(flex: 4, child: _buildCtaCard(context)),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LogoBadge(size: 76),
        const SizedBox(height: 26),
        Text(
          'Waste management,\nsimplified in Cameroon.',
          style: GoogleFonts.sora(
            fontSize: 38,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.02,
            color: cream,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'WastePro connects households, collectors and businesses '
          'around one platform: scheduled pickups, simple subscriptions '
          'and real-time tracking.',
          style: TextStyle(fontSize: 15.5, height: 1.55, color: muted),
        ),
        const SizedBox(height: 34),
        const _HeroFeature(
          icon: Icons.schedule_rounded,
          title: 'Scheduled pickups',
          subtitle: 'On-demand or subscription collections, no paperwork.',
        ),
        const SizedBox(height: 16),
        const _HeroFeature(
          icon: Icons.payments_outlined,
          title: 'Simple payments',
          subtitle: 'Subscription and payment from your phone.',
        ),
        const SizedBox(height: 16),
        const _HeroFeature(
          icon: Icons.verified_outlined,
          title: 'Real-time tracking',
          subtitle: 'Know exactly when your pickup arrives.',
        ),
      ],
    );
  }

  Widget _buildCtaCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: glass,
        border: Border.all(color: glassBorder),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WasteProLogo(size: 56, radius: 14),
          const SizedBox(height: 20),
          Text(
            'Ready to get started?',
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cream,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your account or log in to schedule your first '
            'pickup in just a few minutes.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: muted),
          ),
          const SizedBox(height: 26),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentGold,
                foregroundColor: const Color(0xFF073A1B),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () =>
                  _goToAuth(context, '/login', const LoginScreen()),
              child: Text(
                'Log In',
                style: GoogleFonts.sora(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () =>
                _goToAuth(context, '/register', const PreRegisterScreen()),
            child: Text(
              'Create an account',
              style: GoogleFonts.sora(
                color: cream.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
              ),
            ),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            const Divider(color: glassBorder, height: 1),
            const SizedBox(height: 12),
            // Aperçu console super admin (builds de debug uniquement)
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SuperAdminConsole()),
              ),
              icon: const Icon(
                Icons.admin_panel_settings_outlined,
                size: 16,
                color: cream,
              ),
              label: const Text(
                'Super admin console preview (dev)',
                style: TextStyle(color: cream, fontSize: 12.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- Mobile ----------

  Widget _buildMobile(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(child: _LogoBadge(size: 88)),
        const SizedBox(height: 26),
        Text(
          'Waste management,\nsimplified in Cameroon.',
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.02,
            color: cream,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Scheduled pickups, simple subscriptions and real-time tracking.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, height: 1.5, color: muted),
        ),
        const SizedBox(height: 36),
        _buildCtaCard(context),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Badge logo (le logo WastePro).
class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return WasteProLogo(size: size, radius: size * 0.28);
  }
}

/// Une promesse produit (icône + titre + sous-titre).
class _HeroFeature extends StatelessWidget {
  const _HeroFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: WelcomeScreen.glass,
            border: Border.all(color: WelcomeScreen.glassBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: WelcomeScreen.accentGold),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: WelcomeScreen.cream,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: WelcomeScreen.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
