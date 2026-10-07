/// Notification in-app pour le client — écrite par le backoffice quand le
/// chef d'agence prend une décision sur une candidature, lue par le tableau
/// de bord client (cloche) et par l'écran « Application status ».
///
/// Collection Firestore : `notifications/{id}` (id = `notif{regId}` — un doc
/// par candidature, donc une décision ne duplique jamais la notification).
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.phone,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.pickupId = '',
    this.read = false,
  });

  final String id;

  /// Numéro de téléphone du client (canonique +237…).
  final String phone;

  /// Nature de la décision : `'approved'` | `'rejected'`.
  final String type;

  final String title;
  final String message;

  /// True une fois la notification vue (cloche sans badge).
  final bool read;

  /// Id du pickup concerné (type `pickup_to_confirm` uniquement) — utilisé
  /// pour ouvrir l'écran de validation QR sur le bon document `pickups`.
  final String pickupId;

  /// Date ISO (YYYY-MM-DD) de la décision.
  final String createdAt;

  NotificationModel copyWith({bool? read}) => NotificationModel(
    id: id,
    phone: phone,
    type: type,
    title: title,
    message: message,
    createdAt: createdAt,
    pickupId: pickupId,
    read: read ?? this.read,
  );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phone': phone,
      'type': type,
      'title': title,
      'message': message,
      'read': read,
      'pickupId': pickupId,
      'createdAt': createdAt,
    };
  }

  factory NotificationModel.fromMap(String id, Map<String, dynamic> map) {
    return NotificationModel(
      id: id,
      phone: map['phone'] as String? ?? '',
      type: map['type'] as String? ?? '',
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      read: map['read'] as bool? ?? false,
      pickupId: map['pickupId'] as String? ?? '',
      createdAt: map['createdAt'] as String? ?? '',
    );
  }
}
