/// Canonical WastePro client subscription plans (UI + upgrade ranking).
library;

class SubscriptionPlanInfo {
  const SubscriptionPlanInfo({
    required this.id,
    required this.title,
    required this.price,
    required this.subtitle,
    required this.icon,
    required this.rank,
    this.popular = false,
  });

  final String id;
  final String title;
  final double price;
  final String subtitle;
  final String icon; // material icon name key for mapping in UI
  final int rank; // higher = better plan
  final bool popular;
}

class SubscriptionPlans {
  static const monthly = SubscriptionPlanInfo(
    id: 'monthly',
    title: 'Monthly',
    price: 3000,
    subtitle: '1 collection per week',
    icon: 'calendar_month',
    rank: 1,
  );

  static const weekly = SubscriptionPlanInfo(
    id: 'weekly',
    title: 'Weekly',
    price: 5500,
    subtitle: '2 collections per week',
    icon: 'view_week',
    rank: 2,
    popular: true,
  );

  static const daily = SubscriptionPlanInfo(
    id: 'daily',
    title: 'Daily',
    price: 15000,
    subtitle: 'Collection every single day',
    icon: 'wb_sunny',
    rank: 3,
  );

  static const List<SubscriptionPlanInfo> all = [monthly, weekly, daily];

  static SubscriptionPlanInfo? byTitle(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final key = raw.trim().toLowerCase();
    for (final p in all) {
      if (p.title.toLowerCase() == key || p.id == key) return p;
    }
    // Legacy / backoffice labels.
    if (key.contains('daily') || key.contains('premium')) return daily;
    if (key.contains('week') || key.contains('standard') || key.contains('essential')) {
      return weekly;
    }
    if (key.contains('month') || key.contains('basic')) return monthly;
    return null;
  }

  static int rankOf(String? plan) => byTitle(plan)?.rank ?? 0;

  /// Plans strictly higher than [currentPlanTitle].
  static List<SubscriptionPlanInfo> upgradesFrom(String? currentPlanTitle) {
    final currentRank = rankOf(currentPlanTitle);
    return all.where((p) => p.rank > currentRank).toList();
  }
}
