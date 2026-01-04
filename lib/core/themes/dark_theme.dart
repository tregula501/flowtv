import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Dark theme configuration (default for IPTV viewing)
class DarkTheme {
  DarkTheme._();

  static const Color _background = Color(0xFF0F0F0F);
  static const Color _surface = Color(0xFF1A1A1A);
  static const Color _surfaceVariant = Color(0xFF262626);
  static const Color _onBackground = Color(0xFFE5E5E5);
  static const Color _onSurface = Color(0xFFE5E5E5);
  static const Color _onSurfaceVariant = Color(0xFFA3A3A3);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppTheme.primaryColor,
        secondary: AppTheme.secondaryColor,
        error: AppTheme.errorColor,
        surface: _surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: _onSurface,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: _background,
      appBarTheme: const AppBarTheme(
        backgroundColor: _surface,
        foregroundColor: _onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        tileColor: Colors.transparent,
        selectedTileColor: AppTheme.primaryColor,
      ),
      dividerTheme: const DividerThemeData(
        color: _surfaceVariant,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.primaryColor,
        ),
      ),
      iconTheme: const IconThemeData(
        color: _onSurfaceVariant,
        size: 24,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: _onBackground,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: _onBackground,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _onBackground,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _onBackground,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: _onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: _onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: _onSurfaceVariant,
        ),
      ),
    );
  }
}
