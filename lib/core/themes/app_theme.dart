import 'package:flutter/material.dart';

import 'dark_theme.dart';
import 'light_theme.dart';

/// App theme configuration
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => LightTheme.theme;
  static ThemeData get darkTheme => DarkTheme.theme;

  // Common colors used across themes
  static const Color primaryColor = Color(0xFF6366F1); // Indigo
  static const Color secondaryColor = Color(0xFF8B5CF6); // Purple
  static const Color errorColor = Color(0xFFEF4444);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF59E0B);

  // Accent colors for categories
  static const Color sportsColor = Color(0xFF22C55E);
  static const Color newsColor = Color(0xFF3B82F6);
  static const Color moviesColor = Color(0xFFEC4899);
  static const Color kidsColor = Color(0xFFFBBF24);
  static const Color musicColor = Color(0xFF8B5CF6);
}
