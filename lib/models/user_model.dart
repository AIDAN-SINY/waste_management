class UserModel {
  final String phoneNumber;
  final String fullName;
  final String role;
  final String password; // Legacy only — never written since the Auth migration
  final String? uid; // Firebase Auth uid (set after tool/migrate_auth.mjs)
  final String? registrationStatus; // pending | approved | rejected (applicants)
  final double? latitude;
  final double? longitude;
  final String? subscriptionPlan;
  final bool? isSubscribed;
  final String? neighborhood;
  final double earnings;
  final int successPickups;
  final bool isVerified;
  final String? assignedCollector;
  final String societeId; // '' for clients/collectors without a console link
  final String agenceId;
  final String agenceName; // e.g. "Yaoundé — Etoudi"
  final String collecteurId; // collecteur assigné au client par le backoffice

  UserModel({
    required this.phoneNumber,
    required this.fullName,
    required this.role,
    this.password = '',
    this.uid,
    this.registrationStatus,
    this.latitude,
    this.longitude,
    this.subscriptionPlan,
    this.isSubscribed,
    this.neighborhood,
    this.earnings = 0,
    this.successPickups = 0,
    this.isVerified = false,
    this.assignedCollector,
    this.societeId = '',
    this.agenceId = '',
    this.agenceName = '',
    this.collecteurId = '',
  });

  String get displayInitial {
    final name = fullName.trim();
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  String get firstName {
    final name = fullName.trim();
    if (name.isEmpty) return 'User';
    return name.split(RegExp(r'\s+')).first;
  }

  String get formattedPhone {
    final digits = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+237') || digits.startsWith('237')) {
      return digits.startsWith('+') ? digits : '+$digits';
    }
    if (digits.length == 9) return '+237$digits';
    return phoneNumber;
  }

  Map<String, dynamic> toMap() {
    return {
      'phoneNumber': phoneNumber,
      'fullName': fullName,
      'role': role,
      'uid': uid,
      'registrationStatus': registrationStatus,
      'latitude': latitude,
      'longitude': longitude,
      'subscription_plan': subscriptionPlan,
      'isSubscribed': isSubscribed,
      'societeId': societeId,
      'agenceId': agenceId,
      'agenceName': agenceName,
      'collecteurId': collecteurId,
      // No `password`: secrets live in Firebase Auth only (this map is also
      // cached on the device by UserProvider).
      'neighborhood': neighborhood,
      'earnings': earnings,
      'successPickups': successPickups,
      'isVerified': isVerified,
      if (assignedCollector != null) 'assignedCollector': assignedCollector,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      phoneNumber: map['phoneNumber']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      role: (map['role'] as String?)?.trim().toLowerCase() ?? 'client',
      password: map['password'] ?? '', // Read for legacy docs only
      uid: map['uid'] as String?,
      registrationStatus: map['registrationStatus'] as String?,
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      subscriptionPlan: map['subscription_plan'] as String?,
      isSubscribed: map['isSubscribed'] as bool?,
      neighborhood: map['neighborhood'] as String?,
      earnings: (map['earnings'] as num?)?.toDouble() ?? 0,
      successPickups: (map['successPickups'] as num?)?.toInt() ?? 0,
      isVerified: map['isVerified'] == true,
      assignedCollector: map['assignedCollector'] as String?,
      societeId: map['societeId'] as String? ?? '',
      agenceId: map['agenceId'] as String? ?? '',
      agenceName: map['agenceName'] as String? ?? '',
      collecteurId: map['collecteurId'] as String? ?? '',
    );
  }

  UserModel copyWith({
    String? phoneNumber,
    String? fullName,
    String? role,
    String? password,
    String? uid,
    String? registrationStatus,
    double? latitude,
    double? longitude,
    String? subscriptionPlan,
    bool? isSubscribed,
    String? neighborhood,
    double? earnings,
    int? successPickups,
    bool? isVerified,
    String? assignedCollector,
    String? societeId,
    String? agenceId,
    String? agenceName,
    String? collecteurId,
  }) {
    return UserModel(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      password: password ?? this.password,
      uid: uid ?? this.uid,
      registrationStatus: registrationStatus ?? this.registrationStatus,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      neighborhood: neighborhood ?? this.neighborhood,
      earnings: earnings ?? this.earnings,
      successPickups: successPickups ?? this.successPickups,
      isVerified: isVerified ?? this.isVerified,
      assignedCollector: assignedCollector ?? this.assignedCollector,
      societeId: societeId ?? this.societeId,
      agenceId: agenceId ?? this.agenceId,
      agenceName: agenceName ?? this.agenceName,
      collecteurId: collecteurId ?? this.collecteurId,
    );
  }
}
