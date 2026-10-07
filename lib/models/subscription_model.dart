import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionModel {
  final String planName; // Basic, Standard, Premium
  final int price; // 3000, 5500, 15000
  final int pickupsPerWeek;
  final DateTime startDate;
  final DateTime expiryDate;

  SubscriptionModel({
    required this.planName,
    required this.price,
    required this.pickupsPerWeek,
    required this.startDate,
    required this.expiryDate,
  });

  // Convert for Firestore
  Map<String, dynamic> toMap() {
    return {
      'planName': planName,
      'price': price,
      'pickupsPerWeek': pickupsPerWeek,
      'startDate': Timestamp.fromDate(startDate),
      'expiryDate': Timestamp.fromDate(expiryDate),
    };
  }
}
