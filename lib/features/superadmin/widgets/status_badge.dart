import 'package:flutter/material.dart';

import '../theme.dart';

/// Status pill with the design's color mapping.
///
/// Handles both the new English values ('Active', 'Suspended', …) and the
/// legacy French values stored before the app switched to English ('Actif',
/// 'Suspendu', …) so existing Firestore records keep their colors until they
/// are edited.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      'Active' || 'Actif' => (SuperAdminTheme.greenSoft, SuperAdminTheme.green),
      'Suspended' || 'Suspendu' =>
        (SuperAdminTheme.redSoft, SuperAdminTheme.red),
      'General Administrator' || 'Administrateur Général' =>
        (SuperAdminTheme.goldSoft, SuperAdminTheme.goldDim),
      _ => (const Color(0xFFEDF2EA), SuperAdminTheme.muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SuperAdminTheme.inter(
                10.5,
                weight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
