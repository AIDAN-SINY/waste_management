import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert' show utf8;
import '../models/user_model.dart';
import '../services/auth_backend.dart';
import '../services/auth_service.dart';

/// État de connexion global de l'app.
///
/// Depuis la migration sécurité, la session vit dans Firebase Auth (email
/// dérivé du numéro) : [tryAutoLogin] restaure la session persistée par Auth
/// et recharge le profil `users/{téléphone}` correspondant via
/// `auth_profiles/{uid}` (uid → téléphone).
class UserProvider with ChangeNotifier {
  UserProvider({AuthBackend? backend})
      : _backend = backend ?? FirebaseAuthBackend();

  final AuthBackend _backend;

  UserModel? _user;
  bool _isLoading = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;

  // 1. Set User and Persist Session
  Future<void> setUser(UserModel user) async {
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_phone',
      user.phoneNumber,
    ); // Save phone locally
    // Cache du profil : permet de restaurer la session HORS-LIGNE
    // (les lectures Firestore `get()` ne rendent jamais la main sans
    // réseau — seule la persistance locale peut le faire).
    await prefs.setString('cached_user', jsonEncode(user.toMap()));
    notifyListeners();
  }

  // 2. Try Auto-Login on Startup (session Firebase Auth persistée)
  Future<void> tryAutoLogin() async {
    // Restauration OFFLINE-D'ABORD : si le profil est en cache local, on
    // le restaure immédiatement (le réseau ne doit jamais bloquer le
    // lancement de l'app — notamment sur web en localhost sans connexion).
    final cached = await _restoreCachedUser();
    if (cached != null) {
      _user = cached;
      notifyListeners();
    }

    final uid = _backend.currentUid;
    if (uid == null) return;

    // Profils Auth → téléphone. Doc en cache Firestore accepté ici :
    // un get() réseau peut ne jamais répondre hors-ligne.
    String? phone;
    try {
      final profile = await FirebaseFirestore.instance
          .collection('auth_profiles')
          .doc(uid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (profile.exists) {
        phone = profile.data()?['phone'] as String?;
      }
    } catch (_) {
      // Hors-ligne / pas encore de cache → on tentera le réseau ci-dessous.
    }

    if (phone == null || phone.isEmpty) {
      // Réseau uniquement si le cache n'a rien donné (app fraîchement
      // installée). Borné par un timeout pour ne pas geler le démarrage.
      try {
        final profile = await FirebaseFirestore.instance
            .collection('auth_profiles')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 8));
        if (profile.exists) {
          phone = profile.data()?['phone'] as String?;
        }
      } catch (e) {
        debugPrint("Error restoring session (offline?): $e");
        return; // Le cache éventuel suffit pour démarrer.
      }
    }
    if (phone == null || phone.isEmpty) return;

    // Si le cache a déjà fourni CET utilisateur, pas besoin de réseau :
    // la session démarre instantanément, hors-ligne comme en ligne.
    if (cached != null && cached.phoneNumber == phone) return;

    await refreshUser(phone);
  }

  /// Lit le profil utilisateur mis en cache par [setUser].
  Future<UserModel?> _restoreCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_user');
      if (raw == null || raw.isEmpty) return null;
      return UserModel.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint("Error reading cached user: $e");
      return null;
    }
  }

  // 3. Fetch/Refresh user data from Firestore
  Future<void> refreshUser(String phone) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Essaie la clé telle que sauvegardée, puis sa forme canonique
      // (+237...) : un doc créé à la main dans la console peut avoir une
      // clé différente du champ phoneNumber (ex. clé '677123456', champ
      // '+237677123456').
      // NOTE : on ne remet plus _user à null — un refresh hors-ligne ne
      // doit pas déconnecter l'utilisateur (le cache reste la référence).
      UserModel? fetched;
      for (final key in AuthService.canonicalKeys(phone)) {
        if (key.isEmpty) continue;
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(key)
            .get()
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw TimeoutException('refreshUser($key)'),
            );
        if (doc.exists) {
          fetched = UserModel.fromMap(doc.data()!);
          break;
        }
      }
      if (fetched != null) {
        _user = fetched;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user', jsonEncode(fetched.toMap()));
      } else if (_user == null) {
        // Aucun doc trouvé (ni réseau ni cache) et aucun utilisateur en
        // mémoire : on délègue à l'écran de login via user == null.
        debugPrint('refreshUser: no user doc found for $phone');
      }
    } catch (e) {
      debugPrint("Error fetching user: $e");
      // On garde l'utilisateur courant (cache) : ne jamais déconnecter
      // pour une simple panne réseau.
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Met à jour le point de collecte (latitude/longitude) du client.
  ///
  /// Écrit dans `users/{phone}` ET `clients/{id}` quand le client est lié à
  /// une fiche backoffice (le collecteur lit la fiche `clients` pour sa
  /// tournée, le dashboard lit `users` pour l'affichage).
  Future<void> updateLocation({
    required double latitude,
    required double longitude,
  }) async {
    final user = _user;
    if (user == null) throw 'You must be logged in.';
    try {
      final batch = FirebaseFirestore.instance.batch();
      final phoneKey = await _resolveUserDocKey(user.phoneNumber);
      batch.set(
        FirebaseFirestore.instance.collection('users').doc(phoneKey),
        {
          'latitude': latitude,
          'longitude': longitude,
          'location_updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Fiche backoffice liée (créée à l'approbation) : même mise à jour,
      // le collecteur en tire sa tournée du jour.
      final clientDoc = await _findClientDoc(user.phoneNumber);
      if (clientDoc != null) {
        batch.set(
          FirebaseFirestore.instance.collection('clients').doc(clientDoc),
          {
            'latitude': latitude,
            'longitude': longitude,
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      _user = UserModel(
        phoneNumber: user.phoneNumber,
        fullName: user.fullName,
        role: user.role,
        uid: user.uid,
        registrationStatus: user.registrationStatus,
        latitude: latitude,
        longitude: longitude,
        subscriptionPlan: user.subscriptionPlan,
        isSubscribed: user.isSubscribed,
        societeId: user.societeId,
        agenceId: user.agenceId,
        agenceName: user.agenceName,
        collecteurId: user.collecteurId,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating location: $e');
      throw 'Could not save your collection point. Please try again.';
    }
  }

  /// Définit (ou change) le code PIN de sécurité du client.
  ///
  /// Seul un hash SHA-256 est stocké — jamais le PIN en clair.
  Future<void> updateSecurityPin(String pin) async {
    final user = _user;
    if (user == null) throw 'You must be logged in.';
    if (pin.length != 4 || int.tryParse(pin) == null) {
      throw 'The PIN must be exactly 4 digits.';
    }
    try {
      final hash = sha256.convert(utf8.encode('wastepro:pin:$pin')).toString();
      final phoneKey = await _resolveUserDocKey(user.phoneNumber);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(phoneKey)
          .set(
            {
              'securityPinHash': hash,
              'security_pin_updated_at': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('Error updating security PIN: $e');
      throw 'Could not save your PIN. Please try again.';
    }
  }

  /// Vrai si un PIN de sécurité a déjà été défini.
  Future<bool> hasSecurityPin() async {
    final user = _user;
    if (user == null) return false;
    try {
      final phoneKey = await _resolveUserDocKey(user.phoneNumber);
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(phoneKey)
          .get();
      final hash = doc.data()?['securityPinHash'] as String? ?? '';
      return hash.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Vérifie un PIN saisi contre le hash stocké.
  Future<bool> verifySecurityPin(String pin) async {
    final user = _user;
    if (user == null) return false;
    try {
      final phoneKey = await _resolveUserDocKey(user.phoneNumber);
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(phoneKey)
          .get();
      final hash = doc.data()?['securityPinHash'] as String? ?? '';
      if (hash.isEmpty) return false;
      return hash == sha256.convert(utf8.encode('wastepro:pin:$pin')).toString();
    } catch (_) {
      return false;
    }
  }

  /// Clé du doc `users` du compte : essaie la forme canonique puis la clé
  /// brute (docs créés à la main avec un numéro sans +237).
  Future<String> _resolveUserDocKey(String phone) async {
    for (final key in AuthService.canonicalKeys(phone)) {
      if (key.isEmpty) continue;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(key)
          .get();
      if (doc.exists) return key;
    }
    // Aucun doc existant : la forme canonique fera foi (créé au merge).
    return AuthService.canonicalPhone(phone);
  }

  /// Id du doc `clients` lié à ce numéro (fiche backoffice), ou null.
  Future<String?> _findClientDoc(String phone) async {
    final canonical = AuthService.canonicalPhone(phone);
    if (canonical.isEmpty) return null;
    String digitsOf(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
    final target = digitsOf(canonical);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('clients')
          .where('phone', isEqualTo: canonical)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.id;
      // Secours : comparaison sur les chiffres (espaces / +237 variants).
      final loose = await FirebaseFirestore.instance
          .collection('clients')
          .where('phone', isGreaterThanOrEqualTo: canonical.substring(0, 5))
          .limit(50)
          .get();
      for (final d in loose.docs) {
        if (digitsOf(d.data()['phone'] as String? ?? '') == target) {
          return d.id;
        }
      }
    } catch (e) {
      debugPrint('Error finding client doc: $e');
    }
    return null;
  }

  // 4. Logout and Clear Session (Firebase Auth)
  Future<void> logout() async {
    //  Ordre critique : la session APP est vidée SYNCHRONIQUEMENT, AVANT
    // le signOut backend. Si le signOut Firebase reste bloqué (réseau,
    // plugin web/desktop…), l'utilisateur doit quand même pouvoir quitter
    // le backoffice et se reconnecter avec un autre compte — le prochain
    // signInWithEmailAndPassword remplacera de toute façon la session Auth.
    _user = null;
    notifyListeners();

    // Nettoyage local best-effort (ne bloque jamais le logout).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_phone'); // Delete saved session
      await prefs.remove('cached_user'); // Delete cached profile
    } catch (e) {
      debugPrint("Error clearing saved session: $e");
    }

    // SignOut Firebase en arrière-plan (best-effort).
    try {
      await _backend.signOut();
    } catch (e) {
      debugPrint("Error signing out: $e");
    }
  }
}
