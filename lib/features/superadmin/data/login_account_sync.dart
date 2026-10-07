import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/platform_user_model.dart';
import '../../../services/auth_backend.dart';
import '../../../services/auth_service.dart';

/// Erreur métier de la synchro du compte de connexion (message affiché tel
/// quel par le toast du drawer, sans préfixe « Exception: »).
class LoginSyncError implements Exception {
  LoginSyncError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Helpers partagés entre la console super admin et la console entreprise
/// pour créer / mettre à jour / supprimer le compte de connexion d'un
/// utilisateur console.
///
/// Depuis la migration sécurité :
///   - le mot de passe vit dans Firebase Auth (email dérivé du numéro) et
///     n'est JAMAIS écrit dans Firestore — les comptes sont gérés par la
///     Cloud Function `manageAccount` (Admin SDK), qui n'a pas besoin du
///     mot de passe actuel ;
///   - `utilisateurs/{id}.hasLogin` indique qu'un compte de connexion existe ;
///   - `users/{téléphone}` porte le profil de connexion + le `uid` Auth ;
///   - `auth_profiles/{uid}` porte rôle + scope pour les règles Firestore ;
///   - le compte Auth (via [ensureAuthAccount]) est assuré AVANT le batch
///     Firestore (le `uid` est écrit dans le doc) ; en cas d'échec du
///     batch, l'appelant doit détruire le compte Auth (rollback).
class LoginAccountSync {
  LoginAccountSync._();

  // --- Normalisation du numéro ---

  /// Normalise un numéro de téléphone : sans espaces ni tirets, préfixe
  /// +237 (gère aussi le « 237... » saisi sans le +).
  static String canonicalPhone(String phone) {
    final cleaned = phone.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) return '';
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('237')) return '+$cleaned';
    return '+237$cleaned';
  }

  // --- Validation ---

  /// Un utilisateur avec un mot de passe DOIT avoir un numéro, sinon le
  /// compte de connexion users/{phone} ne peut pas exister.
  static void requirePhone(PlatformUserModel user) {
    if (user.wantsLogin && canonicalPhone(user.telephone).isEmpty) {
      throw LoginSyncError(
        'A phone number is required to create the login account. Add a '
        'number to this user.',
      );
    }
  }

  /// Vérifie AVANT toute écriture que le numéro peut recevoir un compte de
  /// connexion console : ni compte client/collecteur réel, ni numéro déjà
  /// utilisé par un autre utilisateur console.
  static Future<void> preflight(
    FirebaseFirestore db,
    PlatformUserModel user,
  ) async {
    if (!user.wantsLogin) return;
    final phone = canonicalPhone(user.telephone);
    if (phone.isEmpty) return;
    if (_isSuspended(user)) return;
    await _assertPhoneAvailable(db, db.collection('users').doc(phone), user);
  }

  static bool _isSuspended(PlatformUserModel user) =>
      user.status == 'Suspended' || user.status == 'Suspendu';

  // --- Compte Firebase Auth (Cloud Function `manageAccount`) ---

  /// Assure le compte Firebase Auth d'un utilisateur console et renvoie son
  /// `uid` : création avec [PlatformUserModel.password], ou réactivation du
  /// compte existant (mot de passe changé s'il en est saisi un nouveau).
  /// '' si l'utilisateur n'a pas de compte de connexion ou est suspendu.
  static Future<String> ensureAuthAccount(
    AuthBackend backend,
    PlatformUserModel user,
  ) async {
    final phone = canonicalPhone(user.telephone);
    if (!user.wantsLogin || phone.isEmpty || _isSuspended(user)) return '';
    try {
      return await backend.ensureAccount(
        email: AuthService.emailFor(phone),
        password: user.password,
      );
    } on AuthBackendException catch (e) {
      if (e.code == 'password-required') {
        throw LoginSyncError(
          'This user has no login account yet: set a password to create it.',
        );
      }
      throw LoginSyncError(
        e.message.isEmpty ? 'Unable to update the login account.' : e.message,
      );
    }
  }

  /// Suspension : le compte Auth est désactivé (uid conservé — la
  /// réactivation n'exige pas de nouveau mot de passe).
  static Future<void> disableAuthAccount(
    AuthBackend backend,
    PlatformUserModel user,
  ) async {
    final phone = canonicalPhone(user.telephone);
    if (phone.isEmpty || !user.wantsLogin) return;
    try {
      await backend.disableAccount(email: AuthService.emailFor(phone));
    } on AuthBackendException catch (e) {
      throw LoginSyncError(
        'Unable to suspend the login account: '
        '${e.message.isEmpty ? e.code : e.message}',
      );
    }
  }

  /// Numéro changé : le compte Auth de l'ancien numéro passe sur le nouveau
  /// (même uid, même mot de passe — l'admin n'a pas à le ressaisir).
  static Future<void> moveAuthAccount(
    AuthBackend backend,
    PlatformUserModel oldUser,
    String newPhone,
  ) async {
    final oldPhone = canonicalPhone(oldUser.telephone);
    final target = canonicalPhone(newPhone);
    if (!oldUser.wantsLogin || oldPhone.isEmpty || target.isEmpty) return;
    try {
      await backend.moveAccount(
        email: AuthService.emailFor(oldPhone),
        newEmail: AuthService.emailFor(target),
      );
    } on AuthBackendException catch (e) {
      throw LoginSyncError(
        e.code == 'email-already-in-use'
            ? 'An account already exists with this number. Choose a '
                'different number.'
            : 'Unable to move the login account: '
                '${e.message.isEmpty ? e.code : e.message}',
      );
    }
  }

  /// Supprime le compte Firebase Auth d'un utilisateur console.
  static Future<void> deleteAuthAccount(
    AuthBackend backend,
    PlatformUserModel user,
  ) async {
    final phone = canonicalPhone(user.telephone);
    if (phone.isEmpty || !user.wantsLogin) return;
    try {
      await backend.deleteAccount(email: AuthService.emailFor(phone));
    } catch (_) {
      // Best-effort : si le compte Auth n'existe pas déjà, ce n'est pas grave.
    }
  }

  /// Ajoute au batch [batch] la synchronisation du compte de connexion
  /// `users/{téléphone}` + `auth_profiles/{uid}` pour [user] (création,
  /// mise à jour, suspension ou suppression). Appelé entre deux écritures du
  /// même batch pour garder l'ensemble atomique.
  ///
  /// [uid] : uid Auth assuré via [ensureAuthAccount] ('' si aucun compte).
  static Future<void> stage(
    WriteBatch batch,
    FirebaseFirestore db,
    PlatformUserModel user, {
    String oldPhone = '',
    String uid = '',
  }) async {
    requirePhone(user);
    final phone = canonicalPhone(user.telephone);

    // Ancien numéro → supprime l'ancien compte (même si le nouveau n'a pas
    // de mot de passe : un seed qui perd son login ne doit pas garder
    // l'ancien compte actif).
    final oldCanonical = canonicalPhone(oldPhone);
    if (oldCanonical.isNotEmpty && oldCanonical != phone) {
      final oldDoc = await db.collection('users').doc(oldCanonical).get();
      if (oldDoc.exists && oldDoc.data()?['consoleCreated'] == true) {
        batch.delete(db.collection('users').doc(oldCanonical));
        final oldUid = oldDoc.data()?['uid'] as String?;
        if (oldUid != null && oldUid.isNotEmpty) {
          batch.delete(db.collection('auth_profiles').doc(oldUid));
        }
      }
    }

    if (!user.wantsLogin) return;
    final ref = db.collection('users').doc(phone);

    if (_isSuspended(user)) {
      final doc = await ref.get();
      if (doc.exists && doc.data()?['consoleCreated'] == true) {
        batch.delete(ref);
        final oldUid = doc.data()?['uid'] as String?;
        if (oldUid != null && oldUid.isNotEmpty) {
          batch.delete(db.collection('auth_profiles').doc(oldUid));
        }
      }
    } else {
      await _assertPhoneAvailable(db, ref, user);
      batch.set(ref, {
        'phoneNumber': phone,
        'fullName': user.nom,
        'role': loginRoleFor(user.role),
        'uid': uid,
        'societeId': user.societeId,
        'agenceId': user.agenceId,
        'isSubscribed': false,
        'consoleCreated': true,
        'consoleUserId': user.id,
      });
      if (uid.isNotEmpty) {
        batch.set(db.collection('auth_profiles').doc(uid), {
          'uid': uid,
          'phone': phone,
          'role': loginRoleFor(user.role),
          'status': 'active',
          'societeId': user.societeId,
          'agenceId': user.agenceId,
        });
      }
    }
  }

  /// Ajoute au batch la suppression du compte de connexion s'il a été créé
  /// par la console. Utilisé lors de la suppression d'un utilisateur.
  static Future<void> stageDeleteLogin(
    WriteBatch batch,
    FirebaseFirestore db,
    String phone,
  ) async {
    final canonical = canonicalPhone(phone);
    if (canonical.isEmpty) return;
    final doc = await db.collection('users').doc(canonical).get();
    if (doc.exists && doc.data()?['consoleCreated'] == true) {
      batch.delete(db.collection('users').doc(canonical));
      final uid = doc.data()?['uid'] as String?;
      if (uid != null && uid.isNotEmpty) {
        batch.delete(db.collection('auth_profiles').doc(uid));
      }
    }
  }

  // --- Helpers privés ---

  static Future<void> _assertPhoneAvailable(
    FirebaseFirestore db,
    DocumentReference<Map<String, dynamic>> ref,
    PlatformUserModel user,
  ) async {
    final existing = await ref.get();
    if (!existing.exists) return;
    final data = existing.data()!;
    if (data['consoleCreated'] != true) {
      throw LoginSyncError(
        'A client account already exists with this number. Choose a '
        'different number.',
      );
    }
    final owner = data['consoleUserId'];
    if (owner != null && owner != user.id) {
      throw LoginSyncError(
        'Another console user already uses this number for login. Choose a '
        'different number.',
      );
    }
  }

  /// Rôle de connexion (`users`) correspondant à un rôle console
  /// (`utilisateurs`).
  static String loginRoleFor(String consoleRole) {
    final role = consoleRole.trim().toLowerCase();
    if (role == 'general administrator' ||
        role == 'administrateur général') {
      return 'general_admin';
    }
    return 'agency_manager';
  }
}