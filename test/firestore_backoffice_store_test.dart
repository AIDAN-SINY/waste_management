import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseException, SetOptions;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/backoffice/data/firestore_backoffice_store.dart';
import 'package:waste_pro/features/backoffice/data/seed_data.dart';

import 'fakes/fake_auth_backend.dart';

/// Lets the snapshot listeners catch up with seed writes / CRUD writes.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'seeds empty collections with the design data + collector whitelist',
    () async {
      final db = FakeFirebaseFirestore();
      final store = FirestoreBackofficeStore(
        db: db,
        backend: FakeAuthBackend(),
      );
      await store.initialLoad;
      await _settle();

      expect(store.error, isNull);
      expect(store.isLoading, isFalse);
      expect(store.clients.length, seedClients.length);
      expect(store.collecteurs.length, seedCollecteurs.length);

      // The seed is correctly written to Firestore (deterministic ids 'cl1'...).
      final clients = await db.collection('clients').get();
      expect(clients.docs.length, seedClients.length);
      final collecteurs = await db.collection('collecteurs').get();
      expect(collecteurs.docs.length, seedCollecteurs.length);

      // Active seeded collectors are pre-approved (whitelist).
      final whitelist = await db.collection('collectors').get();
      final active = seedCollecteurs.where((c) => c.status == 'Active').length;
      expect(whitelist.docs.length, active);

      store.dispose();
    },
  );

  test('keeps existing data and only seeds the empty collections', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('clients').doc('custom').set({
      'id': 'custom',
      'name': 'Client Existant',
      'phone': '+237 600 00 00 00',
      'zone': 'Yaoundé',
      'plan': 'Standard',
      'status': 'Active',
    });

    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
    );
    await store.initialLoad;
    await _settle();

    // The existing document is preserved, not overwritten by the seed.
    expect(store.clients.single.name, 'Client Existant');
    // The empty collectors collection is seeded.
    expect(store.collecteurs.length, seedCollecteurs.length);

    store.dispose();
  });

  test(
    'creating a client with a password creates a real login account',
    () async {
      final db = FakeFirebaseFirestore();
      final store = FirestoreBackofficeStore(
        db: db,
        backend: FakeAuthBackend(),
        seedIfEmpty: false,
      );
      await store.initialLoad;
      await _settle();

      await store.addClient(
        name: 'Claude Nguema',
        phone: '+237 612 34 56 78',
        zone: 'Bonanjo',
        plan: 'Premium',
        status: 'Active',
        password: 'secret123',
      );
      expect(store.clients.single.name, 'Claude Nguema');

      final clientDoc = await db.collection('clients').get();
      expect(clientDoc.docs.single.data()['name'], 'Claude Nguema');

      // The login account exists: client role + Auth uid (the password lives
      // in Firebase Auth, never in the doc), so the person can log in to
      // their client interface.
      final login = await db.collection('users').doc('+237612345678').get();
      expect(login.exists, isTrue);
      expect(login.data()?['role'], 'client');
      expect(login.data()?['uid'], isNotEmpty);
      expect(login.data()?['password'], isNull);
      expect(login.data()?['fullName'], 'Claude Nguema');
      expect(login.data()?['consoleCreated'], isTrue);
      // Not paid at the agency: access only, the client pays in the app.
      expect(login.data()?['subscription_plan'], '');
      expect(login.data()?['isSubscribed'], isFalse);
      expect(store.clients.single.plan, 'None');

      store.dispose();
    },
  );

  test('a client paid in cash: the plan is recorded by the server', () async {
    final db = FakeFirebaseFirestore();
    final cash = <List<String>>[];
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
      recordCashPayment: (phone, plan) async => cash.add([phone, plan]),
    );
    await store.initialLoad;
    await _settle();

    await store.addClient(
      name: 'Cash Client',
      phone: '+237 612 00 00 01',
      zone: 'Bonanjo',
      plan: 'Weekly',
      paidInCash: true,
      status: 'Active',
      password: 'secret123',
    );
    expect(cash, [
      ['+237 612 00 00 01', 'Weekly'],
    ]);
    expect(store.clients.single.plan, 'Weekly');

    // Renewal in cash from the client card.
    await store.updateClient(store.clients.single, cashPlan: 'Daily');
    expect(cash.last, ['+237 612 00 00 01', 'Daily']);
    expect(store.clients.single.plan, 'Daily');

    // A cash subscription needs the client's login (password).
    await expectLater(
      store.addClient(
        name: 'No Login',
        phone: '+237 612 00 00 02',
        zone: 'Bonanjo',
        plan: 'Monthly',
        paidInCash: true,
        status: 'Active',
      ),
      throwsA(isA<Object>()),
    );
    expect(cash, hasLength(2));

    store.dispose();
  });

  test(
    'creating a client without a password creates no login account',
    () async {
      final db = FakeFirebaseFirestore();
      final store = FirestoreBackofficeStore(
        db: db,
        backend: FakeAuthBackend(),
        seedIfEmpty: false,
      );
      await store.initialLoad;
      await _settle();

      await store.addClient(
        name: 'Client Demo',
        phone: '+237 622 22 22 22',
        zone: 'Akwa',
        plan: 'Standard',
        status: 'Active',
      );
      expect(
        (await db.collection('users').doc('+237622222222').get()).exists,
        isFalse,
      );

      store.dispose();
    },
  );

  test('creating a collector with a password creates a collector login + '
      'whitelist entry', () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    await store.addCollecteur(
      name: 'Boris Ndongo',
      phone: '+237 655 00 00 00',
      zone: 'Bonanjo / Akwa',
      rating: 4.7,
      status: 'Active',
      password: 'collector123',
    );
    expect(store.collecteurs.single.name, 'Boris Ndongo');

    final login = await db.collection('users').doc('+237655000000').get();
    expect(login.exists, isTrue);
    expect(login.data()?['role'], 'collector');
    expect(login.data()?['uid'], isNotEmpty);
    expect(login.data()?['password'], isNull);
    expect(login.data()?['fullName'], 'Boris Ndongo');

    // The number is pre-approved for self-registration.
    final whitelist = await db
        .collection('collectors')
        .doc('+237655000000')
        .get();
    expect(whitelist.exists, isTrue);

    store.dispose();
  });

  test('updating name and password keeps the login account in sync', () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    await store.addClient(
      name: 'Claude Nguema',
      phone: '+237 612 34 56 78',
      zone: 'Bonanjo',
      plan: 'Premium',
      status: 'Active',
      password: 'secret123',
    );
    final client = store.clients.first;

    await store.updateClient(
      client.copyWith(name: 'Claude Nguema Jr'),
      password: 'newpass456',
    );

    final login = await db.collection('users').doc('+237612345678').get();
    expect(login.data()?['fullName'], 'Claude Nguema Jr');
    expect(login.data()?['uid'], isNotEmpty);
    expect(login.data()?['password'], isNull);

    store.dispose();
  });

  test(
    'suspending a client removes its login; reactivating recreates it',
    () async {
      final db = FakeFirebaseFirestore();
      final store = FirestoreBackofficeStore(
        db: db,
        backend: FakeAuthBackend(),
        seedIfEmpty: false,
      );
      await store.initialLoad;
      await _settle();

      await store.addClient(
        name: 'Claude Nguema',
        phone: '+237 612 34 56 78',
        zone: 'Bonanjo',
        plan: 'Premium',
        status: 'Active',
        password: 'secret123',
      );
      final client = store.clients.first;

      // Suspended → no more login account (no more login possible).
      await store.updateClient(client.copyWith(status: 'Suspended'));
      expect(
        (await db.collection('users').doc('+237612345678').get()).exists,
        isFalse,
      );

      // Reactivated → the login account is recreated (uid + auth_profiles).
      await store.updateClient(client.copyWith(status: 'Active'));
      final login = await db.collection('users').doc('+237612345678').get();
      expect(login.exists, isTrue);
      expect(login.data()?['uid'], isNotEmpty);
      expect(login.data()?['password'], isNull);

      store.dispose();
    },
  );

  test(
    'an inactive collector gets no login account nor whitelist entry',
    () async {
      final db = FakeFirebaseFirestore();
      final store = FirestoreBackofficeStore(
        db: db,
        backend: FakeAuthBackend(),
        seedIfEmpty: false,
      );
      await store.initialLoad;
      await _settle();

      await store.addCollecteur(
        name: 'Boris Ndongo',
        phone: '+237 655 00 00 00',
        zone: 'Deido',
        rating: 4.0,
        status: 'Inactive',
        password: 'collector123',
      );
      expect(
        (await db.collection('users').doc('+237655000000').get()).exists,
        isFalse,
      );
      expect(
        (await db.collection('collectors').doc('+237655000000').get()).exists,
        isFalse,
      );

      // Reactivated → the login account and the approval are created.
      final collecteur = store.collecteurs.first;
      await store.updateCollecteur(collecteur.copyWith(status: 'Active'));
      expect(
        (await db.collection('users').doc('+237655000000').get()).exists,
        isTrue,
      );
      expect(
        (await db.collection('collectors').doc('+237655000000').get()).exists,
        isTrue,
      );

      store.dispose();
    },
  );

  test('deleting a client removes its console-created login account', () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    await store.addClient(
      name: 'Claude Nguema',
      phone: '+237 612 34 56 78',
      zone: 'Bonanjo',
      plan: 'Premium',
      status: 'Active',
      password: 'secret123',
    );
    await store.deleteClient(store.clients.first.id);

    expect(store.clients, isEmpty);
    expect(
      (await db.collection('users').doc('+237612345678').get()).exists,
      isFalse,
    );

    store.dispose();
  });

  test(
    'passwords never reach Firestore; suspension disables the login and '
    'reactivation restores it without a new password',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend();
      final store = FirestoreBackofficeStore(
        db: db,
        backend: backend,
        seedIfEmpty: false,
      );
      await store.initialLoad;
      await _settle();
      const email = '237612345678@wastepro.cm';

      await store.addClient(
        name: 'Claude Nguema',
        phone: '+237 612 34 56 78',
        zone: 'Bonanjo',
        plan: 'Premium',
        status: 'Active',
        password: 'secret123',
      );
      final client = store.clients.first;
      final clientDoc = await db.collection('clients').doc(client.id).get();
      expect(clientDoc.data()!.containsKey('password'), isFalse);
      expect(await backend.signIn(email: email, password: 'secret123'),
          isNotEmpty);

      // Suspended → login refused, same Auth account kept.
      await store.updateClient(client.copyWith(status: 'Suspended'));
      expect(backend.isDisabled(email), isTrue);

      // Reactivated without retyping the password → login works again.
      await store.updateClient(client.copyWith(status: 'Active'));
      expect(backend.isDisabled(email), isFalse);
      final login = await db.collection('users').doc('+237612345678').get();
      expect(login.data()?['uid'], isNotEmpty);
      expect(await backend.signIn(email: email, password: 'secret123'),
          login.data()?['uid']);

      // Deleted → login profile, rules profile and Auth account are gone.
      final uid = login.data()!['uid'] as String;
      await store.deleteClient(client.id);
      expect((await db.collection('auth_profiles').doc(uid).get()).exists,
          isFalse);
      expect(backend.hasAccount(email), isFalse);

      store.dispose();
    },
  );

  test(
    'approval gives access only; editing the card never activates the plan',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = FakeAuthBackend();
      final store = FirestoreBackofficeStore(
        db: db,
        backend: backend,
        seedIfEmpty: false,
      );
      await store.initialLoad;
      await _settle();
      const phone = '+237698220011';
      // Account created at pre-registration.
      const email = '237698220011@wastepro.cm';
      backend.seedAccount(email, 'secret123');

      await db.collection('users').doc(phone).set({
        'phoneNumber': phone,
        'role': 'pending_client',
        'uid': backend.uidFor(email),
        'fcmToken': 'device-token',
      });
      await db.collection('registrations').doc('rgP').set({
        'id': 'rgP',
        'fullName': 'Paul Payer',
        'phone': phone,
        'zone': 'Bastos',
        'agenceId': 'ag1',
        'agenceName': 'Yaoundé',
        'societeId': 'so1',
        'status': 'pending',
        'createdAt': '2026-10-05',
      });
      await _settle();
      await store.approveRegistration(
        store.registrations.single,
        collecteurId: 'co1',
      );

      // Access granted, no subscription until the client pays.
      var login = (await db.collection('users').doc(phone).get()).data()!;
      expect(login['role'], 'client');
      expect(login['isSubscribed'], isFalse);
      expect(login['subscription_plan'], '');
      expect(login['fcmToken'], 'device-token');
      final client = store.clients.single;
      expect(client.plan, 'None');

      // The client paid in the app (server-side fields).
      await db.collection('users').doc(phone).set({
        'active_contract_id': 'CTR-1',
        'collection_days': ['Monday'],
      }, SetOptions(merge: true));

      // Editing the card (name only) changes neither the subscription nor
      // the server-set fields.
      await store.updateClient(client.copyWith(name: 'Paul P.'));
      login = (await db.collection('users').doc(phone).get()).data()!;
      expect(login['fullName'], 'Paul P.');
      expect(login['isSubscribed'], isFalse);
      expect(login['active_contract_id'], 'CTR-1');
      expect(login['collection_days'], ['Monday']);
      expect(login['fcmToken'], 'device-token');

      // Changing the plan on the card alone grants nothing: only a recorded
      // payment (cash at the agency, or the app) does.
      await store.updateClient(
        store.clients.single.copyWith(plan: 'Daily'),
      );
      login = (await db.collection('users').doc(phone).get()).data()!;
      expect(login['isSubscribed'], isFalse);
      expect(store.clients.single.plan, 'None');

      store.dispose();
    },
  );

  test('deleting a collecteur removes its whitelist entry too', () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    await store.addCollecteur(
      name: 'Boris Ndongo',
      phone: '+237 655 00 00 00',
      zone: 'Bonanjo',
      rating: 4.7,
      status: 'Active',
      password: 'collector123',
    );
    await store.deleteCollecteur(store.collecteurs.first.id);

    expect(store.collecteurs, isEmpty);
    expect(
      (await db.collection('users').doc('+237655000000').get()).exists,
      isFalse,
    );
    expect(
      (await db.collection('collectors').doc('+237655000000').get()).exists,
      isFalse,
    );

    store.dispose();
  });

  test(
    'never deletes a real account when removing an entity sharing its phone',
    () async {
      final db = FakeFirebaseFirestore();
      // A real client account already exists for this number (no console marker)
      // — and a backoffice collector references the same number.
      await db.collection('users').doc('+237655000000').set({
        'phoneNumber': '+237655000000',
        'fullName': 'Client Réel',
        'role': 'client',
      });
      await db.collection('collecteurs').doc('x1').set({
        'id': 'x1',
        'name': 'Ancien collecteur',
        'phone': '+237 655 00 00 00',
        'zone': 'Akwa',
        'rating': 4.0,
        'status': 'Inactive',
      });

      final store = FirestoreBackofficeStore(
        db: db,
        backend: FakeAuthBackend(),
        seedIfEmpty: false,
      );
      await store.initialLoad;
      await _settle();

      await store.deleteCollecteur('x1');

      // Le compte client réel n'a pas été supprimé.
      final real = await db.collection('users').doc('+237655000000').get();
      expect(real.exists, isTrue);
      expect(real.data()?['role'], 'client');

      store.dispose();
    },
  );

  test('never clobbers an existing real account with the same phone', () async {
    final db = FakeFirebaseFirestore();
    // Un client réel existe déjà avec ce numéro (pas de marqueur console).
    await db.collection('users').doc('+237688888888').set({
      'phoneNumber': '+237688888888',
      'fullName': 'Client Existant',
      'role': 'client',
    });

    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    await expectLater(
      store.addClient(
        name: 'Faux Client',
        phone: '+237 688 88 88 88',
        zone: 'Akwa',
        plan: 'Standard',
        status: 'Active',
        password: 'hack',
      ),
      throwsA(isA<Exception>()),
    );

    // Le compte client réel n'a pas été écrasé.
    final client = await db.collection('users').doc('+237688888888').get();
    expect(client.data()?['role'], 'client');
    // Et aucun client n'a été créé dans la collection du backoffice.
    expect(store.clients, isEmpty);

    store.dispose();
  });

  test('permission-denied after logout does not trigger a banner',
      () async {
    final db = FakeFirebaseFirestore();
    // Simulates a revoked Firebase Auth session (logout): still-active listeners
    // are rejected by rules → no error displayed.
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
      isSignedOut: () => true,
    );
    await store.initialLoad;
    await _settle();

    store.handleStreamError(
      FirebaseException(plugin: 'firestore', code: 'permission-denied'),
    );

    expect(store.error, isNull,
        reason: 'Après logout, permission-denied est attendu — pas une erreur.');
    expect(store.isLoading, isFalse);

    store.dispose();
  });

  test('permission-denied pendant une session active affiche l erreur',
      () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
      isSignedOut: () => false,
    );
    await store.initialLoad;
    await _settle();

    store.handleStreamError(
      FirebaseException(plugin: 'firestore', code: 'permission-denied'),
    );

    expect(store.error, contains('Access denied'));

    store.dispose();
  });

  test('scoped store only sees the connected agency data (Phase 3)', () async {
    final db = FakeFirebaseFirestore();
    // Des clients et collecteurs de DEUX agences différentes.
    await db.collection('clients').doc('clA').set({
      'id': 'clA',
      'name': 'Client A',
      'phone': '+237 611 11 11 11',
      'zone': 'Bonanjo',
      'plan': 'Standard',
      'status': 'Active',
      'agenceId': 'agA',
      'societeId': 'so1',
    });
    await db.collection('clients').doc('clB').set({
      'id': 'clB',
      'name': 'Client B',
      'phone': '+237 622 22 22 22',
      'zone': 'Akwa',
      'plan': 'Standard',
      'status': 'Active',
      'agenceId': 'agB',
      'societeId': 'so1',
    });
    await db.collection('collecteurs').doc('coA').set({
      'id': 'coA',
      'name': 'Collecteur A',
      'phone': '+237 655 11 11 11',
      'zone': 'Bonanjo',
      'rating': 4.5,
      'status': 'Active',
      'agenceId': 'agA',
    });
    await db.collection('collecteurs').doc('coB').set({
      'id': 'coB',
      'name': 'Collecteur B',
      'phone': '+237 655 22 22 22',
      'zone': 'Akwa',
      'rating': 4.0,
      'status': 'Active',
      'agenceId': 'agB',
    });

    // Le chef d'agence de agA ne voit QUE les données de agA.
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
      agenceId: 'agA',
      societeId: 'so1',
    );
    await store.initialLoad;
    await _settle();

    expect(store.clients.single.id, 'clA');
    expect(store.collecteurs.single.id, 'coA');

    // Créer un client le rattache automatiquement à l'agence du chef.
    await store.addClient(
      name: 'Nouveau Client',
      phone: '+237 633 33 33 33',
      zone: 'Bonanjo',
      plan: 'Premium',
      status: 'Active',
      password: 'secret',
    );
    expect(store.clients.firstWhere((c) => c.name == 'Nouveau Client').agenceId,
        'agA');

    store.dispose();
  });

  test(
    'approving a registration creates the client + its login account',
    () async {
      final db = FakeFirebaseFirestore();
      final store = FirestoreBackofficeStore(
        db: db,
        backend: FakeAuthBackend(),
        seedIfEmpty: false,
      );
      await store.initialLoad;
      await _settle();

      await db.collection('registrations').doc('rgX').set({
        'id': 'rgX',
        'fullName': 'Carine Mbappe',
        'phone': '+237 698 22 44 66',
        'zone': 'Bonanjo',
        'agenceId': 'ag1',
        'agenceName': 'Yaoundé — Bastos',
        'societeId': 'so1',
        'status': 'pending',
        'collecteurId': '',
        'password': 'secret123',
        'createdAt': '2026-08-10',
      });
      await _settle();
      expect(store.registrations.single.status, 'pending');

      await store.approveRegistration(
        store.registrations.single,
        collecteurId: 'co1',
      );

      // Candidature approuvée avec le collecteur assigné (Firestore).
      final regDoc = await db.collection('registrations').doc('rgX').get();
      expect(regDoc.data()?['status'], 'approved');
      expect(regDoc.data()?['collecteurId'], 'co1');

      // Client créé, rattaché à l'agence + au collecteur.
      final client = store.clients.singleWhere(
        (c) => c.name == 'Carine Mbappe',
      );
      expect(client.collecteurId, 'co1');
      expect(client.agenceId, 'ag1');
      expect(client.zone, 'Bonanjo');

      // Compte de connexion : uid Auth + auth_profiles (le mot de passe
      // choisi par le client vit dans Auth, pas dans Firestore).
      final login = await db.collection('users').doc('+237698224466').get();
      expect(login.exists, isTrue);
      expect(login.data()?['role'], 'client');
      expect(login.data()?['uid'], isNotEmpty);
      expect(login.data()?['password'], isNull);
      expect(login.data()?['fullName'], 'Carine Mbappe');

      // Le client est notifié dans l'app (cloche du dashboard).
      final notif = await db
          .collection('notifications')
          .doc('notifrgX')
          .get();
      expect(notif.exists, isTrue);
      expect(notif.data()?['phone'], '+237698224466');
      expect(notif.data()?['type'], 'approved');
      expect(notif.data()?['read'], false);
      expect(notif.data()?['title'], 'Application approved');

      store.dispose();
    },
  );

  test('rejecting a registration marks it rejected without creating a client',
      () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    await db.collection('registrations').doc('rgX').set({
      'id': 'rgX',
      'fullName': 'Carine Mbappe',
      'phone': '+237 698 22 44 66',
      'zone': 'Bonanjo',
      'agenceId': 'ag1',
      'agenceName': 'Yaoundé — Bastos',
      'societeId': 'so1',
      'status': 'pending',
      'collecteurId': '',
      'password': 'secret123',
      'createdAt': '2026-08-10',
    });
    await _settle();

    await store.rejectRegistration(store.registrations.single);

    final regDoc = await db.collection('registrations').doc('rgX').get();
    expect(regDoc.data()?['status'], 'rejected');
    expect(store.registrations.single.status, 'rejected');
    expect(store.clients, isEmpty);
    expect(
      (await db.collection('users').doc('+237698224466').get()).exists,
      isFalse,
    );

    // Le client est notifié du rejet (cloche du dashboard).
    final notif = await db
        .collection('notifications')
        .doc('notifrgX')
        .get();
    expect(notif.exists, isTrue);
    expect(notif.data()?['phone'], '+237698224466');
    expect(notif.data()?['type'], 'rejected');
    expect(notif.data()?['read'], false);

    store.dispose();
  });

  test(      'reassigning a collector updates the client, the login account and '
    'the upcoming collections',
    () async {
      final db = FakeFirebaseFirestore();
      final store = FirestoreBackofficeStore(
        db: db,
        backend: FakeAuthBackend(),
        seedIfEmpty: false,
      );
      await store.initialLoad;
      await _settle();

      // Collecteurs connus (résolution id → nom).
      await db.collection('collecteurs').doc('co1').set({
        'id': 'co1',
        'name': 'Paul Mbarga',
        'phone': '+237 678 90 11 22',
        'zone': 'Bonanjo / Akwa',
        'rating': 4.8,
        'status': 'Active',
      });
      await db.collection('collecteurs').doc('co2').set({
        'id': 'co2',
        'name': 'Vincent Onana',
        'phone': '+237 693 55 44 33',
        'zone': 'Bonapriso / Bali',
        'rating': 4.5,
        'status': 'Active',
      });
      // Client assigné à Paul Mbarga + son compte de connexion console.
      await db.collection('clients').doc('clX').set({
        'id': 'clX',
        'name': 'Carine Mbappe',
        'phone': '+237 698 22 44 66',
        'zone': 'Bonanjo',
        'plan': 'Standard',
        'status': 'Active',
        'agenceId': 'ag1',
        'societeId': 'so1',
        'collecteurId': 'co1',
      });
      await db.collection('users').doc('+237698224466').set({
        'phoneNumber': '+237698224466',
        'fullName': 'Carine Mbappe',
        'role': 'client',
        'uid': 'uid-legacy-client',
        'consoleCreated': true,
        'agenceId': 'ag1',
        'societeId': 'so1',
        'collecteurId': 'co1',
      });
      // Collectes : une à venir (Scheduled) + une effectuée, par co1.
      await db.collection('collectes').doc('ccX').set({
        'id': 'ccX',
        'client': 'Carine Mbappe',
        'collecteur': 'Paul Mbarga',
        'date': '2026-08-12',
        'poids': 0,
        'status': 'Scheduled',
      });
      await db.collection('collectes').doc('ccY').set({
        'id': 'ccY',
        'client': 'Carine Mbappe',
        'collecteur': 'Paul Mbarga',
        'date': '2026-08-05',
        'poids': 4.1,
        'status': 'Completed',
      });
      await _settle();

      await store.reassignCollecteur(clientId: 'clX', collecteurId: 'co2');

      // 1. La fiche client porte le nouveau collecteur.
      final clientDoc = await db.collection('clients').doc('clX').get();
      expect(clientDoc.data()?['collecteurId'], 'co2');
      // 2. Le compte de connexion est mis à jour (l'app client le sait).
      final login = await db.collection('users').doc('+237698224466').get();
      expect(login.data()?['collecteurId'], 'co2');
      // 3. La collecte à venir bascule, l'historique effectué ne change pas.
      final upcoming = await db.collection('collectes').doc('ccX').get();
      expect(upcoming.data()?['collecteur'], 'Vincent Onana');
      final done = await db.collection('collectes').doc('ccY').get();
      expect(done.data()?['collecteur'], 'Paul Mbarga');

      store.dispose();
    },
  );

  test('reassigning works even when the client has no login account',
      () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    await db.collection('collecteurs').doc('co1').set({
      'id': 'co1',
      'name': 'Paul Mbarga',
      'phone': '+237 678 90 11 22',
      'zone': 'Bonanjo / Akwa',
      'rating': 4.8,
      'status': 'Active',
    });
    await db.collection('collecteurs').doc('co2').set({
      'id': 'co2',
      'name': 'Vincent Onana',
      'phone': '+237 693 55 44 33',
      'zone': 'Bonapriso / Bali',
      'rating': 4.5,
      'status': 'Active',
    });
    // Client sans compte de connexion (créé sans mot de passe).
    await db.collection('clients').doc('clY').set({
      'id': 'clY',
      'name': 'Client Sans Compte',
      'phone': '+237 600 00 00 00',
      'zone': 'Akwa',
      'plan': 'Essential',
      'status': 'Active',
      'agenceId': 'ag1',
      'societeId': 'so1',
      'collecteurId': 'co1',
    });
    await _settle();

    // Ne doit PAS lever d'erreur (pas de users/{phone} à mettre à jour).
    await store.reassignCollecteur(clientId: 'clY', collecteurId: 'co2');

    final clientDoc = await db.collection('clients').doc('clY').get();
    expect(clientDoc.data()?['collecteurId'], 'co2');

    store.dispose();
  });

  test('changing the phone number migrates the login account', () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    await store.addClient(
      name: 'Claude Nguema',
      phone: '+237 612 34 56 78',
      zone: 'Bonanjo',
      plan: 'Premium',
      status: 'Active',
      password: 'secret123',
    );
    final client = store.clients.first;

    await store.updateClient(client.copyWith(phone: '+237 699 99 99 99'));

    // L'ancien compte de connexion est migré vers le nouveau numéro.
    expect(
      (await db.collection('users').doc('+237612345678').get()).exists,
      isFalse,
    );
    final moved = await db.collection('users').doc('+237699999999').get();
    expect(moved.exists, isTrue);
    expect(moved.data()?['uid'], isNotEmpty);
    expect(moved.data()?['password'], isNull);

    store.dispose();
  });

  test('collector pickups appear live in the Collections list', () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    // A client of the agency.
    await db.collection('clients').doc('clP').set({
      'id': 'clP',
      'name': 'Alice Njoya',
      'phone': '+237699000001',
      'zone': 'Bastos',
      'plan': 'Standard',
      'status': 'Active',
      'agenceId': 'ag1',
      'societeId': 'so1',
    });
    await _settle();

    // The collector's app writes a pickup awaiting client confirmation.
    await db.collection('pickups').doc('PKP-1').set({
      'client_id': '+237699000001',
      'collector_id': 'co1',
      'collector_name': 'Paul Mbarga',
      'date': '2026-09-09',
      'poids': 4.5,
      'status': 'pending_client_confirmation',
    });
    await _settle();

    // Mirrored as Scheduled (awaiting the client's QR validation).
    final pending = store.collectes.where((c) => c.id == 'pkp:PKP-1').toList();
    expect(pending.length, 1);
    expect(pending.single.status, 'Scheduled');
    expect(pending.single.client, 'Alice Njoya');
    expect(pending.single.collecteur, 'Paul Mbarga');

    // The client scans the QR code → verified → Completed in real time.
    await db.collection('pickups').doc('PKP-1').update({
      'status': 'verified',
    });
    await _settle();
    expect(
      store.collectes.firstWhere((c) => c.id == 'pkp:PKP-1').status,
      'Completed',
    );

    store.dispose();
  });

  test('approving a registration copies the picked GPS point onto the client',
      () async {
    final db = FakeFirebaseFirestore();
    final store = FirestoreBackofficeStore(
      db: db,
      backend: FakeAuthBackend(),
      seedIfEmpty: false,
    );
    await store.initialLoad;
    await _settle();

    // A collector to assign.
    await store.addCollecteur(
      name: 'Paul Mbarga',
      phone: '+237 655 00 11 22',
      zone: 'Bastos',
      rating: 4.5,
      status: 'Active',
      password: 'collect123',
    );
    final collector = store.collecteurs.first;

    // Registration carrying the map-picked coordinates.
    await db.collection('registrations').doc('regGPS').set({
      'id': 'regGPS',
      'fullName': 'Alice Njoya',
      'phone': '+237699000002',
      'zone': 'Nlongkak',
      'agenceId': 'ag1',
      'agenceName': 'Yaoundé — Bastos',
      'societeId': 'so1',
      'status': 'pending',
      'password': 'client123',
      'latitude': 3.8687,
      'longitude': 11.5142,
      'createdAt': '2026-09-09',
    });
    await _settle();
    final reg = store.registrations.firstWhere((r) => r.id == 'regGPS');
    expect(reg.latitude, 3.8687);
    expect(reg.longitude, 11.5142);

    await store.approveRegistration(reg, collecteurId: collector.id);
    await _settle();

    final client = store.clients.firstWhere((c) => c.phone == '+237699000002');
    expect(client.latitude, 3.8687);
    expect(client.longitude, 11.5142);

    // The collector's tour (clients collection) now has the GPS point.
    final clientDoc = await db.collection('clients').doc(client.id).get();
    expect(clientDoc.data()?['latitude'], 3.8687);
    expect(clientDoc.data()?['longitude'], 11.5142);

    store.dispose();
  });
}
