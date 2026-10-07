import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../models/agence_model.dart';
import '../../../models/platform_user_model.dart';
import '../../../models/societe_model.dart';
import '../../../services/auth_backend.dart';
import '../../backoffice/models.dart';
import '../../superadmin/data/login_account_sync.dart';
import 'company_store.dart';

/// Firestore-backed implementation of [CompanyStore] for the real company
/// console (General Administrator).
///
/// Les données sont scopées à l'entreprise ([societeId]) :
///   - `societes/{societeId}` (document unique)
///   - `agences` où `societeId == X`
///   - `utilisateurs` où `societeId == X`
///
/// La création / édition des utilisateurs (chefs d'agence) synchronise
/// automatiquement leur compte de connexion `users/{téléphone}` (rôle
/// `agency_manager`), via [LoginAccountSync].
class FirestoreCompanyStore extends CompanyStore {
  FirestoreCompanyStore({
    FirebaseFirestore? db,
    AuthBackend? backend,
    required super.societeId,
    this.seedIfEmpty = false,
    @visibleForTesting bool Function()? isSignedOut,
  }) : _isSignedOutOverride = isSignedOut,
       _db = db ?? FirebaseFirestore.instance,
       _backend = backend ?? FirebaseAuthBackend() {
    societes.clear();
    agences.clear();
    utilisateurs.clear();
    load();
  }

  final FirebaseFirestore _db;

  /// Backend Auth (création de comptes chef d'agence). Injectable en test.
  final AuthBackend _backend;

  final bool seedIfEmpty;
  final List<StreamSubscription<dynamic>> _subs = [];

  Completer<void>? _loadCompleter;
  int _pending = 0;

  /// Complète une fois le premier snapshot de chaque collection appliqué.
  Future<void> get initialLoad =>
      _loadCompleter?.future ?? Future<void>.value();

  @override
  String nextId() => 'c${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<void> load() async {
    _cancelSubscriptions();
    setLoading(true);
    setErrorValue(null);
    _pending = 4;
    _loadCompleter = Completer<void>();
    notifyListeners();

    _subs.add(
      _db
          .collection('societes')
          .doc(societeId)
          .snapshots()
          .listen(_onSociete, onError: handleStreamError),
    );
    _subs.add(
      _db
          .collection('agences')
          .where('societeId', isEqualTo: societeId)
          .snapshots()
          .listen(_onAgences, onError: handleStreamError),
    );
    _subs.add(
      _db
          .collection('utilisateurs')
          .where('societeId', isEqualTo: societeId)
          .snapshots()
          .listen(_onUtilisateurs, onError: handleStreamError),
    );
    // Clients abonnés de l'entreprise (graphique annuel de l'Overview).
    _subs.add(
      _db
          .collection('clients')
          .where('societeId', isEqualTo: societeId)
          .snapshots()
          .listen(_onClients, onError: handleStreamError),
    );

    await _loadCompleter!.future;
  }

  // --- Snapshot handlers ---

  void _onSociete(DocumentSnapshot<Map<String, dynamic>> doc) {
    societes.clear();
    if (doc.exists) {
      societes.add(SocieteModel.fromMap(doc.data()!));
    }
    _markLoaded();
  }

  void _onAgences(QuerySnapshot<Map<String, dynamic>> qs) {
    agences
      ..clear()
      ..addAll(qs.docs.map((d) => AgenceModel.fromMap(d.data())));
    if (seedIfEmpty && qs.docs.isEmpty && societeId.isNotEmpty) {
      // Pas de seed pour la console entreprise (les données viennent du
      // super admin).
    }
    _markLoaded();
  }

  void _onUtilisateurs(QuerySnapshot<Map<String, dynamic>> qs) {
    utilisateurs
      ..clear()
      ..addAll(qs.docs.map((d) => PlatformUserModel.fromMap(d.data())));
    if (seedIfEmpty && qs.docs.isEmpty && societeId.isNotEmpty) {}
    _markLoaded();
  }

  void _onClients(QuerySnapshot<Map<String, dynamic>> qs) {
    clients
      ..clear()
      ..addAll(qs.docs.map((d) => ClientModel.fromMap(d.data())));
    _markLoaded();
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

  bool _isSignedOut() {
    final override = _isSignedOutOverride;
    if (override != null) return override();
    return false;
  }

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

  // --- Agences CRUD ---

  @override
  Future<AgenceModel> addAgence({
    required String ville,
    String location = '',
    required String responsable,
    required String telephone,
    required String status,
  }) async {
    final model = AgenceModel(
      id: nextId(),
      societe: societeNom,
      societeId: societeId,
      ville: ville,
      location: location,
      responsable: responsable,
      telephone: telephone,
      status: status,
    );
    try {
      await _db.collection('agences').doc(model.id).set(model.toMap());
    } catch (error) {
      throw _friendlyError(error);
    }
    final index = agences.indexWhere((a) => a.id == model.id);
    if (index == -1) {
      agences.add(model);
    } else {
      agences[index] = model;
    }
    notifyListeners();
    return model;
  }

  @override
  Future<void> updateAgence(AgenceModel updated) async {
    try {
      await _db.collection('agences').doc(updated.id).set(updated.toMap());
    } catch (error) {
      throw _friendlyError(error);
    }
    final index = agences.indexWhere((a) => a.id == updated.id);
    if (index != -1) agences[index] = updated;
    notifyListeners();
  }

  @override
  Future<void> deleteAgence(String id) async {
    try {
      await _db.collection('agences').doc(id).delete();
    } catch (error) {
      throw _friendlyError(error);
    }
    agences.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  // --- Utilisateurs (chefs d'agence) CRUD ---

  @override
  Future<void> addUtilisateur({
    required String nom,
    required String telephone,
    required String role,
    required String agence,
    String agenceId = '',
    required String status,
    required String password,
  }) async {
    final model = PlatformUserModel(
      id: nextId(),
      nom: nom,
      telephone: telephone,
      role: role,
      agence: agence,
      societeId: societeId,
      agenceId: agenceId,
      status: status,
      password: password,
    );
    LoginAccountSync.requirePhone(model);
    await LoginAccountSync.preflight(_db, model);
    // Compte Firebase Auth créé AVANT le batch (le `uid` est écrit dans le
    // doc `users`) ; en cas d'échec du batch, le compte est détruit.
    final authUid = await LoginAccountSync.ensureAuthAccount(_backend, model);
    try {
      final batch = _db.batch();
      batch.set(_db.collection('utilisateurs').doc(model.id), model.toMap());
      await LoginAccountSync.stage(batch, _db, model, uid: authUid);
      await batch.commit();
    } catch (error) {
      // Rollback du compte Auth (jamais d'orphelin côté Firebase Auth).
      if (authUid.isNotEmpty) {
        await LoginAccountSync.deleteAuthAccount(_backend, model);
      }
      if (error is! FirebaseException) rethrow;
      throw _friendlyError(error);
    }
    // Kept as persisted (the typed password is not held in memory).
    final saved = PlatformUserModel.fromMap(model.toMap());
    final index = utilisateurs.indexWhere((u) => u.id == model.id);
    if (index == -1) {
      utilisateurs.add(saved);
    } else {
      utilisateurs[index] = saved;
    }
    notifyListeners();
  }

  @override
  Future<void> updateUtilisateur(PlatformUserModel updated) async {
    LoginAccountSync.requirePhone(updated);
    String oldPhone = '';
    // Ancienne version (mot de passe actuel) pour la synchro Auth.
    final existingDoc =
        await _db.collection('utilisateurs').doc(updated.id).get();
    final oldModel = existingDoc.exists
        ? PlatformUserModel.fromMap(existingDoc.data()!)
        : updated;
    if (existingDoc.exists) {
      oldPhone = LoginAccountSync.canonicalPhone(oldModel.telephone);
    }
    try {
      await LoginAccountSync.preflight(_db, updated);
      // Suspension → le compte Auth est DÉSACTIVÉ (plus de login possible,
      // uid conservé pour la réactivation).
      final isNowSuspended =
          updated.status == 'Suspended' || updated.status == 'Suspendu';
      final wasActive =
          oldModel.status != 'Suspended' && oldModel.status != 'Suspendu';
      if (isNowSuspended && wasActive) {
        await LoginAccountSync.disableAuthAccount(_backend, oldModel);
      }
      // Numéro CHANGÉ → le compte Auth passe sur le nouveau numéro (même
      // uid, même mot de passe) ; l'ancien profil `users` est retiré par le
      // batch ci-dessous.
      final newPhone = LoginAccountSync.canonicalPhone(updated.telephone);
      if (oldPhone.isNotEmpty && oldPhone != newPhone) {
        await LoginAccountSync.moveAuthAccount(_backend, oldModel, newPhone);
      }
      // Compte assuré (créé, réactivé, mot de passe changé si saisi).
      final authUid =
          await LoginAccountSync.ensureAuthAccount(_backend, updated);
      final batch = _db.batch();
      batch.set(
        _db.collection('utilisateurs').doc(updated.id),
        updated.toMap(),
      );
      await LoginAccountSync.stage(
        batch,
        _db,
        updated,
        oldPhone: oldPhone,
        uid: authUid,
      );
      await batch.commit();
    } catch (error) {
      if (error is! FirebaseException) rethrow;
      throw _friendlyError(error);
    }
    final index = utilisateurs.indexWhere((u) => u.id == updated.id);
    if (index != -1) {
      utilisateurs[index] = PlatformUserModel.fromMap(updated.toMap());
    }
    notifyListeners();
  }

  @override
  Future<void> deleteUtilisateur(String id) async {
    var existing = const PlatformUserModel(
      id: '',
      nom: '',
      telephone: '',
      role: '',
      agence: '',
      status: '',
    );
    for (final u in utilisateurs) {
      if (u.id == id) {
        existing = u;
        break;
      }
    }
    // Suppression réelle du compte Auth (Cloud Function `manageAccount`).
    await LoginAccountSync.deleteAuthAccount(_backend, existing);
    try {
      final batch = _db.batch();
      batch.delete(_db.collection('utilisateurs').doc(id));
      await LoginAccountSync.stageDeleteLogin(
        batch,
        _db,
        existing.telephone,
      );
      await batch.commit();
    } catch (error) {
      if (error is! FirebaseException) rethrow;
      throw _friendlyError(error);
    }
    utilisateurs.removeWhere((u) => u.id == id);
    notifyListeners();
  }

  // --- Helpers ---

  String _friendlyError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
          return 'Service unavailable. Check your internet connection.';
        case 'permission-denied':
          return 'Access denied. Check the project Firestore rules.';
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
    _cancelSubscriptions();
    super.dispose();
  }
}