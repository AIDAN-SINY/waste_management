import 'package:flutter/material.dart';

import '../theme.dart';

/// Right-side slide-in drawer used for create/edit forms (design's "drawer").
///
/// The [body] widget owns its form state (e.g. via onChanged callbacks);
/// [onSave] is invoked when the user presses "Save" — the drawer
/// closes itself afterwards.
Future<void> showCrudDrawer(
  BuildContext context, {
  required String title,
  required Widget body,
  required Future<void> Function() onSave,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, _, _) => _CrudDrawer(
      title: title,
      body: body,
      onSave: onSave,
    ),
    transitionBuilder: (context, anim, _, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
  );
}

class _CrudDrawer extends StatefulWidget {
  const _CrudDrawer({
    required this.title,
    required this.body,
    required this.onSave,
  });

  final String title;
  final Widget body;
  final Future<void> Function() onSave;

  @override
  State<_CrudDrawer> createState() => _CrudDrawerState();
}

class _CrudDrawerState extends State<_CrudDrawer> {
  bool _saving = false;

  Future<void> _handleSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave();
      // Only close on success; on error the caller shows a toast and the
      // drawer stays open so the user can retry.
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Swallowed: error toasts are the caller's responsibility.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final drawerWidth = (width * 0.92).clamp(0.0, 420.0);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: SuperAdminTheme.surface,
        child: SizedBox(
          width: drawerWidth,
          height: double.infinity,
          child: Column(
            children: [
              // Head
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: SuperAdminTheme.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: SuperAdminTheme.sora(16, weight: FontWeight.w700),
                      ),
                    ),
                    _IconButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: widget.body,
                ),
              ),
              // Foot
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: SuperAdminTheme.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(
                              color: SuperAdminTheme.border,
                            ),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
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
                          backgroundColor: SuperAdminTheme.ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _saving ? null : _handleSave,
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: SuperAdminTheme.cream,
                                ),
                              )
                            : Text(
                                'Save',
                                style: SuperAdminTheme.inter(
                                  12.5,
                                  weight: FontWeight.w600,
                                  color: SuperAdminTheme.cream,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small square ghost button (used for the drawer close).
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: SuperAdminTheme.border),
        ),
        child: Icon(icon, size: 15, color: SuperAdminTheme.muted),
      ),
    );
  }
}
