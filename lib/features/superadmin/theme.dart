import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';

/// Design tokens of the Super Admin console.
///
/// Ported 1:1 from the CSS variables of `super-admin-desktop.html`.
class SuperAdminTheme {
  SuperAdminTheme._();

  // --- Palette (brand colours: lib/core/brand.dart) ---
  /// Sidebar: the logo's darkest green.
  static const Color ink = Brand.greenDark;
  static const Color inkSoft = Brand.greenDeep;
  static const Color gold = Brand.gold;
  static const Color goldSoft = Brand.goldSoft;
  static const Color goldDim = Brand.goldDim;
  static const Color green = Brand.leaf;
  static const Color greenSoft = Brand.greenSoft;
  static const Color red = Color(0xFFC1443D);
  static const Color redSoft = Color(0xFFF8E4E2);
  static const Color blue = Color(0xFF3D6BE8);
  static const Color blueSoft = Color(0xFFE7EEFB);
  static const Color cream = Color(0xFFF5F1E8);
  static const Color bg = Brand.background;
  static const Color surface = Brand.surface;
  static const Color border = Brand.border;
  static const Color text = Brand.text;
  static const Color muted = Brand.muted;
  static const Color rowHover = Color(0xFFF8FBF6);
  static const Color inkLine = Color(0x17F5F1E8); // cream @ ~9%

  // --- Metrics ---
  static const double sidebarWidth = 248;
  static const double sidebarWidthCollapsed = 76;
  static const double radius = 14;

  // --- Typography ---
  static TextStyle sora(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color color = text,
    double? height,
  }) {
    return GoogleFonts.sora(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  static TextStyle inter(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = text,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  // --- Surfaces ---
  static BoxDecoration card() {
    return BoxDecoration(
      color: surface,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  static BoxDecoration chip(Color bgColor) {
    return BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
    );
  }
}

/// Utility to build avatar initials like the design ("PM", "SA"...).
String saInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final letters = parts.take(2).map((w) => w[0]).join();
  return letters.toUpperCase();
}
