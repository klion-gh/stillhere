/// The Material theme, built from the active palette.
///
/// Colours are mutable statics rather than theme entries because every screen
/// reads them directly. That has a cost — a widget reading them has no
/// dependency Flutter can track — which is what appearance.dart's watchPalette
/// exists to repair.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';

/// StillHere's visual identity. Dark-first — the app is meant to feel like a
/// quiet, private room.
///
/// These are deliberately mutable statics rather than constants: the user can
/// switch palettes at runtime, and every screen reads its colours from here.
/// [apply] is called before the app rebuilds with a new palette.
class AppColors {
  static Color background = AppPalette.midnight.background;
  static Color surface = AppPalette.midnight.surface;
  static Color surfaceHigh = AppPalette.midnight.surfaceHigh;
  static Color surfaceOutline = AppPalette.midnight.surfaceOutline;

  static Color primary = AppPalette.midnight.primary;
  static Color primaryDeep = AppPalette.midnight.primaryDeep;
  static Color accent = AppPalette.midnight.accent;

  // Semantic, not decorative — a failure is red and a success is green in
  // every palette, so these stay fixed.
  static const Color danger = Color(0xFFFF5C7A);
  static const Color success = Color(0xFF4ADE80);

  static Color textPrimary = AppPalette.midnight.textPrimary;
  static Color textSecondary = AppPalette.midnight.textSecondary;
  static Color textMuted = AppPalette.midnight.textMuted;

  /// Backdrop gradient used on the auth/connect/call screens.
  static LinearGradient nightGradient = AppPalette.midnight.backdropGradient;

  static LinearGradient brandGradient = AppPalette.midnight.brandGradient;

  static void apply(AppPalette palette) {
    background = palette.background;
    surface = palette.surface;
    surfaceHigh = palette.surfaceHigh;
    surfaceOutline = palette.surfaceOutline;
    primary = palette.primary;
    primaryDeep = palette.primaryDeep;
    accent = palette.accent;
    textPrimary = palette.textPrimary;
    textSecondary = palette.textSecondary;
    textMuted = palette.textMuted;
    nightGradient = palette.backdropGradient;
    brandGradient = palette.brandGradient;
  }

  /// Deterministic per-user avatar gradient — same tag always gets the same
  /// colors, so people become recognizable by color at a glance.
  static LinearGradient avatarGradient(String seed) {
    const palettes = <List<Color>>[
      [Color(0xFF8B7CF6), Color(0xFF5B8DEF)],
      [Color(0xFF4ECDC4), Color(0xFF44A08D)],
      [Color(0xFFFF8FB1), Color(0xFFE05C8B)],
      [Color(0xFFFFB86C), Color(0xFFF97316)],
      [Color(0xFF60A5FA), Color(0xFF3B82F6)],
      [Color(0xFFA78BFA), Color(0xFFEC4899)],
      [Color(0xFF34D399), Color(0xFF10B981)],
      [Color(0xFFFBBF24), Color(0xFFF59E0B)],
    ];
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    final colors = palettes[hash % palettes.length];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }
}

ThemeData buildAppTheme([AppPalette? palette]) {
  if (palette != null) AppColors.apply(palette);

  final colorScheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryDeep,
    onPrimaryContainer: Colors.white,
    secondary: AppColors.accent,
    onSecondary: const Color(0xFF06231F),
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.surfaceHigh,
    error: AppColors.danger,
    onError: Colors.white,
    outline: AppColors.surfaceOutline,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: AppColors.textSecondary),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      hintStyle: TextStyle(color: AppColors.textMuted),
      labelStyle: TextStyle(color: AppColors.textSecondary),
      prefixStyle: TextStyle(color: AppColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.surfaceOutline, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.surfaceOutline,
        disabledForegroundColor: AppColors.textMuted,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.5),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 15),
    ),
    dividerTheme: DividerThemeData(color: AppColors.surfaceOutline, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.primary),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.textSecondary,
      textColor: AppColors.textPrimary,
    ),
  );
}
