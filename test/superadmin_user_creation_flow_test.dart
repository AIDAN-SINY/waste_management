import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/superadmin/data/firestore_platform_store.dart';
import 'package:waste_pro/features/superadmin/super_admin_console.dart';
import 'package:waste_pro/services/auth_service.dart';

import 'fakes/fake_auth_backend.dart';

import 'helpers/setup_firebase.dart';

/// End-to-end flow: the superadmin creates a user in the console
/// (real Firestore store), the login account `users/{phone}`
/// is written with the Auth uid (password lives in Firebase Auth), and
/// this user can log in with their phone + password.
void main() {
  setUpAll(() => setupFirebaseMocks());

  testWidgets(
      'superadmin creates a user via drawer → user can log in',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final backend = FakeAuthBackend();
    final store = FirestorePlatformStore(
      db: db,
      backend: backend,
      seedIfEmpty: false,
      isSignedOut: () => false,
    );
    await store.initialLoad;

    // Desktop console with real Firestore store (as after a super admin login).
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: SuperAdminConsole(store: store, db: db)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    // With a real Firestore store, no "demo preview" banner.
    expect(find.textContaining('Demo preview'), findsNothing);

    // Aller sur la page Utilisateurs et ouvrir le drawer « New user ».
    // ("Users" also appears elsewhere: target the first one, the sidebar.)
    await tester.tap(find.text('Users').first);
    await tester.pumpAndSettle();
    expect(find.text('New user'), findsOneWidget);
    await tester.tap(find.text('New user'));
    await tester.pumpAndSettle();
    expect(find.text('Full name'), findsOneWidget);

    // Fill in the form: name, phone, password.
    await tester.enterText(find.byType(TextFormField).at(0), 'Marie Ekwalla');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      '+237 699 99 99 99',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'secret123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // No errors during creation. Flush the success toast timer.
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));

    // Le compte de connexion a bien été écrit dans `users` (rôle
    // agency_manager + uid Auth — le mot de passe vit dans Firebase Auth).
    final loginDoc = await db.collection('users').doc('+237699999999').get();
    expect(loginDoc.exists, isTrue,
        reason: 'the console must create the login account users/{phone}');
    // Default drawer role = Agency Manager → login role
    // agency_manager (Phase 1: real role, no longer the generic 'admin').
    expect(loginDoc.data()?['role'], 'agency_manager');
    expect(loginDoc.data()?['uid'], isNotEmpty);
    expect(loginDoc.data()?['password'], isNull,
        reason: 'no more plaintext password in Firestore');
    expect(loginDoc.data()?['fullName'], 'Marie Ekwalla');
    expect(loginDoc.data()?['consoleCreated'], isTrue);

    // The created user logs in with their phone + the password set by
    // the superadmin.
    final auth = AuthService(db: db, backend: backend);
    final user = await auth.login('+237 699 99 99 99', 'secret123');
    expect(user, isNotNull,
        reason: 'the user created by the superadmin must be able to '
            'log in with phone + password');
    expect(user!.fullName, 'Marie Ekwalla');
    expect(user.role, 'agency_manager');

    store.dispose();
  });

  testWidgets('un mauvais mot de passe est rejeté pour un user créé en console',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final backend = FakeAuthBackend();
    final store = FirestorePlatformStore(
      db: db,
      backend: backend,
      seedIfEmpty: false,
      isSignedOut: () => false,
    );
    await store.initialLoad;

    // Création via la console (comme dans le parcours réel du superadmin).
    await store.addUtilisateur(
      nom: 'Jean Dooh',
      telephone: '+237 677 12 34 56',
      role: 'Agency Manager',
      agence: 'Yaoundé — Bastos',
      status: 'Active',
      password: 'mdp-cons',
    );

    final auth = AuthService(db: db, backend: backend);
    expect(
      () => auth.login('+237677123456', 'mauvais'),
      throwsA('Incorrect Password'),
    );
    // Et le bon mot de passe fonctionne.
    final user = await auth.login('+237677123456', 'mdp-cons');
    expect(user, isNotNull);
    expect(user!.role, 'agency_manager');

    store.dispose();
  });

  test('le rôle de connexion reflète le rôle console (Phase 1)', () async {
    final db = FakeFirebaseFirestore();
    final backend = FakeAuthBackend();
    final store = FirestorePlatformStore(
      db: db,
      backend: backend,
      seedIfEmpty: false,
      isSignedOut: () => false,
    );
    await store.initialLoad;

    // General Administrator → general_admin (console entreprise).
    await store.addUtilisateur(
      nom: 'Cheffe Entreprise',
      telephone: '+237 699 44 44 44',
      role: 'General Administrator',
      agence: '—',
      status: 'Active',
      password: 'mdp-ga',
    );
    // Agency Manager → agency_manager (backoffice de son agence).
    await store.addUtilisateur(
      nom: 'Chef Agence',
      telephone: '+237 699 55 55 55',
      role: 'Agency Manager',
      agence: 'Yaoundé',
      status: 'Active',
      password: 'mdp-am',
    );

    final auth = AuthService(db: db, backend: backend);
    final ga = await auth.login('+237699444444', 'mdp-ga');
    expect(ga, isNotNull);
    expect(ga!.role, 'general_admin');
    final am = await auth.login('+237699555555', 'mdp-am');
    expect(am, isNotNull);
    expect(am!.role, 'agency_manager');

    store.dispose();
  });

  testWidgets('création sans téléphone est bloquée (pas de compte de connexion)',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final store = FirestorePlatformStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
      isSignedOut: () => false,
    );
    await store.initialLoad;

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: SuperAdminConsole(store: store, db: db)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Users').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New user'));
    await tester.pumpAndSettle();
    expect(find.text('Full name'), findsOneWidget);

    // Nom + mot de passe, MAIS pas de téléphone → la sauvegarde doit être
    // refusée (le compte de connexion users/{phone} n aurait pas de clé).
    await tester.enterText(find.byType(TextFormField).at(0), 'Marie Ekwalla');
    await tester.enterText(find.byType(TextFormField).at(2), 'secret123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Toast d'erreur + le drawer reste ouvert pour corriger.
    expect(find.text('The field "Phone" is required.'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);

    // Rien n'a été écrit : ni l'utilisateur, ni un compte de connexion.
    final utilisateurs = await db.collection('utilisateurs').get();
    expect(utilisateurs.docs, isEmpty);
    final users = await db.collection('users').get();
    expect(users.docs, isEmpty);

    // Flush le timer du toast (3 s) pour que le test se termine proprement.
    await tester.pump(const Duration(seconds: 4));

    store.dispose();
  });

  test('addUtilisateur avec mot de passe mais téléphone vide → erreur (backstop)',
      () async {
    final db = FakeFirebaseFirestore();
    final store = FirestorePlatformStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
      isSignedOut: () => false,
    );
    await store.initialLoad;

    // Backstop côté store : même sans passer par le formulaire, un user avec
    // un mot de passe mais sans numéro doit être refusé — jamais un utilisateur
    // « fantôme » incapable de se connecter.
    expect(
      () => store.addUtilisateur(
        nom: 'Sans Numéro',
        telephone: '',
        role: 'Agency Manager',
        agence: '—',
        status: 'Active',
        password: 'secret123',
      ),
      throwsA(
        predicate(
          (e) => e.toString().contains('phone number is required'),
        ),
      ),
    );

    final utilisateurs = await db.collection('utilisateurs').get();
    expect(utilisateurs.docs, isEmpty);
    final users = await db.collection('users').get();
    expect(users.docs, isEmpty);

    store.dispose();
  });

  test('changer le téléphone d un utilisateur migre son compte de connexion',
      () async {
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
      nom: 'Marie Ekwalla',
      telephone: '+237 699 11 11 11',
      role: 'Agency Manager',
      agence: 'Yaoundé — Bastos',
      status: 'Active',
      password: 'secret123',
    );
    final created = store.utilisateurs.single;

    // Le compte d'origine fonctionne.
    final auth = AuthService(db: db, backend: backend);
    expect((await auth.login('+237699111111', 'secret123'))?.fullName,
        'Marie Ekwalla');

    // Le superadmin change le numéro de l'utilisateur.
    await store.updateUtilisateur(
      created.copyWith(telephone: '+237 699 22 22 22'),
    );

    // L'ancien compte de connexion a été supprimé : l'ancien numéro ne se
    // connecte plus, le nouveau fonctionne.
    final oldDoc = await db.collection('users').doc('+237699111111').get();
    expect(oldDoc.exists, isFalse,
        reason: 'l ancien compte users/{oldPhone} doit être supprimé');
    expect(await auth.login('+237699111111', 'secret123'), isNull);
    final migrated =
        await auth.login('+237699222222', 'secret123');
    expect(migrated, isNotNull);
    expect(migrated!.fullName, 'Marie Ekwalla');

    store.dispose();
  });

  test('deux utilisateurs console ne peuvent pas partager le même numéro',
      () async {
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
      nom: 'Premier',
      telephone: '+237 699 33 33 33',
      role: 'Agency Manager',
      agence: 'Yaoundé',
      status: 'Active',
      password: 'mdp-1',
    );

    // Même numéro pour un second utilisateur → refusé, et rien d'écrit.
    expect(
      () => store.addUtilisateur(
        nom: 'Second',
        telephone: '+237 699 33 33 33',
        role: 'Agency Manager',
        agence: 'Yaoundé',
        status: 'Active',
        password: 'mdp-2',
      ),
      throwsA(predicate((e) => e.toString().contains('already uses this number'))),
    );

    final utilisateurs = await db.collection('utilisateurs').get();
    expect(utilisateurs.docs, hasLength(1),
        reason: 'le second utilisateur ne doit pas être créé');

    // Le compte de connexion du premier est intact : son mot de passe marche,
    // celui du second (jamais créé) est rejeté.
    final auth = AuthService(db: db, backend: backend);
    expect((await auth.login('+237699333333', 'mdp-1'))?.fullName, 'Premier');
    expect(
      () => auth.login('+237699333333', 'mdp-2'),
      throwsA('Incorrect Password'),
    );

    store.dispose();
  });
}
