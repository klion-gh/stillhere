import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'logger.dart';

const _tag = 'appearance';
const _paletteKey = 'appearance_palette';
const _backgroundKey = 'appearance_background';

/// A colour scheme the user can pick. Each one redefines the accent family
/// and the surface tint; the layout and typography stay identical so the app
/// still feels like one product.
enum AppPaletteId { midnight, emerald, sunset, ocean, graphite, sakura }

class AppPalette {
  final AppPaletteId id;
  final String name;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceOutline;
  final Color primary;
  final Color primaryDeep;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  const AppPalette({
    required this.id,
    required this.name,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceOutline,
    required this.primary,
    required this.primaryDeep,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, accent],
      );

  LinearGradient get backdropGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(background, primary, 0.10)!,
          background,
          Color.lerp(background, accent, 0.06)!,
        ],
      );

  static const midnight = AppPalette(
    id: AppPaletteId.midnight,
    name: 'Полночь',
    background: Color(0xFF0E0B18),
    surface: Color(0xFF171327),
    surfaceHigh: Color(0xFF211C36),
    surfaceOutline: Color(0xFF2E2748),
    primary: Color(0xFF8B7CF6),
    primaryDeep: Color(0xFF6D5AE0),
    accent: Color(0xFF5B8DEF),
    textPrimary: Color(0xFFF2EFFA),
    textSecondary: Color(0xFF9C93B8),
    textMuted: Color(0xFF6B6385),
  );

  static const emerald = AppPalette(
    id: AppPaletteId.emerald,
    name: 'Изумруд',
    background: Color(0xFF07140F),
    surface: Color(0xFF0F2019),
    surfaceHigh: Color(0xFF162C23),
    surfaceOutline: Color(0xFF224034),
    primary: Color(0xFF34D399),
    primaryDeep: Color(0xFF10B981),
    accent: Color(0xFF4ECDC4),
    textPrimary: Color(0xFFECFDF5),
    textSecondary: Color(0xFF8CAFA1),
    textMuted: Color(0xFF5E7D71),
  );

  static const sunset = AppPalette(
    id: AppPaletteId.sunset,
    name: 'Закат',
    background: Color(0xFF17090C),
    surface: Color(0xFF261216),
    surfaceHigh: Color(0xFF33191E),
    surfaceOutline: Color(0xFF48252C),
    primary: Color(0xFFFF7A59),
    primaryDeep: Color(0xFFE85D3D),
    accent: Color(0xFFFFB86C),
    textPrimary: Color(0xFFFFF1EC),
    textSecondary: Color(0xFFC0968D),
    textMuted: Color(0xFF8C6A63),
  );

  static const ocean = AppPalette(
    id: AppPaletteId.ocean,
    name: 'Океан',
    background: Color(0xFF061320),
    surface: Color(0xFF0C2033),
    surfaceHigh: Color(0xFF122C45),
    surfaceOutline: Color(0xFF1D3F5E),
    primary: Color(0xFF38BDF8),
    primaryDeep: Color(0xFF0EA5E9),
    accent: Color(0xFF6EE7B7),
    textPrimary: Color(0xFFECFAFF),
    textSecondary: Color(0xFF8AA9BF),
    textMuted: Color(0xFF5C7A88),
  );

  static const graphite = AppPalette(
    id: AppPaletteId.graphite,
    name: 'Графит',
    background: Color(0xFF0D0D0F),
    surface: Color(0xFF17171A),
    surfaceHigh: Color(0xFF212126),
    surfaceOutline: Color(0xFF2E2E35),
    primary: Color(0xFFE4E4E7),
    primaryDeep: Color(0xFFA1A1AA),
    accent: Color(0xFF7DD3FC),
    textPrimary: Color(0xFFF4F4F5),
    textSecondary: Color(0xFF9A9AA5),
    textMuted: Color(0xFF67676F),
  );

  static const sakura = AppPalette(
    id: AppPaletteId.sakura,
    name: 'Сакура',
    background: Color(0xFF15090F),
    surface: Color(0xFF23121B),
    surfaceHigh: Color(0xFF301926),
    surfaceOutline: Color(0xFF452537),
    primary: Color(0xFFFF8FB1),
    primaryDeep: Color(0xFFE05C8B),
    accent: Color(0xFFC084FC),
    textPrimary: Color(0xFFFFEFF5),
    textSecondary: Color(0xFFC195A8),
    textMuted: Color(0xFF8E6A79),
  );

  static const all = <AppPalette>[midnight, emerald, sunset, ocean, graphite, sakura];

  static AppPalette byId(AppPaletteId id) => all.firstWhere((p) => p.id == id, orElse: () => midnight);
}

/// Animated backdrop behind the full-screen flows and chat list.
enum AppBackgroundId { plain, orbs, aurora, stars }

class AppBackgroundOption {
  final AppBackgroundId id;
  final String name;
  final String description;

  const AppBackgroundOption({required this.id, required this.name, required this.description});

  static const all = <AppBackgroundOption>[
    AppBackgroundOption(id: AppBackgroundId.plain, name: 'Без анимации', description: 'Спокойный градиент'),
    AppBackgroundOption(id: AppBackgroundId.orbs, name: 'Сферы', description: 'Плавно плывущие пятна света'),
    AppBackgroundOption(id: AppBackgroundId.aurora, name: 'Сияние', description: 'Мягкие переливы, как северное сияние'),
    AppBackgroundOption(id: AppBackgroundId.stars, name: 'Звёзды', description: 'Медленное мерцание звёзд'),
  ];
}

class AppearanceState {
  final AppPaletteId paletteId;
  final AppBackgroundId backgroundId;

  const AppearanceState({
    this.paletteId = AppPaletteId.midnight,
    this.backgroundId = AppBackgroundId.orbs,
  });

  AppPalette get palette => AppPalette.byId(paletteId);

  AppearanceState copyWith({AppPaletteId? paletteId, AppBackgroundId? backgroundId}) {
    return AppearanceState(
      paletteId: paletteId ?? this.paletteId,
      backgroundId: backgroundId ?? this.backgroundId,
    );
  }
}

class AppearanceController extends StateNotifier<AppearanceState> {
  AppearanceController() : super(const AppearanceState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paletteName = prefs.getString(_paletteKey);
      final backgroundName = prefs.getString(_backgroundKey);
      state = AppearanceState(
        paletteId: AppPaletteId.values.firstWhere(
          (v) => v.name == paletteName,
          orElse: () => AppPaletteId.midnight,
        ),
        backgroundId: AppBackgroundId.values.firstWhere(
          (v) => v.name == backgroundName,
          orElse: () => AppBackgroundId.orbs,
        ),
      );
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to load appearance', e, st);
    }
  }

  Future<void> setPalette(AppPaletteId id) async {
    state = state.copyWith(paletteId: id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paletteKey, id.name);
  }

  Future<void> setBackground(AppBackgroundId id) async {
    state = state.copyWith(backgroundId: id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backgroundKey, id.name);
  }
}

final appearanceProvider =
    StateNotifierProvider<AppearanceController, AppearanceState>((ref) => AppearanceController());
