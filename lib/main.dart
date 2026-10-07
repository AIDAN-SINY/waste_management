
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/brand.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';

// Providers
import 'providers/user_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/notification_provider.dart';
import 'services/notification_service.dart';
import 'services/offline_sync_service.dart';

// Screens
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/pre_register_screen.dart';
import 'features/auth/screens/application_status_screen.dart';
import 'features/home/client_dashboard.dart';
import 'features/home/collector_dashboard.dart';
import 'features/backoffice/backoffice_screen.dart';
import 'features/backoffice/data/backoffice_store.dart';
import 'features/company/company_console.dart';
import 'features/superadmin/data/firestore_platform_store.dart';
import 'features/superadmin/data/platform_store.dart';
import 'features/superadmin/super_admin_console.dart';
import 'routing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // No secrets in the app: CamPay, Hugging Face, SMS / WhatsApp keys live
  // in the Cloud Functions (functions/index.js).
  // Initialize Firebase — wrapped in try-catch so the app launches offline.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('Firebase init skipped (offline or unavailable): $e');
  }

  // App Check : prouve que les requêtes viennent de la vraie app (et non
  // d'un client qui aurait extrait les clés API publiques). En debug, le
  // provider debug atteste TOUT appareil ; en production, Play Integrity
  // (Android) / App Attest (iOS).
  //
  //  PAS sur web : sans webProvider (reCAPTCHA), le plugin web jette un
  // `ArgumentError` à CHAQUE lancement (l'erreur « App Check activation
  // skipped » dans la console) — et App Check n'est pas appliqué côté
  // console, donc inutile de le déclencher ici. À réactiver le jour où un
  // provider reCAPTCHA web est configuré.
  if (!kIsWeb) {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode
            ? AndroidProvider.debug
            : AndroidProvider.playIntegrity,
        appleProvider: kDebugMode
            ? AppleProvider.debug
            : AppleProvider.appAttest,
      );
    } catch (e) {
      debugPrint('App Check activation skipped: $e');
    }
  }

  // Configure Firestore offline persistence — skip if Firebase init failed.
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    // Initialize offline sync service for collector mobile app.
    await OfflineSyncService.instance.init();
  } catch (e) {
    debugPrint('Firestore/OfflineSync init skipped: $e');
  }

  // Initialize Provider and Check for existing session
  final userProvider = UserProvider();
  await userProvider.tryAutoLogin();

  // Contract expiry + renewal reminders: daily server job
  // (`contractExpiry` in functions/index.js).

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: userProvider),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(
          create: (_) => NotificationProvider(
            service: NotificationService(),
          ),
        ),
      ],
      child: const WasteProApp(),
    ),
  );
}

/// Provides access to the super admin console Firestore store (created
/// lazily, shared across all console instances to avoid duplicating
/// Firestore subscriptions).
class ConsoleStoreScope extends InheritedWidget {
  const ConsoleStoreScope({
    super.key,
    required this.ensureStore,
    required super.child,
  });

  final PlatformStore Function() ensureStore;

  static PlatformStore storeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ConsoleStoreScope>()!;
    return scope.ensureStore();
  }

  @override
  bool updateShouldNotify(ConsoleStoreScope oldWidget) => true;
}

class WasteProApp extends StatefulWidget {
  const WasteProApp({super.key, this.consoleStore, this.backofficeStore, this.db});

  /// Console store injected by tests (mock) — otherwise a
  /// [FirestorePlatformStore] is created lazily.
  final PlatformStore? consoleStore;

  /// Backoffice store injected by tests (mock) — otherwise a
  /// [FirestoreBackofficeStore] is created by the screen.
  final BackofficeStore? backofficeStore;

  /// Optional Firestore instance for dependency injection in tests.
  final FirebaseFirestore? db;

  @override
  State<WasteProApp> createState() => _WasteProAppState();
}

class _WasteProAppState extends State<WasteProApp> {
  FirestorePlatformStore? _consoleStore;
  GoRouter? _router;
  UserProvider? _userProvider;

  PlatformStore ensureConsoleStore() {
    final override = widget.consoleStore;
    if (override != null) return override;
    // Ne réutilise jamais un store disposé : après dispose, on en recrée un
    // (sinon « A FirestorePlatformStore was used after being disposed »).
    return _consoleStore ??= FirestorePlatformStore();
  }

  GoRouter _buildRouter(UserProvider userProvider) {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: userProvider,
      redirect: (context, state) => consoleRedirect(
        user: userProvider.user,
        path: state.uri.path,
        // En debug, la console reste consultable sans session (store mock)
        // pour prévisualiser/développer par URL.
        allowConsolePreview: kDebugMode,
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              AuthWrapper(backofficeStore: widget.backofficeStore, db: widget.db),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          // Client pre-registration (application): the real account is only created
          // after approval by the agency manager.
          path: '/register',
          builder: (context, state) => const PreRegisterScreen(),
        ),
        GoRoute(
          path: '/console/:page',
          builder: (context, state) {
            final user = context.read<UserProvider>().user;
            final useMock = kDebugMode && user == null;
            return SuperAdminConsole(
              // Sans session (preview debug) → store mock ; sinon le
              // store Firestore partagé.
              store: useMock ? null : ConsoleStoreScope.storeOf(context),
              page: state.pathParameters['page'],
              autoCreate: state.uri.queryParameters['create'],
              db: widget.db,
            );
          },
        ),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userProvider = Provider.of<UserProvider>(context);
    if (_userProvider != userProvider || _router == null) {
      _userProvider = userProvider;
      _router = _buildRouter(userProvider);
    }
  }

  @override
  void dispose() {
    // On ne dispose que le store créé ici (jamais celui injecté par les tests).
    if (widget.consoleStore == null) {
      _consoleStore?.dispose();
      // Réinitialise la référence : un store disposé ne doit plus jamais
      // être rendu par ensureConsoleStore() (sinon l'erreur « used after
      // being disposed » à la prochaine ouverture de la console).
      _consoleStore = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConsoleStoreScope(
      ensureStore: ensureConsoleStore,
      child: MaterialApp.router(
        title: 'Waste Pro Cameroon',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          // Brand colours of the logo (lib/core/brand.dart).
          colorScheme: Brand.colorScheme,
          scaffoldBackgroundColor: Brand.background,
          progressIndicatorTheme:
              const ProgressIndicatorThemeData(color: Brand.green),
          useMaterial3: true,
        ),
        routerConfig: _router!,
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key, this.backofficeStore, this.db});

  /// Backoffice store injected by tests (mock) — otherwise the screen creates
  /// its own [FirestoreBackofficeStore].
  final BackofficeStore? backofficeStore;

  /// Optional Firestore instance for dependency injection in tests.
  final FirebaseFirestore? db;

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

/// Screen shown to an Agency Manager whose account does not yet
/// have an assigned agency (Phase 3).
///
/// Without an agency, the backoffice would have no scope: rather than
/// letting the user see data from all agencies, we ask them to contact
/// their administrator. The company (General Administrator) or super admin
/// must assign the agency manager to an agency in the console; the next
/// login will grant access.
class UnassignedManagerScreen extends StatelessWidget {
  const UnassignedManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Brand.gold.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    size: 30,
                    color: Brand.gold,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No agency assigned yet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your account is not linked to any agency. Contact your '
                  'company administrator so they can assign you to an '
                  'agency — then log in again to access the backoffice.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () {
                    final provider = context.read<UserProvider>();
                    if (provider.user != null) provider.logout();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _lastPhone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.read<UserProvider>().user;
    final currentPhone = user?.phoneNumber;

    // User just logged in → initialize FCM.
    if (currentPhone != null && currentPhone != _lastPhone) {
      _lastPhone = currentPhone;
      context.read<NotificationProvider>().initialize(currentPhone);
    }

    // User just logged out → clear FCM token.
    if (currentPhone == null && _lastPhone != null) {
      context.read<NotificationProvider>().clearOnLogout(_lastPhone!);
      _lastPhone = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    if (userProvider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 1. If no user is logged in, show the Welcome/Preview Screen
    if (userProvider.user == null) {
      return const WelcomeScreen();
    }

    // 2. If user is logged in, direct to their specific Dashboard
    final user = userProvider.user!;
    final role = user.role.trim().toLowerCase();

    // General / Super Administrators: their console.
    if (role == 'super_admin') {
      return SuperAdminConsole(
        store: ConsoleStoreScope.storeOf(context),
        db: widget.db,
      );
    }
    if (role == 'general_admin') {
      return CompanyConsole(societeId: user.societeId);
    }

    if (role == 'collector') {
      return CollectorDashboard(db: widget.db);
    } else if (role == 'pending_client') {
      // Candidature en attente (pré-inscription) : le compte existe déjà
      // (créé à la soumission), mais le client n'est pas encore approuvé —
      // on le garde sur l'écran de suivi de candidature.
      return ApplicationStatusScreen(initialPhone: user.phoneNumber);
    } else if (role == 'agency_manager') {
      // Phase 3 (défense en profondeur) : un chef d'agence sans agence
      // assignée ne doit JAMAIS tomber sur le backoffice non scopé (il
      // verrait les données de toutes les agences). Un écran dédié lui
      // demande de contacter son administrateur.
      if (user.agenceId.isEmpty) {
        return const UnassignedManagerScreen();
      }
      return BackofficeScreen(
        store: widget.backofficeStore,
        agenceId: user.agenceId,
        societeId: user.societeId,
      );
    } else if (role == 'admin') {
      // 'admin' : comptes créés avant la Phase 1 (legacy) → backoffice
      // global (comportement conservé).
      return BackofficeScreen(
        store: widget.backofficeStore,
        agenceId: user.agenceId,
        societeId: user.societeId,
      );
    } else {
      return const ClientDashboard();
    }
  }
}
