import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// StillHere's visual identity: a deep indigo-to-violet night palette with
/// a warm coral accent for calls. Dark-first — the app is meant to feel
/// like a quiet, private room.
class AppColors {
  static const Color background = Color(0xFF0E0B18);
  static const Color surface = Color(0xFF171327);
  static const Color surfaceHigh = Color(0xFF211C36);
  static const Color surfaceOutline = Color(0xFF2E2748);

  static const Color primary = Color(0xFF8B7CF6);
  static const Color primaryDeep = Color(0xFF6D5AE0);
  static const Color accent = Color(0xFF4ECDC4);
  static const Color danger = Color(0xFFFF5C7A);
  static const Color success = Color(0xFF4ADE80);

  static const Color textPrimary = Color(0xFFF2EFFA);
  static const Color textSecondary = Color(0xFF9C93B8);
  static const Color textMuted = Color(0xFF6B6385);

  /// Backdrop gradient used on the auth/connect/call screens.
  static const LinearGradient nightGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF15102A), Color(0xFF0E0B18), Color(0xFF130E24)],
  );

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B7CF6), Color(0xFF5B8DEF)],
  );

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

ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryDeep,
    onPrimaryContainer: Colors.white,
    secondary: AppColors.accent,
    onSecondary: Color(0xFF06231F),
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
    appBarTheme: const AppBarTheme(
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
      systemOverlayStyle: SystemUiOverlayStyle(
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
      hintStyle: const TextStyle(color: AppColors.textMuted),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      prefixStyle: const TextStyle(color: AppColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.surfaceOutline, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
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
      titleTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.5),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.surfaceOutline, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondary,
      textColor: AppColors.textPrimary,
    ),
  );
}
