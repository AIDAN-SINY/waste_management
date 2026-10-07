import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../superadmin/theme.dart';

/// Confirmation dialog shown right after the agency modal creates a manager:
/// it displays the generated login credentials (phone + numeric password)
/// once, so the admin can share them with the manager before moving on.
Future<void> showManagerCredentialsDialog(
  BuildContext context, {
  required String managerName,
  required String managerPhone,
  required String password,
}) {
  return showGeneralDialog<void>(
    context: context,
    // Non-dismissible: the password is shown only once — the admin must
    // explicitly acknowledge it with the "Done" button.
    barrierDismissible: false,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => _ManagerCredentialsDialog(
      managerName: managerName,
      managerPhone: managerPhone,
      password: password,
    ),
    transitionBuilder: (context, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _ManagerCredentialsDialog extends StatefulWidget {
  const _ManagerCredentialsDialog({
    required this.managerName,
    required this.managerPhone,
    required this.password,
  });

  final String managerName;
  final String managerPhone;
  final String password;

  @override
  State<_ManagerCredentialsDialog> createState() =>
      _ManagerCredentialsDialogState();
}

class _ManagerCredentialsDialogState extends State<_ManagerCredentialsDialog> {
  bool _copiedPhone = false;
  bool _copiedPassword = false;

  Future<void> _copy(String value, {required bool password}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() {
      if (password) {
        _copiedPassword = true;
      } else {
        _copiedPhone = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dialogWidth = (width * 0.92).clamp(0.0, 440.0);

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth),
        child: Material(
          color: SuperAdminTheme.surface,
          borderRadius: BorderRadius.circular(SuperAdminTheme.radius),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: SuperAdminTheme.greenSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 26,
                      color: SuperAdminTheme.green,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Manager account created',
                  textAlign: TextAlign.center,
                  style: SuperAdminTheme.sora(16, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Share these login details with ${widget.managerName}. '
                  'They sign in with their phone number and this password.',
                  textAlign: TextAlign.center,
                  style: SuperAdminTheme.inter(
                    12.5,
                    color: SuperAdminTheme.muted,
                  ),
                ),
                const SizedBox(height: 18),
                _credentialRow(
                  label: 'Phone',
                  value: widget.managerPhone,
                  copied: _copiedPhone,
                  onCopy: () => _copy(
                    widget.managerPhone,
                    password: false,
                  ),
                ),
                const SizedBox(height: 10),
                _credentialRow(
                  label: 'Password',
                  value: widget.password,
                  copied: _copiedPassword,
                  onCopy: () => _copy(widget.password, password: true),
                ),
                const SizedBox(height: 20),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    backgroundColor: SuperAdminTheme.ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Done',
                    style: SuperAdminTheme.inter(
                      12.5,
                      weight: FontWeight.w600,
                      color: SuperAdminTheme.cream,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _credentialRow({
    required String label,
    required String value,
    required bool copied,
    required VoidCallback onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SuperAdminTheme.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SuperAdminTheme.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label.toUpperCase(),
              style: SuperAdminTheme.inter(
                10,
                weight: FontWeight.w600,
                color: SuperAdminTheme.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: SuperAdminTheme.inter(13, weight: FontWeight.w700),
            ),
          ),
          InkWell(
            onTap: onCopy,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: copied
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: SuperAdminTheme.green,
                    )
                  : const Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: SuperAdminTheme.muted,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
