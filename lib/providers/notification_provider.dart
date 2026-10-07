import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../services/notification_service.dart';

/// Wraps [NotificationService] as a [ChangeNotifier] so the widget tree
/// can react to foreground push notifications and the app can manage the
/// service lifecycle (init on login, dispose on logout).
///
/// When constructed without a [service] (test / preview mode), all methods
/// become silent no-ops — no Firebase dependency is required.
class NotificationProvider extends ChangeNotifier {
  NotificationProvider({NotificationService? service})
      : _service = service;

  final NotificationService? _service;
  StreamSubscription<RemoteMessage>? _sub;

  /// Latest foreground message (null until one arrives).
  RemoteMessage? get lastMessage => _lastMessage;
  RemoteMessage? _lastMessage;

  /// Stream of foreground messages — useful for showing in-app toasts.
  Stream<RemoteMessage> get onMessage =>
      _service?.onForegroundMessage ?? const Stream.empty();

  /// Whether the service has been initialized for the current user.
  bool get isInitialized => _isInitialized;
  bool _isInitialized = false;

  /// Whether a real FCM service is backing this provider.
  bool get hasService => _service != null;

  /// Initializes FCM for the given user (request permission, get token,
  /// start listening).  Safe to call multiple times (no-ops if already
  /// initialized for the same user).
  Future<void> initialize(String userPhone) async {
    if (_isInitialized || _service == null) return;
    await _service.initialize(userPhone: userPhone);
    _sub = _service.onForegroundMessage.listen((msg) {
      _lastMessage = msg;
      notifyListeners();
    });
    _isInitialized = true;
    notifyListeners();
  }

  /// Subscribes to a broadcast topic.
  Future<void> subscribeToTopic(String topic) async =>
      _service?.subscribeToTopic(topic);

  /// Unsubscribes from a broadcast topic.
  Future<void> unsubscribeFromTopic(String topic) async =>
      _service?.unsubscribeFromTopic(topic);

  /// Clears the FCM token and resets state — call on logout.
  Future<void> clearOnLogout(String userPhone) async {
    await _service?.clearToken(userPhone);
    _sub?.cancel();
    _sub = null;
    _lastMessage = null;
    _isInitialized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service?.dispose();
    super.dispose();
  }
}
