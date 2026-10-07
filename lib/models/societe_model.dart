/// A company registered on the platform (multi-tenant structure).
///
/// Mirrors the "Companies" entity from the super admin console design.
class SocieteModel {
  final String id;
  final String raisonSociale;
  final String adresse;
  final String telephone;
  final String email;
  final String status; // 'Active' | 'Suspended' (legacy docs may say 'Actif')

  const SocieteModel({
    required this.id,
    required this.raisonSociale,
    required this.adresse,
    required this.telephone,
    required this.email,
    required this.status,
  });

  SocieteModel copyWith({
    String? raisonSociale,
    String? adresse,
    String? telephone,
    String? email,
    String? status,
  }) {
    return SocieteModel(
      id: id,
      raisonSociale: raisonSociale ?? this.raisonSociale,
      adresse: adresse ?? this.adresse,
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'raisonSociale': raisonSociale,
      'adresse': adresse,
      'telephone': telephone,
      'email': email,
      'status': status,
    };
  }

  factory SocieteModel.fromMap(Map<String, dynamic> map) {
    return SocieteModel(
      id: map['id'] as String? ?? '',
      raisonSociale: map['raisonSociale'] as String? ?? '',
      adresse: map['adresse'] as String? ?? '',
      telephone: map['telephone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      status: map['status'] as String? ?? 'Active',
    );
  }
}
