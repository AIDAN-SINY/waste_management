import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/backoffice/data/backoffice_store.dart';

void main() {
  group('BackofficeStore.reassignCollecteur', () {
    test('updates the client and only their upcoming collections', () async {
      final store = BackofficeStore();

      // Aïcha Bello (cl4) is assigned to Paul Mbarga (co1); her collection
      // cc3 (Scheduled) is carried by Paul Mbarga.
      final cl4 = store.clients.firstWhere((c) => c.id == 'cl4');
      expect(cl4.collecteurId, 'co1');
      expect(store.collectes.firstWhere((c) => c.id == 'cc3').collecteur,
          'Paul Mbarga');

      await store.reassignCollecteur(clientId: 'cl4', collecteurId: 'co2');

      // The client record carries the new collector.
      expect(store.clients.firstWhere((c) => c.id == 'cl4').collecteurId, 'co2');

      // The upcoming collection switches to Vincent Onana.
      expect(store.collectes.firstWhere((c) => c.id == 'cc3').collecteur,
          'Vincent Onana');

      // History (completed collection) does not change.
      expect(store.collectes.firstWhere((c) => c.id == 'cc1').collecteur,
          'Paul Mbarga');
    });

    test('does not touch collections of other clients', () async {
      final store = BackofficeStore();

      await store.reassignCollecteur(clientId: 'cl4', collecteurId: 'co2');

      // Marie Ekwalla (cl2, co2) et sa collecte cc2 (Completed, Vincent Onana)
      // restent intactes.
      expect(store.clients.firstWhere((c) => c.id == 'cl2').collecteurId, 'co2');
      expect(store.collectes.firstWhere((c) => c.id == 'cc2').collecteur,
          'Vincent Onana');
    });

    test('does nothing when the collector is the same', () async {
      final store = BackofficeStore();

      await store.reassignCollecteur(clientId: 'cl1', collecteurId: 'co1');

      expect(store.clients.firstWhere((c) => c.id == 'cl1').collecteurId, 'co1');
      expect(store.collectes.firstWhere((c) => c.id == 'cc1').collecteur,
          'Paul Mbarga');
    });

    test('an unknown client is a no-op', () async {
      final store = BackofficeStore();
      final count = store.clients.length;

      await store.reassignCollecteur(clientId: 'nope', collecteurId: 'co2');

      expect(store.clients.length, count);
    });
  });

  group('BackofficeStore.notifications', () {
    test('approving an application creates an approved notification', () async {
      final store = BackofficeStore();
      final reg = store.pendingRegistrations.first;

      await store.approveRegistration(reg, collecteurId: 'co1');

      final notif = store.notifications.single;
      expect(notif.id, 'notif${reg.id}');
      expect(notif.type, 'approved');
      expect(notif.title, 'Application approved');
      expect(notif.read, isFalse);
    });

    test('rejecting an application creates a rejected notification', () async {
      final store = BackofficeStore();
      final reg = store.pendingRegistrations.first;

      await store.rejectRegistration(reg);

      final notif = store.notifications.single;
      expect(notif.type, 'rejected');
      expect(notif.title, 'Application rejected');
    });

    test('a new decision on the same application replaces the notification',
        () async {
      final store = BackofficeStore();
      final reg = store.pendingRegistrations.first;

      await store.rejectRegistration(reg);
      await store.approveRegistration(reg, collecteurId: 'co1');

      expect(store.notifications.length, 1);
      expect(store.notifications.single.type, 'approved');
    });
  });
}
