import 'package:flutter/material.dart';

import '../theme.dart';

class _ToastData {
  final Key key;
  final String message;
  final bool isError;

  _ToastData(this.key, this.message, this.isError);
}

/// Lightweight toast system for the console.
///
/// Usage: `ToastService.show('Message')` — the [ToastService.host] widget
/// must be present in the console's widget tree.
class ToastService {
  ToastService._();

  static final ValueNotifier<List<_ToastData>> _toasts = ValueNotifier([]);

  static void show(String message, {bool isError = false}) {
    final data = _ToastData(UniqueKey(), message, isError);
    _toasts.value = [..._toasts.value, data];
    Future.delayed(const Duration(seconds: 3), () {
      _toasts.value = _toasts.value.where((t) => t.key != data.key).toList();
    });
  }

  /// Place inside a [Stack] (bottom-right corner), non-interactive.
  static Widget host() {
    return Positioned(
      right: 22,
      bottom: 22,
      child: IgnorePointer(
        child: ValueListenableBuilder<List<_ToastData>>(
          valueListenable: _toasts,
          builder: (context, toasts, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final t in toasts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    // Each toast animates itself in (_ToastWidget).
                    child: _ToastWidget(toast: t),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ToastWidget extends StatelessWidget {
  const _ToastWidget({required this.toast});

  final _ToastData toast;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(40 * (1 - t), 0),
          child: Opacity(opacity: t, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: toast.isError ? SuperAdminTheme.red : SuperAdminTheme.ink,
          borderRadius: BorderRadius.circular(11),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              toast.isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              size: 15,
              color: toast.isError
                  ? Colors.white
                  : SuperAdminTheme.gold,
            ),
            const SizedBox(width: 10),
            Text(
              toast.message,
              style: SuperAdminTheme.inter(
                12.5,
                weight: FontWeight.w500,
                color: SuperAdminTheme.cream,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
