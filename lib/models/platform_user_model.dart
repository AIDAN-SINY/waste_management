/// A platform back-office user managed by the super admin (or by the
/// General Administrator in the company console).
///
/// These are the "Users" entity from the super admin console design:
/// accounts with a platform role ('General Administrator' | 'Agency Manager')
/// attached to a company and optionally an agency.
///
/// [password] is a FORM value only (creation / password change): it is
/// handed to Firebase Auth through the `manageAccount` Cloud Function and
/// never written to Firestore. [hasLogin] records that the user has a login
/// account (phone + password) mirrored in the `users` collection.
class PlatformUserModel {
  final String id;
  final String nom;
  final String telephone;
  final String role; // 'General Administrator' | 'Agency Manager' (legacy: FR)
  final String agence;
  final String societeId; // foreign key to the parent company
  final String agenceId; // foreign key to the agency ('' for GAs)
  final String status; // 'Active' | 'Suspended' (legacy: 'Actif'/'Suspendu')
  final String password; // form only — '' = unchanged
  final bool hasLogin;

  const PlatformUserModel({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.role,
    required this.agence,
    this.societeId = '',
    this.agenceId = '',
    required this.status,
    this.password = '',
    this.hasLogin = false,
  });

  /// The user has (or is getting, via a new password) a login account.
  bool get wantsLogin => hasLogin || password.isNotEmpty;

  PlatformUserModel copyWith({
    String? nom,
    String? telephone,
    String? role,
    String? agence,
    String? societeId,
    String? agenceId,
    String? status,
    String? password,
    bool? hasLogin,
  }) {
    return PlatformUserModel(
      id: id,
      nom: nom ?? this.nom,
      telephone: telephone ?? this.telephone,
      role: role ?? this.role,
      agence: agence ?? this.agence,
      societeId: societeId ?? this.societeId,
      agenceId: agenceId ?? this.agenceId,
      status: status ?? this.status,
      password: password ?? this.password,
      hasLogin: hasLogin ?? this.hasLogin,
    );
  }

  /// Firestore document — never contains the password.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
      'telephone': telephone,
      'role': role,
      'agence': agence,
      'societeId': societeId,
      'agenceId': agenceId,
      'status': status,
      'hasLogin': wantsLogin,
    };
  }

  factory PlatformUserModel.fromMap(Map<String, dynamic> map) {
    return PlatformUserModel(
      id: map['id'] as String? ?? '',
      nom: map['nom'] as String? ?? '',
      telephone: map['telephone'] as String? ?? '',
      role: map['role'] as String? ?? 'Agency Manager',
      agence: map['agence'] as String? ?? '—',
      societeId: map['societeId'] as String? ?? '',
      agenceId: map['agenceId'] as String? ?? '',
      status: map['status'] as String? ?? 'Active',
      // Legacy docs (before passwords were removed) carry `password`.
      hasLogin: map['hasLogin'] as bool? ??
          (map['password'] as String? ?? '').isNotEmpty,
    );
  }
}
