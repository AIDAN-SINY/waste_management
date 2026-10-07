import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';

/// Design tokens of the mobile backoffice (entreprise manager).
///
/// Ported 1:1 from the CSS variables of `backoffice-mobile.html`.
class BackofficeTheme {
  BackofficeTheme._();

  // --- Palette (brand colours: lib/core/brand.dart) ---
  static const Color green = Brand.green;
  static const Color greenSoft = Brand.greenSoft;
  static const Color gold = Brand.gold;
  static const Color goldSoft = Brand.goldSoft;
  static const Color goldDim = Brand.goldDim;
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
  static const Color graySoft = Color(0xFFEDF2EA);
  static const Color shell = Color(0xFFDCE5D8); // page body behind the phone
  static const Color success = Brand.leaf;
  static const double radius = 16;

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
}

/// Avatar initials like the design ("PM", "MA"...).
String boInitials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((w) => w[0]).join().toUpperCase();
}

/// Formats money the fr-FR way: 8000 → "8 000".
String boMoney(int n) {
  final s = n.toString();
  return s.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
}

/// Formats a `yyyy-MM-dd` date as "04 Aug".
String boFmtDate(String isoDate) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final month = int.tryParse(parts[1]) ?? 1;
  final day = parts[2];
  if (month < 1 || month > 12) return isoDate;
  return '$day ${months[month - 1]}';
}
