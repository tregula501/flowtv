import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Theme mode provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark); // Default to dark for IPTV

  void setThemeMode(ThemeMode mode) {
    state = mode;
  }

  void toggleTheme() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  bool get isDark => state == ThemeMode.dark;
}
