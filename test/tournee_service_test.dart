import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/services/tournee_service.dart';

void main() {
  test('recordPickup writes a pickup pending client confirmation', () async {
    final db = FakeFirebaseFirestore();
    final service = TourneeService(db: db);

    final pickupId = await service.recordPickup(
      collectorId: '+237678901122',
      collectorName: 'Paul Mbarga',
      stop: TourneeStop(
        clientId: 'c4',
        clientName: 'Marie Ekwalla',
        clientPhone: '+237699100004',
        address: 'Rue 12',
        quartier: 'Akwa',
        zoneName: 'Akwa',
        plan: 'Weekly',
        pickupTime: '08:00',
        status: 'In Progress',
        latitude: 4.05,
        longitude: 9.7,
      ),
      poids: 0,
      commentaire: '',
      heureArrivee: '08:02',
      heureDepart: '08:10',
      photoBase64: 'AAAA',
    );

    final pickup = await db.collection('pickups').doc(pickupId).get();
    expect(pickup.exists, isTrue);
    final data = pickup.data()!;
    expect(data['client_id'], '+237699100004');
    expect(data['collector_id'], '+237678901122');
    expect(data['status'], 'pending_client_confirmation');
    expect(data['poids'], 0);
    expect(data['photo_url'], 'data:image/jpeg;base64,AAAA');
    expect(data['latitude'], 4.05);

    // The client's users doc is flagged as collected.
    final user = await db.collection('users').doc('+237699100004').get();
    expect(user.data()?['needsPickup'], isFalse);
  });
}
