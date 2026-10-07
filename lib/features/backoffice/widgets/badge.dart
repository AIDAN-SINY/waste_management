import 'package:flutter/material.dart';

import '../theme.dart';

/// Status pill, faithful to the design's `.badge` variants.
class BoBadge extends StatelessWidget {
  const BoBadge({super.key, required this.status});

  final String status;

  (Color, Color) _colors() {
    switch (status) {
      case 'Active' || 'Actif':
      case 'Completed' || 'Effectué':
      case 'Paid' || 'Payée':
      case 'Approved':
        return (BackofficeTheme.greenSoft, BackofficeTheme.success);
      case 'Scheduled' || 'Prévu':
      case 'Pending' || 'En attente':
        return (BackofficeTheme.goldSoft, BackofficeTheme.goldDim);
      case 'Rejected':
        return (BackofficeTheme.redSoft, BackofficeTheme.red);
      case 'Suspended' || 'Suspendu':
      case 'Missed' || 'Manqué':
      case 'Overdue' || 'En retard':
        return (BackofficeTheme.redSoft, BackofficeTheme.red);
      default:
        return (BackofficeTheme.graySoft, BackofficeTheme.muted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: BackofficeTheme.inter(
          9.5,
          weight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
