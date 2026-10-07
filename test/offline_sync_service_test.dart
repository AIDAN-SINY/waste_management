import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/services/offline_sync_service.dart';

void main() {
  group('PendingOperation', () {
    test('toMap/fromMap round-trip', () {
      final op = PendingOperation(
        id: 'OP-123-pickups',
        type: 'set',
        collection: 'pickups',
        documentId: 'PKP-123',
        data: {'client_id': '677123456', 'status': 'completed'},
        timestamp: 1724851200000,
        retries: 0,
      );

      final map = op.toMap();
      final op2 = PendingOperation.fromMap(map);

      expect(op2.id, 'OP-123-pickups');
      expect(op2.type, 'set');
      expect(op2.collection, 'pickups');
      expect(op2.documentId, 'PKP-123');
      expect(op2.data['client_id'], '677123456');
      expect(op2.data['status'], 'completed');
      expect(op2.timestamp, 1724851200000);
      expect(op2.retries, 0);
    });

    test('retries default to 0', () {
      final op = PendingOperation(
        id: 'OP-1',
        type: 'set',
        collection: 'test',
        documentId: 'doc1',
        data: {},
        timestamp: 0,
      );
      expect(op.retries, 0);
    });

    test('retries from fromMap defaults to 0 when missing', () {
      final op = PendingOperation.fromMap({
        'id': 'OP-1',
        'type': 'set',
        'collection': 'test',
        'documentId': 'doc1',
        'data': <String, dynamic>{},
        'timestamp': 0,
      });
      expect(op.retries, 0);
    });

    test('preserves complex data in round-trip', () {
      final op = PendingOperation(
        id: 'OP-2',
        type: 'update',
        collection: 'users',
        documentId: 'user123',
        data: {
          'needsPickup': false,
          'lastCollection': '2026-08-28',
          'nested': {'key': 'value'},
        },
        timestamp: 1724851200000,
        retries: 2,
      );

      final map = op.toMap();
      final op2 = PendingOperation.fromMap(map);

      expect(op2.data['needsPickup'], false);
      expect(op2.data['lastCollection'], '2026-08-28');
      expect(op2.retries, 2);
    });
  });
}
