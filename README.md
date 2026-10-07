# waste_pro

A new Flutter project for househol.

## Sécurité — Phase 1 (Firebase Auth + règles Firestore)

- **Connexion** : Firebase Auth (email dérivé du numéro : `2376XXXXXXX@wastepro.cm`).
  Les comptes créés avant cette migration sont migrés à la volée à leur première
  connexion (mot de passe vérifié sur le doc `users` hérité, puis compte auth créé).
- **Rôles** : collection `roles/{uid}` (client / collector / admin / super_admin),
  écrite à la première connexion et à l'inscription.
- **Règles Firestore** (`firestore.rules`) : toute lecture/écriture exige une
  session Firebase Auth. Les collections d'administration sont verrouillées par
  rôle (super_admin pour sociétés/agences/utilisateurs ; admin pour
  clients/collecteurs). Aucune auto-promotion possible (le rôle du doc `roles`
  doit correspondre à celui du doc `users`).

### Déploiement / prérequis

1. Firebase Console → Authentication → Sign-in method → activer **Email/Password**.
2. Déployer les règles : `firebase deploy --only firestore:rules`.
3. (Recommandé) `flutterfire configure` pour enregistrer une app web dédiée.
4. Build web + hosting : `flutter build web && firebase deploy --only hosting`.

### Limite connue (transition)

Les comptes « legacy » (doc `users` sans champ `email`) restent lisibles sans
auth (get ciblé, pour la migration) tant qu'ils n'ont pas été connectés une
première fois. **Connecter le compte super admin juste après le déploiement**
pour le migrer immédiatement. La révocation complète (suspension) et la
suppression des mots de passe hérités de Firestore passeront par des Cloud
Functions (suivi Phase 2).

## Routage URL — Phase 2 (console super admin)

La console super admin vit sur des routes URL (`go_router`) :

- `/console/overview`, `/console/societes`, `/console/agences`,
  `/console/utilisateurs`, `/console/rapports`, `/console/parametres`
- Rechargement de page → la page est restaurée depuis l'URL.
- Bouton retour du navigateur → historique par page.
- Liens partageables (`https://site.fr/#/console/societes`).
- Redirection par rôle (`lib/routing.dart`) : la console est réservée au
  super admin ; les non-connectés sont renvoyés à l'accueil (sauf preview
  debug, `kDebugMode`).
- Palette de commandes (⌘K) : « Nouvelle société/agence/utilisateur » ouvre
  le drawer ciblé via `?create=`.

En debug uniquement, la console est consultable sans session (store mock)
via son URL — pratique pour développer l'interface web. En production, la
session + les règles Firestore sont obligatoires.

## État du déploiement (août 2026)

- **App en ligne** : `https://waste-pro-f67a5.web.app` (Firebase Hosting,
  build release). La console exige une session réelle (pas de preview).
- **Règles Firestore déployées** (`firestore.rules`) — trois corrections
  importantes appliquées après tests réels sur le projet :
  1. `role()` et les helpers `userEmail`/`userRole` sont protégés contre les
     documents manquants (`exists()` + ternaire) — une erreur d'évaluation
     faisait échouer TOUTE la règle (inscription bloquée).
  2. La condition d'email de l'update `users` utilise des tests `in`
     explicites — dans l'évaluateur, un champ **absent ≠ null** : les docs
     legacy (sans `email`) étaient impossibles à mettre à jour (migration
     bloquée).
  3. La migration d'un compte legacy est réservée à **SON propriétaire** :
     l'email posé doit être celui de l'utilisateur (`== authEmail()`) **et**
     dérivé du numéro du doc lui-même (`derivedEmail(phone)`) — sans ça,
     n'importe qui connecté pouvait poser son email sur un doc legacy et
     s'approprier son rôle (escalade de privilèges, testée et bloquée).
- **App Check** : l'application sur le service Authentication a été
  **désactivée** (elle bloquait tout login web/mobile ; le web exigerait une
  clé reCAPTCHA Enterprise payante). Firestore n'était pas concerné. →
  réactivable plus tard via console Firebase (App Check) après mise en place
  de reCAPTCHA Enterprise.
- **Compte super admin migré** : `+237674738258` (daizi) est lié à Firebase
  Auth (email `237674738258@wastepro.cm`), doc `roles` créé. Les autres
  comptes legacy seront migrés à leur première connexion.
- **Provider Email/Password** : déjà actif sur le projet.

⚠️ **Recommandations** : changer le mot de passe du compte super admin (il est
encore stocké en clair dans Firestore côté legacy) ; supprimer les données de
test dans `users` (docs sans préfixe `+` : `653645807`, `658783091`, …) ;
restreindre la règle `users list` (actuellement `signedIn()` → tout utilisateur
connecté peut lister les profils, mots de passe legacy compris — à restreindre
une fois que les flux mobiles qui en dépendent seront couverts autrement).

## Getting Started

This project is a starting point for a Flutter application.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
