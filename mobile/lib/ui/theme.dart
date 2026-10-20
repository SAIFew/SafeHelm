import 'package:flutter/material.dart';

class SafeHelmTheme {
  // Brand Colors
  static const Color background = Color(0xFF0C101A);
  static const Color surface = Color(0xFF141B2D);
  static const Color surfaceHighlight = Color(0xFF1E2842);
  static const Color cardBorder = Color(0xFF263354);

  // Accent & Status Colors
  static const Color primary = Color(0xFF3B82F6); // Electric Blue
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color emergencyRed = Color(0xFFEF4444); // Urgent Emergency Red
  static const Color emergencyRedLight = Color(0xFFF87171);
  static const Color successGreen = Color(0xFF10B981); // Emerald Green
  static const Color warningAmber = Color(0xFFF59E0B); // Caution Amber
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textBright = Color(0xFFF8FAFC);

  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          onPrimary: Colors.white,
          surface: surface,
          onSurface: textBright,
          error: emergencyRed,
          onError: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: textBright,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
          iconTheme: IconThemeData(color: primaryLight),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: cardBorder, width: 1),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          indicatorColor: primary.withOpacity(0.2),
          iconTheme: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const IconThemeData(color: primaryLight);
            }
            return const IconThemeData(color: textMuted);
          }),
          labelTextStyle: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return const TextStyle(
                color: primaryLight,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              );
            }
            return const TextStyle(color: textMuted, fontSize: 12);
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceHighlight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          labelStyle: const TextStyle(color: textMuted),
        ),
      );
}
