class JobModel {
  final String id;
  final String clientId;
  final String collectorId;
  final String status; // 'pending', 'accepted', 'completed', 'cancelled'
  final String location;
  final double latitude;
  final double longitude;
  final String description;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? proofPhotoUrl;

  JobModel({
    required this.id,
    required this.clientId,
    required this.collectorId,
    required this.status,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.createdAt,
    this.completedAt,
    this.proofPhotoUrl,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
      id: json['id'] as String,
      clientId: json['clientId'] as String,
      collectorId: json['collectorId'] as String,
      status: json['status'] as String,
      location: json['location'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      description: json['description'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      proofPhotoUrl: json['proofPhotoUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientId': clientId,
      'collectorId': collectorId,
      'status': status,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'proofPhotoUrl': proofPhotoUrl,
    };
  }
}
