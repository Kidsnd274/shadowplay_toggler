import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _charcoal = Color(0xFF1A1A1A);
  static const _graphite = Color(0xFF2A2A2A);
  static const _nvidiaGreen = Color(0xFF76B900);
  static const _borderGrey = Color(0xFF3A3A3A);
  static const _textPrimary = Color(0xFFE0E0E0);
  static const _textSecondary = Color(0xFFB0B0B0);
  static const _error = Color(0xFFCF6679);

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _charcoal,
    colorScheme: const ColorScheme.dark(
      primary: _nvidiaGreen,
      secondary: _nvidiaGreen,
      surface: _graphite,
      error: _error,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: _textPrimary,
      onError: Colors.black,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _charcoal,
      foregroundColor: _textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: _textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: _graphite,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: _borderGrey),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _nvidiaGreen,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _textPrimary,
        side: const BorderSide(color: _borderGrey),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _nvidiaGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _charcoal,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: _borderGrey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: _borderGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: _nvidiaGreen, width: 2),
      ),
      labelStyle: const TextStyle(color: _textSecondary),
      hintStyle: const TextStyle(color: _textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: _nvidiaGreen,
      unselectedLabelColor: _textSecondary,
      indicatorColor: _nvidiaGreen,
      indicatorSize: TabBarIndicatorSize.tab,
    ),
    dividerTheme: const DividerThemeData(
      color: _borderGrey,
      thickness: 1,
      space: 1,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        color: _textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: _textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: TextStyle(
        color: _textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(color: _textPrimary, fontSize: 14),
      bodyMedium: TextStyle(color: _textPrimary, fontSize: 13),
      bodySmall: TextStyle(color: _textSecondary, fontSize: 12),
      labelLarge: TextStyle(
        color: _textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(color: _textSecondary, fontSize: 12),
      labelSmall: TextStyle(color: _textSecondary, fontSize: 11),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: _graphite,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _borderGrey),
      ),
      textStyle: const TextStyle(color: _textPrimary, fontSize: 12),
    ),
  );
}
