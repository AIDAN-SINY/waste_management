import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/superadmin/data/platform_store.dart';

void main() {
  test('renaming a société cascades to its agences', () {
    final store = PlatformStore();

    store.updateSociete(
      store.societes.first.copyWith(raisonSociale: 'WastePro Yaoundé SAS'),
    );

    expect(
      store.agences.where((a) => a.societe == 'WastePro Yaoundé SARL'),
      isEmpty,
    );
    expect(
      store.agences.where((a) => a.societe == 'WastePro Yaoundé SAS').length,
      2,
    );
  });

  test('dashboard helpers count the design data correctly', () {
    final store = PlatformStore();

    // Seed: 3 companies (2 Active), 4 agencies, 4 users.
    expect(store.societesActives, 2);
    expect(store.agencesCount, 4);
    expect(store.utilisateursCount, 4);
  });

  test('agency helpers scope clients, collectors and managers per agency',
      () {
    final store = PlatformStore();

    // ag1 (Yaoundé — Bastos): Jean Dooh is the seeded manager, 3 clients,
    // 2 collecteurs (seedClientsParAgence / seedCollecteursParAgence).
    final managers = store.managersForAgence('ag1');
    expect(managers.map((m) => m.nom), ['Jean Dooh']);

    final clients = store.clientsForAgence('ag1');
    expect(clients.length, 3);
    expect(clients.every((c) => c.agenceId == 'ag1'), isTrue);

    final collecteurs = store.collecteursForAgence('ag1');
    expect(collecteurs.length, 2);
    expect(collecteurs.every((c) => c.agenceId == 'ag1'), isTrue);

    // An agency with no seeded collector returns an empty list.
    expect(store.collecteursForAgence('ag2').length, 1);
  });

  test('company helpers scope agencies, managers, clients and collectors '
      'per company', () {
    final store = PlatformStore();

    // so1 (WastePro Yaoundé SARL) owns ag1 + ag2 (seed data).
    final agences = store.agencesForSociete('so1');
    expect(agences.length, 2);
    expect(agences.every((a) => a.societeId == 'so1'), isTrue);

    // Managers = company users: Jean Dooh, Aïcha Bello
    // (agences de so1) + Platform Admin (societeId so1).
    final managers = store.managersForSociete('so1');
    expect(managers.length, 3);
    expect(
      managers.map((m) => m.nom),
      ['Jean Dooh', 'Aïcha Bello', 'Platform Admin'],
    );

    // Clients = 3 (ag1) + 2 (ag2).
    final clients = store.clientsForSociete('so1');
    expect(clients.length, 5);
    expect(clients.every((c) => c.societeId == 'so1'), isTrue);

    // Collecteurs = 2 (ag1) + 1 (ag2).
    final collecteurs = store.collecteursForSociete('so1');
    expect(collecteurs.length, 3);
    expect(collecteurs.every((c) => c.societeId == 'so1'), isTrue);

    // so3 (EcoCollecte Kribi) has only one seeded agency → 1 client,
    // 1 collecteur.
    expect(store.agencesForSociete('so3').length, 1);
    expect(store.clientsForSociete('so3').length, 1);
    expect(store.collecteursForSociete('so3').length, 1);
  });
}
