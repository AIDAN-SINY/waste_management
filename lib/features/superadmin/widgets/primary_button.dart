import 'package:flutter/material.dart';

import '../theme.dart';

/// Dark primary button with icon, matching the design's `.btn-primary`.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: SuperAdminTheme.ink,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: SuperAdminTheme.cream),
            const SizedBox(width: 8),
            Text(
              label,
              style: SuperAdminTheme.inter(
                12.5,
                weight: FontWeight.w600,
                color: SuperAdminTheme.cream,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
