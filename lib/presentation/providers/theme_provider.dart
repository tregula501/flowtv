import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../../data/datasources/local/database_service.dart';

/// Convert between [ThemeMode] and the integer stored in the database.
///   0 = system, 1 = light, 2 = dark
ThemeMode themeModeFromIndex(int index) {
  return switch (index) {
    0 => ThemeMode.system,
    1 => ThemeMode.light,
    _ => ThemeMode.dark,
  };
}

int themeModeToIndex(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 0,
    ThemeMode.light => 1,
    ThemeMode.dark => 2,
  };
}

/// Theme mode notifier - persists to database
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadFromDatabase();
    return ThemeMode.dark; // Default until DB value loads
  }

  Future<void> _loadFromDatabase() async {
    try {
      final db = DatabaseService.instance;
      final settings =
          await (db.select(db.appSettingsTable)..limit(1)).getSingle();
      final mode = themeModeFromIndex(settings.themeMode);
      if (state != mode) {
        state = mode;
      }
    } catch (e) {
      AppLogger.warning('Could not load theme from database: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    _persistToDatabase(mode);
  }

  void toggleTheme() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setThemeMode(next);
  }

  bool get isDark => state == ThemeMode.dark;

  Future<void> _persistToDatabase(ThemeMode mode) async {
    try {
      final db = DatabaseService.instance;
      await (db.update(db.appSettingsTable)
            ..where((t) => t.id.equals(1)))
          .write(
        AppSettingsTableCompanion(
          themeMode: Value(themeModeToIndex(mode)),
        ),
      );
    } catch (e) {
      AppLogger.warning('Could not save theme to database: $e');
    }
  }
}

/// Theme mode provider
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
