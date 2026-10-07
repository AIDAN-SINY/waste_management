import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('loads only data for ITS company (scoping)', () async {
    final db = FakeFirebaseFirestore();
    // Two companies with agencies and users.
    await db.collection('societes').doc('so1').set({
      'id': 'so1',
      'raisonSociale': 'WastePro Yaoundé SARL',
      'adresse': 'Bonanjo',
      'telephone': '+237 233 42 10 10',
      'email': 'contact@yde.cm',
      'status': 'Active',
    });
    await db.collection('societes').doc('so2').set({
      'id': 'so2',
      'raisonSociale': 'Eco Yaoundé SA',
      'adresse': 'Bastos',
      'telephone': '+237 222 20 30 40',
      'email': 'contact@yde.cm',
      'status': 'Active',
    });
    await db.collection('agences').doc('ag1').set({
      'id': 'ag1',
      'societe': 'WastePro Yaoundé SARL',
      'societeId': 'so1',
      'ville': 'Yaoundé — Bastos',
      'responsable': 'Jean Dooh',
      'telephone': '+237 677 12 34 56',
      'status': 'Active',
    });
    await db.collection('agences').doc('ag2').set({
      'id': 'ag2',
      'societe': 'Eco Yaoundé SA',
      'societeId': 'so2',
      'ville': 'Yaoundé',
      'responsable': 'Marie Ekwalla',
      'telephone': '+237 690 45 12 78',
      'status': 'Active',
    });
    await db.collection('utilisateurs').doc('us1').set({
      'id': 'us1',
      'nom': 'Chef Bonanjo',
      'telephone': '+237 677 12 34 56',
      'role': 'Agency Manager',
      'agence': 'Yaoundé — Bastos',
      'societeId': 'so1',
      'agenceId': 'ag1',
      'status': 'Active',
      'password': '',
    });
    await db.collection('utilisateurs').doc('us2').set({
      'id': 'us2',
      'nom': 'Chef Yaoundé',
      'telephone': '+237 690 45 12 78',
      'role': 'Agency Manager',
      'agence': 'Yaoundé',
      'societeId': 'so2',
      'agenceId': 'ag2',
      'status': 'Active',
      'password': '',
    });

    // La console du General Administrator de so1 ne doit voir QUE so1.
    final store = FirestoreCompanyStore(
      db: db,
      backend: FakeAuthBackend(),
      societeId: 'so1',
    );
    await store.initialLoad;
    await _settle();

    expect(store.societes.single.raisonSociale, 'WastePro Yaoundé SARL');
    expect(store.agences.single.id, 'ag1');
    expect(store.utilisateurs.single.id, 'us1');
    expect(store.societeNom, 'WastePro Yaoundé SARL');

    store.dispose();
  });

  test('créer un chef d agence crée son compte de connexion scopé', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('societes').doc('so1').set({
      'id': 'so1',
      'raisonSociale': 'WastePro Yaoundé SARL',
      'adresse': 'Bonanjo',
      'telephone': '+237 233 42 10 10',
      'email': 'contact@yde.cm',
      'status': 'Active',
    });
    final backend = FakeAuthBackend();
    final store = FirestoreCompanyStore(
      db: db,
      backend: backend,
      societeId: 'so1',
    );
    await store.initialLoad;
    await _settle();

    // L'entreprise crée une agence puis y nomme un chef.
    await store.addAgence(
      ville: 'Yaoundé — Mokolo',
      responsable: 'Paul Biya Jr',
      telephone: '+237 688 11 22 33',
      status: 'Active',
    );
    final agence = store.agences.single;
    expect(agence.societeId, 'so1');

    await store.addUtilisateur(
      nom: 'Chef Akwa',
      telephone: '+237 699 88 77 66',
      role: 'Agency Manager',
      agence: agence.ville,
      agenceId: agence.id,
      status: 'Active',
      password: 'mdp-chef',
    );

    // Le compte de connexion porte le rôle agency_manager ET le scoping
    // societeId/agenceId : le chef arrivera dans le backoffice de son agence.
    final login = await db.collection('users').doc('+237699887766').get();
    expect(login.exists, isTrue);
    expect(login.data()?['role'], 'agency_manager');
    expect(login.data()?['societeId'], 'so1');
    expect(login.data()?['agenceId'], agence.id);

    final auth = AuthService(db: db, backend: backend);
    final user = await auth.login('+237699887766', 'mdp-chef');
    expect(user, isNotNull);
    expect(user!.role, 'agency_manager');
    expect(user.agenceId, agence.id);

    store.dispose();
  });

  test('supprimer un chef d agence supprime son compte de connexion',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('societes').doc('so1').set({
      'id': 'so1',
      'raisonSociale': 'WastePro Yaoundé SARL',
      'adresse': 'Bonanjo',
      'telephone': '+237 233 42 10 10',
      'email': 'contact@yde.cm',
      'status': 'Active',
    });
    final store = FirestoreCompanyStore(
      db: db,
      backend: FakeAuthBackend(),
      societeId: 'so1',
    );
    await store.initialLoad;
    await _settle();

    await store.addAgence(
      ville: 'Yaoundé — Mokolo',
      responsable: 'Paul Biya Jr',
      telephone: '+237 688 11 22 33',
      status: 'Active',
    );
    final agence = store.agences.single;
    await store.addUtilisateur(
      nom: 'Chef Akwa',
      telephone: '+237 699 88 77 66',
      role: 'Agency Manager',
      agence: agence.ville,
      agenceId: agence.id,
      status: 'Active',
      password: 'mdp-chef',
    );

    await store.deleteUtilisateur(store.utilisateurs.single.id);

    expect(store.utilisateurs, isEmpty);
    expect(
      (await db.collection('users').doc('+237699887766').get()).exists,
      isFalse,
    );

    store.dispose();
  });

  test('le General Administrator de l entreprise est exclu des managers',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('societes').doc('so1').set({
      'id': 'so1',
      'raisonSociale': 'WastePro Yaoundé SARL',
      'adresse': 'Bonanjo',
      'telephone': '+237 233 42 10 10',
      'email': 'contact@yde.cm',
      'status': 'Active',
    });
    // Jean Cams = General Administrator de l'entreprise (créé par le super
    // admin) + deux chefs d'agence.
    await db.collection('utilisateurs').doc('us-ga').set({
      'id': 'us-ga',
      'nom': 'Jean Cams',
      'telephone': '+237 600 00 00 00',
      'role': 'General Administrator',
      'agence': '—',
      'societeId': 'so1',
      'agenceId': '',
      'status': 'Active',
      'password': '',
    });
    await db.collection('utilisateurs').doc('us-m1').set({
      'id': 'us-m1',
      'nom': 'Chef Bastos',
      'telephone': '+237 677 12 34 56',
      'role': 'Agency Manager',
      'agence': 'Yaoundé — Bastos',
      'societeId': 'so1',
      'agenceId': 'ag1',
      'status': 'Active',
      'password': '',
    });
    await db.collection('utilisateurs').doc('us-m2').set({
      'id': 'us-m2',
      'nom': 'Chef Mokolo',
      'telephone': '+237 690 45 12 78',
      'role': 'Agency Manager',
      'agence': 'Yaoundé — Mokolo',
      'societeId': 'so1',
      'agenceId': 'ag2',
      'status': 'Active',
      'password': '',
    });

    final store = FirestoreCompanyStore(
      db: db,
      backend: FakeAuthBackend(),
      societeId: 'so1',
    );
    await store.initialLoad;
    await _settle();

    // Le GA reste dans `utilisateurs` (gestion des comptes) mais jamais
    // dans les listes de managers.
    expect(store.utilisateurs.length, 3);
    expect(store.managers.map((m) => m.nom), ['Chef Bastos', 'Chef Mokolo']);
    expect(store.managersCount, 2);
    expect(store.scopedUtilisateurs.map((m) => m.nom),
        ['Chef Bastos', 'Chef Mokolo']);
    expect(store.managersForAgence('ag1'), 1);
    expect(store.managersForAgence('ag2'), 1);

    store.dispose();
  });
}
