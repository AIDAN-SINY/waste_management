import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../models/agence_model.dart';
import '../../../models/platform_user_model.dart';
import '../../../models/societe_model.dart';
import '../../../services/auth_backend.dart';
import '../../backoffice/models.dart';
import 'login_account_sync.dart';
import 'platform_store.dart';
import 'seed_data.dart';

/// Firestore-backed implementation of [PlatformStore] for the real
/// super admin console.
///
/// - Collections: `societes`, `agences`, `utilisateurs` (document id = entity id).
/// - Data stays in sync in real time through snapshot listeners.
/// - When a collection is empty on first load, it is seeded with the
///   design's default entities (see [seedIfEmpty]) so the console is
///   never blank on a fresh project.
/// - On failure (network / rules), [error] is set so the console can show a
///   banner with a retry action; the mock data is never shown.
class FirestorePlatformStore extends PlatformStore {
  FirestorePlatformStore({
    FirebaseFirestore? db,
    AuthBackend? backend,
    this.seedIfEmpty = true,
    @visibleForTesting bool Function()? isSignedOut,
  }) : _isSignedOutOverride = isSignedOut,
       _db = db ?? FirebaseFirestore.instance,
       _backend = backend ?? FirebaseAuthBackend() {
    // Never flash the design's mock data in the real console.
    societes.clear();
    agences.clear();
    utilisateurs.clear();
    clients.clear();
    collecteurs.clear();
    load();
  }

  final FirebaseFirestore _db;

  /// Backend Auth (création de comptes console). Injectable par les tests.
  final AuthBackend _backend;

  /// When true, an empty collection is populated with [seedSocietes] /
  /// [seedAgences] / [seedUtilisateurs] on first load.
  final bool seedIfEmpty;

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs =
      [];

  Completer<void>? _loadCompleter;
  int _pending = 0;
  bool _seededSocietes = false;
  bool _seededAgences = false;
  bool _seededUtilisateurs = false;

  /// Completes once the first snapshot of every collection has been applied
  /// (or an error occurred). Used by tests to await the initial load.
  Future<void> get initialLoad =>
      _loadCompleter?.future ?? Future<void>.value();

  @override
  String nextId() => 'f${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<void> load() async {
    _cancelSubscriptions();
    setLoading(true);
    setErrorValue(null);
    _pending = 5;
    _seededSocietes = false;
    _seededAgences = false;
    _seededUtilisateurs = false;
    _loadCompleter = Completer<void>();
    notifyListeners();

    _subs.add(
      _db.collection('societes').snapshots().listen(
            _onSocietes,
            onError: handleStreamError,
          ),
    );
    _subs.add(
      _db.collection('agences').snapshots().listen(
            _onAgences,
            onError: handleStreamError,
          ),
    );
    _subs.add(
      _db.collection('utilisateurs').snapshots().listen(
            _onUtilisateurs,
            onError: handleStreamError,
          ),
    );
    // Phase 3 : la console super admin voit TOUT (aucun filtre) — les
    // clients/collecteurs alimentent la fiche détail d'une agence (stats,
    // tables). Le seed de ces collections reste la propriété du backoffice.
    _subs.add(
      _db.collection('clients').snapshots().listen(
            _onClients,
            onError: handleStreamError,
          ),
    );
    _subs.add(
      _db.collection('collecteurs').snapshots().listen(
            _onCollecteurs,
            onError: handleStreamError,
          ),
    );

    await _loadCompleter!.future;
  }

  // --- Snapshot handlers ---

  void _onSocietes(QuerySnapshot<Map<String, dynamic>> qs) {
    societes
      ..clear()
      ..addAll(qs.docs.map((d) => SocieteModel.fromMap(d.data())));
    if (seedIfEmpty && qs.docs.isEmpty && !_seededSocietes) {
      _seededSocietes = true;
      _seedCollection(
        'societes',
        seedSocietes.map((s) => s.toMap()).toList(),
      );
    }
    _markLoaded();
  }

  void _onAgences(QuerySnapshot<Map<String, dynamic>> qs) {
    agences
      ..clear()
      ..addAll(qs.docs.map((d) => AgenceModel.fromMap(d.data())));
    if (seedIfEmpty && qs.docs.isEmpty && !_seededAgences) {
      _seededAgences = true;
      _seedCollection('agences', seedAgences.map((a) => a.toMap()).toList());
    }
    _markLoaded();
  }

  void _onUtilisateurs(QuerySnapshot<Map<String, dynamic>> qs) {
    utilisateurs
      ..clear()
      ..addAll(qs.docs.map((d) => PlatformUserModel.fromMap(d.data())));
    if (seedIfEmpty && qs.docs.isEmpty && !_seededUtilisateurs) {
      _seededUtilisateurs = true;
      _seedCollection(
        'utilisateurs',
        seedUtilisateurs.map((u) => u.toMap()).toList(),
      );
    }
    _markLoaded();
  }

  void _onClients(QuerySnapshot<Map<String, dynamic>> qs) {
    clients
      ..clear()
      ..addAll(qs.docs.map((d) => ClientModel.fromMap(d.data())));
    _markLoaded();
  }

  void _onCollecteurs(QuerySnapshot<Map<String, dynamic>> qs) {
    collecteurs
      ..clear()
      ..addAll(qs.docs.map((d) => CollecteurModel.fromMap(d.data())));
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

  // --- Sociétés CRUD ---

  @override
  Future<void> addSociete({
    required String raisonSociale,
    required String adresse,
    required String telephone,
    required String email,
    required String status,
  }) async {
    final model = SocieteModel(
      id: nextId(),
      raisonSociale: raisonSociale,
      adresse: adresse,
      telephone: telephone,
      email: email,
      status: status,
    );
    try {
      await _db.collection('societes').doc(model.id).set(model.toMap());
    } catch (error) {
      throw _friendlyError(error);
    }
    // Upsert: the snapshot listener may already have applied this document.
    final index = societes.indexWhere((s) => s.id == model.id);
    if (index == -1) {
      societes.add(model);
    } else {
      societes[index] = model;
    }
    notifyListeners();
  }

  @override
  Future<void> updateSociete(SocieteModel updated) async {
    String? oldName;
    for (final s in societes) {
      if (s.id == updated.id) {
        oldName = s.raisonSociale;
        break;
      }
    }
    try {
      await _db.collection('societes').doc(updated.id).set(updated.toMap());
      // Cascade the rename to agences referencing the old name (agences
      // store the société by name, not by id).
      if (oldName != null && oldName != updated.raisonSociale) {
        final agenceDocs = await _db
            .collection('agences')
            .where('societe', isEqualTo: oldName)
            .get();
        if (agenceDocs.docs.isNotEmpty) {
          final batch = _db.batch();
          for (final doc in agenceDocs.docs) {
            batch.update(doc.reference, {'societe': updated.raisonSociale});
          }
          await batch.commit();
        }
      }
    } catch (error) {
      throw _friendlyError(error);
    }
    final index = societes.indexWhere((s) => s.id == updated.id);
    if (index != -1) societes[index] = updated;
    // Keep the local list in sync with the rename (snapshots will confirm).
    if (oldName != null && oldName != updated.raisonSociale) {
      for (var i = 0; i < agences.length; i++) {
        if (agences[i].societe == oldName) {
          agences[i] = agences[i].copyWith(societe: updated.raisonSociale);
        }
      }
    }
    notifyListeners();
  }

  @override
  Future<void> deleteSociete(String id) async {
    try {
      await _db.collection('societes').doc(id).delete();
    } catch (error) {
      throw _friendlyError(error);
    }
    societes.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  // --- Agences CRUD ---

  @override
  Future<void> addAgence({
    required String societe,
    String societeId = '',
    required String ville,
    required String responsable,
    required String telephone,
    required String status,
  }) async {
    final model = AgenceModel(
      id: nextId(),
      societe: societe,
      societeId: societeId,
      ville: ville,
      responsable: responsable,
      telephone: telephone,
      status: status,
    );
    try {
      await _db.collection('agences').doc(model.id).set(model.toMap());
    } catch (error) {
      throw _friendlyError(error);
    }
    // Upsert: the snapshot listener may already have applied this document.
    final index = agences.indexWhere((a) => a.id == model.id);
    if (index == -1) {
      agences.add(model);
    } else {
      agences[index] = model;
    }
    notifyListeners();
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

  // --- Utilisateurs CRUD ---

  @override
  Future<void> addUtilisateur({
    required String nom,
    required String telephone,
    required String role,
    required String agence,
    String societeId = '',
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
    // Validé AVANT l'écriture : jamais d'utilisateur « fantôme » qui
    // apparaîtrait dans la liste sans compte de connexion.
    _requireLoginPhone(model);
    await _preflightLogin(model);
    // Compte Firebase Auth créé AVANT le batch (le `uid` est écrit dans le
    // doc `users`) ; en cas d'échec du batch, le compte est détruit.
    final authUid = await LoginAccountSync.ensureAuthAccount(_backend, model);
    try {
      // Un seul batch atomique : soit l'utilisateur ET son compte de
      // connexion sont écrits, soit rien (jamais un utilisateur dans
      // `utilisateurs` sans compte dans `users`).
      final batch = _db.batch();
      batch.set(_db.collection('utilisateurs').doc(model.id), model.toMap());
      await _stageLoginSync(batch, model, uid: authUid);
      await batch.commit();
    } catch (error) {
      // Rollback du compte Auth (jamais d'orphelin côté Firebase Auth).
      if (authUid.isNotEmpty) {
        await LoginAccountSync.deleteAuthAccount(_backend, model);
      }
      if (error is! FirebaseException) rethrow;
      throw _friendlyError(error);
    }
    // Upsert: the snapshot listener may already have applied this document.
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
    _requireLoginPhone(updated);
    // Ancienne version (mot de passe actuel + numéro) pour la synchro Auth.
    final existingDoc =
        await _db.collection('utilisateurs').doc(updated.id).get();
    final oldModel = existingDoc.exists
        ? PlatformUserModel.fromMap(existingDoc.data()!)
        : updated;
    final oldPhone = _canonicalPhone(oldModel.telephone);
    try {
      await _preflightLogin(updated);
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
      final newPhone = _canonicalPhone(updated.telephone);
      if (oldPhone.isNotEmpty && oldPhone != newPhone) {
        await LoginAccountSync.moveAuthAccount(_backend, oldModel, newPhone);
      }
      // Compte assuré (créé, réactivé, mot de passe changé si saisi).
      final authUid =
          await LoginAccountSync.ensureAuthAccount(_backend, updated);
      // Batch atomique : utilisateur + synchro du compte de connexion +
      // suppression de l'ancien compte en cas de changement de numéro.
      final batch = _db.batch();
      batch.set(
        _db.collection('utilisateurs').doc(updated.id),
        updated.toMap(),
      );
      await _stageLoginSync(batch, updated, oldPhone: oldPhone, uid: authUid);
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
    // Supprime aussi le compte de connexion correspondant dans `users`.
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
      // Ne supprime le compte de connexion que s'il a été créé par la
      // console (marqueur consoleCreated) — jamais un compte client réel.
      final phone = _canonicalPhone(existing.telephone);
      if (phone.isNotEmpty) {
        final loginDoc = await _db.collection('users').doc(phone).get();
        if (loginDoc.exists && loginDoc.data()?['consoleCreated'] == true) {
          batch.delete(loginDoc.reference);
          final uid = loginDoc.data()?['uid'] as String?;
          if (uid != null && uid.isNotEmpty) {
            batch.delete(_db.collection('auth_profiles').doc(uid));
          }
        }
      }
      await batch.commit();
    } catch (error) {
      if (error is! FirebaseException) rethrow;
      throw _friendlyError(error);
    }
    utilisateurs.removeWhere((u) => u.id == id);
    notifyListeners();
  }

  /// Crée (ou met à jour) le compte de connexion dans la collection `users`
  /// pour un utilisateur console qui a un mot de passe. Sans mot de passe,
  /// aucun compte de connexion n'est créé (ex. les utilisateurs seedés).
  ///
  /// - Statut « Suspendu » → le compte de connexion est supprimé (plus de
  ///   login possible) tant que l'utilisateur n'est pas réactivé.
  /// - Un numéro déjà utilisé par un compte client/collecteur réel n'est
  ///   jamais écrasé : une erreur est levée à la place.
  /// Garde : un utilisateur avec un mot de passe DOIT avoir un numéro,
  /// sinon le compte de connexion users/{phone} ne peut pas exister et il ne
  /// pourrait jamais se connecter (symptôme : « le bouton charge puis
  /// s'arrête » au login). Levée avant toute écriture ET en défense dans
  /// [_syncLogin].
  void _requireLoginPhone(PlatformUserModel user) {
    if (user.wantsLogin && _canonicalPhone(user.telephone).isEmpty) {
      throw _SyncError(
        'A phone number is required to create the login account. Add a '
        'number to this user.',
      );
    }
  }

  /// Vérifie AVANT toute écriture que le numéro peut recevoir un compte de
  /// connexion console : ni compte client/collecteur réel, ni numéro déjà
  /// utilisé par un autre utilisateur console. Évite de créer un doc
  /// « fantôme » dans `utilisateurs` sans compte de connexion.
  Future<void> _preflightLogin(PlatformUserModel user) async {
    if (!user.wantsLogin) return;
    final phone = _canonicalPhone(user.telephone);
    if (phone.isEmpty) return;
    // Suspendu → pas de compte à créer (juste à supprimer) : rien à vérifier.
    if (user.status == 'Suspended' || user.status == 'Suspendu') return;
    await _assertLoginPhoneAvailable(
      _db.collection('users').doc(phone),
      user,
    );
  }

  /// Ajoute au batch [batch] la synchronisation du compte de connexion
  /// `users/{téléphone}` + `auth_profiles/{uid}` pour [user] (création,
  /// mise à jour, suspension ou suppression) — délègue à
  /// [LoginAccountSync.stage].
  ///
  /// [uid] : uid Auth créé via [_createOrReuseAuth] ('' si aucun compte).
  Future<void> _stageLoginSync(
    WriteBatch batch,
    PlatformUserModel user, {
    String oldPhone = '',
    String uid = '',
  }) {
    return LoginAccountSync.stage(
      batch,
      _db,
      user,
      oldPhone: oldPhone,
      uid: uid,
    );
  }

  /// Refuse d'écraser : (1) un compte client/collecteur réel (pas de
  /// marqueur console), (2) le compte de connexion d'un AUTRE utilisateur
  /// console (même numéro saisi deux fois). Réécrire le sien est permis
  /// (édition du même utilisateur, y compris docs hérités sans propriétaire).
  Future<void> _assertLoginPhoneAvailable(
    DocumentReference<Map<String, dynamic>> ref,
    PlatformUserModel user,
  ) async {
    final existing = await ref.get();
    if (!existing.exists) return;
    final data = existing.data()!;
    if (data['consoleCreated'] != true) {
      throw _SyncError(
        'A client account already exists with this number. Choose a '
        'different number.',
      );
    }
    final owner = data['consoleUserId'];
    if (owner != null && owner != user.id) {
      throw _SyncError(
        'Another console user already uses this number for login. Choose a '
        'different number.',
      );
    }
  }

  /// Normalise un numéro de téléphone : sans espaces ni tirets, préfixe +237
  /// (gère aussi le « 237... » saisi sans le +).
  String _canonicalPhone(String phone) {
    final cleaned = phone.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) return '';
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('237')) return '+$cleaned';
    return '+237$cleaned';
  }

  // --- Helpers ---

  String _friendlyError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
          return 'Service unavailable. Check your internet connection.';
        case 'permission-denied':
          // Les règles LOCALES (firestore.rules) sont ouvertes : si Firebase
          // refuse quand même, c'est que les règles DÉPLOYÉES sur le projet
          // sont périmées (ex. collection ajoutée après le dernier
          // déploiement). Le correctif est `firebase deploy --only
          // firestore:rules`.
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
    _cancelSubscriptions();
    super.dispose();
  }
}

/// Erreur métier de la synchro du compte de connexion (message affiché tel
/// quel par le toast du drawer, sans préfixe « Exception: »).
class _SyncError implements Exception {
  _SyncError(this.message);

  final String message;

  @override
  String toString() => message;
}
