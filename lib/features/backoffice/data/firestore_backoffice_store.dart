import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../models/assignment_model.dart';
import '../../../services/auth_backend.dart';
import '../../../services/auth_service.dart';
import '../../../services/functions_client.dart';
import '../../../services/invoice_service.dart';
import '../../../services/notification_service.dart';
import '../models.dart';
import 'backoffice_store.dart';
import 'seed_data.dart';

/// Firestore-backed implementation of [BackofficeStore] for the real mobile
/// backoffice (entreprise manager).
///
/// - Collections: `clients`, `collecteurs` (document id = entity id).
/// - Data stays in sync in real time through snapshot listeners.
/// - When a collection is empty on first load, it is seeded with the
///   design's default entities (see [seedIfEmpty]) so the backoffice is
///   never blank on a fresh project.
/// - Creating / editing a client or collector with a password (sent to
///   Firebase Auth only, never stored in Firestore) also creates
///   its **login account** in `users` (role 'client' / 'collector', marker
///   `consoleCreated`) so the person can log in to their dedicated
///   interface. Active collectors are also pre-approved in the `collectors`
///   whitelist.
/// - On failure (network / rules), [error] is set so the screen can show a
///   banner with a retry action; the mock data is never shown.
class FirestoreBackofficeStore extends BackofficeStore {
  FirestoreBackofficeStore({
    FirebaseFirestore? db,
    AuthBackend? backend,
    InvoiceService? invoiceService,
    this.seedIfEmpty = true,
    this.agenceId = '',
    this.societeId = '',
    @visibleForTesting bool Function()? isSignedOut,
    @visibleForTesting
    Future<void> Function(String phone, String plan)? recordCashPayment,
    @visibleForTesting Future<void> Function(String issueId)? notifyIssueAssigned,
  }) : _isSignedOutOverride = isSignedOut,
       _recordCashPayment = recordCashPayment,
       _notifyIssueAssigned = notifyIssueAssigned,
       _db = db ?? FirebaseFirestore.instance,
       _backend = backend ?? FirebaseAuthBackend(),
       _invoiceService = invoiceService ?? InvoiceService(db: db) {
    _isScoped = agenceId.isNotEmpty;
    // Never flash the design's mock data in the real backoffice.
    clients.clear();
    collecteurs.clear();
    registrations.clear();
    zones.clear();
    contrats.clear();
    collectes.clear();
    factures.clear();
    frequences.clear();
    vehicles.clear();
    maintenanceLogs.clear();
    load();
  }

  final FirebaseFirestore _db;

  /// Cash payment recorder (tests); defaults to the Cloud Function.
  final Future<void> Function(String phone, String plan)? _recordCashPayment;

  /// Issue-assignment notification (tests); defaults to the `notify` function.
  final Future<void> Function(String issueId)? _notifyIssueAssigned;

  /// Backend Auth (création de comptes client/collecteur). Injectable en test.
  final AuthBackend _backend;

  /// Génération automatique des factures de contrats (Paiements → Factures).
  /// Injectable en test (suit le `db` du store quand non fourni).
  final InvoiceService _invoiceService;

  /// When true, an empty collection is populated with [seedClients] /
  /// [seedCollecteurs] on first load.
  final bool seedIfEmpty;

  /// Id de l'agence du chef connecté (facultatif). Quand non vide, les
  /// données du backoffice sont filtrées à cette agence.
  final String agenceId;

  /// Id de l'entreprise (facultatif, porté par le login).
  final String societeId;

  /// Vrai quand le backoffice est limité à une agence (Phase 3).
  bool _isScoped = false;

  /// Ville (nom) de l'agence du chef — clé de secours pour retrouver les
  /// candidatures écrites avec le NOM de l'agence (`agenceName`) plutôt
  /// qu'avec son id (ex. doublons d'agences homonymes, candidatures dont
  /// l'`agenceId` pointe vers un autre doc que celui du chef).
  ///
  /// Compromis assumé : les chefs d'agences homonymes voient les mêmes
  /// candidatures (partage par nom) ; à l'approbation, le client est créé
  /// sous l'agence CHOISIE par le client (`reg.agenceId`), jamais sous
  /// celle du chef qui approuve — aucune donnée n'est corrompue.
  String _agencyVille = '';

  /// Candidatures vues par le query `agenceId == X` (clé = id du doc).
  final Map<String, RegistrationModel> _regsById = {};

  /// Candidatures vues par le query de secours `agenceName == ville`.
  final Map<String, RegistrationModel> _regsByName = {};

  /// Vrai après [dispose] : aucune notification ne doit plus être émise
  /// (garde pour les lectures one-shot comme [_loadAgenceVille], qui ne
  /// passent pas par un abonnement annulable).
  bool _disposed = false;

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs =
      [];

  Completer<void>? _loadCompleter;
  int _pending = 0;
  bool _seededClients = false;
  bool _seededCollecteurs = false;
  bool _seededContrats = false;
  bool _seededCollectes = false;
  bool _seededFactures = false;
  bool _seededFrequences = false;
  bool _seededVehicles = false;
  bool _seededMaintenance = false;

  /// Completes once the first snapshot of every collection has been applied
  /// (or an error occurred). Used by tests to await the initial load.
  Future<void> get initialLoad =>
      _loadCompleter?.future ?? Future<void>.value();

  @override
  String nextId() => 'b${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<void> load() async {
    _cancelSubscriptions();
    setLoading(true);
    setErrorValue(null);
    _pending = 12;
    _seededClients = false;
    _seededCollecteurs = false;
    _seededContrats = false;
    _seededCollectes = false;
    _seededFactures = false;
    _seededFrequences = false;
    _seededVehicles = false;
    _seededMaintenance = false;
    _regsById.clear();
    _regsByName.clear();
    _loadCompleter = Completer<void>();
    notifyListeners();

    // Phase 3 : quand le backoffice est scopé à une agence, les listeners
    // filtrent sur agenceId — le chef d'agence ne voit que SES données.
    final clientsQuery = _isScoped
        ? _db.collection('clients').where('agenceId', isEqualTo: agenceId)
        : _db.collection('clients');
    final collecteursQuery = _isScoped
        ? _db.collection('collecteurs').where('agenceId', isEqualTo: agenceId)
        : _db.collection('collecteurs');
    // Candidatures : celles adressées à cette agence (sélection dans le
    // formulaire client).
    final registrationsQuery = _isScoped
        ? _db
              .collection('registrations')
              .where('agenceId', isEqualTo: agenceId)
        : _db.collection('registrations');

    // Phase 3 : charge la ville de l'agence AVANT de monter les listeners
    // de candidatures — c'est la clé de secours par NOM (voir
    // [_agencyVille]). Silencieux : un échec ne doit pas bloquer le
    // backoffice (la recherche par id reste active).
    if (_isScoped && agenceId.isNotEmpty) {
      _agencyVille = await _loadAgenceVille();
    } else {
      _agencyVille = '';
    }

    _subs.add(
      clientsQuery.snapshots().listen(_onClients, onError: handleStreamError),
    );
    _subs.add(
      collecteursQuery
          .snapshots()
          .listen(_onCollecteurs, onError: handleStreamError),
    );
    // Fallback par NOM d'agence : un where supplémentaire sur un SEUL champ
    // (pas d'index composé requis). Fusionné en mémoire avec le listener par
    // id dans [registrations].
    if (_isScoped && _agencyVille.isNotEmpty) {
      _subs.add(
        _db
            .collection('registrations')
            .where('agenceName', isEqualTo: _agencyVille)
            .snapshots()
            .listen(
              _onRegistrationsByName,
              // Le fallback par nom est best-effort : un échec de CE query
              // ne doit pas afficher de bannière alors que le query par id
              // fonctionne (mêmes règles, mais défense en profondeur).
              onError: _ignoreFallbackError,
            ),
      );
    }
    _subs.add(
      registrationsQuery
          .snapshots()
          .listen(_onRegistrations, onError: handleStreamError),
    );

    // Issues reported by clients (agency stamped by `stampIssueScope`).
    final issuesQuery = _isScoped
        ? _db.collection('issues').where('agenceId', isEqualTo: agenceId)
        : _db.collection('issues');
    _subs.add(
      issuesQuery.snapshots().listen(_onIssues, onError: handleStreamError),
    );

    // Zones (collection calendars).
    final zonesQuery = _isScoped
        ? _db.collection('zones').where('agenceId', isEqualTo: agenceId)
        : _db.collection('zones');
    _subs.add(
      zonesQuery.snapshots().listen(_onZones, onError: handleStreamError),
    );

    // Assignments (collector → zone + time).
    final assignmentsQuery = _isScoped
        ? _db.collection('assignments').where('agenceId', isEqualTo: agenceId)
        : _db.collection('assignments');
    _subs.add(
      assignmentsQuery.snapshots().listen(_onAssignments, onError: handleStreamError),
    );

    // Contracts (contrats).
    final contratsQuery = _isScoped
        ? _db.collection('contrats').where('agenceId', isEqualTo: agenceId)
        : _db.collection('contrats');
    _subs.add(
      contratsQuery.snapshots().listen(_onContrats, onError: handleStreamError),
    );

    // Collections (collectes).
    final collectesQuery = _isScoped
        ? _db.collection('collectes').where('agenceId', isEqualTo: agenceId)
        : _db.collection('collectes');
    _subs.add(
      collectesQuery.snapshots().listen(_onCollectes, onError: handleStreamError),
    );

    // Pickups written by the collector's app (`pickups` collection): each
    // verified/pending/missed pickup is mirrored into the Collections list
    // so the agency manager sees field activity in real time. Scoped by
    // the agency the `stampPickupScope` function copies from the client
    // (the rules refuse other agencies' pickups).
    final pickupsQuery = _isScoped
        ? _db.collection('pickups').where('agenceId', isEqualTo: agenceId)
        : _db.collection('pickups');
    _subs.add(
      pickupsQuery.snapshots().listen(
            _onPickups,
            onError: handleStreamError,
          ),
    );

    // Invoices (factures).
    final facturesQuery = _isScoped
        ? _db.collection('factures').where('agenceId', isEqualTo: agenceId)
        : _db.collection('factures');
    _subs.add(
      facturesQuery.snapshots().listen(_onFactures, onError: handleStreamError),
    );

    // Frequency reference data — shared by all agencies (not scoped).
    _subs.add(
      _db
          .collection('frequences')
          .snapshots()
          .listen(_onFrequences, onError: handleStreamError),
    );

    // Vehicles (fleet) — loaded from Firestore like the other entities.
    final vehiclesQuery = _isScoped
        ? _db.collection('vehicles').where('agenceId', isEqualTo: agenceId)
        : _db.collection('vehicles');
    _subs.add(
      vehiclesQuery.snapshots().listen(_onVehicles, onError: handleStreamError),
    );

    // Vehicle maintenance logs.
    final maintenanceQuery = _isScoped
        ? _db
              .collection('vehicle_maintenance')
              .where('agenceId', isEqualTo: agenceId)
        : _db.collection('vehicle_maintenance');
    _subs.add(
      maintenanceQuery
          .snapshots()
          .listen(_onMaintenance, onError: handleStreamError),
    );

    await _loadCompleter!.future;
  }

  /// Lit `agences/{agenceId}`, expose son `ville` comme nom d'agence
  /// (sidebar) et le renvoie pour le fallback par nom des candidatures
  /// ('' si indisponible).
  Future<String> _loadAgenceVille() async {
    try {
      final doc = await _db.collection('agences').doc(agenceId).get();
      if (_disposed) return '';
      if (!doc.exists) return '';
      final ville = doc.data()?['ville'] as String? ?? '';
      if (ville.isNotEmpty) setAgenceName(ville);
      return ville;
    } catch (_) {
      // Silencieux (voir [load]).
      return '';
    }
  }

  // --- Snapshot handlers ---

  void _onClients(QuerySnapshot<Map<String, dynamic>> qs) {
    clients
      ..clear()
      ..addAll(qs.docs.map((d) => ClientModel.fromMap(d.data())));
    if (_seedEnabled && qs.docs.isEmpty && !_seededClients) {
      _seededClients = true;
      _seedCollection('clients', seedClients.map((c) => c.toMap()).toList());
    }
    _markLoaded();
  }

  void _onCollecteurs(QuerySnapshot<Map<String, dynamic>> qs) {
    collecteurs
      ..clear()
      ..addAll(qs.docs.map((d) => CollecteurModel.fromMap(d.data())));
    if (_seedEnabled && qs.docs.isEmpty && !_seededCollecteurs) {
      _seededCollecteurs = true;
      _seedCollection(
        'collecteurs',
        seedCollecteurs.map((c) => c.toMap()).toList(),
      );
      _seedCollectorWhitelist();
    }
    _markLoaded();
  }

  void _onRegistrations(QuerySnapshot<Map<String, dynamic>> qs) {
    _regsById
      ..clear()
      ..addEntries(
        qs.docs.map(
          (d) => MapEntry(d.id, RegistrationModel.fromMap(d.data())),
        ),
      );
    _rebuildRegistrations();
    _markLoaded();
  }

  void _onIssues(QuerySnapshot<Map<String, dynamic>> qs) {
    issues
      ..clear()
      ..addAll(
        qs.docs.map((d) {
          try {
            return IssueModel.fromMap({...d.data(), 'id': d.id});
          } catch (_) {
            return null;
          }
        }).whereType<IssueModel>(),
      );
    _markLoaded();
  }

  void _onZones(QuerySnapshot<Map<String, dynamic>> qs) {
    zones
      ..clear()
      ..addAll(
        qs.docs.map((d) {
          try {
            return ZoneModel.fromMap(d.data());
          } catch (_) {
            return null;
          }
        }).whereType<ZoneModel>(),
      );
    _markLoaded();
  }

  void _onAssignments(QuerySnapshot<Map<String, dynamic>> qs) {
    assignments
      ..clear()
      ..addAll(
        qs.docs.map((d) {
          try {
            return AssignmentModel.fromMap(d.data());
          } catch (_) {
            return null;
          }
        }).whereType<AssignmentModel>(),
      );
    _markLoaded();
  }

  void _onContrats(QuerySnapshot<Map<String, dynamic>> qs) {
    contrats
      ..clear()
      ..addAll(
        qs.docs.map((d) {
          try {
            return ContratModel.fromMap(d.data());
          } catch (_) {
            return null;
          }
        }).whereType<ContratModel>(),
      );
    if (_seedEnabled && qs.docs.isEmpty && !_seededContrats) {
      _seededContrats = true;
      _seedCollection('contrats', seedContrats.map((c) => c.toMap()).toList());
    }
    _markLoaded();
  }

  /// Mirrors `pickups` docs (collector app) into the `collectes` list.
  ///
  /// A pickup is keyed `pkp:<pickup_id>`. `verified` → Completed,
  /// `pending_client_confirmation` → Scheduled (awaiting confirmation),
  /// `missed` → Missed. Resolved client/collector names come from the
  /// `clients` / `collecteurs` lists already loaded by this store. When a
  /// pickup doc disappears (deleted), its mirror is removed too.
  void _onPickups(QuerySnapshot<Map<String, dynamic>> qs) {
    final live = <String, Map<String, dynamic>>{
      for (final d in qs.docs) d.id: d.data(),
    };

    // Remove mirrors whose pickup doc no longer exists.
    collectes.removeWhere((c) => c.id.startsWith('pkp:') && !live.containsKey(c.id.substring(4)));

    for (final entry in live.entries) {
      final data = entry.value;
      final status = data['status'] as String? ?? '';
      final boStatus = switch (status) {
        'verified' => 'Completed',
        'pending_client_confirmation' => 'Scheduled',
        'missed' => 'Missed',
        _ => null, // 'disputed' etc. — surface only through Issues.
      };
      if (boStatus == null) continue;

      final clientPhone = data['client_id'] as String? ?? '';
      final collectorId = data['collector_id'] as String? ?? '';

      // Agency scoping: resolve the client, then keep only pickups of our
      // agency (or unscoped stores keep everything).
      ClientModel? client;
      for (final c in clients) {
        if (c.phone == clientPhone) {
          client = c;
          break;
        }
      }
      if (_isScoped && client != null && client.agenceId != agenceId) continue;
      if (_isScoped && client == null) continue; // cannot attribute → skip

      String collectorName = data['collector_name'] as String? ?? '';
      if (collectorName.isEmpty) {
        for (final col in collecteurs) {
          if (col.id == collectorId || col.phone == collectorId) {
            collectorName = col.name;
            break;
          }
        }
      }

      final poids = (data['poids'] as num?)?.toDouble() ?? 0;
      final date = data['date'] as String? ?? '';
      final model = CollecteModel(
        id: 'pkp:${entry.key}',
        client: client?.name ?? clientPhone,
        collecteur: collectorName,
        date: date,
        poids: poids,
        status: boStatus,
        agenceId: client?.agenceId ?? '',
        societeId: client?.societeId ?? '',
      );

      final index = collectes.indexWhere((c) => c.id == model.id);
      if (index != -1) {
        collectes[index] = model;
      } else {
        collectes.add(model);
      }
    }
    _markLoaded();
    notifyListeners();
  }

  void _onCollectes(QuerySnapshot<Map<String, dynamic>> qs) {
    collectes
      ..clear()
      ..addAll(
        qs.docs.map((d) {
          try {
            return CollecteModel.fromMap(d.data());
          } catch (_) {
            return null;
          }
        }).whereType<CollecteModel>(),
      );
    if (_seedEnabled && qs.docs.isEmpty && !_seededCollectes) {
      _seededCollectes = true;
      _seedCollection('collectes', seedCollectes.map((c) => c.toMap()).toList());
    }
    _markLoaded();
  }

  void _onFactures(QuerySnapshot<Map<String, dynamic>> qs) {
    factures
      ..clear()
      ..addAll(
        qs.docs.map((d) {
          try {
            return FactureModel.fromMap(d.data());
          } catch (_) {
            return null;
          }
        }).whereType<FactureModel>(),
      );
    if (_seedEnabled && qs.docs.isEmpty && !_seededFactures) {
      _seededFactures = true;
      _seedCollection('factures', seedFactures.map((c) => c.toMap()).toList());
    }
    _markLoaded();
  }

  void _onFrequences(QuerySnapshot<Map<String, dynamic>> qs) {
    frequences
      ..clear()
      ..addAll(
        qs.docs.map((d) {
          try {
            return FrequenceModel.fromMap(d.data());
          } catch (_) {
            return null;
          }
        }).whereType<FrequenceModel>(),
      );
    if (_seedEnabled && qs.docs.isEmpty && !_seededFrequences) {
      _seededFrequences = true;
      _seedCollection(
        'frequences',
        seedFrequences.map((c) => c.toMap()).toList(),
      );
    }
    _markLoaded();
  }

  void _onVehicles(QuerySnapshot<Map<String, dynamic>> qs) {
    vehicles
      ..clear()
      ..addAll(
        qs.docs.map((d) {
          try {
            return VehicleModel.fromMap(d.data());
          } catch (_) {
            return null;
          }
        }).whereType<VehicleModel>(),
      );
    if (_seedEnabled && qs.docs.isEmpty && !_seededVehicles) {
      _seededVehicles = true;
      _seedCollection('vehicles', seedVehicles.map((c) => c.toMap()).toList());
    }
    _markLoaded();
  }

  void _onMaintenance(QuerySnapshot<Map<String, dynamic>> qs) {
    maintenanceLogs
      ..clear()
      ..addAll(
        qs.docs.map((d) {
          try {
            return VehicleMaintenanceModel.fromMap(d.data());
          } catch (_) {
            return null;
          }
        }).whereType<VehicleMaintenanceModel>(),
      );
    if (_seedEnabled && qs.docs.isEmpty && !_seededMaintenance) {
      _seededMaintenance = true;
      _seedCollection(
        'vehicle_maintenance',
        seedMaintenanceLogs.map((c) => c.toMap()).toList(),
      );
    }
    _markLoaded();
  }

  /// Erreur du fallback par nom : ignorée (best-effort, voir [load]).
  void _ignoreFallbackError(Object error) {}

  /// Snapshots du fallback par `agenceName` (uniquement quand le backoffice
  /// est scopé). Ne marque pas le chargement initial (le listener par id
  /// s'en charge).
  void _onRegistrationsByName(QuerySnapshot<Map<String, dynamic>> qs) {
    _regsByName
      ..clear()
      ..addEntries(
        qs.docs.map(
          (d) => MapEntry(d.id, RegistrationModel.fromMap(d.data())),
        ),
      );
    _rebuildRegistrations();
  }

  /// Fusionne les candidatures vues par id et par nom (dédoublonnées par id)
  /// dans [registrations].
  void _rebuildRegistrations() {
    final merged = <String, RegistrationModel>{..._regsById, ..._regsByName};
    registrations
      ..clear()
      ..addAll(merged.values);
  }

  void _markLoaded() {
    if (_pending > 0) _pending--;
    if (_pending <= 0) {
      setLoading(false);
      final completer = _loadCompleter;
      if (completer != null && !completer.isCompleted) completer.complete();
    }
    notifyListeners();
  }

  final bool Function()? _isSignedOutOverride;

  /// Point d'entrée des erreurs de flux (exposé pour les tests).
  ///
  /// Après une déconnexion, le token est révoqué et les règles rejettent
  /// les listeners encore actifs (permission-denied…) : c'est attendu — la
  /// console est en train de se démonter, on n'affiche pas de bannière.
  @visibleForTesting
  void handleStreamError(Object error) {
    setLoading(false);
    if (!_isSignedOut()) {
      setErrorValue(_friendlyError(error));
    }
    final completer = _loadCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    notifyListeners();
  }

  /// Vrai quand aucune session active n'existe (déconnecté).
  ///
  /// Le cas « logout → permission-denied attendu » reste testable via
  /// [_isSignedOutOverride] ; en production la valeur par défaut affiche
  /// les erreurs (défense en profondeur : ne jamais masquer un vrai
  /// problème d'accès sous prétexte d'un démontage).
  bool _isSignedOut() {
    final override = _isSignedOutOverride;
    if (override != null) return override();
    return false;
  }

  Future<void> _seedCollection(
    String collection,
    List<Map<String, dynamic>> docs,
  ) async {
    try {
      final batch = _db.batch();
      for (final doc in docs) {
        batch.set(_db.collection(collection).doc(doc['id'] as String), doc);
      }
      await batch.commit();
    } catch (error) {
      setErrorValue(_friendlyError(error));
      notifyListeners();
    }
  }

  /// Pré-approuve (liste blanche `collectors`) les collecteurs seedés actifs,
  /// pour que le flow d'auto-inscription leur attribue le rôle 'collector'.
  Future<void> _seedCollectorWhitelist() async {
    try {
      final batch = _db.batch();
      for (final c in seedCollecteurs.where((c) => _isActive(c.status))) {
        final phone = _canonicalPhone(c.phone);
        if (phone.isNotEmpty) {
          batch.set(_db.collection('collectors').doc(phone), {
            'phone': phone,
            'name': c.name,
          });
        }
      }
      await batch.commit();
    } catch (error) {
      setErrorValue(_friendlyError(error));
      notifyListeners();
    }
  }

  /// Le seed est désactivé quand le backoffice est scopé à une agence
  /// (les données viennent de l'entreprise, pas du seed).
  bool get _seedEnabled => seedIfEmpty && !_isScoped;

  // --- Issues ---

  @override
  Future<void> assignIssue(IssueModel issue, CollecteurModel collecteur) async {
    final phone = AuthService.canonicalPhone(collecteur.phone);
    try {
      await _db.collection('issues').doc(issue.id).update({
        'status': 'assigned',
        'assignedCollecteurId': collecteur.id,
        'assignedCollectorName': collecteur.name,
        'assignedCollectorPhone': phone,
        'assignedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = issues.indexWhere((i) => i.id == issue.id);
    if (index != -1) {
      issues[index] = issue.copyWith(
        status: 'assigned',
        assignedCollecteurId: collecteur.id,
        assignedCollectorName: collecteur.name,
        assignedCollectorPhone: phone,
      );
    }
    notifyListeners();
    // The server notifies the collector and the client (best-effort).
    await (_notifyIssueAssigned ??
        (id) => NotificationService(db: _db)
            .notifyIssueEvent(IssueEvent.assigned, issueId: id))(issue.id);
  }

  @override
  Future<void> resolveIssue(IssueModel issue) async {
    try {
      await _db.collection('issues').doc(issue.id).update({
        'status': 'resolved',
      });
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = issues.indexWhere((i) => i.id == issue.id);
    if (index != -1) {
      issues[index] = issue.copyWith(status: 'resolved');
    }
    notifyListeners();
  }

  // --- Assignments ---

  @override
  Future<void> addAssignment({
    required String collecteurId,
    required String collecteurName,
    required String zoneId,
    required String zoneName,
    required String startTime,
    required String endTime,
    required String date,
    String status = 'Active',
  }) async {
    final finalAgenceId = agenceId;
    final finalSocieteId = societeId;
    final id = nextId();
    final assignment = AssignmentModel(
      id: id,
      collecteurId: collecteurId,
      collecteurName: collecteurName,
      zoneId: zoneId,
      zoneName: zoneName,
      startTime: startTime,
      endTime: endTime,
      date: date,
      status: status,
      agenceId: finalAgenceId,
      societeId: finalSocieteId,
    );
    try {
      await _db.collection('assignments').doc(id).set(assignment.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
  }

  @override
  Future<void> updateAssignment(AssignmentModel updated) async {
    try {
      await _db.collection('assignments').doc(updated.id).update(updated.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = assignments.indexWhere((a) => a.id == updated.id);
    if (index != -1) assignments[index] = updated;
    notifyListeners();
  }

  @override
  Future<void> deleteAssignment(String id) async {
    try {
      await _db.collection('assignments').doc(id).delete();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    assignments.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  // --- Zones ---

  @override
  Future<void> addZone({
    required String name,
    required List<String> collectionDays,
    required String standardPickupTime,
  }) async {
    final id = nextId();
    final zone = ZoneModel(
      id: id,
      name: name,
      collectionDays: collectionDays,
      standardPickupTime: standardPickupTime,
      agenceId: agenceId,
      societeId: societeId,
    );
    try {
      await _db.collection('zones').doc(id).set(zone.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
  }

  @override
  Future<void> updateZone(ZoneModel updated) async {
    try {
      await _db.collection('zones').doc(updated.id).update(updated.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = zones.indexWhere((z) => z.id == updated.id);
    if (index != -1) zones[index] = updated;
    notifyListeners();
  }

  @override
  Future<void> deleteZone(String id) async {
    try {
      await _db.collection('zones').doc(id).delete();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    zones.removeWhere((z) => z.id == id);
    notifyListeners();
  }

  // --- Vehicles ---

  @override
  Future<void> addVehicle({
    required String plateNumber,
    required String type,
    String brand = '',
    String model = '',
    int year = 0,
    String status = 'Active',
    String assignedCollecteurId = '',
    String assignedCollecteurName = '',
    int mileage = 0,
    String lastMaintenanceDate = '',
    String notes = '',
  }) async {
    final id = nextId();
    final vehicle = VehicleModel(
      id: id,
      plateNumber: plateNumber,
      type: type,
      brand: brand,
      model: model,
      year: year,
      status: status,
      agenceId: agenceId,
      societeId: societeId,
      assignedCollecteurId: assignedCollecteurId,
      assignedCollecteurName: assignedCollecteurName,
      mileage: mileage,
      lastMaintenanceDate: lastMaintenanceDate,
      notes: notes,
    );
    try {
      await _db.collection('vehicles').doc(id).set(vehicle.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
  }

  @override
  Future<void> updateVehicle(VehicleModel updated) async {
    try {
      await _db.collection('vehicles').doc(updated.id).update(updated.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = vehicles.indexWhere((v) => v.id == updated.id);
    if (index != -1) vehicles[index] = updated;
    notifyListeners();
  }

  @override
  Future<void> deleteVehicle(String id) async {
    try {
      await _db.collection('vehicles').doc(id).delete();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    vehicles.removeWhere((v) => v.id == id);
    notifyListeners();
  }

  // --- Vehicle Maintenance ---

  @override
  Future<void> addMaintenanceLog({
    required String vehicleId,
    required String vehiclePlate,
    required String type,
    String description = '',
    int mileageAtService = 0,
    required String serviceDate,
    int cost = 0,
    String mechanicName = '',
    String nextServiceDate = '',
    int nextServiceMileage = 0,
    String status = 'Completed',
  }) async {
    final id = nextId();
    final log = VehicleMaintenanceModel(
      id: id,
      vehicleId: vehicleId,
      vehiclePlate: vehiclePlate,
      type: type,
      description: description,
      mileageAtService: mileageAtService,
      serviceDate: serviceDate,
      cost: cost,
      mechanicName: mechanicName,
      nextServiceDate: nextServiceDate,
      nextServiceMileage: nextServiceMileage,
      status: status,
      agenceId: agenceId,
      societeId: societeId,
    );
    try {
      await _db.collection('vehicle_maintenance').doc(id).set(log.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    // Update vehicle's last maintenance date.
    final vi = vehicles.indexWhere((v) => v.id == vehicleId);
    if (vi != -1) {
      vehicles[vi] = vehicles[vi].copyWith(
        lastMaintenanceDate: serviceDate,
        mileage: mileageAtService > vehicles[vi].mileage ? mileageAtService : vehicles[vi].mileage,
      );
    }
  }

  @override
  Future<void> updateMaintenanceLog(VehicleMaintenanceModel updated) async {
    try {
      await _db.collection('vehicle_maintenance').doc(updated.id).update(updated.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = maintenanceLogs.indexWhere((m) => m.id == updated.id);
    if (index != -1) maintenanceLogs[index] = updated;
    notifyListeners();
  }

  @override
  Future<void> deleteMaintenanceLog(String id) async {
    try {
      await _db.collection('vehicle_maintenance').doc(id).delete();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    maintenanceLogs.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  // --- Candidatures (pré-inscriptions clients) ---

  @override
  Future<void> approveRegistration(
    RegistrationModel reg, {
    required String collecteurId,
  }) async {
    final clientId = nextId();
    final client = ClientModel(
      id: clientId,
      name: reg.fullName,
      phone: reg.phone,
      zone: reg.zone,
      // Approval = access only: the plan starts when the client pays
      // (the payment function sets the plan and the subscription date).
      plan: 'None',
      status: 'Active',
      agenceId: reg.agenceId,
      societeId: reg.societeId,
      collecteurId: collecteurId,
      // Photo choisie à la pré-inscription (data URL base64) : reportée
      // telle quelle sur le compte client.
      photoUrl: reg.photoUrl,
      // Point de collecte GPS choisi à la pré-inscription : le collecteur
      // voit le client sur sa tournée et le client sur la carte.
      latitude: reg.latitude,
      longitude: reg.longitude,
      adresse: reg.zone,
      quartier: reg.zone,
    );
    final canonical = _canonicalPhone(reg.phone);
    // Garde anti-doublon : une candidature déjà traitée (ou supprimée) ne
    // doit jamais créer un second client. Vérifiée AVANT l'écriture —
    // l'approbation est atomique ou rien.
    // Parallelise les lectures Firestore (candidature + compte existant).
    final regDocFuture = _db.collection('registrations').doc(reg.id).get();
    final userDocFuture = canonical.isEmpty
        ? Future.value(null)
        : _db.collection('users').doc(canonical).get();
    final regDocResults = await Future.wait([regDocFuture, userDocFuture]);
    final regDoc = regDocResults[0] as DocumentSnapshot<Map<String, dynamic>>;
    final userDoc = regDocResults[1];

    if (!regDoc.exists) {
      throw _SyncError('This application no longer exists.');
    }
    if (regDoc.data()?['status'] != 'pending') {
      throw _SyncError('This application has already been reviewed.');
    }

    // The applicant's Auth account was created at pre-registration (the
    // password never leaves Firebase Auth): reuse its uid. Legacy
    // applications (before the Auth migration) still carry the chosen
    // password: the account is created from it.
    var uid = '';
    var createdEmail = '';
    if (userDoc != null && userDoc.exists) {
      uid = userDoc.data()?['uid'] as String? ?? '';
    } else if (reg.password.isNotEmpty && canonical.isNotEmpty) {
      final email = AuthService.emailFor(canonical);
      try {
        uid = await _backend.ensureAccount(email: email, password: reg.password);
        createdEmail = email;
      } on AuthBackendException catch (e) {
        throw _SyncError(
          e.message.isEmpty ? 'Unable to create the login account.' : e.message,
        );
      }
    }

    try {
      final batch = _db.batch();
      // 1. Le client (plus aucun mot de passe en clair : il vit dans Auth).
      batch.set(_db.collection('clients').doc(clientId), client.toMap());
      // 2. Compte de connexion : le rôle passe de pending_client à client
      //    (le client peut enfin accéder à son dashboard).
      if (canonical.isNotEmpty) {
        batch.set(_db.collection('users').doc(canonical), {
          'phoneNumber': canonical,
          'fullName': reg.fullName,
          'role': 'client',
          'uid': uid,
          'registrationStatus': 'approved',
          // Access only — the subscription is activated by the client's
          // payment (server-side), never by the approval.
          'subscription_plan': '',
          'isSubscribed': false,
          'agenceId': reg.agenceId,
          'agenceName': reg.agenceName,
          'societeId': reg.societeId,
          'collecteurId': collecteurId,
          // Point de collecte : repris sur le compte de connexion pour que
          // le profil et l'écran « Collection Point » affichent un point
          // même avant toute mise à jour ultérieure.
          if (reg.latitude != null) 'latitude': reg.latitude,
          if (reg.longitude != null) 'longitude': reg.longitude,
          // Marqueur : compte créé/géré par le backoffice admin.
          'consoleCreated': true,
          // Merge: keeps what the applicant's device already saved (push
          // token, security PIN…).
        }, SetOptions(merge: true));
        if (uid.isNotEmpty) {
          batch.set(_db.collection('auth_profiles').doc(uid), {
            'uid': uid,
            'phone': canonical,
            'role': 'client',
            'status': 'approved',
            'societeId': reg.societeId,
            'agenceId': reg.agenceId,
          });
        }
      }
      // 3. La candidature passe à 'approved' avec le collecteur assigné.
      batch.update(_db.collection('registrations').doc(reg.id), {
        'status': 'approved',
        'collecteurId': collecteurId,
      });
      // 4. Le client est notifié dans l'app (cloche du dashboard) : la
      //    décision est visible dès sa prochaine ouverture de l'app.
      if (canonical.isNotEmpty) {
        batch.set(
          _db.collection('notifications').doc('notif${reg.id}'),
          _notificationMap(
            regId: reg.id,
            phone: canonical,
            type: 'approved',
            title: 'Application approved',
            message: 'Your application was approved. Choose and pay your '
                'plan in the app to start your pickups.',
          ),
        );
      }
      // The legacy password is consumed: it never stays in Firestore.
      if (reg.password.isNotEmpty) {
        batch.update(_db.collection('registrations').doc(reg.id), {
          'password': FieldValue.delete(),
        });
      }
      await batch.commit();
    } catch (error) {
      // Rollback : jamais de compte Auth orphelin si l'approbation échoue.
      await _deleteAuthQuietly(createdEmail);
      throw _SyncError(_friendlyError(error));
    }
    // Mise à jour locale optimiste (le snapshot confirmera).
    final index = registrations.indexWhere((r) => r.id == reg.id);
    final updated = reg.copyWith(status: 'approved', collecteurId: collecteurId);
    if (index != -1) {
      registrations[index] = updated;
    } else {
      registrations.add(updated);
    }
    if (!clients.any((c) => c.id == clientId)) clients.add(client);
    notifyListeners();
  }

  @override
  Future<void> rejectRegistration(RegistrationModel reg) async {
    final canonical = _canonicalPhone(reg.phone);
    try {
      final batch = _db.batch();
      batch.update(_db.collection('registrations').doc(reg.id), {
        'status': 'rejected',
      });
      // Le client peut rester connecté : son compte n'est pas supprimé — il
      // verra le rejet sur son écran de suivi et pourra re-postuler. Le
      // statut est marqué sur le profil + auth_profiles (règles).
      if (canonical.isNotEmpty) {
        final userDoc = await _db.collection('users').doc(canonical).get();
        if (userDoc.exists) {
          batch.update(_db.collection('users').doc(canonical), {
            'registrationStatus': 'rejected',
          });
          final uid = userDoc.data()?['uid'] as String?;
          if (uid != null && uid.isNotEmpty) {
            batch.update(_db.collection('auth_profiles').doc(uid), {
              'status': 'rejected',
            });
          }
        }
      }
      // Notifie le client dans l'app (cloche du dashboard).
      if (canonical.isNotEmpty) {
        batch.set(
          _db.collection('notifications').doc('notif${reg.id}'),
          _notificationMap(
            regId: reg.id,
            phone: canonical,
            type: 'rejected',
            title: 'Application rejected',
            message: 'Your application was rejected. You can submit a new '
                'application from the app.',
          ),
        );
      }
      await batch.commit();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = registrations.indexWhere((r) => r.id == reg.id);
    final updated = reg.copyWith(status: 'rejected');
    if (index != -1) {
      registrations[index] = updated;
    } else {
      registrations.add(updated);
    }
    notifyListeners();
  }

  /// Doc de notification pour une décision de candidature. Id déterministe
  /// (`notif{regId}`) : une décision = une notification, jamais de doublon.
  Map<String, dynamic> _notificationMap({
    required String regId,
    required String phone,
    required String type,
    required String title,
    required String message,
  }) {
    final now = DateTime.now();
    final iso =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return {
      'id': 'notif$regId',
      'phone': phone,
      'type': type,
      'title': title,
      'message': message,
      'read': false,
      'createdAt': iso,
    };
  }

  /// Réassigne le collecteur d'un client — atomiquement :
  ///   1. `clients/{id}` porte le nouveau `collecteurId` ;
  ///   2. le compte de connexion `users/{téléphone}` est mis à jour (l'app
  ///      client connaît son nouveau collecteur) ;
  ///   3. les collectes à venir du client (Scheduled / Missed) portant
  ///      l'ancien collecteur basculent vers le nouveau — l'historique des
  ///      collectes effectuées ne change pas.
  @override
  Future<void> reassignCollecteur({
    required String clientId,
    required String collecteurId,
  }) async {
    ClientModel? client;
    for (final c in clients) {
      if (c.id == clientId) {
        client = c;
        break;
      }
    }
    if (client == null) return;
    if (client.collecteurId == collecteurId) return;

    final oldName = collecteurNameFor(collecteurs, client.collecteurId);
    final newName = collecteurNameFor(collecteurs, collecteurId);
    final canonical = _canonicalPhone(client.phone);

    try {
      final batch = _db.batch();
      // 1. Le client porte son nouveau collecteur (merge : on ne touche qu'à
      //    ce champ, même si le doc a été modifié hors console).
      batch.set(
        _db.collection('clients').doc(clientId),
        {'collecteurId': collecteurId},
        SetOptions(merge: true),
      );
      // 2 & 3. Parallélise les lectures Firestore (login + collectes).
      final loginFuture = canonical.isNotEmpty
          ? _db.collection('users').doc(canonical).get()
          : Future.value(null);
      Query<Map<String, dynamic>> collectesOfClient = _db
          .collection('collectes')
          .where('client', isEqualTo: client.name);
      if (_isScoped) {
        // The rules only allow this agency's collectes.
        collectesOfClient =
            collectesOfClient.where('agenceId', isEqualTo: agenceId);
      }
      final collectesFuture = (newName.isNotEmpty && oldName.isNotEmpty)
          ? collectesOfClient.get()
          : Future.value(null);
      final parallelResults =
          await Future.wait([loginFuture, collectesFuture]);
      final login = parallelResults[0]
          as DocumentSnapshot<Map<String, dynamic>>?;
      final upcoming = parallelResults[1]
          as QuerySnapshot<Map<String, dynamic>>?;

      if (login != null && login.exists) {
        batch.update(login.reference, {'collecteurId': collecteurId});
      }
      if (upcoming != null) {
        for (final doc in upcoming.docs) {
          final data = doc.data();
          final status = data['status'] as String? ?? '';
          final isDone = status == 'Completed' || status == 'Effectué';
          if (!isDone && data['collecteur'] == oldName) {
            batch.update(doc.reference, {'collecteur': newName});
          }
        }
      }
      await batch.commit();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }

    // Mise à jour locale optimiste (le snapshot confirmera).
    final idx = clients.indexWhere((c) => c.id == clientId);
    if (idx != -1) clients[idx] = client.copyWith(collecteurId: collecteurId);
    if (newName.isNotEmpty && oldName.isNotEmpty) {
      for (var i = 0; i < collectes.length; i++) {
        final col = collectes[i];
        final isDone = col.status == 'Completed' || col.status == 'Effectué';
        if (!isDone &&
            col.client == client.name &&
            col.collecteur == oldName) {
          collectes[i] = col.copyWith(collecteur: newName);
        }
      }
    }
    notifyListeners();
  }

  // --- Clients CRUD ---

  @override
  Future<void> addClient({
    required String name,
    required String phone,
    required String zone,
    required String plan,
    required String status,
    bool paidInCash = false,
    String password = '',
    String agenceId = '',
    String societeId = '',
    String adresse = '',
    String quartier = '',
    double? latitude,
    double? longitude,
    String photoUrl = '',
    String housingType = '',
    List<String> collectionDays = const [],
    String pickupTime = '',
    String subscribedAt = '',
  }) async {
    final finalAgenceId = agenceId.isNotEmpty ? agenceId : this.agenceId;
    final finalSocieteId = societeId.isNotEmpty ? societeId : this.societeId;
    if (paidInCash && password.isEmpty) {
      throw _SyncError(
        'A cash subscription needs the client\'s login: set a password.',
      );
    }
    // The plan and subscription are only ever activated by a recorded
    // payment (server-side): here the client starts with access only.
    final model = ClientModel(
      id: nextId(),
      name: name,
      phone: phone,
      zone: zone,
      plan: 'None',
      status: status,
      agenceId: finalAgenceId,
      societeId: finalSocieteId,
      adresse: adresse,
      quartier: quartier,
      latitude: latitude,
      longitude: longitude,
      photoUrl: photoUrl,
      housingType: housingType,
      subscribedAt: subscribedAt,
    );
    await _saveWithLogin(
      collection: 'clients',
      id: model.id,
      entityMap: model.toMap(),
      phone: phone,
      fullName: name,
      role: 'client',
      password: password,
      active: _isActive(status),
      subscriptionPlan: '',
      isSubscribed: false,
      collecteurId: model.collecteurId,
      collectionDays: collectionDays,
      pickupTime: pickupTime,
    );
    // Upsert : le snapshot peut déjà avoir appliqué ce document.
    var saved = model;
    if (paidInCash && _isActive(status)) {
      await _recordCash(phone, plan, created: true);
      saved = model.copyWith(plan: plan, subscribedAt: backofficeTodayIso());
    }
    final index = clients.indexWhere((c) => c.id == model.id);
    if (index == -1) {
      clients.add(saved);
    } else {
      clients[index] = saved;
    }
    notifyListeners();
  }

  @override
  Future<void> updateClient(ClientModel updated, {
    String password = '',
    List<String> collectionDays = const [],
    String pickupTime = '',
    String cashPlan = '',
  }) async {
    ClientModel? old;
    for (final c in clients) {
      if (c.id == updated.id) {
        old = c;
        break;
      }
    }
    final active = _isActive(updated.status);
    // The plan is never edited here: it only changes with a recorded
    // payment ([cashPlan], or the client's own payment in the app).
    final kept = updated.copyWith(plan: old?.plan ?? updated.plan);
    // Mot de passe vide = inchangé (il ne vit que dans Firebase Auth).
    await _saveWithLogin(
      collection: 'clients',
      id: kept.id,
      entityMap: kept.toMap(),
      phone: kept.phone,
      fullName: kept.name,
      role: 'client',
      password: password,
      active: active,
      // A suspension switches the subscription off; nothing else touches it.
      subscriptionPlan: null,
      isSubscribed: active ? null : false,
      collecteurId: kept.collecteurId,
      collectionDays: collectionDays,
      pickupTime: pickupTime,
      oldPhone: old != null && old.phone != kept.phone ? old.phone : null,
    );
    var saved = kept;
    if (cashPlan.isNotEmpty && active) {
      await _recordCash(kept.phone, cashPlan, created: false);
      saved = kept.copyWith(plan: cashPlan);
    }
    final index = clients.indexWhere((c) => c.id == kept.id);
    if (index != -1) {
      clients[index] = saved;
    } else {
      clients.add(saved);
    }
    notifyListeners();
  }

  /// Records a subscription paid in cash at the agency (Cloud Function
  /// `recordCashPayment`: contract, subscription, paid invoice, cash
  /// transaction). Injectable in tests.
  Future<void> _recordCash(
    String phone,
    String plan, {
    required bool created,
  }) async {
    try {
      await (_recordCashPayment ?? _callRecordCashPayment)(phone, plan);
    } catch (error) {
      throw _SyncError(
        '${created ? 'Client saved, but the' : 'The'} cash payment could not '
        'be recorded: $error',
      );
    }
  }

  static Future<void> _callRecordCashPayment(String phone, String plan) =>
      FunctionsClient().post('recordCashPayment', {
        'phone': phone,
        'plan': plan.toLowerCase(),
      });

  @override
  Future<void> deleteClient(String id) async {
    ClientModel? existing;
    for (final c in clients) {
      if (c.id == id) {
        existing = c;
        break;
      }
    }
    var authEmail = '';
    try {
      final batch = _db.batch();
      batch.delete(_db.collection('clients').doc(id));
      authEmail = await _stageLoginDeletion(batch, existing?.phone);
      await batch.commit();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    await _deleteAuthQuietly(authEmail);
    clients.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Collecteurs CRUD ---

  @override
  Future<void> addCollecteur({
    required String name,
    required String phone,
    required String zone,
    required double rating,
    required String status,
    String password = '',
    String agenceId = '',
    String societeId = '',
    String cni = '',
    String photoUrl = '',
    String vehicle = '',
    int salary = 0,
    ZoneArea? zoneArea,
  }) async {
    final finalAgenceId = agenceId.isNotEmpty ? agenceId : this.agenceId;
    final finalSocieteId = societeId.isNotEmpty ? societeId : this.societeId;
    final model = CollecteurModel(
      id: nextId(),
      name: name,
      phone: phone,
      zone: zone,
      rating: rating,
      status: status,
      agenceId: finalAgenceId,
      societeId: finalSocieteId,
      cni: cni,
      photoUrl: photoUrl,
      vehicle: vehicle,
      salary: salary,
      zoneArea: zoneArea,
    );
    await _saveWithLogin(
      collection: 'collecteurs',
      id: model.id,
      entityMap: model.toMap(),
      phone: phone,
      fullName: name,
      role: 'collector',
      password: password,
      active: _isActive(status),
      whitelist: true,
      collecteurId: model.id,
    );
    // Upsert : le snapshot peut déjà avoir appliqué ce document.
    final index = collecteurs.indexWhere((c) => c.id == model.id);
    if (index == -1) {
      collecteurs.add(model);
    } else {
      collecteurs[index] = model;
    }
    notifyListeners();
  }

  @override
  Future<void> updateCollecteur(
    CollecteurModel updated, {
    String password = '',
  }) async {
    CollecteurModel? old;
    for (final c in collecteurs) {
      if (c.id == updated.id) {
        old = c;
        break;
      }
    }
    // Mot de passe vide = inchangé (il ne vit que dans Firebase Auth).
    await _saveWithLogin(
      collection: 'collecteurs',
      id: updated.id,
      entityMap: updated.toMap(),
      phone: updated.phone,
      fullName: updated.name,
      role: 'collector',
      password: password,
      active: _isActive(updated.status),
      whitelist: true,
      oldPhone: old != null && old.phone != updated.phone ? old.phone : null,
    );
    final index = collecteurs.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      collecteurs[index] = updated;
    } else {
      collecteurs.add(updated);
    }
    notifyListeners();
  }

  @override
  Future<void> deleteCollecteur(String id) async {
    CollecteurModel? existing;
    for (final c in collecteurs) {
      if (c.id == id) {
        existing = c;
        break;
      }
    }
    var authEmail = '';
    try {
      final batch = _db.batch();
      batch.delete(_db.collection('collecteurs').doc(id));
      authEmail = await _stageLoginDeletion(batch, existing?.phone);
      final phone = _canonicalPhone(existing?.phone ?? '');
      if (phone.isNotEmpty) {
        // Retire aussi l'approbation de la liste blanche des collecteurs.
        batch.delete(_db.collection('collectors').doc(phone));
      }
      await batch.commit();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    await _deleteAuthQuietly(authEmail);
    collecteurs.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Contrats CRUD (persistés dans Firestore) ---

  @override
  Future<void> addContrat({
    required String client,
    required String frequence,
    required int prix,
    required String status,
  }) async {
    final model = ContratModel(
      id: nextId(),
      client: client,
      frequence: frequence,
      prix: prix,
      status: status,
      agenceId: agenceId,
      societeId: societeId,
    );
    try {
      await _db.collection('contrats').doc(model.id).set(model.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    // Facture générée automatiquement pour le contrat (statut Pending :
    // le règlement passera par un paiement CamPay ou une validation
    // manuelle). Best-effort — un échec ne bloque pas le contrat.
    await _invoiceService.generateForContract(
      contractId: model.id,
      clientId: _clientPhoneForName(client),
      clientName: client,
      amount: prix,
      status: 'Pending',
      agenceId: agenceId,
      societeId: societeId,
      source: 'contrats',
    );
    final index = contrats.indexWhere((c) => c.id == model.id);
    if (index == -1) {
      contrats.add(model);
    } else {
      contrats[index] = model;
    }
    notifyListeners();
  }

  /// Téléphone canonique du client [name] (clé `users`) — permet de
  /// rattacher la facture générée au compte client pour le règlement.
  /// '' si introuvable (la facture reste rattachable par son nom).
  String _clientPhoneForName(String name) {
    for (final c in clients) {
      if (c.name == name) return c.phone;
    }
    return '';
  }

  @override
  Future<void> updateContrat(ContratModel updated) async {
    try {
      await _db
          .collection('contrats')
          .doc(updated.id)
          .update(updated.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = contrats.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      contrats[index] = updated;
    } else {
      contrats.add(updated);
    }
    notifyListeners();
  }

  @override
  Future<void> deleteContrat(String id) async {
    try {
      await _db.collection('contrats').doc(id).delete();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    contrats.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Collectes CRUD (persistées dans Firestore) ---

  @override
  Future<void> addCollecte({
    required String client,
    required String collecteur,
    required String date,
    required double poids,
    required String status,
  }) async {
    final model = CollecteModel(
      id: nextId(),
      client: client,
      collecteur: collecteur,
      date: date,
      poids: poids,
      status: status,
      agenceId: agenceId,
      societeId: societeId,
    );
    try {
      await _db.collection('collectes').doc(model.id).set(model.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = collectes.indexWhere((c) => c.id == model.id);
    if (index == -1) {
      collectes.add(model);
    } else {
      collectes[index] = model;
    }
    notifyListeners();
  }

  @override
  Future<void> updateCollecte(CollecteModel updated) async {
    try {
      await _db
          .collection('collectes')
          .doc(updated.id)
          .update(updated.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = collectes.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      collectes[index] = updated;
    } else {
      collectes.add(updated);
    }
    notifyListeners();
  }

  @override
  Future<void> deleteCollecte(String id) async {
    try {
      await _db.collection('collectes').doc(id).delete();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    collectes.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Factures CRUD (persistées dans Firestore) ---

  @override
  Future<void> addFacture({
    required String client,
    required int montant,
    required String echeance,
    required String status,
  }) async {
    final model = FactureModel(
      id: nextId(),
      client: client,
      montant: montant,
      echeance: echeance,
      status: status,
      agenceId: agenceId,
      societeId: societeId,
    );
    try {
      await _db.collection('factures').doc(model.id).set(model.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = factures.indexWhere((c) => c.id == model.id);
    if (index == -1) {
      factures.add(model);
    } else {
      factures[index] = model;
    }
    notifyListeners();
  }

  @override
  Future<void> updateFacture(FactureModel updated) async {
    try {
      await _db
          .collection('factures')
          .doc(updated.id)
          .update(updated.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = factures.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      factures[index] = updated;
    } else {
      factures.add(updated);
    }
    notifyListeners();
  }

  @override
  Future<void> deleteFacture(String id) async {
    try {
      await _db.collection('factures').doc(id).delete();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    factures.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Frequences CRUD (persistées dans Firestore) ---

  @override
  Future<void> addFrequence({
    required String libelle,
    required int jours,
  }) async {
    final model = FrequenceModel(id: nextId(), libelle: libelle, jours: jours);
    try {
      await _db.collection('frequences').doc(model.id).set(model.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = frequences.indexWhere((c) => c.id == model.id);
    if (index == -1) {
      frequences.add(model);
    } else {
      frequences[index] = model;
    }
    notifyListeners();
  }

  @override
  Future<void> updateFrequence(FrequenceModel updated) async {
    try {
      await _db
          .collection('frequences')
          .doc(updated.id)
          .update(updated.toMap());
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    final index = frequences.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      frequences[index] = updated;
    } else {
      frequences.add(updated);
    }
    notifyListeners();
  }

  @override
  Future<void> deleteFrequence(String id) async {
    try {
      await _db.collection('frequences').doc(id).delete();
    } catch (error) {
      throw _SyncError(_friendlyError(error));
    }
    frequences.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Comptes de connexion ---

  /// Écrit l'entité + synchronise son compte de connexion `users/{téléphone}`
  /// + `auth_profiles/{uid}` (et la liste blanche `collectors` pour les
  /// collecteurs) dans un seul batch, donc de façon atomique.
  ///
  /// Le mot de passe choisi par l'admin va UNIQUEMENT dans Firebase Auth, via
  /// la Cloud Function `manageAccount` (compte assuré AVANT le batch, `uid`
  /// stocké dans le doc `users`) — il n'est jamais écrit dans Firestore.
  /// Mot de passe vide = inchangé.
  ///
  /// - Statut inactif/suspendu → le profil de connexion est supprimé et le
  ///   compte Auth désactivé ; la réactivation le réactive (même uid).
  /// - Un numéro déjà utilisé par un compte réel (non créé par la console)
  ///   n'est jamais écrasé : une erreur est levée à la place.
  Future<void> _saveWithLogin({
    required String collection,
    required String id,
    required Map<String, dynamic> entityMap,
    required String phone,
    required String fullName,
    required String role,
    required String password,
    required bool active,
    String? subscriptionPlan,
    bool? isSubscribed,
    bool whitelist = false,
    String? oldPhone,
    String collecteurId = '',
    List<String> collectionDays = const [],
    String pickupTime = '',
  }) async {
    final canonical = _canonicalPhone(phone);
    final oldCanonical = oldPhone == null ? '' : _canonicalPhone(oldPhone);
    final loginRef = canonical.isEmpty
        ? null
        : _db.collection('users').doc(canonical);

    final existing = loginRef == null ? null : await loginRef.get();

    if (active && existing != null && existing.exists) {
      final isConsole = existing.data()?['consoleCreated'] == true;
      if (!isConsole) {
        throw _SyncError(
          'An account already exists with this number. Choose a different '
          'number.',
        );
      }
    }

    // Compte Firebase Auth, assuré AVANT le batch par la Cloud Function
    // `manageAccount` : création avec le mot de passe saisi, ou réactivation
    // du compte existant (nouveau mot de passe s'il en est saisi un). Sans
    // compte ni mot de passe → pas de compte de connexion. Le mot de passe
    // n'est jamais écrit dans Firestore.
    String authUid = '';
    String createdEmail = ''; // compte créé ici → détruit si le batch échoue
    // Téléphone changé → le compte Auth passe sur le nouveau numéro (même
    // uid, même mot de passe) avant d'être assuré ci-dessous.
    var movedUid = '';
    if (loginRef != null &&
        oldCanonical.isNotEmpty &&
        oldCanonical != canonical) {
      final oldDoc = await _db.collection('users').doc(oldCanonical).get();
      if (oldDoc.data()?['consoleCreated'] == true) {
        try {
          movedUid = await _backend.moveAccount(
                email: AuthService.emailFor(oldCanonical),
                newEmail: AuthService.emailFor(canonical),
              ) ??
              '';
        } on AuthBackendException catch (e) {
          throw _SyncError(
            e.code == 'email-already-in-use'
                ? 'An account already exists with this number. Choose a '
                    'different number.'
                : 'Unable to move the login account.',
          );
        }
      }
    }
    final keepsLogin =
        existing == null || !existing.exists ||
        existing.data()?['consoleCreated'] == true;
    if (loginRef != null && !active && password.isNotEmpty && keepsLogin) {
      // Créé (ou modifié) inactif avec un mot de passe : le compte est
      // préparé puis désactivé — l'activation n'exigera pas de le ressaisir.
      try {
        final email = AuthService.emailFor(canonical);
        await _backend.ensureAccount(email: email, password: password);
        await _backend.disableAccount(email: email);
      } on AuthBackendException catch (e) {
        throw _SyncError(
          e.message.isEmpty ? 'Unable to create the login account.' : e.message,
        );
      }
    }
    if (loginRef != null && active) {
      final existingUid =
          existing!.data()?['uid'] as String? ?? movedUid;
      final email = AuthService.emailFor(canonical);
      try {
        authUid = await _backend.ensureAccount(
          email: email,
          password: password,
        );
        if (existingUid.isEmpty && password.isNotEmpty) createdEmail = email;
      } on AuthBackendException catch (e) {
        if (e.code != 'password-required') {
          throw _SyncError(
            e.message.isEmpty ? 'Unable to update the login account.' : e.message,
          );
        }
      }
    }

    final batch = _db.batch();
    batch.set(_db.collection(collection).doc(id), entityMap);

    // Téléphone changé → retire l'ancien profil de connexion (s'il a été
    // créé par la console). Staged BEFORE the new profile: when the account
    // was moved, the uid is the same and its `auth_profiles` doc is
    // rewritten just below (in a batch, the last write wins).
    var oldAuthEmail = '';
    if (oldCanonical.isNotEmpty && oldCanonical != canonical) {
      final staged = await _stageLoginDeletion(batch, oldCanonical);
      // A moved account no longer exists under the old number.
      if (movedUid.isEmpty) oldAuthEmail = staged;
    }

    if (loginRef != null) {
      if (active) {
        if (authUid.isNotEmpty) {
          final loginData = <String, dynamic>{
            'phoneNumber': canonical,
            'fullName': fullName,
            'role': role,
            'uid': authUid,
            'subscription_plan': ?subscriptionPlan,
            'isSubscribed': ?isSubscribed,
            // Le collecteur du client est porté par son compte : l'app
            // client peut afficher / contacter le bon collecteur.
            'collecteurId': collecteurId,
            // Scope of the account: a collector's tour queries (and the
            // rules) are limited to their agency.
            'agenceId': entityMap['agenceId'] as String? ?? '',
            'societeId': entityMap['societeId'] as String? ?? '',
            // Marqueur : compte créé/géré par le backoffice admin — seul ce
            // type de compte peut être écrasé ou supprimé proprement.
            'consoleCreated': true,
          };
          // Clients created from the backoffice receive the manager's
          // selected collection_days so tournee_service shows them on the
          // collector dashboard immediately.
          if (role == 'client' && collectionDays.isNotEmpty) {
            loginData['collection_days'] = collectionDays;
          }
          if (role == 'client' && pickupTime.isNotEmpty) {
            loginData['pickup_time'] = pickupTime;
          }
          // Merge: an edit from the client card must never wipe what the
          // server / the device saved on the login profile (paid plan,
          // active contract, collection days, push token, PIN…).
          batch.set(loginRef, loginData, SetOptions(merge: true));
          batch.set(_db.collection('auth_profiles').doc(authUid), {
            'uid': authUid,
            'phone': canonical,
            'role': role,
            'status': 'active',
            'societeId': entityMap['societeId'] as String? ?? '',
            'agenceId': entityMap['agenceId'] as String? ?? '',
          });
        }
      } else if (existing!.exists &&
          existing.data()?['consoleCreated'] == true) {
        batch.delete(loginRef);
        final oldUid = existing.data()?['uid'] as String?;
        if (oldUid != null && oldUid.isNotEmpty) {
          batch.delete(_db.collection('auth_profiles').doc(oldUid));
        }
        // Suspension → le compte Auth est DÉSACTIVÉ (plus de login
        // possible) ; la réactivation le réactive sans nouveau mot de passe.
        try {
          await _backend.disableAccount(
            email: AuthService.emailFor(canonical),
          );
        } on AuthBackendException catch (e) {
          throw _SyncError(
            'Unable to suspend the login account: '
            '${e.message.isEmpty ? e.code : e.message}',
          );
        }
      }
    }

    // Pré-approbation des collecteurs actifs (auto-inscription → 'collector').
    if (whitelist) {
      if (active && canonical.isNotEmpty) {
        batch.set(_db.collection('collectors').doc(canonical), {
          'phone': canonical,
          'name': fullName,
        });
      } else if (canonical.isNotEmpty) {
        batch.delete(_db.collection('collectors').doc(canonical));
      }
      if (oldCanonical.isNotEmpty && oldCanonical != canonical) {
        batch.delete(_db.collection('collectors').doc(oldCanonical));
      }
    }

    try {
      await batch.commit();
    } catch (error) {
      // Rollback du compte Auth créé ici si le batch échoue.
      await _deleteAuthQuietly(createdEmail);
      throw _SyncError(_friendlyError(error));
    }
    await _deleteAuthQuietly(oldAuthEmail);
  }

  /// Supprime le compte de connexion d'un téléphone (profil `users` + profil
  /// de règles `auth_profiles`), uniquement s'il a été créé par le
  /// backoffice (jamais un compte client/collecteur réel). Renvoie l'email
  /// Auth à supprimer après le commit ('' si rien).
  Future<String> _stageLoginDeletion(WriteBatch batch, String? phone) async {
    final canonical = _canonicalPhone(phone ?? '');
    if (canonical.isEmpty) return '';
    final doc = await _db.collection('users').doc(canonical).get();
    if (!doc.exists || doc.data()?['consoleCreated'] != true) return '';
    batch.delete(doc.reference);
    final uid = doc.data()?['uid'] as String? ?? '';
    if (uid.isNotEmpty) {
      // Sans ça, le uid garderait son rôle (et ses accès) dans les règles.
      batch.delete(_db.collection('auth_profiles').doc(uid));
    }
    return AuthService.emailFor(canonical);
  }

  /// Supprime le compte Firebase Auth (best-effort, après le commit).
  Future<void> _deleteAuthQuietly(String email) async {
    if (email.isEmpty) return;
    try {
      await _backend.deleteAccount(email: email);
    } catch (_) {}
  }

  // --- Helpers ---

  /// Vrai pour les statuts « actif » anglais ET hérités français (les
  /// enregistrements Firestore créés avant le passage à l'anglais gardent
  /// leurs valeurs : 'Actif'). Sans ça, éditer un client legacy le
  /// considérerait inactif et supprimerait son compte de connexion.
  bool _isActive(String status) => status == 'Active' || status == 'Actif';

  /// Normalise un numéro de téléphone : sans espaces ni tirets, préfixe +237
  /// (gère aussi le « 237... » saisi sans le +).
  String _canonicalPhone(String phone) {
    final cleaned = phone.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) return '';
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('237')) return '+$cleaned';
    return '+237$cleaned';
  }

  String _friendlyError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
          return 'Service unavailable. Check your internet connection.';
        case 'permission-denied':
          // Les règles LOCALES (firestore.rules) sont ouvertes : si Firebase
          // refuse quand même, c'est que les règles DÉPLOYÉES sur le projet
          // sont périmées (ex. collection `registrations` ajoutée après le
          // dernier déploiement). Le correctif est `firebase deploy
          // --only firestore:rules`.
          return 'Access denied: the Firestore rules deployed on Firebase '
              'are out of date. Deploy the latest rules with: firebase '
              'deploy --only firestore:rules';
        default:
          return error.message ?? 'Firestore error.';
      }
    }
    return 'An error occurred. Please try again.';
  }

  void _cancelSubscriptions() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    super.dispose();
  }
}

/// Erreur métier de la synchro du compte de connexion (message affiché tel
/// quel par le toast du formulaire, sans préfixe « Exception: »).
class _SyncError implements Exception {
  _SyncError(this.message);

  final String message;

  @override
  String toString() => message;
}
