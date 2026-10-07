import 'package:flutter/material.dart';

import '../theme.dart';

/// KPI card of the design's carousel (150px wide, snap aligned). On desktop
/// (web-first), [width] can be null so the card stretches inside an Expanded.
class BoKpiCard extends StatelessWidget {
  const BoKpiCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.trend,
    required this.trendUp,
    required this.value,
    required this.label,
    this.width = 150,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String trend;
  final bool trendUp;
  final String value;
  final String label;

  /// Largeur fixe sur mobile (carrousel) ; null sur desktop (flexible).
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: BackofficeTheme.surface,
        border: Border.all(color: BackofficeTheme.border),
        borderRadius: BorderRadius.circular(BackofficeTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              Text(
                trend,
                style: BackofficeTheme.inter(
                  10,
                  weight: FontWeight.w700,
                  color: trendUp ? BackofficeTheme.success : BackofficeTheme.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: BackofficeTheme.sora(22, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: BackofficeTheme.inter(11, color: BackofficeTheme.muted),
          ),
        ],
      ),
    );
  }
}
