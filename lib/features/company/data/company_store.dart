import 'package:flutter/foundation.dart';

import '../../../models/agence_model.dart';
import '../../../models/platform_user_model.dart';
import '../../../models/societe_model.dart';
import '../../backoffice/models.dart';

/// Store de la console entreprise (General Administrator).
///
/// Données scopées à l'entreprise du connecté ([societeId]) : sa société,
/// ses agences, et ses utilisateurs (chefs d'agence). La base (mock) tient
/// les listes en mémoire ; [FirestoreCompanyStore] (firestore_company_store)
/// persiste dans Firestore avec la même interface (ChangeNotifier + CRUD).
///
/// [selectedAgenceId] permet au General Administrator de « zoomer » sur une
/// agence : le dropdown du header change les stats de l'Overview pour cette
/// agence ('' = toute l'entreprise).
class CompanyStore extends ChangeNotifier {
  CompanyStore({this.societeId = ''});

  /// Entreprise de l'administrateur connecté ('' en preview démo / tests).
  final String societeId;

  /// Id de l'agence sélectionnée par le dropdown du header ('' = toutes).
  String _selectedAgenceId = '';
  String get selectedAgenceId => _selectedAgenceId;

  /// Re-sélectionne l'agence sur laquelle l'Overview se concentre.
  void selectAgence(String id) {
    _selectedAgenceId = id;
    notifyListeners();
  }

  /// L'agence sélectionnée, ou null quand le scope couvre toute l'entreprise.
  AgenceModel? get selectedAgence {
    if (_selectedAgenceId.isEmpty) return null;
    for (final a in agences) {
      if (a.id == _selectedAgenceId) return a;
    }
    return null;
  }

  /// Agences dans le scope courant (toutes, ou uniquement la sélectionnée).
  List<AgenceModel> get scopedAgences {
    final sel = selectedAgence;
    return sel == null ? agences : [sel];
  }

  /// Utilisateurs (chefs d'agence) dans le scope courant.
  ///
  /// Le General Administrator de l'entreprise vit aussi dans `utilisateurs`
  /// (créé par le super admin) : il n'est PAS un chef d'agence, il est
  /// exclu des listes de managers.
  List<PlatformUserModel> get scopedUtilisateurs {
    final sel = selectedAgence;
    final managers = utilisateurs.where(_isManager).toList();
    if (sel == null) return managers;
    return managers
        .where((u) =>
            u.agenceId == sel.id || u.agence == sel.ville)
        .toList();
  }

  /// Vrai si [u] est un chef d'agence (et non le General Administrator
  /// lui-même, ni un rôle inconnu).
  static bool _isManager(PlatformUserModel u) {
    final role = u.role.trim().toLowerCase();
    return role != 'general administrator' &&
        role != 'administrateur général' &&
        role != 'administrateur general';
  }

  /// Clients (abonnés) de l'entreprise dans le scope courant (tous, ou
  /// uniquement ceux de l'agence sélectionnée par le dropdown).
  List<ClientModel> get scopedClients {
    final sel = selectedAgence;
    if (sel == null) return clients;
    return clients.where((c) => c.agenceId == sel.id).toList();
  }

  /// Nombre de chefs d'agence affectés à [agenceId].
  int managersForAgence(String agenceId) {
    return utilisateurs
        .where((u) => _isManager(u) && u.agenceId == agenceId)
        .length;
  }

  /// Agences actives du scope courant.
  int get activeAgencies =>
      scopedAgences.where((a) => a.status == 'Active' || a.status == 'Actif').length;

  /// Répartition des rôles utilisateurs (pour le donut « managers »).
  int get scopedManagersCount => scopedUtilisateurs.length;

  /// Tous les managers (chefs d'agence) de l'entreprise, sans le General
  /// Administrator.
  List<PlatformUserModel> get managers =>
      utilisateurs.where(_isManager).toList();

  /// Nombre de managers (hors General Administrator).
  int get managersCount => managers.length;

  int _uid = 1000;

  /// Génère un id unique. Surchargé par le store Firestore pour produire
  /// des ids qui ne se heurtent jamais entre sessions.
  @protected
  String nextId() => 'id${_uid++}';

  // --- Cycle de vie (prêt pour le store Firestore) ---
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  @protected
  void setLoading(bool value) => _isLoading = value;

  @protected
  void setErrorValue(String? value) => _error = value;

  /// Charge les données initiales. La base (mock) n'a rien à charger.
  Future<void> load() async {}

  // --- Données scopées ---
  final List<SocieteModel> societes = [];
  final List<AgenceModel> agences = [];
  final List<PlatformUserModel> utilisateurs = [];

  /// Clients abonnés de l'entreprise (rempli par le store Firestore :
  /// `clients` où `societeId == X`).
  final List<ClientModel> clients = [];

  /// Nom de l'entreprise (raison sociale) une fois chargée.
  String get societeNom =>
      societes.isNotEmpty ? societes.first.raisonSociale : '';

  // --- Agences CRUD (mock) ---
  /// Creates and returns the new agency (callers use its id to attach
  /// resources like the agency manager).
  Future<AgenceModel> addAgence({
    required String ville,
    String location = '',
    required String responsable,
    required String telephone,
    required String status,
  }) async {
    final agence = AgenceModel(
      id: nextId(),
      societe: societeNom,
      societeId: societeId,
      ville: ville,
      location: location,
      responsable: responsable,
      telephone: telephone,
      status: status,
    );
    agences.add(agence);
    notifyListeners();
    return agence;
  }

  Future<void> updateAgence(AgenceModel updated) async {
    final index = agences.indexWhere((a) => a.id == updated.id);
    if (index != -1) agences[index] = updated;
    notifyListeners();
  }

  Future<void> deleteAgence(String id) async {
    agences.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  // --- Utilisateurs (chefs d'agence) CRUD (mock) ---
  Future<void> addUtilisateur({
    required String nom,
    required String telephone,
    required String role,
    required String agence,
    String agenceId = '',
    required String status,
    required String password,
  }) async {
    utilisateurs.add(
      PlatformUserModel(
        id: nextId(),
        nom: nom,
        telephone: telephone,
        role: role,
        agence: agence,
        societeId: societeId,
        agenceId: agenceId,
        status: status,
        password: password,
      ),
    );
    notifyListeners();
  }

  Future<void> updateUtilisateur(PlatformUserModel updated) async {
    final index = utilisateurs.indexWhere((u) => u.id == updated.id);
    if (index != -1) utilisateurs[index] = updated;
    notifyListeners();
  }

  Future<void> deleteUtilisateur(String id) async {
    utilisateurs.removeWhere((u) => u.id == id);
    notifyListeners();
  }

  // --- Preview demo data ---

  /// Seeds preview data so the demo experience looks rich directly.
  /// Called by [CompanyConsole] when the store is mock (preview mode).
  void seedPreviewData() {
    // Ne seeder qu'une seule fois.
    if (agences.isNotEmpty) return;
    societes.clear();
    agences.clear();
    utilisateurs.clear();
    clients.clear();

    societes.add(const SocieteModel(
      id: 'preview-so1',
      raisonSociale: 'WastePro Yaoundé SARL',
      adresse: '127 Rue du Commerce, Bastos, Yaoundé',
      telephone: '+237 233 42 10 55',
      email: 'contact@wastepro.cm',
      status: 'Active',
    ));

    agences.addAll([
      const AgenceModel(
        id: 'preview-ag1',
        societe: 'WastePro Yaoundé SARL',
        societeId: 'preview-so1',
        ville: 'Yaoundé — Bastos',
        responsable: 'Jean Dooh',
        telephone: '+237 677 12 34 56',
        status: 'Active',
      ),
      const AgenceModel(
        id: 'preview-ag2',
        societe: 'WastePro Yaoundé SARL',
        societeId: 'preview-so1',
        ville: 'Yaoundé — Nlongkak',
        responsable: 'Aïcha Bello',
        telephone: '+237 699 33 67 41',
        status: 'Active',
      ),
      const AgenceModel(
        id: 'preview-ag3',
        societe: 'WastePro Yaoundé SARL',
        societeId: 'preview-so1',
        ville: 'Yaoundé — Mokolo',
        responsable: 'Marie Ekwalla',
        telephone: '+237 690 45 12 78',
        status: 'Active',
      ),
    ]);

    utilisateurs.addAll([
      PlatformUserModel(
        id: 'preview-u1',
        nom: 'Jean Dooh',
        telephone: '+237 677 12 34 56',
        role: 'Agency Manager',
        agence: 'Yaoundé — Bastos',
        societeId: 'preview-so1',
        agenceId: 'preview-ag1',
        status: 'Active',
        password: '',
      ),
      PlatformUserModel(
        id: 'preview-u2',
        nom: 'Aïcha Bello',
        telephone: '+237 699 33 67 41',
        role: 'Agency Manager',
        agence: 'Yaoundé — Nlongkak',
        societeId: 'preview-so1',
        agenceId: 'preview-ag2',
        status: 'Active',
        password: '',
      ),
      PlatformUserModel(
        id: 'preview-u3',
        nom: 'Marie Ekwalla',
        telephone: '+237 690 45 12 78',
        role: 'Agency Manager',
        agence: 'Yaoundé',
        societeId: 'preview-so1',
        agenceId: 'preview-ag3',
        status: 'Active',
        password: '',
      ),
    ]);

    // Clients abonnés : dates réparties sur l'année pour que la carte
    // « nouveaux clients abonnés par mois » soit riche dès l'ouverture.
    clients.addAll([
      ClientModel(
        id: 'preview-c1',
        name: 'Jean Dooh',
        phone: '+237 677 12 34 56',
        zone: 'Bastos',
        plan: 'Weekly',
        status: 'Active',
        agenceId: 'preview-ag1',
        societeId: 'preview-so1',
        subscribedAt: '2026-02-10',
      ),
      ClientModel(
        id: 'preview-c2',
        name: 'Sarah Mbida',
        phone: '+237 691 77 04 22',
        zone: 'Bastos',
        plan: 'Monthly',
        status: 'Active',
        agenceId: 'preview-ag1',
        societeId: 'preview-so1',
        subscribedAt: '2026-03-05',
      ),
      ClientModel(
        id: 'preview-c3',
        name: 'Éric Tchoua',
        phone: '+237 656 40 88 15',
        zone: 'Nkolbisson',
        plan: 'Weekly',
        status: 'Suspended',
        agenceId: 'preview-ag1',
        societeId: 'preview-so1',
        subscribedAt: '2026-01-20',
      ),
      ClientModel(
        id: 'preview-c4',
        name: 'Aïcha Bello',
        phone: '+237 699 33 67 41',
        zone: 'Mokolo',
        plan: 'Weekly',
        status: 'Active',
        agenceId: 'preview-ag2',
        societeId: 'preview-so1',
        subscribedAt: '2026-05-11',
      ),
      ClientModel(
        id: 'preview-c5',
        name: 'Patrice Fotso',
        phone: '+237 674 20 15 63',
        zone: 'Asseng',
        plan: 'Daily',
        status: 'Active',
        agenceId: 'preview-ag2',
        societeId: 'preview-so1',
        subscribedAt: '2026-04-08',
      ),
      ClientModel(
        id: 'preview-c6',
        name: 'Marie Ekwalla',
        phone: '+237 690 45 12 78',
        zone: 'Nlongkak',
        plan: 'Daily',
        status: 'Active',
        agenceId: 'preview-ag2',
        societeId: 'preview-so1',
        subscribedAt: '2026-06-16',
      ),
      ClientModel(
        id: 'preview-c7',
        name: 'Nadine Onguéné',
        phone: '+237 670 22 45 88',
        zone: 'Bastos',
        plan: 'Weekly',
        status: 'Active',
        agenceId: 'preview-ag3',
        societeId: 'preview-so1',
        subscribedAt: '2026-07-03',
      ),
    ]);
  }
}
