import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

/// Error returned by a Cloud Function (message is UI-ready).
class FunctionsException implements Exception {
  const FunctionsException(this.statusCode, this.message);

  /// HTTP status, 0 for a network failure.
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// HTTP client for the project's Cloud Functions (`functions/index.js`).
///
/// Authenticated calls carry the Firebase ID token; the functions read the
/// caller's role from `auth_profiles/{uid}`.
class FunctionsClient {
  FunctionsClient({
    http.Client? client,
    FirebaseAuth? auth,
    String? baseUrl,
    Future<String?> Function()? idToken,
  })  : _client = client ?? http.Client(),
        _auth = auth,
        _baseUrl = baseUrl,
        _idToken = idToken;

  final http.Client _client;
  final FirebaseAuth? _auth;
  final String? _baseUrl;

  /// ID token source (tests); defaults to the signed-in Firebase user.
  final Future<String?> Function()? _idToken;

  /// Server address override: `--dart-define=FUNCTIONS_URL=<url>`
  /// (`cloud` = the deployed Cloud Functions).
  static const String _urlOverride = String.fromEnvironment('FUNCTIONS_URL');

  /// Local server (functions/local-server.js, `npm run local`).
  static const String localServerUrl = 'http://localhost:5055';

  /// Debug runs (`flutter run`) use the local server on this PC; release
  /// builds use the deployed Cloud Functions.
  String get baseUrl {
    if (_baseUrl != null) return _baseUrl;
    final cloud = 'https://us-central1-'
        '${DefaultFirebaseOptions.currentPlatform.projectId}'
        '.cloudfunctions.net';
    if (_urlOverride == 'cloud') return cloud;
    if (_urlOverride.isNotEmpty) return _urlOverride;
    return kDebugMode ? localServerUrl : cloud;
  }

  FirebaseAuth get _firebaseAuth => _auth ?? FirebaseAuth.instance;

  /// POST [body] to [function] as the signed-in user.
  Future<Map<String, dynamic>> post(
    String function,
    Map<String, dynamic> body,
  ) async {
    final token = _idToken != null
        ? await _idToken()
        : await _firebaseAuth.currentUser?.getIdToken();
    if (token == null) {
      throw const FunctionsException(
        401,
        'Your session has expired. Log in again.',
      );
    }
    return _send(
      () => _client.post(
        Uri.parse('$baseUrl/$function'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
  }

  /// Unauthenticated GET (public functions).
  Future<Map<String, dynamic>> getPublic(String function) =>
      _send(() => _client.get(Uri.parse('$baseUrl/$function')));

  /// Unauthenticated POST (public functions, e.g. password reset).
  Future<Map<String, dynamic>> postPublic(
    String function,
    Map<String, dynamic> body,
  ) =>
      _send(
        () => _client.post(
          Uri.parse('$baseUrl/$function'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request();
    } catch (_) {
      throw FunctionsException(
        0,
        baseUrl == localServerUrl
            ? 'The WastePro server is not running. In the functions '
                'folder, start it with: npm.cmd run local'
            : 'Network error. Check your internet connection.',
      );
    }
    Map<String, dynamic> data = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (response.statusCode != 200) {
      throw FunctionsException(
        response.statusCode,
        data['error'] as String? ??
            'Service error (HTTP ${response.statusCode}).',
      );
    }
    return data;
  }
}
