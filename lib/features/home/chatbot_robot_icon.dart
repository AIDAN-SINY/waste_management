import 'package:flutter/material.dart';

/// A cute robot icon widget matching the WastePro chatbot branding.
///
/// Draws a small robot face with antenna, eyes, and a speech bubble —
/// used inside the floating action button on the client dashboard.
class ChatbotRobotIcon extends StatelessWidget {
  const ChatbotRobotIcon({super.key, this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RobotPainter(),
      ),
    );
  }
}

class _RobotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width / 56; // scale factor (56 = base design size)

    // ── Speech bubble (top-right) ──
    final bubblePaint = Paint()..color = Colors.white;
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + 6 * s, 1 * s, 18 * s, 13 * s),
      Radius.circular(4 * s),
    );
    canvas.drawRRect(bubbleRect, bubblePaint);
    // Bubble tail (small triangle)
    final tailPath = Path()
      ..moveTo(cx + 10 * s, 14 * s)
      ..lineTo(cx + 8 * s, 19 * s)
      ..lineTo(cx + 14 * s, 14 * s)
      ..close();
    canvas.drawPath(tailPath, bubblePaint);
    // Bubble dots
    final dotPaint = Paint()..color = const Color(0xFF13261A);
    canvas.drawCircle(Offset(cx + 12 * s, 7.5 * s), 1.2 * s, dotPaint);
    canvas.drawCircle(Offset(cx + 15 * s, 7.5 * s), 1.2 * s, dotPaint);
    canvas.drawCircle(Offset(cx + 18 * s, 7.5 * s), 1.2 * s, dotPaint);

    // ── Antenna stick ──
    final antennaPaint = Paint()
      ..color = const Color(0xFF5B9BD5)
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx, cy - 14 * s),
      Offset(cx, cy - 6 * s),
      antennaPaint,
    );
    // Antenna ball
    canvas.drawCircle(
      Offset(cx, cy - 15 * s),
      3 * s,
      Paint()..color = const Color(0xFF4A8AD4),
    );
    // Antenna highlight
    canvas.drawCircle(
      Offset(cx - 0.8 * s, cy - 15.8 * s),
      1 * s,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );

    // ── Head (rounded rectangle) ──
    final headPaint = Paint()..color = Colors.white;
    final headShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final headRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 4 * s), width: 30 * s, height: 26 * s),
      Radius.circular(10 * s),
    );
    canvas.drawRRect(headRect.shift(Offset(0, 1.5 * s)), headShadow);
    canvas.drawRRect(headRect, headPaint);

    // ── Face screen (dark rounded rectangle) ──
    final facePaint = Paint()..color = const Color(0xFF1A2332);
    final faceRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 5 * s), width: 24 * s, height: 16 * s),
      Radius.circular(7 * s),
    );
    canvas.drawRRect(faceRect, facePaint);

    // ── Eyes (glowing cyan) ──
    final eyePaint = Paint()..color = const Color(0xFF4DD9FF);
    // Left eye
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5.5 * s, cy + 5 * s), width: 5 * s, height: 5.5 * s),
      eyePaint,
    );
    // Right eye
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5.5 * s, cy + 5 * s), width: 5 * s, height: 5.5 * s),
      eyePaint,
    );
    // Eye highlights
    final highlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.6);
    canvas.drawCircle(Offset(cx - 5 * s, cy + 3.8 * s), 1.2 * s, highlightPaint);
    canvas.drawCircle(Offset(cx + 6 * s, cy + 3.8 * s), 1.2 * s, highlightPaint);

    // ── Ears (small blue circles on sides) ──
    final earPaint = Paint()..color = const Color(0xFF4A8AD4);
    canvas.drawCircle(Offset(cx - 15 * s, cy + 4 * s), 3.5 * s, earPaint);
    canvas.drawCircle(Offset(cx + 15 * s, cy + 4 * s), 3.5 * s, earPaint);
    // Ear highlights
    canvas.drawCircle(Offset(cx - 15 * s, cy + 2.8 * s), 1.3 * s,
        Paint()..color = Colors.white.withValues(alpha: 0.35));
    canvas.drawCircle(Offset(cx + 15 * s, cy + 2.8 * s), 1.3 * s,
        Paint()..color = Colors.white.withValues(alpha: 0.35));

    // ── Head outer glow (subtle) ──
    final glowPaint = Paint()
      ..color = const Color(0xFF4DD9FF).withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(headRect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
