import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/subscription_plans.dart';
import '../data/backoffice_store.dart';
import '../models.dart';
import '../theme.dart';
import 'photo_picker_field.dart';
import 'toast.dart';
import 'zone_area_picker.dart';

/// Seuil de bascule web-first du backoffice (≥ 900 px, comme la sidebar).
bool _isBoDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 900;

/// Rayon des coins d'une sheet : tous les coins sur desktop (dialogue
/// centré), uniquement les coins hauts sur mobile (bottom sheet).
BorderRadius _boSheetRadius(BuildContext context, {double radius = 22}) {
  final r = Radius.circular(radius);
  return _isBoDesktop(context) ? BorderRadius.all(r) : BorderRadius.vertical(top: r);
}

/// Ouvre une « sheet » du backoffice en mode web-first : dialogue centré
/// sur desktop (≥ 900 px), bottom sheet classique sur mobile.
///
/// Le contenu [builder] est partagé — chaque feuille s'adapte au mode via
/// [_isBoDesktop] (coins, poignée de drag, largeur bornée).
Future<void> showBoSheet(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (_isBoDesktop(context)) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 28,
          vertical: 40,
        ),
        child: builder(dialogContext),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black45,
    builder: builder,
  );
}

/// Opens the review sheet for a client application (pre-registration).
///
/// The agency manager sees the applicant's details, picks the collector who
/// will be assigned, then approves (which creates the client + login account)
/// or rejects the application.
Future<void> showBoReviewSheet(
  BuildContext context, {
  required BackofficeStore store,
  required RegistrationModel reg,
}) {
  return showBoSheet(
    context,
    builder: (_) => _BoReviewSheet(store: store, reg: reg),
  );
}

/// Opens the create/edit bottom sheet for an entity. [existing] is the model
/// being edited, or null when creating.
Future<void> showBoFormSheet(
  BuildContext context, {
  required BackofficeStore store,
  required BoEntity type,
  Object? existing,
}) {
  return showBoSheet(
    context,
    builder: (_) => _BoFormSheet(store: store, type: type, existing: existing),
  );
}

/// Opens the action sheet (Edit / Delete) for an item.
///
/// [extraLabel] / [onExtra] ajoute une action supplémentaire entre Edit et
/// Delete (ex. « Reassign collector » pour un client).
Future<void> showBoActionSheet(
  BuildContext context, {
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  String? extraLabel,
  VoidCallback? onExtra,
}) {
  return showBoSheet(
    context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                color: BackofficeTheme.surface,
                borderRadius: _boSheetRadius(sheetContext, radius: 16),
              ),
              child: Column(
                children: [
                  _ActionButton(
                    icon: Icons.edit_rounded,
                    label: 'Edit',
                    onTap: () {
                      Navigator.of(context).pop();
                      onEdit();
                    },
                  ),
                  Divider(height: 1, color: BackofficeTheme.border),if (extraLabel != null && onExtra != null) ...[
                  _ActionButton(
                    icon: Icons.swap_horiz_rounded,
                    label: extraLabel,
                    onTap: () {
                      Navigator.of(context).pop();
                      onExtra();
                    },
                  ),
                    Divider(height: 1, color: BackofficeTheme.border),
                  ],
                  _ActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    danger: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      onDelete();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: BackofficeTheme.surface,
                    borderRadius: _boSheetRadius(sheetContext, radius: 16),
                  ),
                  child: Text(
                    'Cancel',
                    textAlign: TextAlign.center,
                    style: BackofficeTheme.inter(
                      14,
                      weight: FontWeight.w700,
                      color: BackofficeTheme.green,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? BackofficeTheme.red : BackofficeTheme.text;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: BackofficeTheme.inter(
                14,
                weight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create / edit form sheet
// ---------------------------------------------------------------------------

class _BoFormSheet extends StatefulWidget {
  const _BoFormSheet({required this.store, required this.type, this.existing});

  final BackofficeStore store;
  final BoEntity type;
  final Object? existing;

  @override
  State<_BoFormSheet> createState() => _BoFormSheetState();
}

class _BoFormSheetState extends State<_BoFormSheet> {
  final _formKey = GlobalKey<FormState>();

  // Shared by most entities.
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _zone;
  late final TextEditingController _number;
  late final TextEditingController _password;
  late final TextEditingController _cni;
  late final TextEditingController _vehicle;
  late final TextEditingController _salary;
  late final TextEditingController _photoUrl;
  late final TextEditingController _photoUrl2;
  late final TextEditingController _pickupTime;
  bool _obscurePassword = true;
  String _selectA = ''; // plan / status / client / libelle
  String _selectB = ''; // status / frequence / client...
  String _selectC = ''; // housing type

  /// Client payment at the agency: 'Not paid yet' / 'No new payment' or
  /// 'Paid in cash' (then [_selectA] = the plan paid).
  String _payment = '';
  static const _paidInCash = 'Paid in cash';
  late DateTime _date;
  final Set<String> _collectionDays = {};

  static const _allDays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  static const _dayAbbrev = {
    'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed',
    'Thursday': 'Thu', 'Friday': 'Fri', 'Saturday': 'Sat',
    'Sunday': 'Sun',
  };

  bool get _isEdit => widget.existing != null;

  /// The edited client's plan ('None' = approved / created, not paid yet).
  String _currentPlanLabel() {
    final plan = (widget.existing as ClientModel?)?.plan ?? '';
    return plan.isEmpty || plan == 'None' ? 'None (not paid yet)' : plan;
  }

  /// Les comptes client/collecteur ont un mot de passe de connexion.
  bool get _needsPassword =>
      widget.type == BoEntity.client || widget.type == BoEntity.collecteur;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _phone = TextEditingController();
    _zone = TextEditingController();
    _number = TextEditingController();
    _password = TextEditingController();
    _cni = TextEditingController();
    _vehicle = TextEditingController();
    _salary = TextEditingController();
    _photoUrl = TextEditingController();
    _photoUrl2 = TextEditingController();
    _pickupTime = TextEditingController();
    _date = DateTime.now();
    _seed();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _zone.dispose();
    _number.dispose();
    _password.dispose();
    _cni.dispose();
    _vehicle.dispose();
    _salary.dispose();
    _photoUrl.dispose();
    _photoUrl2.dispose();
    _pickupTime.dispose();
    super.dispose();
  }

  void _seed() {
    final d = widget.existing;
    switch (widget.type) {
      case BoEntity.client:
        final c = d as ClientModel?;
        _name.text = c?.name ?? '';
        _phone.text = c?.phone ?? '';
        _zone.text = c?.zone ?? '';
        // Plan offered for a cash payment (the client's current plan is
        // only changed by a recorded payment).
        _selectA = SubscriptionPlans.byTitle(c?.plan)?.title ?? 'Monthly';
        _payment = c == null ? 'Not paid yet' : 'No new payment';
        _selectB = c?.status ?? 'Active';
        _cni.text = c?.adresse ?? '';
        _vehicle.text = c?.quartier ?? '';
        _salary.text = c?.latitude != null ? c!.latitude!.toStringAsFixed(6) : '';
        _photoUrl.text = c?.photoUrl ?? '';
        _photoUrl2.text = c?.longitude != null ? c!.longitude!.toStringAsFixed(6) : '';
        _selectC = c?.housingType ?? 'House';
        // Load collection_days from users/{phone} doc (not on ClientModel).
        if (_isEdit && c != null) {
          final canonical = _canonicalPhone(c.phone);
          if (canonical.isNotEmpty) {
            FirebaseFirestore.instance
                .collection('users')
                .doc(canonical)
                .get()
                .then((doc) {
              if (doc.exists && mounted) {
                final days = (doc.data()?['collection_days'] as List<dynamic>?)
                        ?.map((e) => e.toString())
                        .toList() ?? [];
                final time = doc.data()?['pickup_time'] as String? ?? '';
                setState(() {
                  _collectionDays.addAll(days);
                  if (time.isNotEmpty) _pickupTime.text = time;
                });
              }
            });
          }
        }
      case BoEntity.collecteur:
        final c = d as CollecteurModel?;
        _name.text = c?.name ?? '';
        _phone.text = c?.phone ?? '';
        _zone.text = c?.zone ?? '';
        _status = c?.status ?? 'Active';
        _cni.text = c?.cni ?? '';
        _zoneArea = c?.zoneArea;
      case BoEntity.contrat:
        final c = d as ContratModel?;
        _selectA =
            c?.client ??
            (widget.store.clients.isNotEmpty
                ? widget.store.clients.first.name
                : '');
        _selectB =
            c?.frequence ??
            (widget.store.frequences.isNotEmpty
                ? widget.store.frequences.first.libelle
                : '');
        _number.text = c?.prix.toString() ?? '';
        _seedStatus(c?.status ?? 'Active');
      case BoEntity.collecte:
        final c = d as CollecteModel?;
        _selectA =
            c?.client ??
            (widget.store.clients.isNotEmpty
                ? widget.store.clients.first.name
                : '');
        _selectB =
            c?.collecteur ??
            (widget.store.collecteurs.isNotEmpty
                ? widget.store.collecteurs.first.name
                : '');
        _number.text = c != null && c.poids > 0 ? c.poids.toString() : '';
        _date = c != null
            ? (DateTime.tryParse(c.date) ?? DateTime.now())
            : DateTime.now();
        _seedStatus(c?.status ?? 'Scheduled');
      case BoEntity.facture:
        final c = d as FactureModel?;
        _selectA =
            c?.client ??
            (widget.store.clients.isNotEmpty
                ? widget.store.clients.first.name
                : '');
        _number.text = c?.montant.toString() ?? '';
        _date = c != null
            ? (DateTime.tryParse(c.echeance) ?? DateTime.now())
            : DateTime.now();
        _seedStatus(c?.status ?? 'Pending');
      case BoEntity.frequence:
        final c = d as FrequenceModel?;
        _name.text = c?.libelle ?? '';
        _number.text = c?.jours.toString() ?? '7';
      case BoEntity.issue:
        break; // Issues have their own page
      case BoEntity.zone:
        break; // Zones have their own page
      case BoEntity.assignment:
        break; // Assignments have their own page
      case BoEntity.vehicle:
        final v = d as VehicleModel?;
        _name.text = v?.plateNumber ?? '';
        _number.text = v?.brand ?? '';
        _selectC = v?.type ?? 'Tricycle';
        _status = v?.status ?? 'Active';
    }
  }

  void _seedStatus(String status) {
    // status select is the last dropdown of every form except frequence;
    // keep it on a dedicated member when the form has two selects.
    _status = status;
  }

  String _status = '';

  /// Collector form: operating zone circled on the map.
  ZoneArea? _zoneArea;

  Future<void> _pickZoneArea() async {
    final area = await Navigator.of(context).push<ZoneArea>(
      MaterialPageRoute(
        builder: (_) => ZoneAreaPickerScreen(
          initial: _zoneArea,
          initialQuery: _zone.text.trim(),
        ),
      ),
    );
    if (area == null || !mounted) return;
    setState(() {
      _zoneArea = area;
      if (_zone.text.trim().isEmpty) _zone.text = area.name;
    });
  }

  /// « Operating zone on the map »: preview of the circled zone + change.
  Widget _zoneAreaField() {
    final area = _zoneArea;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Operating zone on the map'),
          if (area != null) ...[
            ZoneAreaPreview(area: area),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${area.name} · ${switch (area.source) {
                      'osm' => 'official limits',
                      'drawn' => 'drawn zone',
                      _ => '${(area.radiusMeters / 1000).toStringAsFixed(1)} km around',
                    }}',
                    style: BackofficeTheme.inter(12, weight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  key: const Key('collector_zone_area_change'),
                  onPressed: _pickZoneArea,
                  child: const Text('Change'),
                ),
              ],
            ),
          ] else
            OutlinedButton.icon(
              key: const Key('collector_zone_area'),
              onPressed: _pickZoneArea,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Circle his zone on the map'),
              style: OutlinedButton.styleFrom(
                foregroundColor: BackofficeTheme.green,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
        ],
      ),
    );
  }

  String get _title {
    final base = switch (widget.type) {
      BoEntity.client => 'client',
      BoEntity.collecteur => 'collector',
      BoEntity.contrat => 'contract',
      BoEntity.collecte => 'collection',
      BoEntity.facture => 'invoice',
      BoEntity.frequence => 'frequency',
      BoEntity.issue => 'issue',
      BoEntity.zone => 'zone',
      BoEntity.assignment => 'assignment',
      BoEntity.vehicle => 'vehicle',
    };
    return '${_isEdit ? 'Edit' : 'New'} $base';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _date = picked);
  }

  String _fmtDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final store = widget.store;
    final s = _name.text.trim();
    final phone = _phone.text.trim();
    final zone = _zone.text.trim();
    final numText = _number.text.trim();
    final n = int.tryParse(numText) ?? 0;
    final r = double.tryParse(numText) ?? 0;
    final password = _password.text.trim();

    // Password: required at creation (it lets the person log in to their
    // interface); when editing, empty = keep the current one.
    if (_needsPassword) {
      if (!_isEdit && password.isEmpty) {
        return _warn('Password is required (min. 4 characters)');
      }
      if (password.isNotEmpty && password.length < 6) {
        return _warn('Password must be at least 6 characters');
      }
    }

    try {
      switch (widget.type) {
        case BoEntity.client:
          if (s.isEmpty) return _warn('Client name is required');
          final adresse = _cni.text.trim();
          final quartier = _vehicle.text.trim();
          final lat = double.tryParse(_salary.text.trim());
          final lng = double.tryParse(_photoUrl2.text.trim());
          final photoUrl = _photoUrl.text.trim();
          final housingType = _selectC.isEmpty ? 'House' : _selectC;
          if (_isEdit) {
            await store.updateClient(
              (widget.existing as ClientModel).copyWith(
                name: s,
                phone: phone,
                zone: zone,
                status: _selectB,
                adresse: adresse,
                quartier: quartier,
                latitude: lat,
                longitude: lng,
                photoUrl: photoUrl,
                housingType: housingType,
              ),
              password: password,
              collectionDays: _collectionDays.toList(),
              pickupTime: _pickupTime.text.trim(),
              cashPlan: _payment == _paidInCash ? _selectA : '',
            );
          } else {
            await store.addClient(
              name: s,
              phone: phone,
              zone: zone,
              plan: _selectA,
              paidInCash: _payment == _paidInCash,
              status: _selectB,
              password: password,
              adresse: adresse,
              quartier: quartier,
              latitude: lat,
              longitude: lng,
              photoUrl: photoUrl,
              housingType: housingType,
              collectionDays: _collectionDays.toList(),
              pickupTime: _pickupTime.text.trim(),
            );
          }
        case BoEntity.collecteur:
          if (s.isEmpty) return _warn('Collector name is required');
          final cni = _cni.text.trim();
          // Rating / vehicle / salary / photo are no longer asked: an edit
          // keeps the values already saved, a new collector has none.
          if (_isEdit) {
            await store.updateCollecteur(
              (widget.existing as CollecteurModel).copyWith(
                name: s,
                phone: phone,
                zone: zone,
                status: _status,
                cni: cni,
                zoneArea: _zoneArea,
              ),
              password: password,
            );
          } else {
            await store.addCollecteur(
              name: s,
              phone: phone,
              zone: zone,
              rating: 0,
              status: _status,
              password: password,
              cni: cni,
              zoneArea: _zoneArea,
            );
          }
        case BoEntity.contrat:
          if (_selectA.isEmpty || _selectB.isEmpty) {
            return _warn('No client or frequency available');
          }
          if (n <= 0) return _warn('Price is required');
          if (_isEdit) {
            await store.updateContrat(
              (widget.existing as ContratModel).copyWith(
                client: _selectA,
                frequence: _selectB,
                prix: n,
                status: _status,
              ),
            );
          } else {
            await store.addContrat(
              client: _selectA,
              frequence: _selectB,
              prix: n,
              status: _status,
            );
          }
        case BoEntity.collecte:
          if (_selectA.isEmpty || _selectB.isEmpty) {
            return _warn('No client or collector available');
          }
          if (_isEdit) {
            await store.updateCollecte(
              (widget.existing as CollecteModel).copyWith(
                client: _selectA,
                collecteur: _selectB,
                date: _fmtDate(_date),
                poids: r,
                status: _status,
              ),
            );
          } else {
            await store.addCollecte(
              client: _selectA,
              collecteur: _selectB,
              date: _fmtDate(_date),
              poids: r,
              status: _status,
            );
          }
        case BoEntity.facture:
          if (_selectA.isEmpty) return _warn('No client available');
          if (n <= 0) return _warn('Amount is required');
          if (_isEdit) {
            await store.updateFacture(
              (widget.existing as FactureModel).copyWith(
                client: _selectA,
                montant: n,
                echeance: _fmtDate(_date),
                status: _status,
              ),
            );
          } else {
            await store.addFacture(
              client: _selectA,
              montant: n,
              echeance: _fmtDate(_date),
              status: _status,
            );
          }
        case BoEntity.frequence:
          if (s.isEmpty) return _warn('Label is required');
          if (_isEdit) {
            await store.updateFrequence(
              (widget.existing as FrequenceModel).copyWith(
                libelle: s,
                jours: n,
              ),
            );
          } else {
            await store.addFrequence(libelle: s, jours: n);
          }
        case BoEntity.issue:
          break; // Issues are managed via their own page
        case BoEntity.zone:
          break; // Zones are managed via their own page
        case BoEntity.assignment:
          break; // Assignments are managed via their own page
        case BoEntity.vehicle:
          final plate = _name.text.trim();
          final type = _selectC.isEmpty ? 'Tricycle' : _selectC;
          final brand = _number.text.trim();
          final model = _vehicle.text.trim();
          final statusVal = _status.isEmpty ? 'Active' : _status;
          if (_isEdit) {
            await store.updateVehicle(
              (widget.existing as VehicleModel).copyWith(
                plateNumber: plate,
                type: type,
                brand: brand,
                model: model,
                status: statusVal,
              ),
            );
          } else {
            await store.addVehicle(
              plateNumber: plate,
              type: type,
              brand: brand,
              model: model,
              status: statusVal,
            );
          }
      }
    } catch (e) {
      // Échec (ex. numéro déjà utilisé par un autre compte) : on garde la
      // feuille ouverte pour que l'admin puisse corriger.
      _warn(e.toString());
      return;
    }
    if (mounted) Navigator.of(context).pop();
    BoToastService.show(_isEdit ? 'Changes saved' : 'Added successfully');
  }

  void _warn(String message) {
    BoToastService.show(message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final desktop = _isBoDesktop(context);
    return Padding(
      padding: EdgeInsets.only(bottom: desktop ? 0 : inset),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Desktop (web-first) : dialogue centré borné à 560 px ; mobile :
            // pleine largeur (bottom sheet).
            maxWidth: desktop ? 560 : double.infinity,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: BackofficeTheme.surface,
              borderRadius: _boSheetRadius(context),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Poignée de drag : réservée à la bottom sheet mobile.
                if (!desktop)
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: BackofficeTheme.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(18, desktop ? 10 : 2, 12, 14),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Cancel',
                          style: BackofficeTheme.inter(
                            13,
                            weight: FontWeight.w600,
                            color: BackofficeTheme.muted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _title,
                          textAlign: TextAlign.center,
                          style: BackofficeTheme.sora(
                            14.5,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('bo_sheet_save'),
                        onPressed: _save,
                        child: Text(
                          'OK',
                          style: BackofficeTheme.inter(
                            13,
                            weight: FontWeight.w700,
                            color: BackofficeTheme.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: BackofficeTheme.border),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _fields(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _fields() {
    final store = widget.store;
    switch (widget.type) {
      case BoEntity.client:
        return [
          _text(
            'Full name',
            _name,
            key: const Key('bo_f_name'),
            hint: 'Ex. Jean Dooh',
          ),
          _text('Phone', _phone, hint: '+237 6XX XX XX XX', phone: true),
          _text('Address', _cni, hint: 'Ex. Avenue de la République 123'),
          _text('Zone / Area', _zone, hint: 'Ex. Bastos'),
          _text('Neighborhood', _vehicle, hint: 'Ex. Bastos'),
          // Subscription: only a recorded payment activates a plan — here a
          // cash payment received at the agency; otherwise the client pays
          // in the app.
          if (_isEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Current plan: ${_currentPlanLabel()}',
                style: BackofficeTheme.inter(12, weight: FontWeight.w600),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _select(
                  'Payment',
                  [_isEdit ? 'No new payment' : 'Not paid yet', _paidInCash],
                  _payment,
                  (v) => setState(() => _payment = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _select(
                  'Status',
                  ['Active', 'Suspended'],
                  _selectB,
                  (v) => setState(() => _selectB = v),
                ),
              ),
            ],
          ),
          if (_payment == _paidInCash) ...[
            _select(
              'Plan paid',
              [for (final p in SubscriptionPlans.all) p.title],
              _selectA,
              (v) => setState(() => _selectA = v),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Amount received in cash: '
                '${SubscriptionPlans.byTitle(_selectA)?.price.toStringAsFixed(0) ?? '-'} XAF '
                '— a 30-day subscription starts today.',
                style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
              ),
            ),
          ] else if (!_isEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'The client chooses and pays a plan in the app.',
                style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _select(
                  'Housing Type',
                  ['House', 'Apartment', 'Villa', 'Other'],
                  _selectC.isEmpty ? 'House' : _selectC,
                  (v) => setState(() => _selectC = v),
                ),
              ),
            ],
          ),
          // Collection days multi-select (clients only)
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Collection Day(s)'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _allDays.map((day) {
                    final isSelected = _collectionDays.contains(day);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _collectionDays.remove(day);
                          } else {
                            _collectionDays.add(day);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected ? BackofficeTheme.green : BackofficeTheme.graySoft,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? BackofficeTheme.green : BackofficeTheme.border,
                          ),
                        ),
                        child: Text(
                          _dayAbbrev[day] ?? day,
                          style: BackofficeTheme.inter(
                            11,
                            weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? Colors.white : BackofficeTheme.text,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          // Pickup time window (clients only)
          _text(
            'Pickup Time Window',
            _pickupTime,
            hint: '07:00 — 08:00',
          ),
          Row(
            children: [
              Expanded(
                child: _text(
                  'GPS Latitude',
                  _salary,
                  hint: '3.8665',
                  number: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _text(
                  'GPS Longitude',
                  _photoUrl2,
                  hint: '11.5155',
                  number: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                  ],
                ),
              ),
            ],
          ),
          // Photo : prise avec la caméra ou choisie dans la galerie
          // (même expérience que la pré-inscription côté client).
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: PhotoPickerField(
              key: const Key('bo_f_photo'),
              label: 'Photo',
              initialValue: _photoUrl.text,
              onChanged: (v) => _photoUrl.text = v,
            ),
          ),
          _passwordField(),
        ];
      case BoEntity.collecteur:
        return [
          _text('Full name', _name, hint: 'Ex. Paul Mbarga'),
          _text('Phone', _phone, hint: '+237 6XX XX XX XX', phone: true),
          _text('CNI (National ID)', _cni, hint: 'Ex. 111222333'),
          _text('Assigned zone', _zone, hint: 'Ex. Bastos / Nlongkak'),
          _zoneAreaField(),
          _select(
            'Status',
            ['Active', 'Inactive'],
            _status.isEmpty ? 'Active' : _status,
            (v) => setState(() => _status = v),
          ),
          _passwordField(),
        ];
      case BoEntity.contrat:
        return [
          _select(
            'Client',
            store.clients.map((c) => c.name).toList(),
            _selectA,
            (v) => setState(() => _selectA = v),
          ),
          _select(
            'Frequency',
            store.frequences.map((f) => f.libelle).toList(),
            _selectB,
            (v) => setState(() => _selectB = v),
          ),
          Row(
            children: [
              Expanded(
                child: _text(
                  'Price / month (XAF)',
                  _number,
                  hint: '8000',
                  number: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _select(
                  'Status',
                  ['Active', 'Suspended', 'Expired'],
                  _status.isEmpty ? 'Active' : _status,
                  (v) => setState(() => _status = v),
                ),
              ),
            ],
          ),
        ];
      case BoEntity.collecte:
        return [
          _select(
            'Client',
            store.clients.map((c) => c.name).toList(),
            _selectA,
            (v) => setState(() => _selectA = v),
          ),
          _select(
            'Collector',
            store.collecteurs.map((c) => c.name).toList(),
            _selectB,
            (v) => setState(() => _selectB = v),
          ),
          Row(
            children: [
              Expanded(child: _dateField('Date', _fmtDate(_date), _pickDate)),
              const SizedBox(width: 12),
              Expanded(
                child: _text(
                  'Weight (kg)',
                  _number,
                  hint: '0',
                  number: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
              ),
            ],
          ),
          _select(
            'Status',
            ['Scheduled', 'Completed', 'Missed'],
            _status.isEmpty ? 'Scheduled' : _status,
            (v) => setState(() => _status = v),
          ),
        ];
      case BoEntity.facture:
        return [
          _select(
            'Client',
            store.clients.map((c) => c.name).toList(),
            _selectA,
            (v) => setState(() => _selectA = v),
          ),
          Row(
            children: [
              Expanded(
                child: _text(
                  'Amount (XAF)',
                  _number,
                  hint: '8000',
                  number: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dateField('Due date', _fmtDate(_date), _pickDate),
              ),
            ],
          ),
          _select(
            'Status',
            ['Paid', 'Pending', 'Overdue'],
            _status.isEmpty ? 'Pending' : _status,
            (v) => setState(() => _status = v),
          ),
        ];
      case BoEntity.frequence:
        return [
          _text('Label', _name, hint: 'Ex. Twice a week'),
          _text('Interval (days)', _number, hint: '7', number: true),
        ];
      case BoEntity.issue:
        return []; // Issues have their own page
      case BoEntity.zone:
        return []; // Zones have their own page
      case BoEntity.assignment:
        return []; // Assignments have their own page
      case BoEntity.vehicle:
        return [
          _text('Plate Number', _name, hint: 'CE-123-AE'),
          _select(
            'Type',
            ['Tricycle', 'Truck', 'Motorcycle', 'Van'],
            _selectC.isEmpty ? 'Tricycle' : _selectC,
            (v) => setState(() => _selectC = v),
          ),
          _text('Brand', _number, hint: 'TVS, Bajaj, Isuzu...'),
          _text('Model', _vehicle, hint: 'King HD, RE HD...'),
          _select(
            'Status',
            ['Active', 'Maintenance', 'Retired'],
            _status.isEmpty ? 'Active' : _status,
            (v) => setState(() => _status = v),
          ),
        ];
    }
  }

  String _canonicalPhone(String phone) {
    final cleaned = phone.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) return '';
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('237')) return '+$cleaned';
    return '+237$cleaned';
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: BackofficeTheme.inter(
        11,
        weight: FontWeight.w600,
        color: BackofficeTheme.muted,
      ),
    ),
  );

  Widget _text(
    String label,
    TextEditingController controller, {
    String? hint,
    bool phone = false,
    bool number = false,
    Key? key,
    List<TextInputFormatter>? inputFormatters,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(label),
          TextField(
            key: key,
            controller: controller,
            obscureText: obscure,
            keyboardType: number
                ? TextInputType.number
                : phone
                ? TextInputType.phone
                : TextInputType.text,
            inputFormatters: inputFormatters,
            style: BackofficeTheme.inter(14),
            decoration: _dec(hint, suffixIcon: suffixIcon),
          ),
        ],
      ),
    );
  }

  /// Champ mot de passe (client / collecteur) : c'est lui qui permet à la
  /// personne de se connecter à son interface dédiée.
  Widget _passwordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _text(
          'Password',
          _password,
          key: const Key('bo_f_password'),
          hint: _isEdit ? 'Leave empty to keep current' : 'Min. 4 characters',
          obscure: _obscurePassword,
          suffixIcon: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 17,
              color: BackofficeTheme.muted,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: Text(
            widget.type == BoEntity.client
                ? 'This password lets this client log in to their client app.'
                : 'This password lets this collector log in to their collector app.',
            style: BackofficeTheme.inter(10.5, color: BackofficeTheme.muted),
          ),
        ),
      ],
    );
  }

  Widget _select(
    String label,
    List<String> options,
    String value,
    ValueChanged<String> onChanged,
  ) {
    if (options.isEmpty && value.isEmpty) return const SizedBox.shrink();
    // If the current value isn't in the options list (e.g. a collection
    // references a client that was renamed or deleted), prepend it so the
    // dropdown shows the correct name instead of falling back to the first
    // option.
    final effectiveOptions = (
      value.isNotEmpty && !options.contains(value)
          ? [value, ...options]
          : options
    ).toList();
    final current = effectiveOptions.contains(value) ? value : effectiveOptions.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(label),
          DropdownButtonFormField<String>(
            initialValue: current,
            isExpanded: true,
            style: BackofficeTheme.inter(14),
            dropdownColor: BackofficeTheme.surface,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: BackofficeTheme.muted,
            ),
            decoration: _dec(null),
            items: [
              for (final o in effectiveOptions)
                DropdownMenuItem(
                  value: o,
                  child: Text(o, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _dateField(String label, String value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(label),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: _dec(null),
              child: Text(value, style: BackofficeTheme.inter(14)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String? hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: BackofficeTheme.inter(14, color: BackofficeTheme.muted),
      filled: true,
      fillColor: BackofficeTheme.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: BackofficeTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: BackofficeTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: BackofficeTheme.green),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review sheet (client applications)
// ---------------------------------------------------------------------------

class _BoReviewSheet extends StatefulWidget {
  const _BoReviewSheet({required this.store, required this.reg});

  final BackofficeStore store;
  final RegistrationModel reg;

  @override
  State<_BoReviewSheet> createState() => _BoReviewSheetState();
}

class _BoReviewSheetState extends State<_BoReviewSheet> {
  String _collecteurId = '';
  bool _busy = false;

  /// Collecteurs actifs disponibles pour l'assignation.
  List<CollecteurModel> get _collecteurs => widget.store.collecteurs
      .where((c) => c.status == 'Active' || c.status == 'Actif')
      .toList();

  bool _covers(CollecteurModel c) =>
      collecteurCovers(c, widget.reg.latitude, widget.reg.longitude);

  @override
  void initState() {
    super.initState();
    // Pré-sélection : le collecteur dont la zone (tracée sur la carte)
    // contient le point GPS du demandeur.
    for (final c in _collecteurs) {
      if (_covers(c)) {
        _collecteurId = c.id;
        break;
      }
    }
  }

  String get _collecteurName {
    for (final c in _collecteurs) {
      if (c.id == _collecteurId) return c.name;
    }
    return '';
  }

  Future<void> _approve() async {
    if (_collecteurId.isEmpty) {
      BoToastService.show(
        _collecteurs.isEmpty
            ? 'Create an active collector first'
            : 'Choose the collector to assign',
        isError: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.store.approveRegistration(
        widget.reg,
        collecteurId: _collecteurId,
      );
      if (mounted) Navigator.of(context).pop();
      BoToastService.show(
        '${widget.reg.fullName} approved and assigned to $_collecteurName',
      );
    } catch (e) {
      if (mounted) BoToastService.show(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await widget.store.rejectRegistration(widget.reg);
      if (mounted) Navigator.of(context).pop();
      BoToastService.show('Application rejected');
    } catch (e) {
      if (mounted) BoToastService.show(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reg = widget.reg;
    final desktop = _isBoDesktop(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: desktop ? 0 : MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: desktop ? 560 : double.infinity,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: BackofficeTheme.surface,
              borderRadius: _boSheetRadius(context),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, desktop ? 18 : 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!desktop)
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: BackofficeTheme.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  Text(
                    'Review application',
                    textAlign: TextAlign.center,
                    style: BackofficeTheme.sora(15, weight: FontWeight.w700),
                  ),
              const SizedBox(height: 18),

              // Applicant identity
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BackofficeTheme.greenSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reg.fullName,
                      style: BackofficeTheme.inter(
                        15,
                        weight: FontWeight.w700,
                        color: BackofficeTheme.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _detail(Icons.phone_outlined, reg.phone),
                    _detail(Icons.map_outlined, reg.zone),
                    _detail(Icons.storefront_outlined, reg.agenceName),
                    _detail(
                      Icons.event_outlined,
                      'Applied ${boFmtDate(reg.createdAt)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Collector assignment
              Text(
                'Assign a collector',
                style: BackofficeTheme.inter(
                  11.5,
                  weight: FontWeight.w600,
                  color: BackofficeTheme.muted,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('bo_review_collector'),
                initialValue: _collecteurId.isEmpty ? null : _collecteurId,
                isExpanded: true,
                hint: Text(
                  _collecteurs.isEmpty
                      ? 'No active collector yet'
                      : 'Choose a collector',
                  style: BackofficeTheme.inter(
                    13,
                    color: BackofficeTheme.muted,
                  ),
                ),
                style: BackofficeTheme.inter(13.5),
                dropdownColor: BackofficeTheme.surface,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: BackofficeTheme.muted,
                ),
                decoration: _dec(null),
                items: [
                  for (final c in _collecteurs)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        collecteurOptionLabel(c, covers: _covers(c)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _collecteurId = v ?? ''),
              ),
              const SizedBox(height: 6),
              Text(
                _collecteurs.any(_covers)
                    ? 'Pre-selected: the applicant\'s location is inside this '
                        'collector\'s zone. You can choose another one.'
                    : 'One collector can serve several clients — you can '
                        'reassign them anytime from the Clients page.',
                key: const Key('bo_review_hint'),
                style: BackofficeTheme.inter(
                  10.5,
                  color: BackofficeTheme.muted,
                ),
              ),
              const SizedBox(height: 20),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('bo_review_reject'),
                      onPressed: _busy ? null : _reject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BackofficeTheme.red,
                        side: const BorderSide(color: BackofficeTheme.red),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('bo_review_approve'),
                      onPressed: _busy ? null : _approve,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BackofficeTheme.green,
                        foregroundColor: BackofficeTheme.cream,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: BackofficeTheme.cream,
                              ),
                            )
                          : const Text('Approve'),
                    ),
                  ),
                ],
              ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: BackofficeTheme.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: BackofficeTheme.inter(
                12.5,
                color: BackofficeTheme.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: BackofficeTheme.inter(13, color: BackofficeTheme.muted),
      filled: true,
      fillColor: BackofficeTheme.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: BackofficeTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: BackofficeTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: BackofficeTheme.green),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reassign collector sheet (client)
// ---------------------------------------------------------------------------

/// Opens the reassign sheet for a client: pick the collector who will now
/// serve this client. Updates the client, its login account and the upcoming
/// collections.
Future<void> showBoReassignSheet(
  BuildContext context, {
  required BackofficeStore store,
  required ClientModel client,
}) {
  return showBoSheet(
    context,
    builder: (_) => _BoReassignSheet(store: store, client: client),
  );
}

class _BoReassignSheet extends StatefulWidget {
  const _BoReassignSheet({required this.store, required this.client});

  final BackofficeStore store;
  final ClientModel client;

  @override
  State<_BoReassignSheet> createState() => _BoReassignSheetState();
}

class _BoReassignSheetState extends State<_BoReassignSheet> {
  late String _collecteurId;
  bool _busy = false;

  /// Collecteurs actifs disponibles pour l'assignation.
  List<CollecteurModel> get _collecteurs => widget.store.collecteurs
      .where((c) => c.status == 'Active' || c.status == 'Actif')
      .toList();

  String get _collecteurName {
    for (final c in _collecteurs) {
      if (c.id == _collecteurId) return c.name;
    }
    return '';
  }

  bool _covers(CollecteurModel c) =>
      collecteurCovers(c, widget.client.latitude, widget.client.longitude);

  @override
  void initState() {
    super.initState();
    // Pré-sélectionne le collecteur actuel s'il est toujours actif, sinon
    // celui dont la zone (tracée sur la carte) contient l'adresse du client.
    _collecteurId = _collecteurs.any((c) => c.id == widget.client.collecteurId)
        ? widget.client.collecteurId
        : _collecteurs.where(_covers).map((c) => c.id).firstOrNull ?? '';
  }

  Future<void> _confirm() async {
    if (_collecteurId.isEmpty) {
      BoToastService.show('Choose the collector to assign', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.store.reassignCollecteur(
        clientId: widget.client.id,
        collecteurId: _collecteurId,
      );
      if (mounted) Navigator.of(context).pop();
      BoToastService.show(
        '${widget.client.name} is now assigned to $_collecteurName',
      );
    } catch (e) {
      if (mounted) BoToastService.show(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final desktop = _isBoDesktop(context);
    final current = widget.store.collecteurs
        .where((c) => c.id == client.collecteurId)
        .map((c) => c.name)
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: desktop ? 0 : MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: desktop ? 560 : double.infinity,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: BackofficeTheme.surface,
              borderRadius: _boSheetRadius(context),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, desktop ? 18 : 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!desktop)
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: BackofficeTheme.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  Text(
                    'Reassign collector',
                    textAlign: TextAlign.center,
                    style: BackofficeTheme.sora(15, weight: FontWeight.w700),
                  ),
              const SizedBox(height: 18),

              // Client identity
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BackofficeTheme.greenSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.name,
                      style: BackofficeTheme.inter(
                        15,
                        weight: FontWeight.w700,
                        color: BackofficeTheme.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _detail(Icons.map_outlined, client.zone),
                    _detail(
                      Icons.person_outline_rounded,
                      current.isEmpty
                          ? 'No collector assigned'
                          : 'Current collector: ${current.first}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              Text(
                'New collector',
                style: BackofficeTheme.inter(
                  11.5,
                  weight: FontWeight.w600,
                  color: BackofficeTheme.muted,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('bo_reassign_collector'),
                initialValue: _collecteurId.isEmpty ? null : _collecteurId,
                isExpanded: true,
                hint: Text(
                  _collecteurs.isEmpty
                      ? 'No active collector yet'
                      : 'Choose a collector',
                  style: BackofficeTheme.inter(
                    13,
                    color: BackofficeTheme.muted,
                  ),
                ),
                style: BackofficeTheme.inter(13.5),
                dropdownColor: BackofficeTheme.surface,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: BackofficeTheme.muted,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: BackofficeTheme.bg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: BackofficeTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: BackofficeTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: BackofficeTheme.green),
                  ),
                ),
                items: [
                  for (final c in _collecteurs)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        collecteurOptionLabel(c, covers: _covers(c)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _collecteurId = v ?? ''),
              ),
              const SizedBox(height: 6),
              Text(
                'One collector can serve several clients. The client, its '
                'login account and the upcoming collections will be '
                'updated. Completed pickups keep their history.',
                style: BackofficeTheme.inter(
                  10.5,
                  color: BackofficeTheme.muted,
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                key: const Key('bo_reassign_confirm'),
                onPressed: _busy ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BackofficeTheme.green,
                  foregroundColor: BackofficeTheme.cream,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BackofficeTheme.cream,
                        ),
                      )
                    : Text(
                        _collecteurId.isEmpty
                            ? 'Choose a collector'
                            : 'Confirm reassignment',
                        style: BackofficeTheme.inter(
                          13.5,
                          weight: FontWeight.w600,
                        ),
                      ),
              ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: BackofficeTheme.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: BackofficeTheme.inter(
                12.5,
                color: BackofficeTheme.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
