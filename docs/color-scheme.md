# EI Simulator — Color Scheme Reference

> Source of truth for app-wide palette. All screens, widgets and themes must import `lib/theme/app_colors.dart` instead of hard-coding hex values. See `lib/theme/app_theme.dart` for `ThemeData` wiring (`lib/main.dart:25`).

## 1. Palette

| Swatch | Hex Code | RGB Value | Token | Usage |
| :--- | :--- | :--- | :--- | :--- |
| ![#FAEDED](https://via.placeholder.com/16/FAEDED/FAEDED.png) | `#FAEDED` | `rgb(250, 237, 237)` | `AppColors.bgLight` `0xFFFAEDED` | Very pale pink / off-white — **page background**, card background, dialog background, light area behind bottom sheets |
| ![#FF655B](https://via.placeholder.com/16/FF655B/FF655B.png) | `#FF655B` | `rgb(255, 101, 91)` | `AppColors.coral` `0xFFFF655B` | Coral / salmon orange-red — **primary accent**: chips/pills, `FAB`, `Add Relationship` button, bottom circular actions, `Switch`, focused borders |
| ![#FF1E25](https://via.placeholder.com/16/FF1E25/FF1E25.png) | `#FF1E25` | `rgb(255, 30, 37)` | `AppColors.vividRed` `0xFFFF1E25` | Vivid bright red — **hero / sheet background**, destructive delete, mutual edge/arrow, loading indicator |

No other hues are used. Black/white are used only as text overlays with opacity (`white`, `white70`, `black54`, etc.).

### Dart constants (`lib/theme/app_colors.dart:1`)

```dart
class AppColors {
  static const bgLight  = Color(0xFFFAEDED); // 250,237,237
  static const coral    = Color(0xFFFF655B); // 255,101,91
  static const vividRed = Color(0xFFFF1E25); // 255,30,37
}
```

## 2. Semantic Tokens (how to pick)

| Token | Maps to | Example |
| :--- | :--- | :--- |
| `background` | `bgLight` | `Scaffold.backgroundColor` (`graph_screen.dart:152`, `profile_screen.dart:402`, `main.dart:ThemeData.scaffoldBackgroundColor`) |
| `surface` | `bgLight` | `Card` on red sheet (`profile_screen.dart:252`), `AlertDialog` (`profile_screen.dart:67`), `TextField` fill |
| `primary` | `coral` | `ElevatedButton` / `FAB` (`graph_screen.dart:185`), `Chip` (`profile_screen.dart:200`), `Chip.shape` border |
| `hero` | `vividRed` | Red bottom sheet (`profile_screen.dart:676`), mutual edge `Paint` (`graph_screen.dart:294`), `delete` icon/text |
| `onBackground` | `Colors.black87` / `Color(0xFF2B0000)` | Title on `bgLight` card/dialog |
| `onHero` | `Colors.white` | Text on `vividRed` sheet (`profile_screen.dart:200`) |
| `outline` | `coral.withValues(alpha:0.6)` | Focused `OutlineInputBorder`, `Switch.activeThumbColor` |

## 3. Theme Wiring

`lib/theme/app_theme.dart` exposes `AppTheme.light`:

```dart
ThemeData(
  scaffoldBackgroundColor: AppColors.bgLight,
  appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, iconTheme: IconThemeData(color: Colors.black87), titleTextStyle: TextStyle(color: Colors.black87)),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: AppColors.coral, foregroundColor: Colors.white),
  elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: AppColors.coral, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: 12))),
  chipTheme: ChipThemeData(backgroundColor: AppColors.coral.withValues(alpha:0.2), side: BorderSide(color: AppColors.coral), labelStyle: TextStyle(color: Colors.white)),
  progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.vividRed),
  dialogTheme: DialogTheme(backgroundColor: AppColors.bgLight, shape: RoundedRectangleBorder(borderRadius: 16)),
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.vividRed, primary: AppColors.coral, surface: AppColors.bgLight, error: AppColors.vividRed),
)
```

Applied in `lib/main.dart:25` via `MaterialApp(theme: AppTheme.light, ...)`.

## 4. Migration Notes

*   Remove hard-coded `Color(0xFF0D0D0D)` (dark) from 5 screens: `graph_screen.dart:152`, `profile_screen.dart:402`, `add_edit_person_screen.dart:160`, `add_edit_relationship_screen.dart:189`, `search_screen.dart:46` — replace with `AppColors.bgLight` or `AppColors.vividRed` per sheet.
*   Replace `Colors.pinkAccent` (old accent) with `AppColors.coral` (9 occurrences: `graph_screen:185`, `profile:200`, `add_edit_*` focused borders).
*   Replace `Colors.redAccent` / `vividRed` delete with `AppColors.vividRed`.
*   Keep `withValues(alpha:)` pattern (Flutter ≥3.27) — already used in `graph_screen.dart:294` and `profile_screen.dart:200`.

## 5. Accessibility

*   `bgLight (#FAEDED)` on `white` text fails contrast — always use `black87` or `Color(0xFF3A0000)` on `bgLight` cards (see `profile_screen.dart:338` `title: Color(0xFF3A0000)`).
*   `white` on `vividRed (#FF1E25)` passes AA for 12sp+ (header `profile_screen:202`).
*   Test with `flutter test` and DevTools `Color contrast` overlay at `http://127.0.0.1:.../devtools`.

## 6. References

*   Tokens defined in `lib/theme/app_colors.dart:1`
*   Theme in `lib/theme/app_theme.dart:1`
*   Applied at `lib/main.dart:9` `MaterialApp(theme: AppTheme.light)`
*   Palette requested in user spec `2026-09-02`
