import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// KPI card with a skeleton shimmer then an animated count-up,
/// matching the design's KPI blocks.
class KpiCard extends StatefulWidget {
  const KpiCard({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.value,
    required this.label,
    this.suffix = '',
    this.trend,
    this.trendUp = true,
    this.decimals = 0,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final double value;
  final String label;
  final String suffix;
  final String? trend;
  final bool trendUp;

  /// Number of decimals displayed by the count-up (e.g. 1 for 99.9).
  final int decimals;

  @override
  State<KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<KpiCard> {
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: SuperAdminTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(widget.icon, size: 15, color: widget.iconColor),
              ),
              const Spacer(),
              if (widget.trend != null)
                Row(
                  children: [
                    Icon(
                      widget.trendUp
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 10,
                      color: widget.trendUp
                          ? SuperAdminTheme.green
                          : SuperAdminTheme.red,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      widget.trend!,
                      style: SuperAdminTheme.inter(
                        11,
                        weight: FontWeight.w600,
                        color: widget.trendUp
                            ? SuperAdminTheme.green
                            : SuperAdminTheme.red,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const ShimmerBox(width: 64, height: 26)
          else
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: widget.value),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                final display = widget.decimals > 0
                    ? value.toStringAsFixed(widget.decimals)
                    : '${value.round()}';
                return Text.rich(
                  TextSpan(
                    text: display,
                    style: SuperAdminTheme.sora(
                      26,
                      weight: FontWeight.w700,
                      color: SuperAdminTheme.text,
                    ),
                    children: [
                      if (widget.suffix.isNotEmpty)
                        TextSpan(
                          text: widget.suffix,
                          style: SuperAdminTheme.sora(
                            16,
                            weight: FontWeight.w700,
                            color: SuperAdminTheme.text,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 3),
          Text(
            widget.label,
            style: SuperAdminTheme.inter(
              12,
              color: SuperAdminTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple shimmer placeholder (skeleton loading).
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: ColoredBox(
              color: SuperAdminTheme.border,
              child: Stack(
                children: [
                  Positioned(
                    left: -100 + 260 * _controller.value,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            SuperAdminTheme.border.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.6),
                            SuperAdminTheme.border.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
