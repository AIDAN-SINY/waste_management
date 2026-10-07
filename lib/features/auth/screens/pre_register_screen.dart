import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/agence_model.dart';
import '../../backoffice/widgets/photo_picker_field.dart';
import 'map_picker_screen.dart';
import '../../../services/agency_directory.dart';
import '../../../services/auth_backend.dart';
import '../../../services/auth_service.dart';
import 'login_screen.dart';

/// Pré-inscription client — réservée aux clients (le login reste pour tous).
///
/// Ce n'est pas une inscription immédiate : le client remplit ses infos et
/// choisit l'agence où il veut s'abonner (suggestions selon sa zone, ou il
/// tape directement le nom). La candidature part dans le dashboard du chef
/// d'agence qui l'approuve et lui assigne un collecteur — le compte n'est
/// créé qu'à ce moment.
class PreRegisterScreen extends StatefulWidget {
  const PreRegisterScreen({
    super.key,
    FirebaseFirestore? db,
    AuthBackend? backend,
    this.initialName = '',
    this.initialPhone = '',
    this.initialZone = '',
    this.agencyLoader,
  }) : _db = db,
       _backend = backend;

  /// Source des agences proposées ; par défaut la Cloud Function publique
  /// (les tests injectent [AgencyDirectory.fromFirestore]).
  final Future<AgencyDirectory> Function()? agencyLoader;

  /// Base injectée par les tests ; sinon l'instance par défaut.
  final FirebaseFirestore? _db;

  /// Backend Auth injecté par les tests ; sinon l'instance Firebase.
  final AuthBackend? _backend;

  /// Pré-remplissage du formulaire — utilisé par « Re-apply » depuis
  /// l'écran de statut d'une candidature rejetée (infos conservées).
  final String initialName;
  final String initialPhone;
  final String initialZone;

  @override
  State<PreRegisterScreen> createState() => _PreRegisterScreenState();
}

class _PreRegisterScreenState extends State<PreRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _zoneCtrl = TextEditingController();
  final _agencyCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  FirebaseFirestore get _db => widget._db ?? FirebaseFirestore.instance;

  /// Agences chargées pour les suggestions — filtrées sur celles qui ont
  /// un chef d'agence actif (une candidature vers une agence SANS chef
  /// serait invisible dans tous les backoffices, donc dans le vide).
  List<AgenceModel> _agences = [];
  bool _loadingAgencies = true;

  /// The agency list could not be loaded (server unreachable / not
  /// deployed) — not the same as « no agency ».
  bool _agenciesFailed = false;

  /// Agencies + the zones they serve (automatic search by neighbourhood).
  AgencyDirectory _directory =
      const AgencyDirectory(agences: [], hasManagerlessAgencies: false);

  /// Result of the automatic search for the typed zone; null = nothing
  /// searched yet (zone too short or still typing).
  List<AgencyMatch>? _zoneResults;
  Timer? _zoneDebounce;

  /// Vrai quand des agences existent mais qu'AUCUNE n'a de chef d'agence
  /// actif : on le distingue de « aucune agence » pour guider le client.
  bool _hasManagerlessAgencies = false;

  /// Agence sélectionnée (null = l'utilisateur tape son propre nom).
  AgenceModel? _selected;
  bool _submitting = false;
  bool _submitted = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  /// Photo du client (data URL base64) — optionnelle, comme côté backoffice.
  String _photoUrl = '';

  /// Point de collecte choisi sur la carte (utilisé pour pré-remplir la
  /// zone et transmis à la candidature). La zone reste éditable à la main.
  double? _latitude;
  double? _longitude;

  // Palette cohérente avec LoginScreen.
  static const Color bgDarker = Color(0xFF073A1B);
  static const Color accentGold = Color(0xFFF5B800);
  static const Color cream = Color(0xFFF5F1E8);
  static const Color muted = Color(0xFFAEC0B7);
  static const Color glass = Color(0x12F5F1E8);
  static const Color glassBorder = Color(0x29F5F1E8);

  @override
  void initState() {
    super.initState();
    // Re-apply : le formulaire repart avec les infos de la candidature
    // rejetée (le client n'a qu'à ajuster ce qui a changé).
    _nameCtrl.text = widget.initialName;
    _phoneCtrl.text = widget.initialPhone;
    _zoneCtrl.text = widget.initialZone;
    _loadAgencies();
  }

  Future<void> _loadAgencies() async {
    if (mounted) {
      setState(() {
        _loadingAgencies = true;
        _agenciesFailed = false;
      });
    }
    try {
      // Seules les agences couvertes par un chef d'agence actif.
      final directory = await (widget.agencyLoader ??
          AgencyDirectory.fromPublicFunction)();
      if (mounted) {
        setState(() {
          _directory = directory;
          _agences = directory.agences;
          _hasManagerlessAgencies = directory.hasManagerlessAgencies;
          _loadingAgencies = false;
        });
        // A zone typed while the agencies were loading.
        _searchZone(_zoneCtrl.text);
      }
    } catch (e) {
      debugPrint('[PreRegister] agency list failed: $e');
      if (mounted) {
        setState(() {
          _loadingAgencies = false;
          _agenciesFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _zoneDebounce?.cancel();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _zoneCtrl.dispose();
    _agencyCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // --- Recherche automatique d'agence par quartier ---

  /// Typing in the zone field searches automatically once the user pauses.
  void _onZoneChanged(String value) {
    _zoneDebounce?.cancel();
    _zoneDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchZone(value),
    );
  }

  /// Agencies serving the zone [value] (see
  /// [AgencyDirectory.agenciesForZone]). When exactly one agency covers it,
  /// it is selected automatically — the neighbourhood is enough.
  void _searchZone(String value) {
    if (!mounted) return;
    setState(() {
      if (value.trim().length < 3 || _loadingAgencies) {
        _zoneResults = null;
        return;
      }
      final results = _directory.agenciesForZone(value);
      _zoneResults = results;
      if (results.length == 1) {
        _selected = results.single.agence;
        _agencyCtrl.text = results.single.agence.ville;
      }
    });
  }

  /// « Company — Agency » (the company is omitted when unknown).
  static String _agencyTitle(AgenceModel a) =>
      a.societe.trim().isEmpty ? a.ville : '${a.societe} — ${a.ville}';

  bool _matchesQuery(AgenceModel a, String q) =>
      AgencyDirectory.normalize('${a.societe} ${a.ville}').contains(q);

  /// Agencies proposed in the agency field: those found in the typed zone
  /// (filtered by what is typed in the agency field), then — when the user
  /// searches by name — the other agencies matching that name.
  List<AgencyMatch> get _agencyOptions {
    // Once an agency is chosen, the field shows its name: keep the zone's
    // full list (the choice can still be changed).
    final q = _selected != null
        ? ''
        : AgencyDirectory.normalize(_agencyCtrl.text);
    final inZone = (_zoneResults ?? const <AgencyMatch>[])
        .where((m) => q.isEmpty || _matchesQuery(m.agence, q))
        .toList();
    if (q.isEmpty) return inZone;
    final ids = inZone.map((m) => m.agence.id).toSet();
    return [
      ...inZone,
      for (final a in _agences)
        if (!ids.contains(a.id) && _matchesQuery(a, q)) AgencyMatch(a),
    ];
  }

  void _choose(AgenceModel a) {
    setState(() {
      _selected = a;
      _agencyCtrl.text = a.ville;
    });
  }

  /// Nom d'agence final : la sélection, sinon le nom tapé dans le champ.
  String get _effectiveAgencyName =>
      _selected?.ville ?? _agencyCtrl.text.trim();

  String get _effectiveAgencyId => _selected?.id ?? '';

  String get _effectiveSocieteId => _selected?.societeId ?? '';

  // --- Choix de la zone sur la carte ---

  /// Ouvre [MapPickerScreen] et remplit le champ zone avec l'adresse
  /// choisie par le client (les suggestions d'agences suivent, comme une
  /// saisie manuelle).
  Future<void> _pickOnMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (result == null || !mounted) return;
    final loc = result['location'];
    if (loc is LatLng) {
      _latitude = loc.latitude;
      _longitude = loc.longitude;
    }
    final address = result['address'] as String? ?? '';
    if (address.isEmpty) {
      // Point kept, but its neighbourhood name is unknown.
      _toast('Location saved — now type your neighbourhood name.');
      return;
    }
    _zoneCtrl.text = address;
    _searchZone(address);
  }

  // --- Soumission ---

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_passCtrl.text != _confirmCtrl.text) {
      _toast('Passwords do not match');
      return;
    }
    if (_effectiveAgencyName.isEmpty) {
      _toast('Please choose an agency or type its name');
      return;
    }
    // Garde anti-« vide » : seule une agence AYANT un chef d'agence actif
    // est proposée (voir [_loadAgencies]). Une saisie libre qui ne
    // correspond à aucune de ces agences partirait vers une agence sans
    // backoffice — on la bloque ici plutôt que de l'envoyer dans le vide.
    if (_selected == null) {
      _toast(
        'Choose an agency from the list — this name has no agency manager yet.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final phone = AuthService.canonicalPhone(_phoneCtrl.text.trim());
      await AuthService(db: _db, backend: widget._backend).submitPreRegistration(
        fullName: _nameCtrl.text.trim(),
        phone: phone,
        zone: _zoneCtrl.text.trim(),
        agenceId: _effectiveAgencyId,
        agenceName: _effectiveAgencyName,
        societeId: _effectiveSocieteId,
        password: _passCtrl.text,
        photoUrl: _photoUrl,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) _toast(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Retour au login via le routeur quand il est présent (/login) : une push
  /// impérative resterait empilée AU-DESSUS du routeur et l'URL resterait sur
  /// /register (obligation de recharger la page après le login).
  void _goToLogin() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/login');
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
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
                  child: _submitted
                      ? _buildSuccessCard()
                      : _buildFormCard(),
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

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: glass,
        border: Border.all(color: glassBorder),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: cream,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Apply as a client',
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
              'Tell us about yourself and choose your agency. Your '
              'application is processed right away and a collector is '
              'assigned to you.',
              style: TextStyle(color: muted, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 22),

            _label('Full name'),
            _field(
              _nameCtrl,
              hint: 'Ex. Marie Ekwalla',
              icon: Icons.person_outline_rounded,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter your full name' : null,
            ),
            const SizedBox(height: 14),

            _label('Phone number'),
            _phoneField(),
            const SizedBox(height: 14),

            _label('Neighborhood / zone'),
            _field(
              _zoneCtrl,
              hint: 'Ex. Yaoundé: Bastos',
              icon: Icons.map_outlined,
              onChanged: _onZoneChanged,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter your zone' : null,
              trailing: IconButton(
                key: const Key('zone_pick_map'),
                onPressed: _pickOnMap,
                tooltip: 'Pick your location on the map',
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: accentGold,
                  size: 18,
                ),
              ),
            ),

            const SizedBox(height: 14),

            _label('Agency'),
            _searchAgencyField(),
            const SizedBox(height: 6),

            // Agences trouvées dans la zone saisie (société + agence), ou
            // message « zone non couverte ».
            _agencyOptionsPanel(),

            // Aucune agence proposée : le client doit savoir POURQUOI (sinon
            // il croirait que la recherche est cassée). Deux cas : aucune
            // agence sur la plateforme, ou des agences mais sans chef
            // d'agence pour les traiter.
            if (_agenciesFailed)
              Padding(
                key: const Key('agencies_failed'),
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 14,
                      color: accentGold,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        "Couldn't load the agency list. Check your "
                        'connection and try again.',
                        style: TextStyle(color: accentGold, fontSize: 11.5),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadAgencies,
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: accentGold),
                      ),
                    ),
                  ],
                ),
              )
            else if (!_loadingAgencies && _agences.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 13,
                      color: muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _hasManagerlessAgencies
                            ? 'No agency has a manager yet — applications '
                                  "can't be processed until one is assigned"
                            : 'No agency available yet',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

            // Sélection actuelle (agence choisie ou nom tapé).
            if (_selected != null)
              _selectedChip(
                label: _agencyTitle(_selected!),
                sub: 'Selected agency',
                onClear: () => setState(() {
                  _selected = null;
                  _agencyCtrl.clear();
                }),
              )
            else if (_agencyCtrl.text.trim().isNotEmpty)
              _selectedChip(
                label: _agencyCtrl.text.trim(),
                sub: 'Using typed name',
                onClear: () => setState(() {
                  _agencyCtrl.clear();
                }),
              ),

            const SizedBox(height: 18),
            _label('Password'),
            _field(
              _passCtrl,
              hint: 'Min. 4 characters',
              icon: Icons.lock_outline_rounded,
              obscure: true,
              obscureCtrl: () => setState(() => _obscure1 = !_obscure1),
              isObscure: _obscure1,
              validator: (v) =>
                  (v == null || v.length < 6)
                  ? 'Password must be at least 6 characters'
                  : null,
            ),
            const SizedBox(height: 14),
            _label('Confirm password'),
            _field(
              _confirmCtrl,
              hint: 'Repeat your password',
              icon: Icons.lock_outline_rounded,
              obscure: true,
              obscureCtrl: () => setState(() => _obscure2 = !_obscure2),
              isObscure: _obscure2,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Confirm your password' : null,
            ),

            // Photo (optionnelle) : prise avec la caméra ou choisie dans la
            // galerie — la même image se retrouve sur le compte client créé
            // par le chef d'agence à l'approbation.
            const SizedBox(height: 14),
            _label('Photo (optional)'),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bgDarker.withValues(alpha: 0.35),
                border: Border.all(color: glassBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: PhotoPickerField(
                key: const Key('pre_register_photo'),
                initialValue: _photoUrl,
                onChanged: (v) => setState(() => _photoUrl = v),
                accentColor: accentGold,
                mutedColor: muted,
                borderColor: glassBorder,
                fillColor: bgDarker.withValues(alpha: 0.5),
              ),
            ),

            const SizedBox(height: 22),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentGold,
                  foregroundColor: const Color(0xFF073A1B),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF073A1B),
                        ),
                      )
                    : Text(
                        'Submit application',
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _goToLogin,
                child: const Text(
                  'Already have an account? Log in',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: glass,
        border: Border.all(color: glassBorder),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF2E9E3A).withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 32,
              color: Color(0xFF6CB82E),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Application sent!',
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cream,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your request has been sent to ${_effectiveAgencyName.isEmpty ? 'your agency' : _effectiveAgencyName}. '
            'Your account was created — you can log in right away with the '
            'password you chose. A collector is usually assigned within '
            'seconds; otherwise the agency manager reviews your application '
            'and you can track it in real time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _goToLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentGold,
                foregroundColor: const Color(0xFF073A1B),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Go to login'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _goToLogin,
            child: const Text(
              'Log in to track your application',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(
          color: muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.02,
        ),
      ),
    );
  }

  /// Champ texte générique (fond sombre vitré, icône, option mot de passe,
  /// action de fin de ligne comme « choisir sur la carte »).
  Widget _field(
    TextEditingController ctrl, {
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscure = false,
    bool isObscure = true,
    VoidCallback? obscureCtrl,
    ValueChanged<String>? onChanged,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgDarker.withValues(alpha: 0.35),
        border: Border.all(color: glassBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(icon, size: 17, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: ctrl,
              obscureText: obscure ? isObscure : false,
              onChanged: onChanged,
              validator: validator,
              style: const TextStyle(color: cream, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: muted.withValues(alpha: 0.55)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 13,
                ),
                errorStyle: const TextStyle(fontSize: 10.5),
              ),
            ),
          ),
          if (obscure) ...[
            IconButton(
              onPressed: obscureCtrl,
              icon: Icon(
                isObscure ? Icons.visibility_off : Icons.visibility,
                color: muted,
                size: 18,
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (trailing != null) ...[
            trailing,
            const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }

  /// Champ téléphone avec préfixe +237 (comme le login).
  Widget _phoneField() {
    return Container(
      decoration: BoxDecoration(
        color: bgDarker.withValues(alpha: 0.35),
        border: Border.all(color: glassBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: const Text(
              '+237',
              style: TextStyle(color: muted, fontSize: 14),
            ),
          ),
          Container(width: 1, height: 20, color: glassBorder),
          Expanded(
            child: TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\s-]')),
              ],
              style: const TextStyle(color: cream, fontSize: 14),
              decoration: InputDecoration(
                hintText: '6 XX XX XX XX',
                hintStyle: TextStyle(
                  color: muted.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                errorStyle: const TextStyle(fontSize: 10.5),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter your phone' : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Under the agency field: the agencies found in the zone the user
  /// entered (company + agency name), or why there is none.
  Widget _agencyOptionsPanel() {
    final zone = _zoneCtrl.text.trim();
    if (_loadingAgencies && zone.length >= 3) {
      return _zoneNote(
        Icons.search_rounded,
        'Searching for agencies in your area...',
        muted,
        key: const Key('zone_searching'),
      );
    }
    final options = _agencyOptions;
    final typed = _agencyCtrl.text.trim().isNotEmpty;
    if (options.isEmpty) {
      // Zone entered but no agency covers it (and no name search running).
      if (_zoneResults != null && !typed && _agences.isNotEmpty) {
        return _zoneNote(
          Icons.location_off_outlined,
          'No agency is registered in “$zone” yet — this zone is not '
          'covered. Check the spelling or try a nearby neighbourhood.',
          accentGold,
          key: const Key('zone_not_covered'),
        );
      }
      if (_zoneResults == null && !typed && _agences.isNotEmpty) {
        return _zoneNote(
          Icons.info_outline_rounded,
          'Enter your neighbourhood above to see the agencies serving it.',
          muted,
        );
      }
      return const SizedBox.shrink();
    }
    // A single agency already selected: nothing else to choose.
    if (_selected != null && options.length == 1) {
      return const SizedBox.shrink();
    }
    final inZone = _zoneResults?.length ?? 0;
    return Padding(
      key: const Key('zone_agencies'),
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inZone > 0 && !typed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                inZone == 1
                    ? 'Agency found in “$zone”:'
                    : '$inZone agencies found in “$zone” — choose yours:',
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 230),
            decoration: BoxDecoration(
              color: bgDarker.withValues(alpha: 0.5),
              border: Border.all(color: glassBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final m in options.take(8)) _agencyOptionTile(m),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One proposed agency: company name, agency name, zone it serves.
  Widget _agencyOptionTile(AgencyMatch m) {
    final a = m.agence;
    final selected = _selected?.id == a.id;
    return InkWell(
      key: Key('agency_option_${a.id}'),
      onTap: () => _choose(a),
      child: Container(
        color: selected ? accentGold.withValues(alpha: 0.14) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.storefront_outlined,
              size: 17,
              color: accentGold,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.societe.trim().isEmpty ? a.ville : a.societe,
                    style: const TextStyle(
                      color: cream,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (a.societe.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      a.ville,
                      style: const TextStyle(color: cream, fontSize: 12.5),
                    ),
                  ],
                  if (m.zone != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Serves ${m.zone}',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoneNote(IconData icon, String text, Color color, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  /// Champ de recherche d'agence (saisie libre + suggestions).
  Widget _searchAgencyField() {
    return Container(
      decoration: BoxDecoration(
        color: bgDarker.withValues(alpha: 0.35),
        border: Border.all(
          color: _selected != null ? accentGold : glassBorder,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.storefront_outlined, size: 17, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _agencyCtrl,
              onChanged: (v) => setState(() {
                // La saisie annule la sélection ; si elle correspond
                // EXACTEMENT à une agence connue, elle est re-sélectionnée.
                _selected = null;
                final q = v.trim().toLowerCase();
                if (q.isNotEmpty) {
                  final exact = _agences
                      .where((a) => a.ville.toLowerCase() == q)
                      .toList();
                  if (exact.length == 1) _selected = exact.first;
                }
              }),
              style: const TextStyle(color: cream, fontSize: 14),
              decoration: InputDecoration(
                hintText:
                    _loadingAgencies
                        ? 'Loading agencies...'
                        : 'Search or type your agency name',
                hintStyle: TextStyle(color: muted.withValues(alpha: 0.55)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 13,
                ),
              ),
            ),
          ),
          if (_agencyCtrl.text.isNotEmpty)
            IconButton(
              onPressed: () => setState(() {
                _agencyCtrl.clear();
                _selected = null;
              }),
              icon: const Icon(Icons.close_rounded, color: muted, size: 17),
            ),
        ],
      ),
    );
  }

  Widget _selectedChip({
    required String label,
    required String sub,
    required VoidCallback onClear,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF2E9E3A).withValues(alpha: 0.12),
        border: Border.all(color: const Color(0xFF2E9E3A).withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 15,
            color: Color(0xFF6CB82E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: cream,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(color: muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, color: muted, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}
