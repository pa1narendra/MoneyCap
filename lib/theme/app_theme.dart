import 'package:flutter/material.dart';

/// Design tokens for MoneyCap — a clean, minimal, indigo-accented theme that
/// works comfortably in BOTH light and dark, without harsh contrast.
class AppColors {
  AppColors._();

  /// Indigo brand seed — distinct from the income/expense green/red.
  static const seed = Color(0xFF6366F1); // indigo-500

  // Semantic transaction colors, tuned per brightness so they keep good
  // contrast on a light surface AND don't glare on a dark one.
  static const _incomeLight = Color(0xFF059669); // emerald-600
  static const _incomeDark = Color(0xFF34D399); // emerald-400
  static const _expenseLight = Color(0xFFE11D48); // rose-600
  static const _expenseDark = Color(0xFFFB7185); // rose-400

  static Color income(Brightness b) =>
      b == Brightness.dark ? _incomeDark : _incomeLight;
  static Color expense(Brightness b) =>
      b == Brightness.dark ? _expenseDark : _expenseLight;

  /// Cohesive, distinct palette for charts (pie sections + legend) — reads well
  /// in both light and dark.
  static const chartPalette = <Color>[
    Color(0xFF6366F1), // indigo
    Color(0xFF8B5CF6), // violet
    Color(0xFF22D3EE), // cyan
    Color(0xFFFBBF24), // amber
    Color(0xFFFB7185), // rose
  ];
}

/// Consistent spacing scale — use these instead of magic numbers.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      // Flat, minimal app bar that matches the background in both modes.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
