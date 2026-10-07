/// Billing cycle helpers for subscription payment dates.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionBilling {
  /// Default WastePro billing cycle length.
  static const int cycleDays = 30;

  static DateTime? asDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static DateTime nextPaymentDate(DateTime lastPayment) =>
      lastPayment.add(const Duration(days: cycleDays));

  /// Hours until [target]. Returns 0 if already past.
  static int hoursRemaining(DateTime? target) {
    if (target == null) return 0;
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inHours;
  }

  static String formatDate(DateTime? date) {
    if (date == null) return '—';
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  static String formatHours(int hours) {
    if (hours <= 0) return '0 h';
    if (hours < 48) return '$hours h';
    final days = hours ~/ 24;
    final rem = hours % 24;
    return rem == 0 ? '$days d' : '$days d $rem h';
  }
}
