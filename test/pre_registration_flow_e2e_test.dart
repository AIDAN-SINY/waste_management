import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/backoffice/data/firestore_backoffice_store.dart';
import 'package:waste_pro/services/auth_service.dart';

import 'fakes/fake_auth_backend.dart';

/// Lets snapshot listeners catch up with writes.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'complete flow: client applicant → agency manager sees → approval '
    '→ client logs in',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend()
        ..seedAccount('237677123456@wastepro.cm', 'manager123');

      // --- Context: an agency exists (ag1, company so1) ---
      await db.collection('agences').doc('ag1').set({
        'id': 'ag1',
        'societe': 'WastePro Yaoundé SARL',
        'societeId': 'so1',
        'ville': 'Yaoundé — Bastos',
        'responsable': 'Jean Dooh',
        'telephone': '+237 677 12 34 56',
        'status': 'Active',
      });
      // An active collector in this agency (for assignment).
      await db.collection('collecteurs').doc('co1').set({
        'id': 'co1',
        'name': 'Paul Mbarga',
        'phone': '+237 678 90 11 22',
        'zone': 'Bonanjo / Akwa',
        'rating': 4.8,
        'status': 'Active',
        'agenceId': 'ag1',
        'societeId': 'so1',
      });
      // The agency manager (login account created by the super admin
      // console: role agency_manager, scoped to ag1, Auth uid).
      await db.collection('users').doc('+237677123456').set({
        'phoneNumber': '+237677123456',
        'fullName': 'Jean Dooh',
        'role': 'agency_manager',
        'uid': backend.uidFor('237677123456@wastepro.cm'),
        'societeId': 'so1',
        'agenceId': 'ag1',
        'consoleCreated': true,
      });

      // --- 1. The client fills out the pre-registration (app) ---
      final auth = AuthService(db: db, backend: backend);
      await auth.submitPreRegistration(
        fullName: 'Carine Mbappe',
        phone: '698 22 44 66',
        zone: 'Bonanjo',
        agenceId: 'ag1',
        agenceName: 'Yaoundé — Bastos',
        societeId: 'so1',
        password: 'secret123',
      );

      // The application is correctly recorded (status pending, linked to ag1).
      final regs = await db.collection('registrations').get();
      expect(regs.docs.single.data()['status'], 'pending');
      expect(regs.docs.single.data()['agenceId'], 'ag1');
      // The client has their pending_client profile (created at registration) but
      // no backoffice client yet.
      expect((await db.collection('clients').get()).docs, isEmpty);
      final pendingUser =
          await db.collection('users').doc('+237698224466').get();
      expect(pendingUser.exists, isTrue);
      expect(pendingUser.data()?['role'], 'pending_client');

      // --- 2. The agency manager logs in → backoffice scoped to ag1 ---
      final manager = await AuthService(db: db, backend: backend).login(
        '+237 677 12 34 56',
        'manager123',
      );
      expect(manager, isNotNull);
      expect(manager!.role, 'agency_manager');
      expect(manager.agenceId, 'ag1');

      final store = FirestoreBackofficeStore(
        db: db,
        backend: backend,
        seedIfEmpty: false,
        agenceId: manager.agenceId,
        societeId: manager.societeId,
      );
      await store.initialLoad;
      await _settle();

      // The agency manager SEES Carine's application (scope ag1).
      expect(store.registrations.length, 1);
      expect(store.pendingRegistrations.single.fullName, 'Carine Mbappe');

      // Another agency manager (ag2) would NOT see it.
      final otherStore = FirestoreBackofficeStore(
        db: db,
        backend: backend,
        seedIfEmpty: false,
        agenceId: 'ag2',
      );
      await otherStore.initialLoad;
      await _settle();
      expect(otherStore.registrations, isEmpty);
      otherStore.dispose();

      // --- 3. The agency manager approves and assigns the collector ---
      await store.approveRegistration(
        store.pendingRegistrations.single,
        collecteurId: 'co1',
      );
      await _settle();

      // Client created + login account with the client's password.
      final client = store.clients.singleWhere((c) => c.name == 'Carine Mbappe');
      expect(client.agenceId, 'ag1');
      expect(client.collecteurId, 'co1');
      expect(client.status, 'Active');

      final login = await db.collection('users').doc('+237698224466').get();
      expect(login.exists, isTrue);
      expect(login.data()?['role'], 'client');
      expect(login.data()?['uid'], isNotEmpty);
      expect(login.data()?['password'], isNull);
      expect(login.data()?['collecteurId'], 'co1');

      // --- 4. The client can now log in ---
      final clientUser = await AuthService(db: db, backend: backend)
          .login('698 22 44 66', 'secret123');
      expect(clientUser, isNotNull);
      expect(clientUser!.role, 'client');
      expect(clientUser.agenceId, 'ag1');
      expect(clientUser.collecteurId, 'co1');

      store.dispose();
    },
  );

  test(
    'partial agency name typed by client → resolved to the correct agency',
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

      final auth = AuthService(db: db, backend: FakeAuthBackend());
      // The client types "bastos" (not the full name) without selecting.
      await auth.submitPreRegistration(
        fullName: 'Carine Mbappe',
        phone: '698 22 44 66',
        zone: 'Bastos',
        agenceId: '',
        agenceName: 'bastos',
        societeId: '',
        password: 'secret123',
      );

      final regs = await db.collection('registrations').get();
      // The application is linked to the unique agency found by the partial
      // name — otherwise the agency manager would never see it.
      expect(regs.docs.single.data()['agenceId'], 'ag1');
      expect(regs.docs.single.data()['societeId'], 'so1');
      // The recorded NAME is the ACTUAL name of the resolved agency (not the typed
      // text) — this is the fallback key that makes the application visible
      // in the scoped backoffice and displayed with the correct agency.
      expect(regs.docs.single.data()['agenceName'], 'Yaoundé — Bastos');
    },
  );

  test(
    'two applications from the same number: the 2nd is rejected without crash '
    '(no composite index required)',
    () async {
      final db = FakeFirebaseFirestore();
      final auth = AuthService(db: db, backend: FakeAuthBackend());

      await auth.submitPreRegistration(
        fullName: 'Carine Mbappe',
        phone: '698 22 44 66',
        zone: 'Bonanjo',
        agenceId: 'ag1',
        agenceName: 'Yaoundé — Bastos',
        societeId: 'so1',
        password: 'secret123',
      );
      // No 2nd application: a single where on phone, filtered in memory.
      await expectLater(
        auth.submitPreRegistration(
          fullName: 'Carine Mbappe',
          phone: '698 22 44 66',
          zone: 'Bonanjo',
          agenceId: 'ag1',
          agenceName: 'Yaoundé — Bastos',
          societeId: 'so1',
          password: 'secret123',
        ),
        throwsA(contains('already have a pending application')),
      );
      // Someone without the account's password learns nothing about the
      // application — they are sent to the login screen.
      await expectLater(
        auth.submitPreRegistration(
          fullName: 'Carine Mbappe',
          phone: '698 22 44 66',
          zone: 'Bonanjo',
          agenceId: 'ag1',
          agenceName: 'Yaoundé — Bastos',
          societeId: 'so1',
          password: 'otherpass',
        ),
        throwsA(contains('Please log in instead')),
      );
      expect((await db.collection('registrations').get()).docs, hasLength(1));
    },
  );
}
