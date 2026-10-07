import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Initializes Firebase mocks so that [FirebaseFirestore.instance] and other
/// Firebase services can be used in widget tests without a real Firebase project.
///
/// Usage:
/// ```dart
/// import 'helpers/setup_firebase.dart';
///
/// void main() {
///   setUpAll(() => setupFirebaseMocks());
///   // ...tests that use Firebase...
/// }
/// ```
void setupFirebaseMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  Firebase.initializeApp();
}
