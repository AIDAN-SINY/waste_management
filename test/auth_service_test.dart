import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/services/auth_backend.dart';
import 'package:waste_pro/services/auth_service.dart';

import 'fakes/fake_auth_backend.dart';

/// AuthService wired to an in-memory Auth backend (no Firebase).
AuthService makeAuth(FakeFirebaseFirestore db) =>
    AuthService(db: db, backend: FakeAuthBackend());

/// Backend that replicates the project's enumeration protection:
/// the Auth API cannot tell whether the account exists — every login
/// attempt fails with `invalid-credentials` (like the real backend
/// with the merged `invalid-credential` error from recent SDKs).
class _EnumerationProtectedBackend extends FakeAuthBackend {
  @override
  Future<String> signIn({
    required String email,
    required String password,
  }) {
    throw AuthBackendException('invalid-credentials');
  }
}

void main() {
  group('AuthService.canonicalPhone', () {
    test('normalizes freely entered numbers', () {
      expect(AuthService.canonicalPhone('677123456'), '+237677123456');
      expect(AuthService.canonicalPhone('237677123456'), '+237677123456');
      expect(AuthService.canonicalPhone('+237 677 12 34 56'), '+237677123456');
      expect(AuthService.canonicalPhone(' +2376-77-12-34-56 '), '+237677123456');
      expect(AuthService.canonicalPhone('+237677123456'), '+237677123456');
    });

    test('returns empty string for empty number', () {
      expect(AuthService.canonicalPhone(''), '');
      expect(AuthService.canonicalPhone('   '), '');
    });
  });

  group('AuthService.canonicalKeys', () {
    test('adds the bare key without +237 (manually created docs)', () {
      // An account created manually may use the bare key '653645807'
      // instead of '+237653645807': login must try both.
      expect(AuthService.canonicalKeys('653645807'), {
        '+237653645807',
        '653645807',
      });
      expect(AuthService.canonicalKeys('+237653645807'), {
        '+237653645807',
        '653645807',
      });
    });

    test('ignores empty keys', () {
      expect(AuthService.canonicalKeys(''), {''});
    });
  });

  group('AuthService.login with enumeration protection', () {
    test('reports wrong password when the users doc exists',
        () async {
      final db = FakeFirebaseFirestore();
      // Migrated account: users doc present (with uid), but the Auth API
      // refuses to say whether the email exists (enumeration protection).
      await db.collection('users').doc('+237640996787').set({
        'phoneNumber': '+237640996787',
        'fullName': 'Super Admin',
        'role': 'super_admin',
        'uid': 'uid-superadmin',
      });
      final auth = AuthService(
        db: db,
        backend: _EnumerationProtectedBackend(),
      );

      expect(
        () => auth.login('+237640996787', 'mauvais'),
        throwsA('Incorrect Password'),
      );
    });

    test('returns null (user not found) when no users doc', () async {
      final db = FakeFirebaseFirestore();
      final auth = AuthService(
        db: db,
        backend: _EnumerationProtectedBackend(),
      );

      expect(await auth.login('+237600000000', 'x'), isNull);
    });

    test('finds the users doc via a bare key (canonicalKeys)', () async {
      final db = FakeFirebaseFirestore();
      // Account created manually in the console with a NON-canonical key.
      await db.collection('users').doc('640996787').set({
        'phoneNumber': '640996787',
        'fullName': 'Admin legacy',
        'role': 'admin',
      });
      final auth = AuthService(
        db: db,
        backend: _EnumerationProtectedBackend(),
      );

      expect(
        () => auth.login('640996787', 'mauvais'),
        throwsA('Incorrect Password'),
      );
    });
  });

  group('AuthService.registrationStatus', () {
    test('returns null when the number has no application', () async {
      final db = FakeFirebaseFirestore();
      final auth = makeAuth(db);
      expect(await auth.registrationStatus('698 22 44 66'), isNull);
    });

    test('returns the application status (pending)', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('registrations').doc('reg1').set({
        'id': 'reg1',
        'fullName': 'Carine Mbappe',
        'phone': '+237698224466',
        'status': 'pending',
        'agenceId': 'ag1',
      });
      final auth = makeAuth(db);
      expect(await auth.registrationStatus('698 22 44 66'), 'pending');
    });

    test('returns the MOST RECENT application status', () async {
      final db = FakeFirebaseFirestore();
      // Two applications for the same number (e.g. rejected then resubmitted):
      // the most recent one is authoritative (ids sorted by timestamp).
      await db.collection('registrations').doc('reg1').set({
        'id': 'reg1',
        'phone': '+237698224466',
        'status': 'pending',
      });
      await db.collection('registrations').doc('reg2').set({
        'id': 'reg2',
        'phone': '+237698224466',
        'status': 'rejected',
      });
      final auth = makeAuth(db);
      expect(await auth.registrationStatus('+237698224466'), 'rejected');
    });
  });

  group('AuthService.submitPreRegistration', () {
    Future<void> submit(AuthService auth, {String phone = '698 22 44 66'}) {
      return auth.submitPreRegistration(
        fullName: 'Carine Mbappe',
        phone: phone,
        zone: 'Bonanjo',
        agenceId: 'ag1',
        agenceName: 'Yaoundé — Bastos',
        societeId: 'so1',
        password: 'secret123',
      );
    }

    test('writes a pending application with the canonical number', () async {
      final db = FakeFirebaseFirestore();
      final auth = makeAuth(db);
      await submit(auth);

      final docs = await db.collection('registrations').get();
      expect(docs.docs.single.data()['phone'], '+237698224466');
      expect(docs.docs.single.data()['fullName'], 'Carine Mbappe');
      expect(docs.docs.single.data()['agenceId'], 'ag1');
      expect(docs.docs.single.data()['status'], 'pending');
      expect(docs.docs.single.data()['collecteurId'], '');
    });

    test('rejects a number that already has an account', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('+237698224466').set({
        'phoneNumber': '+237698224466',
        'fullName': 'Déjà client',
        'role': 'client',
        'password': 'x',
      });
      final auth = makeAuth(db);
      expect(
        () => submit(auth),
        throwsA(contains('already has an account')),
      );
      expect((await db.collection('registrations').get()).docs, isEmpty);
    });

    test('rejects a pending application for the same number', () async {
      final db = FakeFirebaseFirestore();
      final auth = makeAuth(db);
      await submit(auth);
      expect(
        () => submit(auth),
        throwsA(contains('already have a pending application')),
      );
      expect((await db.collection('registrations').get()).docs, hasLength(1));
    });

    test('rejects without a valid number', () async {
      final db = FakeFirebaseFirestore();
      final auth = makeAuth(db);
      expect(
        () => submit(auth, phone: '  '),
        throwsA(contains('Invalid phone number')),
      );
    });


    test('resolves a typed agency name to its agenceId (case-insensitive)',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('agences').doc('ag1').set({
        'id': 'ag1',
        'societe': 'WastePro Yaoundé SARL',
        'societeId': 'so1',
        'ville': 'Yaoundé — Bastos',
        'responsable': 'Jean Dooh',
        'telephone': '+237 677 12 34 56',
        'status': 'Active',
      });

      final auth = makeAuth(db);
      await auth.submitPreRegistration(
        fullName: 'Carine Mbappe',
        phone: '698 22 44 66',
        zone: 'Bonanjo',
        agenceId: '', // typed name, no selection
        agenceName: 'YAOUNDÉ — BASTOS',
        societeId: '',
        password: 'secret123',
      );

      // The application is linked to the agency (otherwise invisible to the manager).
      final docs = await db.collection('registrations').get();
      expect(docs.docs.single.data()['agenceId'], 'ag1');
      expect(docs.docs.single.data()['societeId'], 'so1');
    });

    test('rejects an agency name that matches no agency', () async {
      final db = FakeFirebaseFirestore();
      final auth = makeAuth(db);
      // No agencies in the database: typing an unknown name must NOT create
      // an "orphaned" application (empty agenceId) that no agency manager
      // could see or process — the client must choose an existing agency.
      await expectLater(
        auth.submitPreRegistration(
          fullName: 'Carine Mbappe',
          phone: '698 22 44 66',
          zone: 'Kribi',
          agenceId: '',
          agenceName: 'Nouvelle Agence Kribi',
          societeId: '',
          password: 'secret123',
        ),
        throwsA(contains('Agency not found')),
      );
      expect((await db.collection('registrations').get()).docs, isEmpty);
    });
  });
}
