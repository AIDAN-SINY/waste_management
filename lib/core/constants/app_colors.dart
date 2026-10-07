import 'package:flutter/material.dart';

import '../brand.dart';

/// App Colors — aliases of the brand palette ([Brand], from the logo).
class AppColors {
  // Primary: the logo's greens.
  static const Color primary = Brand.green;
  static const Color primaryLight = Brand.lime;
  static const Color primaryDark = Brand.greenDark;

  // Secondary: the logo's golden yellow.
  static const Color secondary = Brand.gold;
  static const Color secondaryLight = Brand.goldBright;
  static const Color secondaryDark = Brand.goldDim;

  // Accent
  static const Color accent = Brand.gold;
  static const Color accentLight = Brand.goldBright;
  static const Color accentDark = Brand.goldDim;

  // Status Colors
  static const Color success = Brand.leaf;
  static const Color warning = Brand.gold;
  static const Color error = Color(0xFFC1443D);
  static const Color info = Color(0xFF3D6BE8);

  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color grey = Brand.muted;
  static const Color greyLight = Brand.background;
  static const Color greyDark = Brand.text;

  // Background
  static const Color background = Brand.background;
  static const Color surface = Brand.surface;

  // Borders
  static const Color border = Brand.border;
}
