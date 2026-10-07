import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:waste_pro/features/home/collector_dashboard.dart';
import 'package:waste_pro/models/user_model.dart';
import 'package:waste_pro/providers/user_provider.dart';

import 'helpers/setup_firebase.dart';

/// The collection flow's photo step opens the real camera via
/// image_picker's method channel — mock it in tests to return a fake
/// capture path so the flow can complete without a device.
const MethodChannel _imagePickerChannel =
    MethodChannel('plugins.flutter.io/image_picker');

/// The validation step captures the collector's GPS via geolocator's
/// method channel — mock it so tests get a deterministic position and no
/// pending timers.
const MethodChannel _geolocatorChannel =
    MethodChannel('flutter.baseflow.com/geolocator');

/// The photo step requests camera permission via permission_handler's
/// method channel before opening the camera — mock it as granted (the
/// request returns a map of {permissionValue: statusCode}; camera = 1,
/// granted = 1).
const MethodChannel _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

class FakeUserProvider extends UserProvider {
  FakeUserProvider(this._user);

  final UserModel _user;

  @override
  UserModel? get user => _user;
}

/// Seeds the fake Firestore with the test data expected by the collector
/// dashboard tests (8 clients, 2 completed, 1 missed, 5 to-do).
Future<FakeFirebaseFirestore> _seedFirestore() async {
  final db = FakeFirebaseFirestore();

  // Day names for collection_days matching.
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  final today = days[DateTime.now().weekday - 1];

  // 8 clients assigned to collector '+237678901122'.
  final clients = [
    ('c1', 'Jean Dooh', '+237699100001', true),
    ('c2', 'Brice Talla', '+237699100002', true),
    ('c3', 'Robert Essomba', '+237699100003', true),
    ('c4', 'Marie Ekwalla', '+237699100004', true),
    ('c5', 'Samuel Njoya', '+237699100005', true),
    ('c6', 'Carine Mbappe', '+237699100006', true),
    ('c7', 'Landry Fokou', '+237699100007', true),
    ('c8', 'Yolande Essomba', '+237699100008', true),
  ];
  const plan = 'Standard \u00b7 2x/week';

  for (final (id, name, phone, active) in clients) {
    await db.collection('clients').doc(id).set({
      'name': name,
      'phone': phone,
      'collecteurId': '+237678901122',
      'status': active ? 'Active' : 'Inactive',
      'plan': plan,
      'adresse': 'Bastos',
      'quartier': 'Nlongkak',
      'zone': 'Bastos',
    });
    // User doc with subscription + collection days.
    await db.collection('users').doc(phone).set({
      'phoneNumber': phone,
      'fullName': name,
      'role': 'client',
      'isSubscribed': true,
      'collection_days': [today],
      'pickup_time': '07:00 — 08:00',
      'zone_name': 'Bastos',
    });
  }

  // Landry Fokou gets GPS coordinates so "Start Route" opens the live
  // route map (it bails out with a toast when the client has no location).
  await db.collection('clients').doc('c7').update({
    'latitude': 3.8667,
    'longitude': 11.5167,
  });

  // Jean Dooh: verified today (Done) — client has confirmed the pickup.
  final todayDate = DateTime.now().toIso8601String().substring(0, 10);
  final ts = DateTime.now();
  await db.collection('pickups').add({
    'client_id': '+237699100001',
    'collector_id': '+237678901122',
    'status': 'verified',
    'date': todayDate,
    'heure_arrivee': '07:15',
    'heure_depart': '07:30',
    'poids': 5.2,
    'commentaire': '',
    'timestamp': ts,
  });
  // Brice Talla: verified today (Done) — client has confirmed the pickup.
  await db.collection('pickups').add({
    'client_id': '+237699100002',
    'collector_id': '+237678901122',
    'status': 'verified',
    'date': todayDate,
    'heure_arrivee': '07:40',
    'heure_depart': '07:55',
    'poids': 3.1,
    'commentaire': '',
    'timestamp': ts,
  });

  // History: pickups from past days (verified).
  await db.collection('pickups').add({
    'client_id': '+237699100003',
    'collector_id': '+237678901122',
    'status': 'verified',
    'date': '2026-08-04',
    'heure_arrivee': '07:10',
    'heure_depart': '07:25',
    'poids': 4.0,
    'commentaire': '',
    'timestamp': ts.subtract(const Duration(days: 2)),
  });
  await db.collection('pickups').add({
    'client_id': '+237699100001',
    'collector_id': '+237678901122',
    'status': 'verified',
    'date': '2026-08-05',
    'heure_arrivee': '07:20',
    'heure_depart': '07:35',
    'poids': 6.0,
    'commentaire': '',
    'timestamp': ts.subtract(const Duration(days: 1)),
  });

  return db;
}

void main() {
  setUpAll(() {
    setupFirebaseMocks();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePickerChannel, (call) async {
      if (call.method == 'pickImage') return '/tmp/wastepro_test_photo.jpg';
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocatorChannel, (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
        case 'requestPermission':
          return 3; // LocationPermission.whileInUse
        case 'getCurrentPosition':
          return {
            'latitude': 3.8480,
            'longitude': 11.5021,
            'accuracy': 5.0,
            'altitude': 700.0,
            'heading': 0.0, 'speed': 0.0,
            'speed_accuracy': 0.0,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        default:
          return null;
      }
    });

    // Camera permission (permission_handler): granted.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, (call) async {
      switch (call.method) {
        case 'requestPermissions':
          return {1: 1}; // camera → granted
        case 'checkPermissionStatus':
          return 1; // granted
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePickerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocatorChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, null);
  });

  late FakeFirebaseFirestore db;

  Future<void> pumpCollector(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    db = await _seedFirestore();

    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: FakeUserProvider(
          UserModel(
            phoneNumber: '+237678901122',
            fullName: 'Paul Mbarga',
            role: 'collector',
            password: 'pw',
          ),
        ),
        child: MaterialApp(home: CollectorDashboard(db: db)),
      ),
    );
    // Let animations (scan line, ring) play without crashing.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('renders topbar, progress card and route list', (tester) async {
    await pumpCollector(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Paul Mbarga'), findsWidgets);
    expect(find.text("Today's Route"), findsOneWidget);
    expect(find.text('2/8'), findsOneWidget); // 2 Done / 8 clients
    expect(find.text('Jean Dooh'), findsOneWidget);
    expect(find.text('Brice Talla'), findsOneWidget);
    expect(find.text('Missed'), findsWidgets);
    // Filters
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Done'), findsWidgets);
    // Tab bar
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('filters the route by status', (tester) async {
    await pumpCollector(tester);

    // Filter chips scroll horizontally: use first matching widget.
    // (No pumpAndSettle: the QR scan line animates in a loop.)
    // 'Done' text appears on both filter chip and status badges,
    // so we tap the first occurrence (the filter chip).
    await tester.tap(find.text('Done').first);
    await tester.pump();
    expect(find.text('Jean Dooh'), findsOneWidget);
    expect(find.text('Brice Talla'), findsOneWidget);

    await tester.tap(find.text('To Do').first);
    await tester.pump();
    expect(find.text('Robert Essomba'), findsOneWidget);
    expect(find.text('Jean Dooh'), findsNothing);

    await tester.tap(find.text('All').first);
    await tester.pump();
    expect(find.text('Jean Dooh'), findsOneWidget);
    expect(find.text('Brice Talla'), findsOneWidget);
  });

  testWidgets('opens client detail sheet from route', (tester) async {
    await pumpCollector(tester);

    await tester.tap(find.text('Robert Essomba'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Detail sheet: actions + the new primary “Done” button.
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Start Route'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    // 'Done' appears both on the route's filter chip and on the detail
    // sheet's primary button.
    expect(find.text('Done'), findsWidgets);
    expect(find.text('Start Collection'), findsNothing);
    expect(find.text('Standard · 2x/week'), findsOneWidget);
  });

  testWidgets('completes the Done flow: photo then popup with green tick',
      (tester) async {
    await pumpCollector(tester);

    // Open client "Robert Essomba" (To Do).
    await tester.tap(find.text('Robert Essomba'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // "Done" opens the proof-photo step (no QR / OTP / signature anymore).
    await tester.tap(find.text('Done').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Take a Photo'), findsOneWidget);
    expect(find.text('Verify Your Presence'), findsNothing);

    // Take the proof photo (mocked camera returns a path).
    await tester.tap(find.text('Tap to take photo'));
    await tester.pump(const Duration(milliseconds: 300));

    // "Done" on the photo step records the pickup and shows the popup.
    await tester.ensureVisible(find.text('Done').last);
    await tester.pump();
    await tester.tap(find.text('Done').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Pickup recorded!'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.textContaining('totally completed when the client validates'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Close the popup.
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 300));

    // Stop status stays In Progress until the client scans the QR code —
    // the counter must NOT advance past 2/8.
    expect(find.text('2/8'), findsOneWidget);
  });

  testWidgets('Done flow on a To Do client ends on the recorded popup',
      (tester) async {
    await pumpCollector(tester);

    // Marie Ekwalla: a To Do client without seeded history pickups.
    // Her card sits below the fold on the 390x844 viewport — scroll to it
    // first or the tap lands on nothing.
    await tester.ensureVisible(find.text('Marie Ekwalla'));
    await tester.pump();
    await tester.tap(find.text('Marie Ekwalla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Done').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Tap to take photo'));
    await tester.pump(const Duration(milliseconds: 300));
    // The photo step's Done button lives inside the sheet's scroll view —
    // bring it on-screen or the tap can miss.
    await tester.ensureVisible(find.text('Done').last);
    await tester.pump();
    await tester.tap(find.text('Done').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pickup recorded!'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The pickup write itself runs after the popup and first reads the
    // photo file (real I/O, which never completes under the widget test's
    // fake clock) — it is covered in test/tournee_service_test.dart. The
    // client's validation request is sent by the `notify` Cloud Function —
    // covered by tool/functions-smoke.
  });

  testWidgets('route map opens with Pause/Resume and elapsed timer',
      (tester) async {
    await pumpCollector(tester);

    // Landry Fokou has coordinates, so "Start Route" opens the map.
    await tester.tap(find.text('Landry Fokou'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Start Route'));
    await tester.pump(); // navigation
    await tester.pump(const Duration(milliseconds: 400));

    // Route map opened with the client's name as title.
    expect(find.text('Landry Fokou'), findsWidgets);
    expect(find.text('Navigate with GPS'), findsOneWidget);
    // Elapsed timer label (mm:ss). It reads the real clock, so on a slow
    // machine it can already show 00:01 — only its format is checked.
    final timer = find.byWidgetPredicate((w) =>
        w is Text && RegExp(r'^\d\d:\d\d$').hasMatch(w.data ?? ''));
    expect(timer, findsOneWidget);
    expect(find.text('Live'), findsOneWidget);

    // Pause freezes the timer: the elapsed label stays identical.
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    final frozen = (tester.widget(timer) as Text).data;
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Live'), findsNothing);
    expect((tester.widget(timer) as Text).data, frozen); // frozen

    // Resume restarts it.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.text('Paused'), findsNothing);
    expect(find.text('Live'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marks a client as missed with a reason', (tester) async {
    await pumpCollector(tester);

    await tester.tap(find.text('Robert Essomba'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Report'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Report a Problem'), findsOneWidget);

    // Confirm is disabled until a reason is selected.
    await tester.tap(find.text('Client absent'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Collection marked as missed.'),
      findsOneWidget,
    );
    // Counter stays 2/8, Robert Essomba is now Missed.
    expect(find.text('2/8'), findsOneWidget);
  });

  testWidgets('switches to history and profile tabs', (tester) async {
    await pumpCollector(tester);

    await tester.tap(find.text('History'));
    await tester.pump();
    expect(find.textContaining('August'), findsWidgets);

    await tester.tap(find.text('Profile'));
    await tester.pump();
    expect(find.text('Collector · Bastos / Nlongkak Zone'), findsOneWidget);
    expect(find.text('312'), findsOneWidget);
    expect(find.text('+237678901122'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
  });
}
