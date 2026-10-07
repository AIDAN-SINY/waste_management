import 'package:flutter/material.dart';

import '../theme.dart';

/// Deletion confirmation modal matching the design (red icon + actions).
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => _ConfirmDialog(title: title, message: message),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: curved, child: child),
      );
    },
  );
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: (MediaQuery.sizeOf(context).width * 0.9).clamp(0.0, 340.0),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: SuperAdminTheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: SuperAdminTheme.redSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: SuperAdminTheme.red,
                size: 20,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: SuperAdminTheme.sora(14.5, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: SuperAdminTheme.inter(
                12,
                color: SuperAdminTheme.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: SuperAdminTheme.border),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: SuperAdminTheme.inter(
                        12.5,
                        weight: FontWeight.w600,
                        color: SuperAdminTheme.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      backgroundColor: SuperAdminTheme.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      'Delete',
                      style: SuperAdminTheme.inter(
                        12.5,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
