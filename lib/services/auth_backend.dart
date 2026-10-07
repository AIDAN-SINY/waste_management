import 'package:firebase_auth/firebase_auth.dart';

import 'functions_client.dart';

/// Business error from the authentication backend.
///
/// [code] is stable and independent of SDK codes (which vary across
/// platforms and versions) — the login screen uses it to translate
/// into user-facing messages:
///   - `user-not-found`: no account for this email;
///   - `wrong-password`: the account exists but the password is wrong;
///   - `invalid-credentials`: the Auth API CANNOT distinguish
///     "no account" from "wrong password" (merged
///     `invalid-credential` + email enumeration protection
///     enabled on the project) — AuthService consults the `users`
///     collection to decide;
///   - `user-disabled`: the account has been disabled (rejected, suspended);
///   - `email-already-in-use`: creation impossible, existing account;
///   - `password-required`: [AuthBackend.ensureAccount] on a number without
///     an account and without a password;
///   - `network`: connection problem (retry on AuthService side);
///   - `unknown`: any other error.
class AuthBackendException implements Exception {
  AuthBackendException(this.code, [this.message = '']);

  final String code;
  final String message;

  @override
  String toString() => message.isEmpty ? code : message;
}

/// Authentication port over Firebase Auth.
///
/// The app never talks to `FirebaseAuth` directly: it goes through this
/// port, which allows
///   - tests to inject an in-memory backend (no plugin required);
///   - keeping a single error translation (see [AuthService]).
///
/// Operations on ANOTHER account ([ensureAccount], [disableAccount],
/// [deleteAccount]) go through the `manageAccount` Cloud Function (Admin
/// SDK): the consoles never need — nor store — anyone's password.
abstract class AuthBackend {
  /// Connecte un compte email + mot de passe sur l'app principale et
  /// renvoie son `uid` (la session est persistée par Firebase Auth).
  ///
  /// Lève [AuthBackendException] (`user-not-found`, `wrong-password`,
  /// `invalid-credentials`, `user-disabled`, `network`…).
  Future<String> signIn({
    required String email,
    required String password,
  });

  /// Crée un compte et OUVRE sa session sur l'app principale (inscription :
  /// les écritures qui suivent sont faites par le compte lui-même, comme
  /// l'exigent les règles Firestore). Lève `email-already-in-use`.
  Future<String> createAccountAndSignIn({
    required String email,
    required String password,
  });

  /// Supprime le compte de la session courante (rollback d'inscription).
  Future<void> deleteCurrentAccount();

  /// Consoles: makes sure the login account exists and is enabled, and
  /// returns its uid. Creates it with [password]; on an existing account,
  /// re-enables it and sets [password] when non-empty. Throws
  /// `password-required` when there is no account and no password.
  Future<String> ensureAccount({
    required String email,
    String password = '',
  });

  /// Consoles: suspends the account (uid kept, login refused).
  Future<void> disableAccount({required String email});

  /// Consoles: deletes the account (no error if it does not exist).
  Future<void> deleteAccount({required String email});

  /// Consoles: phone number changed — the account keeps its uid and
  /// password under [newEmail]. Returns the uid, or null if [email] has no
  /// account. Throws `email-already-in-use` if [newEmail] is taken.
  Future<String?> moveAccount({
    required String email,
    required String newEmail,
  });

  /// Déconnecte la session courante (si elle existe).
  Future<void> signOut();

  /// Uid de la session active, ou null si personne n'est connecté.
  String? get currentUid;
}

/// Implémentation réelle par-dessus `firebase_auth` + `manageAccount`.
class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend({FirebaseAuth? auth, FunctionsClient? functions})
      : _auth = auth,
        _functions = functions;

  /// Lazily resolved: construction never touches
  /// `FirebaseAuth.instance` (injected by tests or resolved on first
  /// use — a backend built before `Firebase.initializeApp` must not
  /// crash).
  FirebaseAuth? _auth;
  final FunctionsClient? _functions;

  FirebaseAuth get _firebaseAuth => _auth ??= FirebaseAuth.instance;

  @override
  String? get currentUid => _firebaseAuth.currentUser?.uid;

  @override
  Future<String> signIn({
    required String email,
    required String password,
  }) async {
    //  PAS de `fetchSignInMethodsForEmail` ici. Cette API devait départager
    // « aucun compte » de « mauvais mot de passe », mais avec la protection
    // contre l'énumération d'emails activée sur le projet (réglage
    // Identity Platform), elle renvoie une liste VIDE même pour un compte
    // existant — le login échouait avec « User not found » pour des
    // identifiants corrects. L'erreur `invalid-credential` des SDK récents
    // fusionne elle aussi les deux cas : on remonte donc un code neutre
    // (`invalid-credentials`) et c'est AuthService qui tranche en
    // consultant la collection `users` (source de vérité de l'existence).
    try {
      final cred = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return cred.user!.uid;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-disabled':
          throw AuthBackendException('user-disabled');
        case 'network-request-failed':
        case 'too-many-requests':
          throw AuthBackendException('network');
        case 'invalid-credential':
        case 'wrong-password':
        case 'invalid-login-credentials':
          throw AuthBackendException('invalid-credentials');
        default:
          throw AuthBackendException('unknown', e.message ?? '');
      }
    }
  }

  @override
  Future<String> createAccountAndSignIn({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return cred.user!.uid;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
        case 'account-exists-with-different-credential':
          throw AuthBackendException('email-already-in-use');
        case 'weak-password':
          throw AuthBackendException(
            'weak-password',
            'Password must be at least 6 characters.',
          );
        case 'network-request-failed':
        case 'too-many-requests':
          throw AuthBackendException('network');
        default:
          throw AuthBackendException('unknown', e.message ?? '');
      }
    }
  }

  @override
  Future<void> deleteCurrentAccount() async {
    await _firebaseAuth.currentUser?.delete();
  }

  @override
  Future<String> ensureAccount({
    required String email,
    String password = '',
  }) async {
    final data = await _manage('ensure', email, password: password);
    return data['uid'] as String;
  }

  @override
  Future<void> disableAccount({required String email}) =>
      _manage('disable', email);

  @override
  Future<void> deleteAccount({required String email}) =>
      _manage('delete', email);

  @override
  Future<String?> moveAccount({
    required String email,
    required String newEmail,
  }) async {
    final data = await _manage('move', email, newEmail: newEmail);
    return data['uid'] as String?;
  }

  @override
  Future<void> signOut() => _firebaseAuth.signOut();

  /// `2376XXXXXXXX@wastepro.cm` → `+2376XXXXXXXX`.
  static String _phoneOf(String email) => '+${email.split('@').first}';

  /// Calls the `manageAccount` Cloud Function as the signed-in staff user.
  Future<Map<String, dynamic>> _manage(
    String action,
    String email, {
    String password = '',
    String newEmail = '',
  }) async {
    try {
      return await (_functions ??
              FunctionsClient(auth: _firebaseAuth))
          .post('manageAccount', {
        'action': action,
        'phone': _phoneOf(email),
        if (password.isNotEmpty) 'password': password,
        if (newEmail.isNotEmpty) 'newPhone': _phoneOf(newEmail),
      });
    } on FunctionsException catch (e) {
      if (e.statusCode == 0) throw AuthBackendException('network');
      if (e.message == 'password-required' ||
          e.message == 'email-already-in-use') {
        throw AuthBackendException(e.message);
      }
      throw AuthBackendException('unknown', e.message);
    }
  }
}
