import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Represents a pending operation that needs to be synced to Firestore.
class PendingOperation {
  PendingOperation({
    required this.id,
    required this.type,
    required this.collection,
    required this.documentId,
    required this.data,
    required this.timestamp,
    this.retries = 0,
  });

  final String id;
  final String type; // 'set' | 'update' | 'delete'
  final String collection;
  final String documentId;
  final Map<String, dynamic> data;
  final int timestamp;
  int retries;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'collection': collection,
        'documentId': documentId,
        'data': data,
        'timestamp': timestamp,
        'retries': retries,
      };

  factory PendingOperation.fromMap(Map<String, dynamic> m) => PendingOperation(
        id: m['id'] as String,
        type: m['type'] as String,
        collection: m['collection'] as String,
        documentId: m['documentId'] as String,
        data: Map<String, dynamic>.from(m['data'] as Map? ?? {}),
        timestamp: m['timestamp'] as int,
        retries: m['retries'] as int? ?? 0,
      );
}

/// Manages offline-first operations for the collector mobile app.
///
/// Features:
/// - Monitors connectivity via [Connectivity]
/// - Queues Firestore write operations in Hive when offline
/// - Automatically syncs queued operations when back online
/// - Caches tour data locally for offline access
/// - Provides online/offline status stream
class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  final Connectivity _connectivity = Connectivity();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Box<dynamic>? _queueBox;
  Box<dynamic>? _cacheBox;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = true;
  bool _isSyncing = false;

  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();
  final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();

  /// Stream of online/offline status.
  Stream<bool> get onlineStream => _onlineController.stream;

  /// Stream of pending operation count.
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  /// Current online status.
  bool get isOnline => _isOnline;

  /// Whether a sync is currently in progress.
  bool get isSyncing => _isSyncing;

  /// Number of pending operations.
  int get pendingCount => _queueBox?.length ?? 0;

  /// Initializes Hive boxes and starts connectivity monitoring.
  Future<void> init() async {
    await Hive.initFlutter();
    _queueBox = await Hive.openBox('offline_queue');
    _cacheBox = await Hive.openBox('offline_cache');

    // Check initial connectivity.
    final results = await _connectivity.checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);
    _onlineController.add(_isOnline);
    _pendingCountController.add(pendingCount);

    // Listen for connectivity changes.
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      _onlineController.add(_isOnline);

      debugPrint(
          '[OfflineSync] Connectivity changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');

      // If we just came back online, sync pending operations.
      if (!wasOnline && _isOnline) {
        syncPendingOperations();
      }
    });

    // Try syncing any leftover operations from a previous session.
    if (_isOnline && pendingCount > 0) {
      syncPendingOperations();
    }
  }

  /// Disposes resources.
  void dispose() {
    _connectivitySub?.cancel();
    _onlineController.close();
    _pendingCountController.close();
  }

  // =========================================================================
  // Queuing Operations
  // =========================================================================

  /// Queues a Firestore write operation for later sync.
  ///
  /// If online, executes immediately. If offline, stores in Hive queue.
  Future<void> queueOperation({
    required String type,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    final op = PendingOperation(
      id: 'OP-${DateTime.now().millisecondsSinceEpoch}-$collection',
      type: type,
      collection: collection,
      documentId: documentId,
      data: data,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    if (_isOnline) {
      try {
        await _executeOperation(op);
        debugPrint('[OfflineSync] Executed immediately: ${op.id}');
      } catch (e) {
        debugPrint('[OfflineSync] Failed immediate execution, queuing: $e');
        _enqueue(op);
      }
    } else {
      _enqueue(op);
      debugPrint('[OfflineSync] Queued for later: ${op.id} (${_queueBox?.length} total)');
    }
  }

  void _enqueue(PendingOperation op) {
    _queueBox?.put(op.id, op.toMap());
    _pendingCountController.add(pendingCount);
  }

  /// Executes a single operation against Firestore.
  Future<void> _executeOperation(PendingOperation op) async {
    final docRef = _db.collection(op.collection).doc(op.documentId);

    switch (op.type) {
      case 'set':
        await docRef.set(op.data, SetOptions(merge: true));
        break;
      case 'update':
        await docRef.update(op.data);
        break;
      case 'delete':
        await docRef.delete();
        break;
      default:
        debugPrint('[OfflineSync] Unknown operation type: ${op.type}');
    }
  }

  // =========================================================================
  // Syncing
  // =========================================================================

  /// Syncs all pending operations to Firestore.
  ///
  /// Operations are processed in order. Failed operations are retried
  /// up to 3 times before being discarded.
  Future<void> syncPendingOperations() async {
    if (_isSyncing || _queueBox == null || _queueBox!.isEmpty) return;

    _isSyncing = true;
    debugPrint('[OfflineSync] Starting sync of ${_queueBox!.length} operations...');

    final toRemove = <String>[];

    final keys = _queueBox!.keys.toList();
    for (final key in keys) {
      final raw = _queueBox!.get(key);
      if (raw == null) continue;
      final op = PendingOperation.fromMap(Map<String, dynamic>.from(raw));

      try {
        await _executeOperation(op);
        toRemove.add(op.id);
        debugPrint('[OfflineSync] Synced: ${op.id}');
      } catch (e) {
        op.retries++;
        if (op.retries >= 3) {
          toRemove.add(op.id);
          debugPrint('[OfflineSync] Giving up on ${op.id} after 3 retries: $e');
        } else {
          _queueBox?.put(op.id, op.toMap());
          debugPrint('[OfflineSync] Retry ${op.retries}/3 for ${op.id}: $e');
        }
      }
    }

    // Remove successfully synced and permanently failed operations.
    for (final id in toRemove) {
      _queueBox?.delete(id);
    }

    _isSyncing = false;
    _pendingCountController.add(pendingCount);
    debugPrint('[OfflineSync] Sync complete. ${toRemove.length} operations processed.');
  }

  // =========================================================================
  // Tour Data Caching
  // =========================================================================

  /// Caches today's tour data for offline access.
  Future<void> cacheTourData(String collectorId, List<Map<String, dynamic>> stops) async {
    final key = 'tour_${collectorId}_${_todayIso()}';
    await _cacheBox?.put(key, jsonEncode(stops));
    debugPrint('[OfflineSync] Cached ${stops.length} tour stops for $collectorId');
  }

  /// Retrieves cached tour data for offline access.
  List<Map<String, dynamic>>? getCachedTourData(String collectorId) {
    final key = 'tour_${collectorId}_${_todayIso()}';
    final raw = _cacheBox?.get(key);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('[OfflineSync] Failed to decode cached tour: $e');
      return null;
    }
  }

  /// Caches collector's history data.
  Future<void> cacheHistoryData(String collectorId, List<Map<String, dynamic>> history) async {
    final key = 'history_$collectorId';
    await _cacheBox?.put(key, jsonEncode(history));
  }

  /// Retrieves cached history data.
  List<Map<String, dynamic>>? getCachedHistoryData(String collectorId) {
    final raw = _cacheBox?.get('history_$collectorId');
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return null;
    }
  }

  /// Clears all cached data (e.g. on logout).
  Future<void> clearCache() async {
    await _cacheBox?.clear();
    debugPrint('[OfflineSync] Cache cleared');
  }

  /// Clears the pending operation queue.
  Future<void> clearQueue() async {
    await _queueBox?.clear();
    _pendingCountController.add(0);
    debugPrint('[OfflineSync] Queue cleared');
  }

  static String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
