/// Assignment of a collector to one or more zones.
///
/// Mirrors the "Affectation" entity from the cahier des charges:
///   - collecteur → one or more zones
///   - start time / end time
///   - date
///
/// Stored in Firestore collection `assignments`.
class AssignmentModel {
  final String id;
  final String collecteurId;
  final String collecteurName;
  final String zoneId;
  final String zoneName;
  final String startTime; // e.g. '07:00'
  final String endTime; // e.g. '12:00'
  final String date; // yyyy-MM-dd
  final String status; // 'Active' | 'Completed' | 'Cancelled'
  final String agenceId;
  final String societeId;

  const AssignmentModel({
    required this.id,
    required this.collecteurId,
    required this.collecteurName,
    required this.zoneId,
    required this.zoneName,
    required this.startTime,
    required this.endTime,
    required this.date,
    required this.status,
    this.agenceId = '',
    this.societeId = '',
  });

  AssignmentModel copyWith({
    String? collecteurId,
    String? collecteurName,
    String? zoneId,
    String? zoneName,
    String? startTime,
    String? endTime,
    String? date,
    String? status,
    String? agenceId,
    String? societeId,
  }) {
    return AssignmentModel(
      id: id,
      collecteurId: collecteurId ?? this.collecteurId,
      collecteurName: collecteurName ?? this.collecteurName,
      zoneId: zoneId ?? this.zoneId,
      zoneName: zoneName ?? this.zoneName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      date: date ?? this.date,
      status: status ?? this.status,
      agenceId: agenceId ?? this.agenceId,
      societeId: societeId ?? this.societeId,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'collecteurId': collecteurId,
        'collecteurName': collecteurName,
        'zoneId': zoneId,
        'zoneName': zoneName,
        'startTime': startTime,
        'endTime': endTime,
        'date': date,
        'status': status,
        'agenceId': agenceId,
        'societeId': societeId,
      };

  factory AssignmentModel.fromMap(Map<String, dynamic> map) =>
      AssignmentModel(
        id: map['id'] as String? ?? '',
        collecteurId: map['collecteurId'] as String? ?? '',
        collecteurName: map['collecteurName'] as String? ?? '',
        zoneId: map['zoneId'] as String? ?? '',
        zoneName: map['zoneName'] as String? ?? '',
        startTime: map['startTime'] as String? ?? '07:00',
        endTime: map['endTime'] as String? ?? '12:00',
        date: map['date'] as String? ?? '',
        status: map['status'] as String? ?? 'Active',
        agenceId: map['agenceId'] as String? ?? '',
        societeId: map['societeId'] as String? ?? '',
      );
}
