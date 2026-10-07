import 'package:flutter/material.dart';

/// WastePro brand palette — taken from the logo (assets/images/logo.png).
///
/// Every theme of the app (client / collector screens, agency backoffice,
/// company console, super admin console, Material theme) is built from
/// these colours. Red / blue stay for errors and information.
class Brand {
  Brand._();

  // --- Greens (the bin, « Waste », the leaves) ---
  /// Deep forest green: « Waste », the bin — primary colour.
  static const Color green = Color(0xFF0B5A2A);

  /// Darkest green: dark backgrounds, sidebars.
  static const Color greenDark = Color(0xFF073A1B);

  /// Between the two (cards on dark backgrounds, pressed states).
  static const Color greenDeep = Color(0xFF0B4A24);

  /// Leaf green: success, positive states.
  static const Color leaf = Color(0xFF2E9E3A);

  /// Lime leaf: highlights, live indicators.
  static const Color lime = Color(0xFF6CB82E);

  /// Very light green tint: soft backgrounds of green elements.
  static const Color greenSoft = Color(0xFFE6F2E4);

  // --- Golden yellow (« Pro », the recycle symbol, the ring) ---
  static const Color gold = Color(0xFFF5B800);
  static const Color goldBright = Color(0xFFF8CC08);
  static const Color goldDim = Color(0xFFB88A00);
  static const Color goldSoft = Color(0xFFFFF4CC);

  /// Text / icons on gold.
  static const Color onGold = greenDark;

  // --- Neutrals (white logo background, faint green tint) ---
  static const Color background = Color(0xFFF4F7F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE1E9DD);
  static const Color text = Color(0xFF13261A);
  static const Color muted = Color(0xFF6E8274);

  /// Material colour scheme of the app.
  static ColorScheme get colorScheme => ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        onPrimary: Colors.white,
        secondary: gold,
        onSecondary: onGold,
        tertiary: leaf,
        surface: surface,
      );
}

/// The WastePro logo (white background, rounded) at [size] pixels.
class WasteProLogo extends StatelessWidget {
  const WasteProLogo({super.key, this.size = 48, this.radius});

  final double size;

  /// Corner radius (defaults to a quarter of [size]).
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size / 4),
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.06),
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.contain,
          semanticLabel: 'WastePro',
          // Tests / missing asset: keep the layout, show a neutral mark.
          errorBuilder: (_, _, _) =>
              Icon(Icons.recycling_rounded, color: Brand.green, size: size * 0.6),
        ),
      ),
    );
  }
}
