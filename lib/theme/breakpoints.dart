import 'package:flutter/widgets.dart';

/// Adaptive breakpoints — single source of truth.
/// Use with `LayoutBuilder(constraints.maxWidth)` or `MediaQuery.sizeOf(context).width`.
/// Never use hardware type or orientation checks.
class AppBreakpoints {
  AppBreakpoints._();

  /// Phone → tablet/desktop threshold (skill example: 600)
  static const double largeScreenMinWidth = 600.0;

  /// Extra breakpoint for graph sidebar (wider content + nav)
  static const double desktopMinWidth = 900.0;

  /// Max content width for readability on large screens
  static const double maxContentWidth = 800.0;
  static const double maxFormWidth = 560.0;
  static const double maxSheetWidth = 640.0;

  static bool isLargeScreen(BoxConstraints c) => c.maxWidth > largeScreenMinWidth;
  static bool isDesktop(BoxConstraints c) => c.maxWidth > desktopMinWidth;
  static bool isLargeScreenWidth(double w) => w > largeScreenMinWidth;
}
