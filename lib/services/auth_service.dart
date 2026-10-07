import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import 'auth_backend.dart';

/// Authentication service — "phone + password" mode on
/// **Firebase Auth** (email derived from phone), profile in `users/{phone}`.
///
/// SECURITY MIGRATION: before this commit, login read `users/{phone}`
/// and compared the PLAINTEXT password stored in Firestore. Since:
///   1. the password is NEVER written to Firestore — it lives in
///      Firebase Auth (hashed by Google);
///   2. login goes through `signInWithEmailAndPassword` (derived email:
///      `2376XXXXXXX@wastepro.cm`);
///   3. each login account has an `auth_profiles/{uid}` (role +
///      scope) that Firestore rules consult to lock down access.
///
/// A migration script (`tool/migrate_auth.mjs`) creates Auth accounts
/// for existing users from their current password — no login data is lost.
class AuthService {
  AuthService({FirebaseFirestore? db, AuthBackend? backend})
    : _db = db ?? FirebaseFirestore.instance,
      _backend = backend ?? FirebaseAuthBackend();

  final FirebaseFirestore _db;
  final AuthBackend _backend;

  /// Normalizes a phone number: strips spaces and dashes, adds +237
  /// prefix (also handles '237...' entered without the +).
  static String canonicalPhone(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) return '';
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('237')) return '+$cleaned';
    return '+237$cleaned';
  }

  /// `users` doc keys to try for a given number:
  ///   1. the canonical form (+237…);
  ///   2. the number as entered;
  ///   3. the number without the +237 prefix (an account created manually in
  ///      the Firebase console may use the bare key, e.g. `'653645807'`
  ///      instead of `'+237653645807'`).
  /// The first doc found is authoritative.
  static Set<String> canonicalKeys(String raw) {
    final canonical = canonicalPhone(raw);
    final trimmed = raw.trim();
    final bare = canonical.startsWith('+237')
        ? canonical.substring(4)
        : trimmed;
    return {canonical, trimmed, bare};
  }

  /// Firebase Auth email derived from a phone number (login identifier).
  ///
  /// Same rule as the `tool/migrate_auth.mjs` migration: the canonical
  /// number without the `+`, followed by the platform domain.
  static String emailFor(String phone) {
    final canonical = canonicalPhone(phone);
    if (canonical.isEmpty) return '';
    return '${canonical.replaceAll('+', '')}@wastepro.cm';
  }

  Future<T> _runWithRetry<T>(
    Future<T> Function() action, {
    int retries = 2,
  }) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await action();
      } on FirebaseException catch (e) {
        final isTransient =
            e.code == 'unavailable' || e.code == 'deadline-exceeded';
        if (isTransient && attempt < retries) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }

        if (e.code == 'unavailable') {
          throw 'The database service is temporarily unavailable. Please check your internet connection and try again.';
        }

        // `permission-denied` = the Firestore rules DEPLOYED on Firebase
        // reject the operation. We translate into an actionable message.
        if (e.code == 'permission-denied') {
          throw 'Access denied: the Firestore rules deployed on Firebase are '
              'out of date. Deploy the latest rules with: firebase deploy '
              '--only firestore:rules';
        }

        throw e.message ?? 'Firestore request failed.';
      } on Exception {
        if (attempt < retries) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }

    throw 'Unable to complete the request right now.';
  }

  /// Logs in a phone + password via Firebase Auth, then loads the
  /// `users/{phone}` profile.
  ///
  /// - `null`: no account for this number.
  /// - `UserModel`: successful login (role may be `pending_client`
  ///   for an application not yet approved).
  /// - Otherwise, an error is thrown (wrong password, disabled account…).
  ///
  /// With enumeration protection enabled on the project, the Auth backend
  /// returns `invalid-credentials` (indistinguishable): we then consult
  /// `users/{phone}` to determine whether the account actually exists
  /// and produce "Incorrect Password" instead of "User not found".
  Future<UserModel?> login(String phone, String password) async {
    final canonical = canonicalPhone(phone);
    if (canonical.isEmpty) return null;
    final email = emailFor(canonical);

    final String uid;
    try {
      uid = await _backend.signIn(email: email, password: password);
    } on AuthBackendException catch (e) {
      if (e.code == 'user-not-found') return null;
      if (e.code == 'wrong-password') throw 'Incorrect Password';
      if (e.code == 'invalid-credentials') {
        // The Auth API cannot distinguish "no account" from "wrong password"
        // (enumeration protection). The deployed rules keep `users` private
        // to signed-in accounts, so this lookup is normally denied — we then
        // answer with a message that reveals nothing about the account.
        final bool exists;
        try {
          exists = await _usersDocExists(canonical);
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied') {
            throw 'Incorrect phone number or password.';
          }
          rethrow;
        }
        if (exists) throw 'Incorrect Password';
        return null;
      }
      if (e.code == 'user-disabled') {
        throw 'This account has been disabled. Please contact your agency '
            'administrator.';
      }
      if (e.code == 'network') {
        throw 'Unable to reach the authentication service. Check your '
            'internet connection and try again.';
      }
      throw e.message.isEmpty ? 'Authentication failed.' : e.message;
    }

    // Profile: try the canonical key then the legacy variants (account created
    // manually in the console, bare key without +237).
    return _runWithRetry<UserModel?>(() async {
      for (final key in canonicalKeys(canonical)) {
        if (key.isEmpty) continue;
        final doc = await _db.collection('users').doc(key).get();
        if (!doc.exists) continue;
        final user = UserModel.fromMap(doc.data()!);
        // A legacy doc (created manually in the console, before migration)
        // may not carry a `uid` — we let it through. If it does carry one,
        // it must match the Auth account that just signed in
        // (otherwise it's a fallback key for a different account).
        final userUid = user.uid;
        if (userUid != null && userUid.isNotEmpty && userUid != uid) {
          continue;
        }
        return user;
      }
      return null;
    });
  }

  Future<bool> _usersDocExists(String canonical) async {
    for (final key in canonicalKeys(canonical)) {
      if (key.isEmpty) continue;
      if ((await _db.collection('users').doc(key).get()).exists) return true;
    }
    return false;
  }

  /// Status of the most recent registration application for
  /// [phone]: `'pending'` | `'approved'` | `'rejected'`, or null if this
  /// number has no application.
  Future<String?> registrationStatus(String phone) async {
    return _runWithRetry<String?>(() async {
      final canonical = canonicalPhone(phone);
      if (canonical.isEmpty) return null;
      final snap = await _db
          .collection('registrations')
          .where('phone', isEqualTo: canonical)
          .get();
      if (snap.docs.isEmpty) return null;
      final docs = snap.docs.toList()..sort((a, b) => b.id.compareTo(a.id));
      return docs.first.data()['status'] as String?;
    });
  }

  /// Submits a client pre-registration application — and **creates the login**
  /// account on Firebase Auth right away.
  ///
  /// "Account from registration" model:
  ///   - an Auth account is created (derived email + chosen password);
  ///   - `users/{phone}` carries the profile with role `pending_client`
  ///     and the Auth `uid` (NO plaintext password);
  ///   - `auth_profiles/{uid}` carries role + scope for Firestore rules;
  ///   - `registrations/{id}` is the application visible to the backoffice.
  ///
  /// The client can log in immediately: the app routes them to the
  /// tracking screen until the agency manager approves (the role then
  /// becomes `client`).
  ///
  /// - A number already linked to a real account (client/collector/console)
  ///   is rejected (they should log in instead).
  /// - A pending application for this number is rejected.
  /// - A REJECTED application allows a new submission (re-apply):
  ///   the existing account is kept (same uid), profile fields are
  ///   updated, and a new `pending` application is written.
  Future<void> submitPreRegistration({
    required String fullName,
    required String phone,
    required String zone,
    required String agenceId,
    required String agenceName,
    required String societeId,
    required String password,
    String photoUrl = '',
    double? latitude,
    double? longitude,
  }) async {
    final canonical = canonicalPhone(phone);
    if (canonical.isEmpty) throw 'Invalid phone number.';
    if (fullName.trim().isEmpty) throw 'Please enter your full name.';
    if (password.length < 6) {
      throw 'Password must be at least 6 characters.';
    }
    if (agenceId.isEmpty && agenceName.trim().isEmpty) {
      throw 'Please choose an agency.';
    }

    // --- Session as the applicant ---
    // Every write below is made BY the applicant's own Auth account (the
    // Firestore rules only let an account create its own pending profile).
    // New number → account created and signed in. Existing account → it
    // must be the applicant's (same password), e.g. a re-apply.
    final email = emailFor(canonical);
    var uid = '';
    var isNewAccount = false;
    try {
      uid = await _backend.createAccountAndSignIn(
        email: email,
        password: password,
      );
      isNewAccount = true;
    } on AuthBackendException catch (e) {
      if (e.code == 'network') {
        throw 'Unable to reach the authentication service. Check your '
            'internet connection and try again.';
      }
      if (e.code != 'email-already-in-use') {
        throw e.message.isEmpty ? 'Unable to create the account.' : e.message;
      }
      try {
        uid = await _backend.signIn(email: email, password: password);
      } on AuthBackendException {
        throw 'An account already exists with this number. Please log in '
            'instead.';
      }
    }

    try {
      await _submitAsApplicant(
        uid: uid,
        isNewAccount: isNewAccount,
        canonical: canonical,
        fullName: fullName,
        zone: zone,
        agenceId: agenceId,
        agenceName: agenceName,
        societeId: societeId,
        photoUrl: photoUrl,
        latitude: latitude,
        longitude: longitude,
      );
    } finally {
      // The applicant logs in from the login screen afterwards.
      try {
        await _backend.signOut();
      } catch (_) {}
    }
  }

  Future<void> _submitAsApplicant({
    required String uid,
    required bool isNewAccount,
    required String canonical,
    required String fullName,
    required String zone,
    required String agenceId,
    required String agenceName,
    required String societeId,
    required String photoUrl,
    double? latitude,
    double? longitude,
  }) async {
    await _runWithRetry(() async {
      final id = 'reg${DateTime.now().microsecondsSinceEpoch}';
      try {
        await _writeApplication(
          id: id,
          uid: uid,
          canonical: canonical,
          fullName: fullName,
          zone: zone,
          agenceId: agenceId,
          agenceName: agenceName,
          societeId: societeId,
          photoUrl: photoUrl,
          latitude: latitude,
          longitude: longitude,
        );
      } catch (_) {
        // Never leave an orphaned Auth account behind a refused or failed
        // application.
        if (isNewAccount) {
          try {
            await _backend.deleteCurrentAccount();
          } catch (_) {}
        }
        rethrow;
      }

      // Server-side verification (OUTSIDE the rollback try/catch: a locally
      // queued application must be able to sync later, without destroying
      // the Auth account already created). With offline persistence, a
      // `batch.commit()` that cannot reach Firestore resolves anyway
      // (write to local cache) — the success screen shown then is a LIE:
      // the application will never reach the agency manager's backoffice.
      // We re-read the doc from the server to confirm the submission
      // actually left.
      bool confirmed = false;
      try {
        confirmed = await _db
            .collection('registrations')
            .doc(id)
            .get(const GetOptions(source: Source.server))
            .then((snap) => snap.exists);
      } on Exception {
        confirmed = false;
      }
      if (!confirmed) {
        throw 'Your device appears to be offline — the application was not '
            'sent. Check your internet connection, then submit again.';
      }
    });
  }

  /// Checks the existing profile (as its owner) then writes the login
  /// profile, the rules profile and the application in one batch.
  Future<void> _writeApplication({
    required String id,
    required String uid,
    required String canonical,
    required String fullName,
    required String zone,
    required String agenceId,
    required String agenceName,
    required String societeId,
    required String photoUrl,
    double? latitude,
    double? longitude,
  }) async {
    // --- Existing profile? ---
    var isReapply = false;
    final existing = await _db.collection('users').doc(canonical).get();
    if (existing.exists) {
      final role = (existing.data()?['role'] as String? ?? '').toLowerCase();
      if (role != 'pending_client') {
        throw 'This number already has an account. Please log in instead.';
      }
      // pending_client: only a REJECTED application allows a re-apply.
      final status = await registrationStatus(canonical);
      if (status != 'rejected') {
        throw 'You already have a pending application. The agency will '
            'contact you soon.';
      }
      isReapply = true;
    }

    // --- Agency name resolution (free typing vs selection) ---
    var finalAgenceId = agenceId;
    var finalSocieteId = societeId;
    var finalAgenceName = agenceName.trim();
    if (finalAgenceId.isEmpty && finalAgenceName.isNotEmpty) {
      final name = agenceName.trim().toLowerCase();
      final agences = await _db.collection('agences').get();
      final exact = agences.docs
          .where(
            (d) => (d.data()['ville'] as String? ?? '').toLowerCase() == name,
          )
          .toList();
      final matches = exact.isNotEmpty
          ? exact
          : agences.docs
                .where(
                  (d) => (d.data()['ville'] as String? ?? '')
                      .toLowerCase()
                      .contains(name),
                )
                .toList();
      if (matches.length == 1) {
        finalAgenceId = matches.single.id;
        finalSocieteId = matches.single.data()['societeId'] as String? ?? '';
        final resolvedVille = matches.single.data()['ville'] as String? ?? '';
        if (resolvedVille.isNotEmpty) finalAgenceName = resolvedVille;
      } else {
        throw matches.isEmpty
            ? 'Agency not found. Choose one of the suggested agencies.'
            : 'Several agencies match this name. Choose one from the '
                  'suggestions.';
      }
    }

    final now = DateTime.now();
    final iso =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final batch = _db.batch();
    // Login profile (no password — it lives in Firebase Auth).
    batch.set(_db.collection('users').doc(canonical), {
      'phoneNumber': canonical,
      'fullName': fullName.trim(),
      'role': 'pending_client',
      'uid': uid,
      'societeId': finalSocieteId,
      'agenceId': finalAgenceId,
      'agenceName': finalAgenceName,
      'collecteurId': '',
      'isSubscribed': false,
    }, SetOptions(merge: isReapply));
    // Rules profile (role + scope), consulted by firestore.rules.
    batch.set(_db.collection('auth_profiles').doc(uid), {
      'uid': uid,
      'phone': canonical,
      'role': 'pending_client',
      'status': 'pending',
      'societeId': finalSocieteId,
      'agenceId': finalAgenceId,
    }, SetOptions(merge: isReapply));
    // Application as seen by the backoffice.
    batch.set(_db.collection('registrations').doc(id), {
      'id': id,
      'fullName': fullName.trim(),
      'phone': canonical,
      'zone': zone.trim(),
      'agenceId': finalAgenceId,
      'agenceName': finalAgenceName,
      'societeId': finalSocieteId,
      'status': 'pending',
      'collecteurId': '',
      'photoUrl': photoUrl,
      // Point de collecte choisi sur la carte : repris sur le client
      // créé à l'approbation (tournée + suivi).
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': iso,
    });
    await batch.commit();
  }

  /// Uid of the active session (null if signed out).
  String? get currentUid => _backend.currentUid;

  /// Signs out the Firebase Auth session.
  Future<void> signOut() => _backend.signOut();
}
