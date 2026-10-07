import 'package:flutter_test/flutter_test.dart';
import 'package:waste_pro/features/backoffice/data/backoffice_store.dart';
import 'package:waste_pro/features/backoffice/models.dart';

void main() {
  group('VehicleModel maintenance fields', () {
    test('defaults are 5000 km and 30 days', () {
      const v = VehicleModel(
        id: 'v1',
        plateNumber: 'CE-101-AE',
        type: 'Tricycle',
      );
      expect(v.maintenanceIntervalKm, 5000);
      expect(v.maintenanceIntervalDays, 30);
    });

    test('copyWith preserves maintenance intervals', () {
      const v = VehicleModel(
        id: 'v1',
        plateNumber: 'CE-101-AE',
        type: 'Tricycle',
        maintenanceIntervalKm: 3000,
        maintenanceIntervalDays: 15,
      );

      final v2 = v.copyWith(mileage: 5000);
      expect(v2.maintenanceIntervalKm, 3000);
      expect(v2.maintenanceIntervalDays, 15);
      expect(v2.mileage, 5000);
    });

    test('toMap/fromMap round-trip preserves maintenance intervals', () {
      const v = VehicleModel(
        id: 'v1',
        plateNumber: 'CE-101-AE',
        type: 'Tricycle',
        mileage: 4320,
        lastMaintenanceDate: '2026-07-15',
        maintenanceIntervalKm: 3000,
        maintenanceIntervalDays: 15,
      );

      final map = v.toMap();
      final v2 = VehicleModel.fromMap(map);

      expect(v2.maintenanceIntervalKm, 3000);
      expect(v2.maintenanceIntervalDays, 15);
      expect(v2.mileage, 4320);
      expect(v2.lastMaintenanceDate, '2026-07-15');
    });

    test('fromMap defaults maintenance intervals when missing', () {
      final v = VehicleModel.fromMap({
        'id': 'v1',
        'plateNumber': 'CE-101-AE',
        'type': 'Tricycle',
      });
      expect(v.maintenanceIntervalKm, 5000);
      expect(v.maintenanceIntervalDays, 30);
    });
  });

  group('VehicleMaintenanceModel', () {
    test('toMap/fromMap round-trip', () {
      const log = VehicleMaintenanceModel(
        id: 'vm1',
        vehicleId: 'v1',
        vehiclePlate: 'CE-101-AE',
        type: 'Oil Change',
        description: 'Full synthetic oil change',
        mileageAtService: 4320,
        serviceDate: '2026-07-15',
        cost: 15000,
        mechanicName: 'Garage Bonamoussadi',
        nextServiceDate: '2026-09-15',
        nextServiceMileage: 9320,
        status: 'Completed',
      );

      final map = log.toMap();
      final log2 = VehicleMaintenanceModel.fromMap(map);

      expect(log2.id, 'vm1');
      expect(log2.vehicleId, 'v1');
      expect(log2.vehiclePlate, 'CE-101-AE');
      expect(log2.type, 'Oil Change');
      expect(log2.description, 'Full synthetic oil change');
      expect(log2.mileageAtService, 4320);
      expect(log2.serviceDate, '2026-07-15');
      expect(log2.cost, 15000);
      expect(log2.mechanicName, 'Garage Bonamoussadi');
      expect(log2.nextServiceDate, '2026-09-15');
      expect(log2.nextServiceMileage, 9320);
      expect(log2.status, 'Completed');
    });

    test('copyWith updates selected fields', () {
      const log = VehicleMaintenanceModel(
        id: 'vm1',
        vehicleId: 'v1',
        vehiclePlate: 'CE-101-AE',
        type: 'Oil Change',
        serviceDate: '2026-07-15',
        status: 'Completed',
      );

      final updated = log.copyWith(status: 'Overdue', cost: 20000);

      expect(updated.status, 'Overdue');
      expect(updated.cost, 20000);
      expect(updated.id, 'vm1');
      expect(updated.type, 'Oil Change');
    });

    test('fromMap handles empty/missing fields', () {
      final log = VehicleMaintenanceModel.fromMap({});
      expect(log.id, '');
      expect(log.vehicleId, '');
      expect(log.type, 'General Inspection');
      expect(log.cost, 0);
      expect(log.mileageAtService, 0);
      expect(log.status, 'Completed');
    });
  });

  group('BackofficeStore maintenance', () {
    test('addMaintenanceLog creates a log entry', () async {
      final store = BackofficeStore();
      final vehicle = store.vehicles.first;

      await store.addMaintenanceLog(
        vehicleId: vehicle.id,
        vehiclePlate: vehicle.plateNumber,
        type: 'Oil Change',
        description: 'Test oil change',
        mileageAtService: 5000,
        serviceDate: '2026-08-28',
        cost: 15000,
      );

      final logs = store.maintenanceForVehicle(vehicle.id);
      expect(logs.length, greaterThanOrEqualTo(1));
      expect(logs.first.type, 'Oil Change');
      expect(logs.first.description, 'Test oil change');
    });

    test('addMaintenanceLog updates vehicle lastMaintenanceDate', () async {
      final store = BackofficeStore();
      final vehicle = store.vehicles.first;

      await store.addMaintenanceLog(
        vehicleId: vehicle.id,
        vehiclePlate: vehicle.plateNumber,
        type: 'Oil Change',
        mileageAtService: 5000,
        serviceDate: '2026-08-28',
      );

      final updatedVehicle = store.vehicles.firstWhere((v) => v.id == vehicle.id);
      expect(updatedVehicle.lastMaintenanceDate, '2026-08-28');
    });

    test('addMaintenanceLog updates vehicle mileage if higher', () async {
      final store = BackofficeStore();
      final vehicle = store.vehicles.first;
      final originalMileage = vehicle.mileage;

      await store.addMaintenanceLog(
        vehicleId: vehicle.id,
        vehiclePlate: vehicle.plateNumber,
        type: 'Oil Change',
        mileageAtService: originalMileage + 1000,
        serviceDate: '2026-08-28',
      );

      final updatedVehicle = store.vehicles.firstWhere((v) => v.id == vehicle.id);
      expect(updatedVehicle.mileage, originalMileage + 1000);
    });

    test('maintenanceForVehicle returns sorted by date descending', () async {
      final store = BackofficeStore();
      final vehicle = store.vehicles.first;

      await store.addMaintenanceLog(
        vehicleId: vehicle.id,
        vehiclePlate: vehicle.plateNumber,
        type: 'Oil Change',
        serviceDate: '2026-06-01',
      );
      await store.addMaintenanceLog(
        vehicleId: vehicle.id,
        vehiclePlate: vehicle.plateNumber,
        type: 'Tire Rotation',
        serviceDate: '2026-08-01',
      );

      final logs = store.maintenanceForVehicle(vehicle.id);
      expect(logs.first.serviceDate, '2026-08-01');
      expect(logs.last.serviceDate, '2026-06-01');
    });

    test('deleteMaintenanceLog removes the entry', () async {
      final store = BackofficeStore();
      final vehicle = store.vehicles.first;
      final before = store.maintenanceForVehicle(vehicle.id).length;

      await store.addMaintenanceLog(
        vehicleId: vehicle.id,
        vehiclePlate: vehicle.plateNumber,
        type: 'Oil Change',
        serviceDate: '2026-08-28',
      );

      final logs = store.maintenanceForVehicle(vehicle.id);
      expect(logs.length, before + 1);
      final logId = logs.first.id;

      await store.deleteMaintenanceLog(logId);

      final logsAfter = store.maintenanceForVehicle(vehicle.id);
      expect(logsAfter.length, before);
    });

    test('vehiclesNeedingMaintenance detects overdue vehicles', () {
      final store = BackofficeStore();
      final needing = store.vehiclesNeedingMaintenance();
      final hasOverdue = needing.any((v) => v.plateNumber == 'CE-404-DH');
      expect(hasOverdue, isTrue);
    });
  });
}
