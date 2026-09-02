import 'package:flutter/material.dart';

/// EI Simulator palette — single source of truth.
/// See `docs/color-scheme.md` for usage and `lib/theme/app_theme.dart` for ThemeData.
class AppColors {
  AppColors._();

  /// Very pale pink / off-white — page background, card/dialog surface.
  /// Hex `#FAEDED` rgb(250,237,237)
  static const Color bgLight = Color(0xFFFAEDED);

  /// Coral / salmon orange-red — primary accent (FAB, chips, pills, Add Relationship).
  /// Hex `#FF655B` rgb(255,101,91)
  static const Color coral = Color(0xFFFF655B);

  /// Vivid bright red — hero sheet, mutual edge, delete, loading.
  /// Hex `#FF1E25` rgb(255,30,37)
  static const Color vividRed = Color(0xFFFF1E25);

  // Semantic aliases (optional, for readability)
  static const Color background = bgLight;
  static const Color surface = bgLight;
  static const Color primary = coral;
  static const Color hero = vividRed;
  static const Color error = vividRed;
}
