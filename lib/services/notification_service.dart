import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'functions_client.dart';

/// Pickup lifecycle events reported to the `notify` Cloud Function.
enum PickupEvent {
  /// Collector finished a pickup → the client is asked to validate it.
  confirmationRequest('pickup_confirmation_request'),

  /// Client validated the pickup → client + collector are notified.
  confirmed('pickup_confirmed'),

  /// Client reported a problem with the pickup.
  disputed('pickup_disputed');

  const PickupEvent(this.wireName);
  final String wireName;
}

/// Issue lifecycle events reported to the `notify` Cloud Function.
enum IssueEvent {
  /// The agency manager assigned the issue → the collector (+ the client).
  assigned('issue_assigned'),

  /// The collector started working on it → the client.
  started('issue_started'),

  /// The collector resolved it → the client.
  resolved('issue_resolved');

  const IssueEvent(this.wireName);
  final String wireName;
}

/// Background message handler — must be a top-level function.
///
/// Called when a notification arrives while the app is in the background or
/// terminated.  Keep this lightweight: just log or persist; the foreground
/// listener handles UI updates.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  debugPrint(
    '[FCM] background message: ${message.messageId} '
    'title=${message.notification?.title}',
  );
}

/// Push notification service backed by Firebase Cloud Messaging (FCM).
///
/// Responsibilities:
///   1. Request permission (iOS / web).
///   2. Obtain and persist the FCM token in the user's Firestore profile
///      (`users/{phone}.fcmToken`) so the backend / Cloud Functions can
///      send targeted push messages.
///   3. Listen for foreground messages and expose them via a stream.
///   4. Handle notification taps (foreground, background, terminated).
class NotificationService {
  NotificationService({
    FirebaseFirestore? db,
    FirebaseMessaging? messaging,
    FunctionsClient? functions,
  })  : _db = db ?? FirebaseFirestore.instance,
        _messagingOverride = messaging,
        _functions = functions;

  final FirebaseFirestore _db;
  final FirebaseMessaging? _messagingOverride;
  final FunctionsClient? _functions;

  /// Resolved lazily: building the service never touches the plugins.
  FirebaseMessaging get _messaging =>
      _messagingOverride ?? FirebaseMessaging.instance;
  FunctionsClient get _functionsClient => _functions ?? FunctionsClient();

  // ------------------------------------------------------------------
  // Foreground message stream
  // ------------------------------------------------------------------

  /// Controller for foreground messages.
  final _foregroundController =
      StreamController<RemoteMessage>.broadcast();

  /// Stream of messages received while the app is in the foreground.
  Stream<RemoteMessage> get onForegroundMessage =>
      _foregroundController.stream;

  // ------------------------------------------------------------------
  // Initialization
  // ------------------------------------------------------------------

  /// Initializes FCM: requests permission, retrieves the token, stores it
  /// in Firestore, and sets up listeners.
  ///
  /// Call once after login (when we know the user's phone number).
  Future<void> initialize({required String userPhone}) async {
    try {
      // 1. Request permission (no-op on Android, critical on iOS / web).
      await _requestPermission();

      // 2. Get and persist the FCM token.
      final token = await _messaging.getToken();
      if (token != null) {
        await _persistToken(userPhone: userPhone, token: token);
      }

      // 3. Listen for token refresh (device re-registration, etc.).
      _messaging.onTokenRefresh.listen((newToken) {
        _persistToken(userPhone: userPhone, token: newToken);
      });

      // 4. Listen for foreground messages.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          '[FCM] foreground message: ${message.messageId} '
          'title=${message.notification?.title}',
        );
        _foregroundController.add(message);
      });

      // 5. Handle notification taps when the app is in the background.
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint(
          '[FCM] message opened from background: ${message.messageId}',
        );
        handleNotificationTap(message);
      });

      // 6. Check if the app was opened from a terminated state via a
      //    notification tap.
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          '[FCM] app opened from terminated via notification: '
          '${initialMessage.messageId}',
        );
        // Delay slightly so the widget tree is ready.
        Future.delayed(
          const Duration(milliseconds: 500),
          () => handleNotificationTap(initialMessage),
        );
      }
    } catch (e) {
      debugPrint('[FCM] initialization error: $e');
    }
  }

  // ------------------------------------------------------------------
  // Permission
  // ------------------------------------------------------------------

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint(
      '[FCM] permission status: ${settings.authorizationStatus}',
    );
  }

  // ------------------------------------------------------------------
  // Token persistence
  // ------------------------------------------------------------------

  /// Stores the FCM token in the user's Firestore profile so Cloud
  /// Functions / backend can target this device.
  Future<void> _persistToken({
    required String userPhone,
    required String token,
  }) async {
    try {
      await _db.collection('users').doc(userPhone).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );
      debugPrint('[FCM] token persisted for $userPhone');
    } catch (e) {
      debugPrint('[FCM] failed to persist token: $e');
    }
  }

  // ------------------------------------------------------------------
  // Token retrieval
  // ------------------------------------------------------------------

  /// Returns the current FCM token (useful for debugging / testing).
  Future<String?> getFCMToken() => _messaging.getToken();

  // ------------------------------------------------------------------
  // Topic management
  // ------------------------------------------------------------------

  /// Subscribes this device to a broadcast topic (e.g. `'all_clients'`,
  /// `'agency_ag1'`).
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
    debugPrint('[FCM] subscribed to topic: $topic');
  }

  /// Unsubscribes this device from a broadcast topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    debugPrint('[FCM] unsubscribed from topic: $topic');
  }

  // ------------------------------------------------------------------
  // Pickup notifications (sent by the `notify` Cloud Function)
  // ------------------------------------------------------------------

  /// Reports a pickup [event] to the server, which notifies the people
  /// concerned (in-app bell, push, SMS / WhatsApp) from fixed templates.
  ///
  /// The app never holds SMS / WhatsApp credentials nor writes another
  /// user's notifications: the server checks that the caller is the
  /// pickup's collector (or client) and reads the details from the pickup.
  /// Best-effort — a failed notification never blocks the pickup flow.
  Future<void> notifyPickupEvent(
    PickupEvent event, {
    required String pickupId,
    String reason = '',
  }) async {
    if (pickupId.isEmpty) return;
    try {
      await _functionsClient.post('notify', {
        'event': event.wireName,
        'pickupId': pickupId,
        if (reason.isNotEmpty) 'reason': reason,
      });
    } catch (e) {
      debugPrint('[NotificationService] notify(${event.wireName}) failed: $e');
    }
  }

  /// Reports an issue [event] to the server (same rules as
  /// [notifyPickupEvent]: the server checks the caller and reads the issue).
  Future<void> notifyIssueEvent(IssueEvent event, {required String issueId}) async {
    if (issueId.isEmpty) return;
    try {
      await _functionsClient.post('notify', {
        'event': event.wireName,
        'issueId': issueId,
      });
    } catch (e) {
      debugPrint('[NotificationService] notify(${event.wireName}) failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // Notification tap handling
  // ------------------------------------------------------------------

  /// Handles a notification tap — routes the user to the relevant screen.
  ///
  /// Uses the `data` payload to determine routing.  Extend this method as
  /// new notification types are added.
  ///
  /// Returns the screen constructor arguments needed, or null if no special
  /// routing is required.
  Map<String, dynamic>? handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String? ?? '';
    debugPrint('[FCM] notification tap: type=$type, data=$data');

    switch (type) {
      case 'pickup_to_confirm':
        return {
          'pickupId': data['pickupId'] as String? ?? '',
          'screen': 'pickup_confirmation',
        };
      default:
        return null;
    }
  }

  // ------------------------------------------------------------------
  // Cleanup
  // ------------------------------------------------------------------

  void dispose() {
    _foregroundController.close();
  }

  /// Removes the FCM token from Firestore on logout.
  Future<void> clearToken(String userPhone) async {
    try {
      await _db.collection('users').doc(userPhone).update({
        'fcmToken': FieldValue.delete(),
      });
      await _messaging.deleteToken();
      debugPrint('[FCM] token cleared for $userPhone');
    } catch (e) {
      debugPrint('[FCM] failed to clear token: $e');
    }
  }
}
