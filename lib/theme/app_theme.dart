import 'package:flutter/material.dart';
import 'app_colors.dart';

/// App-wide ThemeData built from [AppColors].
/// Apply in `lib/main.dart:25` as `MaterialApp(theme: AppTheme.light, ...)`.
/// See `docs/color-scheme.md` for token map.
class AppTheme {
  AppTheme._();

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bgLight,
    // AppBar is transparent over bgLight — icon/title are dark for contrast
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: Colors.black87),
      titleTextStyle: TextStyle(
        color: Colors.black87,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.coral,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.coral,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.coral.withValues(alpha: 0.15),
      side: const BorderSide(color: AppColors.coral),
      labelStyle: const TextStyle(color: Color(0xFF3A0000), fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.vividRed,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bgLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: const TextStyle(
        color: Color(0xFF2B0000),
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
      contentTextStyle: const TextStyle(color: Colors.black54, fontSize: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(color: Colors.black54),
      hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.coral, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    cardTheme: CardThemeData(
      color: AppColors.bgLight,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 8),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.coral;
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.coral.withValues(alpha: 0.4);
        }
        return Colors.black12;
      }),
    ),
    dividerColor: Colors.black.withValues(alpha: 0.08),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.vividRed,
      primary: AppColors.coral,
      secondary: AppColors.coral,
      surface: AppColors.bgLight,
      error: AppColors.vividRed,
      brightness: Brightness.light,
    ),
  );
}
