import 'models/user_model.dart';

/// Phase 2 — Routage URL de la console super admin.
///
/// La console vit sur `/console/:page` (pages : overview, societes, agences,
/// utilisateurs, rapports, parametres). Cela donne :
///   • rechargement de page qui restaure la bonne page ;
///   • bouton retour du navigateur (chaque page = entrée d'historique) ;
///   • liens partageables (`/#/console/societes`).
///
/// Les fonctions de ce module sont pures (testables) — la logique de
/// redirection par rôle y est isolée.

/// Préfixe de base des routes de la console (utilisé aussi par la console
/// pour décider si sa navigation passe par l'URL ou reste interne).
const String consoleBasePath = '/console';

/// Ordre des pages de la console (doit correspondre à l'IndexedStack).
const List<String> consolePageNames = [
  'overview',
  'societes',
  'agences',
  'utilisateurs',
  'rapports',
  'parametres',
];

/// Index de la page de la console à partir de son nom d'URL
/// (inconnu / manquant → vue d'ensemble).
int consolePageIndex(String? page) {
  switch (page) {
    case 'societes':
      return 1;
    case 'agences':
      return 2;
    case 'utilisateurs':
      return 3;
    case 'rapports':
      return 4;
    case 'parametres':
      return 5;
    default:
      return 0;
  }
}

/// Redirection du routeur selon l'état de connexion et le rôle.
///
/// Règles :
///   • `/console/*` → réservé au super admin (sinon retour à l'accueil).
///     En debug, [allowConsolePreview] autorise l'accès sans session pour
///     prévisualiser la console (store mock) par URL.
///   • `/login`, `/register` → interdits une fois connecté (retour à l'accueil).
///   • Accueil `/` → renvoie le super admin vers la console.
///   • Chemin inconnu → accueil.
String? consoleRedirect({
  required UserModel? user,
  required String path,
  bool allowConsolePreview = false,
}) {
  final role = user?.role.trim().toLowerCase();

  if (path.startsWith('/console')) {
    if (user == null) return allowConsolePreview ? null : '/';
    if (role != 'super_admin') return '/';
    return null;
  }

  if (path == '/login' || path == '/register') {
    if (user != null) return '/';
    return null;
  }

  if (path == '/') {
    if (user != null && role == 'super_admin') return '/console/overview';
    return null;
  }

  // Chemin inconnu → retour à l'accueil.
  return '/';
}
