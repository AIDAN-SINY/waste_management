import 'package:waste_pro/services/auth_backend.dart';

/// Backend d'authentification en mémoire pour les tests.
///
/// Remplace `FirebaseAuthBackend` (qui exigerait un vrai Firebase) partout
/// où un test construit un `AuthService`, un store Firestore ou un
/// `UserProvider`. Miroir du comportement réel :
///   - `signIn` : vérifie email + mot de passe, `user-not-found` /
///     `wrong-password` / `user-disabled` ;
///   - `ensureAccount` : crée le compte (mot de passe requis) ou réactive
///     le compte existant (et change son mot de passe s'il est fourni) —
///     comme la Cloud Function `manageAccount` ;
///   - les `uid` sont déterministes par email — le uid renvoyé à la
///     création est exactement celui rendu par `signIn`, donc le
///     contrôle `user.uid == uid` de `AuthService.login` fonctionne.
class FakeAuthBackend implements AuthBackend {
  final Map<String, String> _passwords = {}; // email -> password
  final Map<String, String> _uids = {}; // email -> uid
  final Set<String> _disabled = {}; // emails
  int _uidCounter = 0;
  String? _currentUid;

  /// Prépare un compte existant (comme un compte créé à la main dans la
  /// console Firebase, dont la migration Auth a déjà créé l'entrée).
  void seedAccount(String email, String password) {
    _passwords[email] = password;
    _uidFor(email);
  }

  /// Uid déterministe qu'un compte [email] recevra (le même que celui
  /// rendu à la création / par [signIn]). Utile pour écrire à l'avance le
  /// champ `uid` d'un doc `users` à la main (comme le fait la migration).
  String uidFor(String email) => _uidFor(email);

  /// Vrai si un compte Auth existe pour [email].
  bool hasAccount(String email) => _passwords.containsKey(email);

  /// Vrai si le compte [email] est suspendu.
  bool isDisabled(String email) => _disabled.contains(email);

  String _uidFor(String email) {
    return _uids.putIfAbsent(email, () => 'uid-${++_uidCounter}');
  }

  @override
  Future<String> signIn({
    required String email,
    required String password,
  }) async {
    final stored = _passwords[email];
    if (stored == null) throw AuthBackendException('user-not-found');
    if (stored != password) throw AuthBackendException('wrong-password');
    if (_disabled.contains(email)) {
      throw AuthBackendException('user-disabled');
    }
    _currentUid = _uidFor(email);
    return _currentUid!;
  }

  @override
  Future<String> createAccountAndSignIn({
    required String email,
    required String password,
  }) async {
    if (_passwords.containsKey(email)) {
      throw AuthBackendException('email-already-in-use');
    }
    _passwords[email] = password;
    _currentUid = _uidFor(email);
    return _currentUid!;
  }

  @override
  Future<void> deleteCurrentAccount() async {
    final email = _uids.entries
        .where((e) => e.value == _currentUid)
        .map((e) => e.key)
        .firstOrNull;
    if (email != null) _remove(email);
    _currentUid = null;
  }

  @override
  Future<String> ensureAccount({
    required String email,
    String password = '',
  }) async {
    if (!_passwords.containsKey(email)) {
      if (password.isEmpty) throw AuthBackendException('password-required');
      _passwords[email] = password;
      return _uidFor(email);
    }
    _disabled.remove(email);
    if (password.isNotEmpty) _passwords[email] = password;
    return _uidFor(email);
  }

  @override
  Future<void> disableAccount({required String email}) async {
    if (_passwords.containsKey(email)) _disabled.add(email);
  }

  @override
  Future<void> deleteAccount({required String email}) async => _remove(email);

  @override
  Future<String?> moveAccount({
    required String email,
    required String newEmail,
  }) async {
    final password = _passwords[email];
    if (password == null) return null;
    if (_passwords.containsKey(newEmail)) {
      throw AuthBackendException('email-already-in-use');
    }
    final uid = _uidFor(email);
    final disabled = _disabled.contains(email);
    _remove(email);
    _passwords[newEmail] = password;
    _uids[newEmail] = uid;
    if (disabled) _disabled.add(newEmail);
    return uid;
  }

  void _remove(String email) {
    _passwords.remove(email);
    _uids.remove(email);
    _disabled.remove(email);
  }

  @override
  Future<void> signOut() async {
    _currentUid = null;
  }

  @override
  String? get currentUid => _currentUid;
}
