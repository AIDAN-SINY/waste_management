import 'package:flutter/foundation.dart';

import '../../../models/assignment_model.dart';
import '../models.dart';
import '../../../models/notification_model.dart';
import 'seed_data.dart';

/// In-memory store for the mobile backoffice (entreprise manager).
///
/// Provides the design's mock dataset plus the loading/error lifecycle shared
/// with a future `FirestoreBackofficeStore` (same pattern as the super admin
/// console) — the CRUD methods are the only place that will change.
class BackofficeStore extends ChangeNotifier {
  int _uid = 100;

  /// Generates a unique entity id. Overridden by a Firestore store to
  /// produce ids that never collide across sessions.
  @protected
  String nextId() => 'id${_uid++}';

  // --- Lifecycle state (ready for a Firestore-backed store) ---
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Nom de l'agence du backoffice (rempli par le store Firestore quand le
  /// backoffice est scopé à une agence ; vide pour le store mock / tests).
  String _agenceName = '';

  String get agenceName => _agenceName;

  @protected
  void setAgenceName(String value) {
    if (_agenceName == value) return;
    _agenceName = value;
    notifyListeners();
  }

  @protected
  void setLoading(bool value) => _isLoading = value;

  @protected
  void setErrorValue(String? value) => _error = value;

  /// Loads the initial data. The base (mock) store has nothing to load.
  Future<void> load() async {}

  /// Mock dataset, with two collectes pinned to today so the
  /// « Collectes aujourd'hui » KPI stays alive whatever the date.
  BackofficeStore() {
    final now = DateTime.now();
    final iso =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    if (collectes.length >= 4) {
      collectes[2] = collectes[2].copyWith(date: iso);
      collectes[3] = collectes[3].copyWith(date: iso);
    }
  }

  // --- Mock data (same entities as backoffice-mobile.html) ---
  final List<ClientModel> clients = [...seedClients];
  final List<CollecteurModel> collecteurs = [...seedCollecteurs];
  final List<ContratModel> contrats = [...seedContrats];
  final List<CollecteModel> collectes = [...seedCollectes];
  final List<FactureModel> factures = [...seedFactures];
  final List<FrequenceModel> frequences = [...seedFrequences];

  /// Candidatures clients (pré-inscriptions) — le store Firestore les
  /// remplace par les vraies données de la collection `registrations`.
  final List<RegistrationModel> registrations = [...seedRegistrations];

  /// Notifications in-app des décisions de candidature (approuvée /
  /// rejetée) — le store Firestore écrit dans la collection `notifications`.
  final List<NotificationModel> notifications = [];

  /// Issues reported by clients (overflowing bins, missed collections, etc.).
  final List<IssueModel> issues = [];

  /// Zones managed by the agency (collection calendars).
  final List<ZoneModel> zones = [...seedZones];

  /// Assignments — collector → zone + time window + date.
  final List<AssignmentModel> assignments = [];

  /// Vehicles managed by the agency.
  final List<VehicleModel> vehicles = [...seedVehicles];

  /// Vehicle maintenance logs.
  final List<VehicleMaintenanceModel> maintenanceLogs = [...seedMaintenanceLogs];

  List<RegistrationModel> get pendingRegistrations =>
      registrations.where((r) => r.status == 'pending').toList();

  // --- List filters (per entity) ---
  final Map<BoEntity, String> _filters = {};

  static String _defaultFilter(BoEntity type) => switch (type) {
    BoEntity.client || BoEntity.collecteur || BoEntity.contrat => 'All',
    BoEntity.collecte || BoEntity.facture || BoEntity.issue => 'All',
    BoEntity.frequence || BoEntity.zone || BoEntity.assignment || BoEntity.vehicle => 'All',
  };

  String filterFor(BoEntity type) => _filters[type] ?? _defaultFilter(type);

  void selectFilter(BoEntity type, String value) {
    if (_filters[type] == value) return;
    _filters[type] = value;
    notifyListeners();
  }

  // --- Zone filter (for collectors / clients) ---
  /// Currently selected zone filter ('All' = no filtering).
  String zoneFilter = 'All';

  /// Returns the unique zone names from the collector list.
  List<String> get availableZones {
    final zones = collecteurs.map((c) => c.zone).where((z) => z.isNotEmpty).toSet().toList();
    zones.sort();
    return zones;
  }

  void selectZoneFilter(String value) {
    if (zoneFilter == value) return;
    zoneFilter = value;
    notifyListeners();
  }

  // --- Dashboard helpers ---
  int get clientsActifs => clients.where((c) => c.status == 'Active').length;

  int get collectesAujourdhui {
    final now = DateTime.now();
    final key =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return collectes.where((c) => c.date == key).length;
  }

  /// Revenus (milliers de XAF) = factures payées.
  double get revenusMilliers {
    final total = factures
        .where((f) => f.status == 'Paid')
        .fold<int>(0, (s, f) => s + f.montant);
    return total / 1000;
  }

  /// Taux de réussite = part des collectes effectuées.
  double get tauxReussite {
    if (collectes.isEmpty) return 0;
    final ok = collectes.where((c) => c.status == 'Completed').length;
    return ok / collectes.length * 100;
  }

  // --- Clients CRUD ---
  //
  // [password] crée (ou met à jour) le compte de connexion du client dans
  // `users`. La base (mock) l'ignore ; le store Firestore l'utilise pour
  // que le client puisse se connecter à son interface dédiée.
  //
  // [plan] ('Monthly' | 'Weekly' | 'Daily') only counts when [paidInCash]:
  // the subscription is then recorded as paid in cash at the agency.
  // Otherwise the client gets access only ('None') and pays in the app.
  Future<void> addClient({
    required String name,
    required String phone,
    required String zone,
    required String plan,
    required String status,
    bool paidInCash = false,
    String password = '',
    String agenceId = '',
    String societeId = '',
    String adresse = '',
    String quartier = '',
    double? latitude,
    double? longitude,
    String photoUrl = '',
    String housingType = '',
    List<String> collectionDays = const [],
    String pickupTime = '',
    String subscribedAt = '',
  }) async {
    clients.add(
      ClientModel(
        id: nextId(),
        name: name,
        phone: phone,
        zone: zone,
        plan: paidInCash ? plan : 'None',
        status: status,
        agenceId: agenceId,
        societeId: societeId,
        adresse: adresse,
        quartier: quartier,
        latitude: latitude,
        longitude: longitude,
        photoUrl: photoUrl,
        housingType: housingType,
        subscribedAt: !paidInCash
            ? ''
            : subscribedAt.isNotEmpty
                ? subscribedAt
                : _todayIso(),
      ),
    );
    notifyListeners();
  }

  /// [cashPlan] non-empty = the client just paid that plan in cash at the
  /// agency (renewal / upgrade).
  Future<void> updateClient(ClientModel updated, {
    String password = '',
    List<String> collectionDays = const [],
    String pickupTime = '',
    String cashPlan = '',
  }) async {
    final index = clients.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      clients[index] =
          cashPlan.isEmpty ? updated : updated.copyWith(plan: cashPlan);
    }
    notifyListeners();
  }

  Future<void> deleteClient(String id) async {
    clients.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Collecteurs CRUD ---
  //
  // [password] crée (ou met à jour) le compte de connexion du collecteur
  // dans `users` (rôle 'collector'). La base (mock) l'ignore.
  Future<void> addCollecteur({
    required String name,
    required String phone,
    required String zone,
    required double rating,
    required String status,
    String password = '',
    String agenceId = '',
    String societeId = '',
    String cni = '',
    String photoUrl = '',
    String vehicle = '',
    int salary = 0,
    ZoneArea? zoneArea,
  }) async {
    collecteurs.add(
      CollecteurModel(
        id: nextId(),
        name: name,
        phone: phone,
        zone: zone,
        rating: rating,
        status: status,
        agenceId: agenceId,
        societeId: societeId,
        cni: cni,
        photoUrl: photoUrl,
        vehicle: vehicle,
        salary: salary,
        zoneArea: zoneArea,
      ),
    );
    notifyListeners();
  }

  Future<void> updateCollecteur(
    CollecteurModel updated, {
    String password = '',
  }) async {
    final index = collecteurs.indexWhere((c) => c.id == updated.id);
    if (index != -1) collecteurs[index] = updated;
    notifyListeners();
  }

  Future<void> deleteCollecteur(String id) async {
    collecteurs.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Candidatures (pré-inscriptions clients) ---

  /// Approuve une candidature : crée le client (Active, plan Standard),
  /// l'assigne au collecteur choisi et marque la candidature 'approved'.
  /// Le store Firestore crée aussi son compte de connexion `users/{phone}`.
  Future<void> approveRegistration(
    RegistrationModel reg, {
    required String collecteurId,
  }) async {
    final updated = reg.copyWith(
      status: 'approved',
      collecteurId: collecteurId,
    );
    final index = registrations.indexWhere((r) => r.id == reg.id);
    if (index != -1) {
      registrations[index] = updated;
    } else {
      registrations.add(updated);
    }
    clients.add(
      ClientModel(
        id: nextId(),
        name: reg.fullName,
        phone: reg.phone,
        zone: reg.zone,
        // Approval = access only: the plan starts with the client's payment.
        plan: 'None',
        status: 'Active',
        agenceId: reg.agenceId,
        societeId: reg.societeId,
        collecteurId: collecteurId,
        // Photo choisie à la pré-inscription : reportée sur le client.
        photoUrl: reg.photoUrl,
        // Point de collecte GPS choisi à la pré-inscription.
        latitude: reg.latitude,
        longitude: reg.longitude,
        adresse: reg.zone,
        quartier: reg.zone,
      ),
    );
    _addNotification(reg, type: 'approved');
    notifyListeners();
  }

  /// Rejette une candidature.
  Future<void> rejectRegistration(RegistrationModel reg) async {
    final updated = reg.copyWith(status: 'rejected');
    final index = registrations.indexWhere((r) => r.id == reg.id);
    if (index != -1) {
      registrations[index] = updated;
    } else {
      registrations.add(updated);
    }
    _addNotification(reg, type: 'rejected');
    notifyListeners();
  }

  /// Ajoute la notification in-app correspondant à une décision.
  void _addNotification(RegistrationModel reg, {required String type}) {
    final now = DateTime.now();
    final iso =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    notifications.removeWhere((n) => n.id == 'notif${reg.id}');
    notifications.add(
      NotificationModel(
        id: 'notif${reg.id}',
        phone: reg.phone,
        type: type,
        title: type == 'approved'
            ? 'Application approved'
            : 'Application rejected',
        message: type == 'approved'
            ? 'Your application was approved. Choose and pay your plan in '
                  'the app to start your pickups.'
            : 'Your application was rejected. You can submit a new '
                  'application from the app.',
        createdAt: iso,
      ),
    );
  }

  /// Réassigne le collecteur d'un client : met à jour la fiche client et
  /// bascule ses collectes à venir (Scheduled / Missed) portant l'ancien
  /// collecteur vers le nouveau. Le store Firestore met aussi à jour le
  /// compte de connexion `users/{téléphone}`.
  Future<void> reassignCollecteur({
    required String clientId,
    required String collecteurId,
  }) async {
    final index = clients.indexWhere((c) => c.id == clientId);
    if (index == -1) return;
    final client = clients[index];
    if (client.collecteurId == collecteurId) return;

    final oldName = collecteurNameFor(collecteurs, client.collecteurId);
    final newName = collecteurNameFor(collecteurs, collecteurId);
    clients[index] = client.copyWith(collecteurId: collecteurId);

    // Bascule les collectes à venir portant l'ancien collecteur (même
    // comportement que le store Firestore : l'historique effectué et les
    // collectes sans collecteur ne changent pas).
    if (newName.isNotEmpty && oldName.isNotEmpty) {
      for (var i = 0; i < collectes.length; i++) {
        final col = collectes[i];
        final isDone = col.status == 'Completed' || col.status == 'Effectué';
        if (!isDone &&
            col.client == client.name &&
            col.collecteur == oldName) {
          collectes[i] = col.copyWith(collecteur: newName);
        }
      }
    }
    notifyListeners();
  }

  // --- Contrats CRUD ---
  Future<void> addContrat({
    required String client,
    required String frequence,
    required int prix,
    required String status,
  }) async {
    contrats.add(
      ContratModel(
        id: nextId(),
        client: client,
        frequence: frequence,
        prix: prix,
        status: status,
      ),
    );
    notifyListeners();
  }

  Future<void> updateContrat(ContratModel updated) async {
    final index = contrats.indexWhere((c) => c.id == updated.id);
    if (index != -1) contrats[index] = updated;
    notifyListeners();
  }

  Future<void> deleteContrat(String id) async {
    contrats.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Collectes CRUD ---
  Future<void> addCollecte({
    required String client,
    required String collecteur,
    required String date,
    required double poids,
    required String status,
  }) async {
    collectes.add(
      CollecteModel(
        id: nextId(),
        client: client,
        collecteur: collecteur,
        date: date,
        poids: poids,
        status: status,
      ),
    );
    notifyListeners();
  }

  Future<void> updateCollecte(CollecteModel updated) async {
    final index = collectes.indexWhere((c) => c.id == updated.id);
    if (index != -1) collectes[index] = updated;
    notifyListeners();
  }

  Future<void> deleteCollecte(String id) async {
    collectes.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // --- Factures CRUD ---
  Future<void> addFacture({
    required String client,
    required int montant,
    required String echeance,
    required String status,
  }) async {
    factures.add(
      FactureModel(
        id: nextId(),
        client: client,
        montant: montant,
        echeance: echeance,
        status: status,
      ),
    );
    notifyListeners();
  }

  Future<void> updateFacture(FactureModel updated) async {
    final index = factures.indexWhere((f) => f.id == updated.id);
    if (index != -1) factures[index] = updated;
    notifyListeners();
  }

  Future<void> deleteFacture(String id) async {
    factures.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  // --- Issues CRUD ---

  /// Issues a collector is handling (assigned or in progress) — his
  /// workload, used to work out his availability.
  int openIssuesOf(String collecteurId) => issues
      .where((i) => i.assignedCollecteurId == collecteurId && i.isInProgressFor)
      .length;

  /// Availability of [c] right now (see [collectorAvailability]).
  CollectorAvailability availabilityOf(CollecteurModel c) =>
      collectorAvailability(c, openIssues: openIssuesOf(c.id));

  /// The agency manager assigns [issue] to [collecteur] (or reassigns it):
  /// status 'assigned', the collector is notified.
  Future<void> assignIssue(IssueModel issue, CollecteurModel collecteur) async {
    final index = issues.indexWhere((i) => i.id == issue.id);
    if (index != -1) {
      issues[index] = issue.copyWith(
        status: 'assigned',
        assignedCollecteurId: collecteur.id,
        assignedCollectorName: collecteur.name,
        assignedCollectorPhone: collecteur.phone,
      );
    }
    notifyListeners();
  }

  Future<void> resolveIssue(IssueModel issue) async {
    final index = issues.indexWhere((i) => i.id == issue.id);
    if (index != -1) {
      issues[index] = issue.copyWith(status: 'resolved');
    }
    notifyListeners();
  }

  // --- Zones CRUD ---
  Future<void> addZone({
    required String name,
    required List<String> collectionDays,
    required String standardPickupTime,
  }) async {
    zones.add(
      ZoneModel(
        id: nextId(),
        name: name,
        collectionDays: collectionDays,
        standardPickupTime: standardPickupTime,
      ),
    );
    notifyListeners();
  }

  Future<void> updateZone(ZoneModel updated) async {
    final index = zones.indexWhere((z) => z.id == updated.id);
    if (index != -1) zones[index] = updated;
    notifyListeners();
  }

  Future<void> deleteZone(String id) async {
    zones.removeWhere((z) => z.id == id);
    notifyListeners();
  }

  // --- Assignments CRUD ---
  Future<void> addAssignment({
    required String collecteurId,
    required String collecteurName,
    required String zoneId,
    required String zoneName,
    required String startTime,
    required String endTime,
    required String date,
    String status = 'Active',
  }) async {
    assignments.add(
      AssignmentModel(
        id: nextId(),
        collecteurId: collecteurId,
        collecteurName: collecteurName,
        zoneId: zoneId,
        zoneName: zoneName,
        startTime: startTime,
        endTime: endTime,
        date: date,
        status: status,
      ),
    );
    notifyListeners();
  }

  Future<void> updateAssignment(AssignmentModel updated) async {
    final index = assignments.indexWhere((a) => a.id == updated.id);
    if (index != -1) assignments[index] = updated;
    notifyListeners();
  }

  Future<void> deleteAssignment(String id) async {
    assignments.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  // --- Frequences CRUD ---
  Future<void> addFrequence({
    required String libelle,
    required int jours,
  }) async {
    frequences.add(
      FrequenceModel(id: nextId(), libelle: libelle, jours: jours),
    );
    notifyListeners();
  }

  Future<void> updateFrequence(FrequenceModel updated) async {
    final index = frequences.indexWhere((f) => f.id == updated.id);
    if (index != -1) frequences[index] = updated;
    notifyListeners();
  }

  Future<void> deleteFrequence(String id) async {
    frequences.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  // --- Vehicles CRUD ---
  Future<void> addVehicle({
    required String plateNumber,
    required String type,
    String brand = '',
    String model = '',
    int year = 0,
    String status = 'Active',
    String assignedCollecteurId = '',
    String assignedCollecteurName = '',
    int mileage = 0,
    String lastMaintenanceDate = '',
    String notes = '',
  }) async {
    vehicles.add(
      VehicleModel(
        id: nextId(),
        plateNumber: plateNumber,
        type: type,
        brand: brand,
        model: model,
        year: year,
        status: status,
        assignedCollecteurId: assignedCollecteurId,
        assignedCollecteurName: assignedCollecteurName,
        mileage: mileage,
        lastMaintenanceDate: lastMaintenanceDate,
        notes: notes,
      ),
    );
    notifyListeners();
  }

  Future<void> updateVehicle(VehicleModel updated) async {
    final index = vehicles.indexWhere((v) => v.id == updated.id);
    if (index != -1) vehicles[index] = updated;
    notifyListeners();
  }

  Future<void> deleteVehicle(String id) async {
    vehicles.removeWhere((v) => v.id == id);
    notifyListeners();
  }

  // --- Vehicle Maintenance CRUD ---
  Future<void> addMaintenanceLog({
    required String vehicleId,
    required String vehiclePlate,
    required String type,
    String description = '',
    int mileageAtService = 0,
    required String serviceDate,
    int cost = 0,
    String mechanicName = '',
    String nextServiceDate = '',
    int nextServiceMileage = 0,
    String status = 'Completed',
  }) async {
    maintenanceLogs.add(
      VehicleMaintenanceModel(
        id: nextId(),
        vehicleId: vehicleId,
        vehiclePlate: vehiclePlate,
        type: type,
        description: description,
        mileageAtService: mileageAtService,
        serviceDate: serviceDate,
        cost: cost,
        mechanicName: mechanicName,
        nextServiceDate: nextServiceDate,
        nextServiceMileage: nextServiceMileage,
        status: status,
      ),
    );
    // Update vehicle's last maintenance date and mileage.
    final vi = vehicles.indexWhere((v) => v.id == vehicleId);
    if (vi != -1) {
      vehicles[vi] = vehicles[vi].copyWith(
        lastMaintenanceDate: serviceDate,
        mileage: mileageAtService > vehicles[vi].mileage ? mileageAtService : vehicles[vi].mileage,
      );
    }
    notifyListeners();
  }

  Future<void> updateMaintenanceLog(VehicleMaintenanceModel updated) async {
    final index = maintenanceLogs.indexWhere((m) => m.id == updated.id);
    if (index != -1) maintenanceLogs[index] = updated;
    notifyListeners();
  }

  Future<void> deleteMaintenanceLog(String id) async {
    maintenanceLogs.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  /// Returns maintenance logs for a specific vehicle.
  List<VehicleMaintenanceModel> maintenanceForVehicle(String vehicleId) {
    return maintenanceLogs.where((m) => m.vehicleId == vehicleId).toList()
      ..sort((a, b) => b.serviceDate.compareTo(a.serviceDate));
  }

  /// Returns vehicles that need maintenance soon (within 500 km or 7 days).
  List<VehicleModel> vehiclesNeedingMaintenance() {
    final now = DateTime.now();
    return vehicles.where((v) {
      if (v.status == 'Retired') return false;
      if (v.lastMaintenanceDate.isEmpty) return true;
      final lastDate = DateTime.tryParse(v.lastMaintenanceDate);
      if (lastDate == null) return true;
      final daysSince = now.difference(lastDate).inDays;
      final nextMileage = v.mileage + 500; // within 500 km
      return daysSince >= v.maintenanceIntervalDays - 7 ||
          v.mileage >= nextMileage;
    }).toList();
  }

  /// Date du jour au format yyyy-MM-dd.
  String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

/// Date du jour au format yyyy-MM-dd (partagé avec le store Firestore, qui
/// étend [BackofficeStore] depuis une autre bibliothèque).
String backofficeTodayIso() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
