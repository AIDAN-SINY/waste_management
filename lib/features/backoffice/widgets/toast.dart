import 'package:flutter/material.dart';

import '../theme.dart';

/// Lightweight toast for the backoffice (top of the screen, like the design's
/// `.toast-stack`). Rendered on the root [Overlay] so it stays visible even
/// above the modal sheets. Usage: `BoToastService.show('Message')`.
class BoToastService {
  BoToastService._();

  static OverlayState? _overlay;

  /// Registers the root overlay. Called once by [BackofficeScreen].
  static void init(BuildContext context) {
    _overlay ??= Overlay.maybeOf(context, rootOverlay: true);
  }

  /// Resets the cached overlay between widget tests.
  @visibleForTesting
  static void resetForTesting() {
    _overlay = null;
  }

  static void show(String message, {bool isError = false}) {
    final overlay = _overlay;
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: 12,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: _BoToastWidget(
            message: message,
            isError: isError,
            onDone: () {
              if (entry.mounted) entry.remove();
            },
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (entry.mounted) entry.remove();
    });
  }
}

class _BoToastWidget extends StatefulWidget {
  const _BoToastWidget({
    required this.message,
    required this.isError,
    required this.onDone,
  });

  final String message;
  final bool isError;
  final VoidCallback onDone;

  @override
  State<_BoToastWidget> createState() => _BoToastWidgetState();
}

class _BoToastWidgetState extends State<_BoToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward();
    _opacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.25)),
    );
    _slide = Tween(begin: const Offset(0, -0.5), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isError ? BackofficeTheme.red : BackofficeTheme.green,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                widget.isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                size: 15,
                color:
                    widget.isError ? Colors.white : BackofficeTheme.gold,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.message,
                  style: BackofficeTheme.inter(
                    12,
                    weight: FontWeight.w500,
                    color: BackofficeTheme.cream,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
