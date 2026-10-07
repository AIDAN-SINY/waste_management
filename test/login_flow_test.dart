import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/superadmin/data/firestore_platform_store.dart';
import 'package:waste_pro/services/auth_service.dart';

import 'fakes/fake_auth_backend.dart';

/// AuthService wired to an in-memory Auth backend (no Firebase).
AuthService makeAuth(FakeFirebaseFirestore db, FakeAuthBackend backend) =>
    AuthService(db: db, backend: backend);

/// Integration tests for "phone + password" login (Firebase Auth,
/// after the security migration).
///
/// These tests replicate the real flow with simulated Firestore + an
/// in-memory Auth backend:
///   1. The superadmin logs in with their `users/{phone}` doc
///      (created in the Firebase console, role `super_admin`, Auth account
///      created by migration — hence `seedAccount`).
///   2. The superadmin creates a user via the console → the console writes
///      their login account `users/{phone}` (uid + auth_profiles,
///      NO plaintext password).
///   3. This user can log in with phone + password.
void main() {
  group('superadmin login (account created in Firebase console)', () {
    test('logs in with phone + password', () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend()
        ..seedAccount('237677123456@wastepro.cm', 'admin123');
      // Doc created manually in the console: users/{phone} with role
      // super_admin; the password lives in Firebase Auth (migration),
      // no longer in Firestore.
      await db.collection('users').doc('+237677123456').set({
        'phoneNumber': '+237677123456',
        'fullName': 'Super Admin',
        'role': 'super_admin',
      });

      final auth = makeAuth(db, backend);
      final user = await auth.login('677 12 34 56', 'admin123');

      expect(user, isNotNull);
      expect(user!.role, 'super_admin');
      expect(user.fullName, 'Super Admin');
    });

    test('rejette un mauvais mot de passe', () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend()
        ..seedAccount('237677123456@wastepro.cm', 'admin123');
      await db.collection('users').doc('+237677123456').set({
        'phoneNumber': '+237677123456',
        'fullName': 'Super Admin',
        'role': 'super_admin',
      });

      final auth = makeAuth(db, backend);
      expect(
        () => auth.login('+237677123456', 'wrong'),
        throwsA('Incorrect Password'),
      );
    });

    test('returns null for an unknown number', () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend();
      final auth = makeAuth(db, backend);
      expect(await auth.login('+237600000000', 'x'), isNull);
    });
  });

  group('login regardless of input format (Firebase console)', () {
    test('finds the profile via raw or spaced input', () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend()
        ..seedAccount('237677123456@wastepro.cm', 'admin123');
      // Doc created in the console with a canonical +237... key: login
      // and auto-login (refreshUser) share the canonicalKeys logic and
      // must find the profile regardless of how the number is entered
      // (raw, with spaces/dashes, with or without +237).
      await db.collection('users').doc('+237677123456').set({
        'phoneNumber': '+237677123456',
        'fullName': 'Super Admin',
        'role': 'super_admin',
      });

      final auth = makeAuth(db, backend);

      // Raw input without +237: canonicalKeys tries +237677123456 then
      // 677123456 → the canonical doc is found.
      final byRaw = await auth.login('677123456', 'admin123');
      expect(byRaw, isNotNull);
      expect(byRaw!.role, 'super_admin');

      // Spaced input: same result.
      final bySpaced = await auth.login('+237 677 12 34 56', 'admin123');
      expect(bySpaced, isNotNull);
      expect(bySpaced!.fullName, 'Super Admin');

      // Exact canonical input: same result.
      final byCanonical = await auth.login('+237677123456', 'admin123');
      expect(byCanonical, isNotNull);
      expect(byCanonical!.fullName, 'Super Admin');
    });
  });

  group('legacy accounts created manually with a bare key', () {
    test('logs in via a users/{number without +237} doc', () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend()
        ..seedAccount('237653645807@wastepro.cm', 'motdepasse');
      // Super admin account created manually in the Firebase console with
      // a NON-canonical key ('653645807' instead of '+237653645807').
      // Login must still find it (bare key added to candidate keys
      // by canonicalKeys).
      await db.collection('users').doc('653645807').set({
        'phoneNumber': '653645807',
        'fullName': 'Adams',
        'role': 'super_admin',
      });

      final auth = makeAuth(db, backend);
      final user = await auth.login('653645807', 'motdepasse');

      expect(user, isNotNull);
      expect(user!.role, 'super_admin');
      expect(user.fullName, 'Adams');
    });

    test('prefers the canonical doc when it also exists', () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend()
        ..seedAccount('237696713899@wastepro.cm', 'secret123');
      // Legacy duplicate (bare key, no Auth account) + correct canonical
      // account: login must succeed via the canonical key and not fail
      // on the duplicate.
      await db.collection('users').doc('696713899').set({
        'phoneNumber': '696713899',
        'fullName': 'Nadia (legacy)',
        'role': 'admin',
      });
      await db.collection('users').doc('+237696713899').set({
        'phoneNumber': '+237696713899',
        'fullName': 'Nadia',
        'role': 'admin',
      });

      final auth = makeAuth(db, backend);
      final user = await auth.login('696713899', 'secret123');
      expect(user, isNotNull);
      expect(user!.fullName, 'Nadia');

      // And a wrong password is still rejected despite the duplicate.
      expect(
        () => auth.login('696713899', 'mauvais'),
        throwsA('Incorrect Password'),
      );
    });
  });

  group('users created by the superadmin console', () {
    test('can log in after creation via the console', () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend();
      // The superadmin console (FirestorePlatformStore) creates the Auth
      // account (via the injected backend) + the `users/{phone}` doc (uid,
      // NO plaintext password).
      final store = FirestorePlatformStore(
        db: db,
        backend: backend,
        seedIfEmpty: false,
        isSignedOut: () => false,
      );
      await store.initialLoad;

      await store.addUtilisateur(
        nom: 'Marie Ekwalla',
        telephone: '+237 699 99 99 99',
        role: 'General Administrator',
        agence: 'Yaoundé',
        status: 'Active',
        password: 'secret123',
      );

      // The login account was correctly written with the REAL console role
      // (General Administrator → general_admin, Phase 1) and the Auth uid.
      final loginDoc = await db.collection('users').doc('+237699999999').get();
      expect(loginDoc.exists, isTrue);
      expect(loginDoc.data()?['role'], 'general_admin');
      expect(loginDoc.data()?['uid'], isNotEmpty);
      expect(loginDoc.data()?['password'], isNull,
          reason: 'the password must no longer be written to Firestore');

      // The user logs in with the phone + password set by the superadmin.
      final auth = makeAuth(db, backend);
      final user = await auth.login('+237 699 99 99 99', 'secret123');

      expect(user, isNotNull);
      expect(user!.role, 'general_admin');
      expect(user.fullName, 'Marie Ekwalla');

      store.dispose();
    });

    test('rejects a password different from the one set', () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend();
      final store = FirestorePlatformStore(
        db: db,
        backend: backend,
        seedIfEmpty: false,
        isSignedOut: () => false,
      );
      await store.initialLoad;

      await store.addUtilisateur(
        nom: 'Jean Dooh',
        telephone: '+237 677 12 34 56',
        role: 'Agency Manager',
        agence: 'Yaoundé — Bastos',
        status: 'Active',
        password: 'mdp-cons',
      );

      final auth = makeAuth(db, backend);
      expect(
        () => auth.login('+237677123456', 'autre-mdp'),
        throwsA('Incorrect Password'),
      );

      store.dispose();
    });
  });
}
