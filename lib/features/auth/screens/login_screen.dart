import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../services/auth_backend.dart';
import '../../../services/auth_service.dart';
import '../../../providers/user_provider.dart';
import '../../../main.dart';
import 'forgot_password_screen.dart';
import 'pre_register_screen.dart';

/// Écran de connexion — responsive.
///
/// Sur grand écran (web / Windows) : panneau de marque à gauche (logo,
/// promesses, note de confiance) et carte de connexion à droite, bornée à
/// ~440px (plus d'étirement sur tout l'écran). Sur mobile : le même contenu
/// empilé verticalement, carte également bornée pour rester élégante.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, FirebaseFirestore? db, AuthBackend? backend})
      : _db = db,
        _backend = backend;

  /// Base injectée par les tests ; sinon l'instance par défaut.
  final FirebaseFirestore? _db;

  /// Backend Auth injecté par les tests ; sinon l'instance Firebase.
  final AuthBackend? _backend;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  // Design colors from HTML
  final Color bgDarker = const Color(0xFF073A1B);
  final Color accentGold = const Color(0xFFF5B800);
  final Color cream = const Color(0xFFF5F1E8);
  final Color muted = const Color(0xFFAEC0B7);
  final Color glass = const Color(0xFFF5F1E8).withValues(alpha: 0.07);
  final Color glassBorder = const Color(0xFFF5F1E8).withValues(alpha: 0.16);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOutSine,
      ),
    );
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _passwordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDarker,
      body: Stack(
        children: [
          // Animated background blobs
          _buildAnimatedBackground(),

          // Login content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 900;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 48,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: desktop
                          ? _buildDesktopLayout()
                          : _buildMobileLayout(),
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

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Panneau de marque
        Expanded(flex: 6, child: _buildBrandPanel()),
        const SizedBox(width: 56),
        // Carte de connexion
        Expanded(flex: 4, child: _buildFormColumn()),
      ],
    );
  }

  Widget _buildBrandPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const WasteProLogo(size: 72, radius: 18),
        const SizedBox(height: 24),
        _buildBrandName(size: 30),
        const SizedBox(height: 8),
        Text(
          "Simplified waste collection, from households to businesses.",
          style: TextStyle(color: muted, fontSize: 14.5, height: 1.5),
        ),
        const SizedBox(height: 34),
        const _TrustPoint(
          icon: Icons.shield_outlined,
          text: 'Your data and payments are protected.',
        ),
        const SizedBox(height: 14),
        const _TrustPoint(
          icon: Icons.schedule_rounded,
          text: 'Scheduled pickups tracked in real time.',
        ),
        const SizedBox(height: 14),
        const _TrustPoint(
          icon: Icons.support_agent_rounded,
          text: 'A team available 7 days a week.',
        ),
      ],
    );
  }

  Widget _buildBrandName({required double size}) {
    return RichText(
      text: TextSpan(
        text: 'Waste',
        style: GoogleFonts.sora(
          color: cream,
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02,
        ),
        children: [
          TextSpan(
            text: 'Pro',
            style: GoogleFonts.sora(
              color: accentGold,
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.02,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Mobile ----------

  Widget _buildMobileLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Logo animé
        Center(
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: WasteProLogo(size: 72, radius: 18),
                ),
              );
            },
          ),
        ),
        // Marque
        Center(child: _buildBrandName(size: 24)),
        const SizedBox(height: 4),
        Center(
          child: Text(
            "Simplified waste collection",
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ),
        const SizedBox(height: 30),
        _buildFormColumn(),
      ],
    );
  }

  /// La carte de connexion (champs + bouton) + lien d'inscription.
  Widget _buildFormColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: glass,
                border: Border.all(color: glassBorder),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Phone field
                  _buildLabel('Phone number'),
                  _buildPhoneInput(),

                  const SizedBox(height: 16),

                  // Password field
                  _buildLabel('Password'),
                  _buildPasswordInput(),

                  const SizedBox(height: 16),

                  // Remember me & Forgot password
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (value) =>
                                setState(() => _rememberMe = value ?? false),
                            activeColor: accentGold,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const Text(
                            'Remember me',
                            style: TextStyle(
                              color: Color(0xFFAEC0B7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        key: const Key('forgot_password'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ForgotPasswordScreen(
                              initialPhone: _phoneController.text.trim(),
                            ),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: Color(0xFFF5B800),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleAuth,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentGold,
                        foregroundColor: const Color(0xFF073A1B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF073A1B),
                              ),
                            )
                          : Text(
                              'Log In',
                              style: GoogleFonts.sora(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 22),

        // Sign up hint
        Text(
          "Don't have an account?",
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12),
        ),
        Center(
          child: TextButton(
            onPressed: () {
              // Route via le routeur quand il est présent (/register) : une
              // push impérative resterait empilée au-dessus du routeur et
              // bloquerait la navigation après le login (obligation de
              // recharger la page pour voir le dashboard).
              final router = GoRouter.maybeOf(context);
              if (router != null) {
                router.go('/register');
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PreRegisterScreen(),
                  ),
                );
              }
            },
            child: Text(
              'Create an account',
              style: GoogleFonts.sora(
                color: cream,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _handleAuth() async {
    if (_phoneController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all the fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = AuthService(db: widget._db, backend: widget._backend);
      // La normalisation du numéro (+237, espaces, tirets) est gérée par
      // AuthService.login via canonicalKeys : on lui passe la saisie brute
      // pour qu'il essaie aussi la clé telle que stockée — un compte créé
      // à la main dans la console Firebase peut utiliser le numéro sans
      // préfixe +237 (ex. '653645807' au lieu de '+237653645807').
      final user = await auth.login(
        _phoneController.text.trim(),
        _passwordController.text,
      );

      if (user != null && mounted) {
        await Provider.of<UserProvider>(context, listen: false).setUser(user);
        if (mounted) {
          // Navigation par route (URL) : le routeur redirige ensuite vers le
          // dashboard ou la console selon le rôle. Fallback sans routeur.
          final router = GoRouter.maybeOf(context);
          if (router != null) {
            router.go('/');
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthWrapper()),
              (route) => false,
            );
          }
        }
      } else {
        // Pas de compte Auth pour ce numéro. Depuis le modèle « compte dès
        // l'inscription », un candidat (même en attente) PEUT se connecter —
        // le cas « pas de compte » correspond donc à un numéro sans aucune
        // candidature. Guide legacy : pour les candidatures soumises AVANT
        // la migration Auth, un numéro peut avoir une candidature sans
        // compte connectable — on renvoie vers le login à la place.
        // Signed out, the rules may refuse this lookup: fall back to the
        // generic "not found" message.
        String? status;
        try {
          status = await auth.registrationStatus(
            _phoneController.text.trim(),
          );
        } catch (_) {}
        throw switch (status) {
          'pending' => 'Your application is pending approval. The agency '
              'manager will review it and assign you a collector. Log in '
              'with your chosen password to track it in real time.',
          'rejected' => 'Your application was rejected. Log in with your '
              'chosen password to see the details and re-apply.',
          'approved' => 'Your application has been approved. Log in with '
              'your chosen password to get started.',
          _ => "User not found. Please sign up first.",
        };
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildAnimatedBackground() {
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
        Positioned(
          top: MediaQuery.of(context).size.height * 0.4,
          left: MediaQuery.of(context).size.width * 0.4,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFF0D2E22),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: TextStyle(
          color: muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.02,
        ),
      ),
    );
  }

  Widget _buildPhoneInput() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF073A1B).withValues(alpha: 0.35),
        border: Border.all(color: glassBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text('+237', style: TextStyle(color: muted, fontSize: 14)),
          ),
          Container(width: 1, height: 20, color: glassBorder),
          Expanded(
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: cream, fontSize: 14.5),
              // Entrée → passe au champ mot de passe (l'action « Next » du
              // clavier mobile remplit le même rôle).
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _passwordFocusNode.requestFocus(),
              decoration: InputDecoration(
                hintText: '6 XX XX XX XX',
                hintStyle: TextStyle(color: muted.withValues(alpha: 0.5)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordInput() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF073A1B).withValues(alpha: 0.35),
        border: Border.all(color: glassBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              focusNode: _passwordFocusNode,
              style: TextStyle(color: cream, fontSize: 14.5),
              // Entrée → déclenche directement le login.
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleAuth(),
              decoration: InputDecoration(
                hintText: '••••••••',
                hintStyle: TextStyle(color: muted.withValues(alpha: 0.5)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword ? Icons.visibility_off : Icons.visibility,
              color: muted,
              size: 18,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ],
      ),
    );
  }
}

/// Un point de confiance (icône + texte) du panneau de marque.
class _TrustPoint extends StatelessWidget {
  const _TrustPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F1E8).withValues(alpha: 0.07),
            border: Border.all(
              color: const Color(0xFFF5F1E8).withValues(alpha: 0.16),
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFFF5B800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFFAEC0B7),
            ),
          ),
        ),
      ],
    );
  }
}
