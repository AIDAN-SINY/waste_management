import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/backoffice/data/firestore_backoffice_store.dart';
import 'package:waste_pro/features/company/data/firestore_company_store.dart';
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
    'console → application → backoffice: an agency created by the company '
    'console, its agency manager, the client application, and visibility '
    'in the scoped backoffice',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend();

      // --- The company exists ---
      await db.collection('societes').doc('so9').set({
        'id': 'so9',
        'raisonSociale': 'WastePro Akwa Ltd',
        'adresse': 'Bastos, Yaoundé',
        'telephone': '+237 233 42 10 55',
        'email': 'contact@wastepro-akwa.cm',
        'status': 'Active',
      });

      // --- 1. The General Administrator creates an agency (company console) ---
      final company = FirestoreCompanyStore(
        db: db,
        backend: backend,
        societeId: 'so9',
        seedIfEmpty: false,
      );
      await company.initialLoad;
      await _settle();

      final agence = await company.addAgence(
        ville: 'Yaoundé — Mokolo',
        location: 'Avenue Kennedy',
        responsable: 'Jean Dooh',
        telephone: '+237 677 12 34 56',
        status: 'Active',
      );
      // The agency is written WITH its id in the doc (read by the client
      // form via AgenceModel.fromMap(map['id'])).
      final agenceDoc =
          await db.collection('agences').doc(agence.id).get();
      expect(agenceDoc.exists, isTrue);
      expect(agenceDoc.data()?['id'], agence.id);

      // --- 2. The GA creates the agency manager assigned to this agency ---
      await company.addUtilisateur(
        nom: 'Jean Dooh',
        telephone: '+237 677 12 34 56',
        role: 'Agency Manager',
        agence: agence.ville,
        agenceId: agence.id,
        status: 'Active',
        password: 'manager123',
      );
      await _settle();

      // The manager's login account carries the SAME agenceId as the agency.
      final managerLogin =
          await db.collection('users').doc('+237677123456').get();
      expect(managerLogin.exists, isTrue);
      expect(managerLogin.data()?['role'], 'agency_manager');
      expect(managerLogin.data()?['agenceId'], agence.id);

      // --- 3. The client fills out the pre-registration (agency choice) ---
      final auth = AuthService(db: db, backend: backend);
      await auth.submitPreRegistration(
        fullName: 'Carine Mbappe',
        phone: '698 22 44 66',
        zone: 'Akwa',
        agenceId: agence.id,
        agenceName: agence.ville,
        societeId: 'so9',
        password: 'secret123',
      );

      final regs = await db.collection('registrations').get();
      expect(regs.docs.single.data()['agenceId'], agence.id);

      // --- 4. The agency manager logs in → scoped backoffice ---
      final manager = await AuthService(db: db, backend: backend).login(
        '+237 677 12 34 56',
        'manager123',
      );
      expect(manager, isNotNull);
      expect(manager!.agenceId, agence.id);

      final store = FirestoreBackofficeStore(
        db: db,
        backend: backend,
        seedIfEmpty: false,
        agenceId: manager.agenceId,
        societeId: manager.societeId,
      );
      await store.initialLoad;
      await _settle();

      // The application IS visible in the agency manager's backoffice.
      expect(store.registrations.length, 1);
      expect(store.pendingRegistrations.single.fullName, 'Carine Mbappe');
      expect(store.pendingRegistrations.single.agenceId, agence.id);

      company.dispose();
      store.dispose();
    },
  );

  test(
    'scoped backoffice: an application written with the AGENCY NAME (but '
    'a different id, e.g. a namesake agency) remains visible via fallback',
    () async {
      final db = FakeFirebaseFirestore();

      // Two HOMONYMOUS agencies (e.g. the seeded agency "Yaoundé — Bastos" and
      // a real agency created later with the same name).
      const ville = 'Yaoundé — Bastos';
      await db.collection('agences').doc('agSeed').set({
        'id': 'agSeed',
        'societe': 'WastePro Yaoundé SARL',
        'societeId': 'so1',
        'ville': ville,
        'responsable': 'Jean Dooh',
        'telephone': '+237 677 12 34 56',
        'status': 'Active',
      });
      await db.collection('agences').doc('agReal').set({
        'id': 'agReal',
        'societe': 'WastePro Akwa Ltd',
        'societeId': 'so9',
        'ville': ville,
        'responsable': 'Marie Ekwalla',
        'telephone': '+237 690 45 12 78',
        'status': 'Active',
      });
      // The manager is assigned to the REAL agency (agReal).
      await db.collection('users').doc('+237690451278').set({
        'phoneNumber': '+237690451278',
        'fullName': 'Marie Ekwalla',
        'role': 'agency_manager',
        'password': 'manager123',
        'societeId': 'so9',
        'agenceId': 'agReal',
        'consoleCreated': true,
      });

      // The client selected the namesake agency agSeed (same name): their
      // application carries the id of agSeed but the name "Yaoundé — Bastos".
      await AuthService(db: db, backend: FakeAuthBackend())
          .submitPreRegistration(
        fullName: 'Carine Mbappe',
        phone: '698 22 44 66',
        zone: 'Bonanjo',
        agenceId: 'agSeed',
        agenceName: ville,
        societeId: 'so1',
        password: 'secret123',
      );

      final store = FirestoreBackofficeStore(
        db: db,
        backend: FakeAuthBackend(),
        seedIfEmpty: false,
        agenceId: 'agReal',
        societeId: 'so9',
      );
      await store.initialLoad;
      await _settle();

      // The id doesn't match, but the NAME does: the agency manager SEES the
      // application and can approve it (approval creates the client under
      // the agency chosen by the client).
      expect(store.pendingRegistrations.length, 1);
      expect(store.pendingRegistrations.single.fullName, 'Carine Mbappe');
      expect(store.pendingRegistrations.single.agenceId, 'agSeed');

      // Approval: the client is created under the AGENCY CHOSEN by the
      // client (agSeed), never under the manager's own agency (agReal).
      await store.approveRegistration(
        store.pendingRegistrations.single,
        collecteurId: 'coX',
      );
      await _settle();
      final client = store.clients.singleWhere(
        (c) => c.name == 'Carine Mbappe',
      );
      expect(client.agenceId, 'agSeed');
      final login =
          await db.collection('users').doc('+237698224466').get();
      expect(login.exists, isTrue);
      expect(login.data()?['agenceId'], 'agSeed');

      store.dispose();
    },
  );
}
