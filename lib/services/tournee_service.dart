import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'offline_sync_service.dart';

/// A stop on today's collection route, generated from Firestore data.
///
/// Built by [TourneeService.generateTodayTour] which cross-references:
///   1. `clients` assigned to this collector (`collecteurId == X`)
///   2. `contracts` / `users` with active subscription + today in `collection_days`
///   3. `pickups` already completed today (to mark stops as Done)
class TourneeStop {
  TourneeStop({
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
    required this.address,
    required this.quartier,
    required this.zoneName,
    required this.plan,
    required this.pickupTime,
    required this.status,
    this.heureArrivee = '',
    this.heureDepart = '',
    this.poids = 0,
    this.commentaire = '',
    this.missReason,
    this.latitude,
    this.longitude,
    this.photoUrl = '',
  });

  final String clientId;
  final String clientName;
  final String clientPhone;
  final String address;
  final String quartier;
  final String zoneName;
  final String plan;
  final String pickupTime;

  String status; // 'To Do' | 'In Progress' | 'Done' | 'Missed'
  String? missReason;
  String heureArrivee;
  String heureDepart;
  double poids;
  String commentaire;
  final double? latitude;
  final double? longitude;

  /// Proof-of-visit photo of today's pickup (base64 data URI or URL),
  /// read back from today's pickup doc when the stop is Done.
  String photoUrl;
}

/// Generates today's collection tour for a collector from Firestore data.
///
/// Flow (from the cahier des charges):
///   1. Resolve the collector's zones for today:
///      a) from `assignments` (`collecteurId == X`, today's date, Active),
///      b) falling back to the legacy direct assignment (`clients`
///         docs with `collecteurId == X`) when no assignment exists.
///   2. Check each client has an active subscription with today in
///      `collection_days`
///   3. Check if a pickup was already completed today
///   4. Order In Progress → To Do → Done/Missed
class TourneeService {
  TourneeService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance,
        _dbInjected = db != null;

  final FirebaseFirestore _db;

  /// True when a Firestore instance was explicitly injected — in that case
  /// writes go straight to it (the offline queue singleton would bypass it).
  final bool _dbInjected;

  /// Generates today's tour for [collectorId].
  ///
  /// Returns a list of [TourneeStop] ordered by status.
  /// Falls back gracefully: if no contracts/clients are found, returns
  /// an empty list (the UI shows the "no stops" state).
  ///
  /// [agenceId] (the collector's agency) scopes the client / pickup queries:
  /// the Firestore rules only let a collector read their own agency.
  Future<List<TourneeStop>> generateTodayTour(
    String collectorId, {
    String agenceId = '',
  }) async {
    if (collectorId.isEmpty) return [];
    Query<Map<String, dynamic>> scoped(String collection) {
      final q = _db.collection(collection);
      return agenceId.isEmpty ? q : q.where('agenceId', isEqualTo: agenceId);
    }

    final today = _todayKey(); // e.g. 'Tuesday'
    final todayDate = _todayIso(); // e.g. '2026-08-28'
    final offline = OfflineSyncService.instance;

    try {
      // 1. Resolve the collector's zones from today's assignments
      //    (Affectation: collecteur → zone + start/end time + date).
      final zoneNames = <String>{};
      try {
        final assignmentsSnap = await _db
            .collection('assignments')
            .where('collecteurId', isEqualTo: collectorId)
            .where('date', isEqualTo: todayDate)
            .where('status', isEqualTo: 'Active')
            .get();
        for (final doc in assignmentsSnap.docs) {
          final zoneName = doc.data()['zoneName'] as String? ?? '';
          if (zoneName.isNotEmpty) zoneNames.add(zoneName);
        }
      } catch (e) {
        // Assignments are an enhancement — never block the legacy flow.
        debugPrint('[TourneeService] assignments lookup failed: $e');
      }

      // 2. Fetch clients: by direct assignment (legacy), plus clients in
      //    the assigned zones (assignment-driven).
      final clientsSnap = await scoped('clients')
          .where('collecteurId', isEqualTo: collectorId)
          .where('status', isEqualTo: 'Active')
          .get();

      final clientDocs = [...clientsSnap.docs];
      if (zoneNames.isNotEmpty) {
        // Fetch zone clients for each assigned zone and merge (dedupe by
        // doc id). `whereIn` is limited to 30 values; zones per collector
        // per day are far fewer.
        final zones = zoneNames.take(30).toList();
        final zoneSnap = await scoped('clients')
            .where('status', isEqualTo: 'Active')
            .where('zone', whereIn: zones)
            .get();
        final knownIds = clientDocs.map((d) => d.id).toSet();
        for (final doc in zoneSnap.docs) {
          if (knownIds.add(doc.id)) clientDocs.add(doc);
        }
      }

      if (clientDocs.isEmpty) {
        // Cache empty result.
        offline.cacheTourData(collectorId, []);
        return [];
      }

      // 3. For each client, check if today is a collection day.
      final stops = <TourneeStop>[];
      for (final clientDoc in clientDocs) {
        final cData = clientDoc.data();
        final clientName = cData['name'] as String? ?? '';
        final clientPhone = cData['phone'] as String? ?? '';
        final zone = cData['zone'] as String? ?? '';
        final plan = cData['plan'] as String? ?? 'None';
        final adresse = cData['adresse'] as String? ?? '';
        final quartier = cData['quartier'] as String? ?? '';
        final lat = (cData['latitude'] as num?)?.toDouble();
        final lng = (cData['longitude'] as num?)?.toDouble();

        // Check the user's contract data (collection_days + pickup_time).
        final userDoc =
            await _db.collection('users').doc(clientPhone).get();
        if (!userDoc.exists) continue;
        final uData = userDoc.data()!;
        final collectionDays = (uData['collection_days'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final pickupTime = uData['pickup_time'] as String? ?? '07:00 — 08:00';
        final isSubscribed = uData['isSubscribed'] as bool? ?? false;
        final zoneName = uData['zone_name'] as String? ?? zone;

        // Skip if not subscribed or today is not a collection day.
        if (!isSubscribed) continue;
        if (!collectionDays.contains(today)) continue;

        // 3. Check if a pickup was already completed today.
        String status = 'To Do';
        String heureArrivee = '';
        String heureDepart = '';
        double poids = 0;
        String commentaire = '';
        String photoUrl = '';

        // A pickup is only considered done when the client has confirmed it.
        // 'pending_client_confirmation' means the collector claimed it but the
        // client hasn't validated yet — keep the stop as In Progress / To Do.
        final pickupsSnap = await scoped('pickups')
            .where('client_id', isEqualTo: clientPhone)
            .where('status', isEqualTo: 'verified')
            .get();

        for (final pickupDoc in pickupsSnap.docs) {
          final pData = pickupDoc.data();
          final pickupDate = pData['date'] as String? ?? '';
          if (pickupDate == todayDate) {
            status = 'Done';
            heureArrivee = pData['heure_arrivee'] as String? ?? '';
            heureDepart = pData['heure_depart'] as String? ?? '';
            poids = (pData['poids'] as num?)?.toDouble() ?? 0;
            commentaire = pData['commentaire'] as String? ?? '';
            photoUrl = pData['photo_url'] as String? ?? '';
            break;
          }
        }

        // Also check for pending_client_confirmation pickups so the collector
        // can see which stops are awaiting client confirmation.
        if (status == 'To Do') {
          final pendingSnap = await scoped('pickups')
              .where('client_id', isEqualTo: clientPhone)
              .where('status', isEqualTo: 'pending_client_confirmation')
              .get();
          for (final pickupDoc in pendingSnap.docs) {
            final pData = pickupDoc.data();
            final pickupDate = pData['date'] as String? ?? '';
            if (pickupDate == todayDate) {
            status = 'In Progress';
            heureArrivee = pData['heure_arrivee'] as String? ?? '';
            heureDepart = pData['heure_depart'] as String? ?? '';
            poids = (pData['poids'] as num?)?.toDouble() ?? 0;
            commentaire = pData['commentaire'] as String? ?? '';
            photoUrl = pData['photo_url'] as String? ?? '';
            break;
            }
          }
        }

        stops.add(TourneeStop(
          clientId: clientDoc.id,
          clientName: clientName,
          clientPhone: clientPhone,
          address: adresse.isNotEmpty ? '$adresse, $quartier' : quartier,
          quartier: quartier,
          zoneName: zoneName,
          plan: plan,
          pickupTime: pickupTime,
          status: status,
          heureArrivee: heureArrivee,
          heureDepart: heureDepart,
          poids: poids,
          commentaire: commentaire,
          latitude: lat,
          longitude: lng,
          photoUrl: photoUrl,
        ));
      }

      // 4. Sort: In Progress first, then To Do, then Done/Missed.
      stops.sort((a, b) {
        const statusOrder = {
          'In Progress': 0,
          'To Do': 1,
          'Done': 2,
          'Missed': 3,
        };
        return (statusOrder[a.status] ?? 1)
            .compareTo(statusOrder[b.status] ?? 1);
      });

      // Cache tour data for offline access.
      final cacheData = stops.map((s) => {
        'clientId': s.clientId,
        'clientName': s.clientName,
        'clientPhone': s.clientPhone,
        'address': s.address,
        'quartier': s.quartier,
        'zoneName': s.zoneName,
        'plan': s.plan,
        'pickupTime': s.pickupTime,
        'status': s.status,
        'heureArrivee': s.heureArrivee,
        'heureDepart': s.heureDepart,
        'poids': s.poids,
        'commentaire': s.commentaire,
        'missReason': s.missReason,
        'latitude': s.latitude,
        'longitude': s.longitude,
        'photoUrl': s.photoUrl,
      }).toList();
      offline.cacheTourData(collectorId, cacheData);

      return stops;
    } catch (e) {
      debugPrint('[TourneeService] Error generating tour: $e');
      // Fall back to cached data when offline.
      final cached = offline.getCachedTourData(collectorId);
      if (cached != null && cached.isNotEmpty) {
        debugPrint('[TourneeService] Using cached tour data (${cached.length} stops)');
        return cached.map((m) => TourneeStop(
          clientId: m['clientId'] as String? ?? '',
          clientName: m['clientName'] as String? ?? '',
          clientPhone: m['clientPhone'] as String? ?? '',
          address: m['address'] as String? ?? '',
          quartier: m['quartier'] as String? ?? '',
          zoneName: m['zoneName'] as String? ?? '',
          plan: m['plan'] as String? ?? 'None',
          pickupTime: m['pickupTime'] as String? ?? '07:00',
          status: m['status'] as String? ?? 'To Do',
          heureArrivee: m['heureArrivee'] as String? ?? '',
          heureDepart: m['heureDepart'] as String? ?? '',
          poids: (m['poids'] as num?)?.toDouble() ?? 0,
          commentaire: m['commentaire'] as String? ?? '',
          missReason: m['missReason'] as String?,
          latitude: (m['latitude'] as num?)?.toDouble(),
          longitude: (m['longitude'] as num?)?.toDouble(),
          photoUrl: m['photoUrl'] as String? ?? '',
        )).toList();
      }
      return [];
    }
  }

  /// Records a pickup that the collector has completed but awaits the client's
  /// confirmation before it is considered verified.
  ///
  /// [photoBase64] — optional proof-of-visit photo (base64, no data-uri
  /// prefix) captured by the collector; stored with the pickup so agencies
  /// and clients can view it later.
  /// [latitude]/[longitude] — the collector's GPS position at validation
  /// time (proof the visit really happened at the client's address).
  ///
  /// Returns the id of the created pickup (`PKP-...`) so callers can pass it
  /// to the client validation request / collector notification.
  ///
  /// After the client confirms, call [confirmPickup]. After a dispute, call
  /// [disputePickup].
  Future<String> recordPickup({
    required String collectorId,
    required String collectorName,
    required TourneeStop stop,
    required double poids,
    required String commentaire,
    required String heureArrivee,
    required String heureDepart,
    String photoBase64 = '',
    double? latitude,
    double? longitude,
  }) async {
    final todayDate = _todayIso();
    final pickupId = 'PKP-${DateTime.now().millisecondsSinceEpoch}';

    final pickupData = {
      'pickup_id': pickupId,
      'client_id': stop.clientPhone,
      'collector_id': collectorId,
      'collector_name': collectorName,
      'date': todayDate,
      'heure_arrivee': heureArrivee,
      'heure_depart': heureDepart,
      'poids': poids,
      'commentaire': commentaire,
      'latitude': latitude ?? stop.latitude,
      'longitude': longitude ?? stop.longitude,
      if (photoBase64.isNotEmpty) 'photo_url': 'data:image/jpeg;base64,$photoBase64',
      'status': 'pending_client_confirmation',
      'timestamp': FieldValue.serverTimestamp(),
    };

    // When a db was explicitly injected (tests, previews) write directly;
    // the OfflineSyncService singleton targets FirebaseFirestore.instance
    // and would silently drop the write into its queue instead.
    if (_dbInjected) {
      await _db.collection('pickups').doc(pickupId).set(
            pickupData,
            SetOptions(merge: true),
          );
      // Merge-set (not update) so a missing users doc is created instead
      // of throwing.
      await _db.collection('users').doc(stop.clientPhone).set({
        'needsPickup': false,
        'lastCollection': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return pickupId;
    }

    // Queue via OfflineSyncService for offline support.
    final offline = OfflineSyncService.instance;
    await offline.queueOperation(
      type: 'set',
      collection: 'pickups',
      documentId: pickupId,
      data: pickupData,
    );

    // Also update the user's needsPickup flag.
    await offline.queueOperation(
      type: 'update',
      collection: 'users',
      documentId: stop.clientPhone,
      data: {
        'needsPickup': false,
        'lastCollection': FieldValue.serverTimestamp(),
      },
    );

    return pickupId;
  }

  /// Marks a pending pickup as verified after the client validates it by
  /// scanning the QR code.
  Future<void> confirmPickup(String pickupId) async {
    await _db.collection('pickups').doc(pickupId).update(
      {'status': 'verified'},
    );
  }

  /// Files an issue in the [issues] collection for the agency to review
  /// after the client rejects a pickup (“The pickup didn't occur”).
  ///
  /// The pickup itself **stays `pending_client_confirmation`**: the collector
  /// already validated it, so it must not fall back into the tour “To Do”
  /// list, and the client may still scan the QR code later if the issue is
  /// resolved.
  Future<void> disputePickup({
    required String pickupId,
    required String clientPhone,
    required String clientName,
    required String category,
    required String description,
  }) async {
    // Keep the pickup pending — only the client's QR scan (confirmPickup)
    // moves it out of `pending_client_confirmation`.
    if (pickupId.isNotEmpty) {
      await _db.collection('pickups').doc(pickupId).update(
        {'dispute_reported': true},
      );
    }

    // Create an issue so the agency can review.
    final now = DateTime.now();
    final id = 'ISS-${now.millisecondsSinceEpoch}';
    final createdAt = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    await _db.collection('issues').doc(id).set({
      'id': id,
      'client_id': clientPhone,
      'client_name': clientName,
      'category': category,
      'description': description,
      'status': 'open',
      'created_at': createdAt,
      'related_pickup_id': pickupId,
    });
  }

  /// Records a missed pickup in Firestore (or queues if offline).
  Future<void> recordMissed({
    required String collectorId,
    required String collectorName,
    required TourneeStop stop,
    required String reason,
  }) async {
    final todayDate = _todayIso();
    final pickupId = 'PKP-${DateTime.now().millisecondsSinceEpoch}';

    final pickupData = {
      'pickup_id': pickupId,
      'client_id': stop.clientPhone,
      'collector_id': collectorId,
      'collector_name': collectorName,
      'date': todayDate,
      'status': 'missed',
      'miss_reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    };

    // Queue via OfflineSyncService for offline support.
    final offline = OfflineSyncService.instance;
    await offline.queueOperation(
      type: 'set',
      collection: 'pickups',
      documentId: pickupId,
      data: pickupData,
    );
  }

  /// Fetches the collector's past pickups for the history tab.
  Future<List<Map<String, dynamic>>> fetchHistory(String collectorId) async {
    if (collectorId.isEmpty) return [];
    final offline = OfflineSyncService.instance;

    try {
      final snap = await _db
          .collection('pickups')
          .where('collector_id', isEqualTo: collectorId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      final data = snap.docs.map((d) => d.data()).toList();
      // Cache for offline access.
      offline.cacheHistoryData(collectorId, data);
      return data;
    } catch (e) {
      debugPrint('[TourneeService] Error fetching history: $e');
      // Fall back to cached data.
      final cached = offline.getCachedHistoryData(collectorId);
      if (cached != null && cached.isNotEmpty) {
        debugPrint('[TourneeService] Using cached history (${cached.length} entries)');
        return cached;
      }
      return [];
    }
  }

  /// Returns the English day name for today (e.g. 'Tuesday').
  static String _todayKey() {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[DateTime.now().weekday - 1];
  }

  /// Returns today as ISO date (yyyy-MM-dd).
  static String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
