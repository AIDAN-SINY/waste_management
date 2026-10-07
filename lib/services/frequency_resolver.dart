/// Resolves a client's frequency tier against a zone's fixed collection
/// calendar to produce concrete pickup day(s) and time.
///
/// Design flow (from cahier des charges):
/// 1. Agency Manager defines zone's collection day(s) — e.g. Bastos = Tue & Fri
/// 2. Client picks a frequency tier — Daily, Every 2 days, Weekly, or Monthly
/// 3. This resolver maps the tier to the zone's existing day(s):
///    - **Daily**: no day choice → client gets ALL zone collection days
///    - **Every 2 days**: client picks up to 3 zone days
///    - **Weekly**: client picks exactly 1 zone day
///    - **Monthly**: client picks exactly 1 zone day
/// 4. Contract is created with the resolved day(s) + zone's standard time
class FrequencyResolver {
  FrequencyResolver._();

  /// All supported frequency tiers.
  static const tiers = [
    FrequencyTier.daily,
    FrequencyTier.every2Days,
    FrequencyTier.weekly,
    FrequencyTier.monthly,
  ];

  /// Returns the number of day selections allowed for a given tier.
  ///
  /// - Daily → 0 (auto — all zone days)
  /// - Every 2 days → up to 3 zone days
  /// - Weekly → exactly 1 zone day
  /// - Monthly → exactly 1 zone day
  static int maxSelections(FrequencyTier tier) => switch (tier) {
        FrequencyTier.daily => 0,
        FrequencyTier.every2Days => 3,
        FrequencyTier.weekly => 1,
        FrequencyTier.monthly => 1,
      };

  /// Whether the tier requires the client to pick specific day(s).
  static bool requiresDayChoice(FrequencyTier tier) =>
      tier != FrequencyTier.daily;

  /// Resolves the final collection day(s) for a contract.
  ///
  /// [zoneDays] — the zone's fixed collection days (e.g. ['Tuesday', 'Friday']).
  /// [tier] — the client's chosen frequency tier.
  /// [clientChosenDays] — the days the client selected from the zone's options
  ///   (empty for Daily, which auto-selects all).
  ///
  /// Returns the concrete day(s) the contract will use.
  static List<String> resolve({
    required List<String> zoneDays,
    required FrequencyTier tier,
    List<String> clientChosenDays = const [],
  }) {
    if (tier == FrequencyTier.daily) {
      // Daily: client gets ALL zone collection days automatically.
      return List<String>.from(zoneDays);
    }

    // For other tiers, validate that chosen days are a subset of zone days.
    final validDays = clientChosenDays
        .where((d) => zoneDays.contains(d))
        .toList();

    if (tier == FrequencyTier.weekly || tier == FrequencyTier.monthly) {
      // Must pick exactly 1 day from zone days.
      return validDays.isNotEmpty ? [validDays.first] : [];
    }

    if (tier == FrequencyTier.every2Days) {
      // Can pick up to 3 zone days.
      return validDays.take(3).toList();
    }

    return validDays;
  }

  /// Human-readable label for a frequency tier.
  static String label(FrequencyTier tier) => switch (tier) {
        FrequencyTier.daily => 'Daily',
        FrequencyTier.every2Days => 'Every 2 days',
        FrequencyTier.weekly => 'Weekly',
        FrequencyTier.monthly => 'Monthly',
      };

  /// Short description for UI display.
  static String description(FrequencyTier tier) => switch (tier) {
        FrequencyTier.daily => 'Collection on every zone visit day',
        FrequencyTier.every2Days => 'Choose up to 3 zone days',
        FrequencyTier.weekly => 'Choose 1 zone day per week',
        FrequencyTier.monthly => 'Choose 1 zone day per month',
      };

  /// Suggested price tier (XAF) for display — actual pricing managed elsewhere.
  static int suggestedPrice(FrequencyTier tier) => switch (tier) {
        FrequencyTier.daily => 15000,
        FrequencyTier.every2Days => 10000,
        FrequencyTier.weekly => 5500,
        FrequencyTier.monthly => 3000,
      };
}

/// Frequency tiers available for client subscription.
enum FrequencyTier {
  daily,
  every2Days,
  weekly,
  monthly,
}
