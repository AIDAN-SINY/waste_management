import 'dart:async';
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Manages real-time GPS position uploads for collectors and provides
/// streams for clients/agency managers to track collector positions.
class LiveTrackingService {
  LiveTrackingService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  StreamSubscription<Position>? _positionSub;

  // ── Upload (Collector side) ──────────────────────────────────────

  /// Start streaming the collector's GPS position and uploading to Firestore.
  /// Called when the collector opens the app.
  void startTracking({
    required String collectorId,
    required String collectorName,
  }) {
    // Cancel any existing stream first.
    stopTracking();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25, // Update every 25 meters
        timeLimit: Duration(seconds: 30),
      ),
    ).listen(
      (position) => _uploadPosition(
        collectorId: collectorId,
        collectorName: collectorName,
        position: position,
      ),
      onError: (e) {
        dev.log('[LiveTracking] Position stream error: $e');
      },
    );

    // Also do an immediate first upload.
    _uploadCurrentPosition(collectorId: collectorId, collectorName: collectorName);
  }

  /// Stop uploading GPS position.
  void stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  /// Do a single immediate position upload (e.g. when the collector starts route).
  Future<void> _uploadCurrentPosition({
    required String collectorId,
    required String collectorName,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _uploadPosition(
        collectorId: collectorId,
        collectorName: collectorName,
        position: position,
      );
    } catch (e) {
      dev.log('[LiveTracking] Failed to get current position: $e');
    }
  }

  /// Upload a position to the `collectors` Firestore document.
  Future<void> _uploadPosition({
    required String collectorId,
    required String collectorName,
    required Position position,
  }) async {
    try {
      await _db.collection('collecteurs').doc(collectorId).set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'heading': position.heading,
        'speed': position.speed,
        'accuracy': position.accuracy,
        'lastPositionUpdate': FieldValue.serverTimestamp(),
        'isTracking': true,
      }, SetOptions(merge: true));
    } catch (e) {
      dev.log('[LiveTracking] Failed to upload position: $e');
    }
  }

  /// Mark the collector as not tracking (e.g. when they log out).
  Future<void> stopTrackingFirestore(String collectorId) async {
    try {
      await _db.collection('collecteurs').doc(collectorId).set({
        'isTracking': false,
        'lastPositionUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      dev.log('[LiveTracking] Failed to stop tracking: $e');
    }
  }

  // ── Read (Client / Agency Manager side) ──────────────────────────

  /// Stream a single collector's position in real time.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCollectorPosition(
    String collectorId,
  ) {
    return _db.collection('collecteurs').doc(collectorId).snapshots();
  }

  /// Stream the positions of [agenceId]'s collectors (agency manager map).
  /// Returns a list of maps with: id, name, latitude, longitude, isTracking, etc.
  /// Collectors without a position are skipped in memory.
  Stream<List<Map<String, dynamic>>> watchAllCollectors({
    String agenceId = '',
  }) {
    Query<Map<String, dynamic>> query = _db.collection('collecteurs');
    // The rules only allow the manager's own agency.
    if (agenceId.isNotEmpty) {
      query = query.where('agenceId', isEqualTo: agenceId);
    }
    return query.snapshots().map((snapshot) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        // Reject missing, (0,0), or out-of-country coordinates (e.g. a stray
        // test record parked in Washington) — same guard as the client/collector
        // tracking screens, so the backoffice map never flies to a bogus spot.
        final inCountry = lat != null && lng != null &&
            !(lat == 0 && lng == 0) &&
            (lat > 1 && lat < 14) && (lng > 8 && lng < 17);
        if (inCountry) {
          list.add({
            'id': doc.id,
            'name': (data['name'] as String?) ?? '',
            'latitude': lat,
            'longitude': lng,
            'heading': (data['heading'] as num?)?.toDouble() ?? 0,
            'speed': (data['speed'] as num?)?.toDouble() ?? 0,
            'accuracy': (data['accuracy'] as num?)?.toDouble() ?? 0,
            'isTracking': data['isTracking'] as bool? ?? false,
            'lastPositionUpdate': data['lastPositionUpdate'],
          });
        }
      }
      return list;
    });
  }

  void dispose() {
    stopTracking();
  }
}
