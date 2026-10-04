import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const MaterialColor primarySwatch = MaterialColor(
    0xFF1E88E5, // Primary value
    <int, Color>{
      50: Color(0xFFE3F2FD),
      100: Color(0xFFBBDEFB),
      200: Color(0xFF90CAF9),
      300: Color(0xFF64B5F6),
      400: Color(0xFF42A5F5),
      500: Color(0xFF1E88E5), // Primary
      600: Color(0xFF1976D2),
      700: Color(0xFF1565C0),
      800: Color(0xFF0D47A1),
      900: Color(0xFF0D2E75),
    },
  );
  
  // Secondary Colors
  static const Color secondary = Color(0xFF26A69A);
  
  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF2196F3);
  
  // Neutral Colors
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Colors.white;
  static const Color onPrimary = Colors.white;
  static const Color onSecondary = Colors.white;
  static const Color onBackground = Color(0xFF1A1A1A);
  static const Color onSurface = Color(0xFF1A1A1A);
  static const Color onError = Colors.white;
  
  // Text Colors
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textDisabled = Color(0xFF9E9E9E);
  
  // Border Colors
  static const Color borderLight = Color(0xFFE0E0E0);
  static const Color borderDark = Color(0xFFBDBDBD);
  
  // Background Colors
  static const Color backgroundLight = Color(0xFFF5F7FA);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  
  // Status Backgrounds
  static const Color successLight = Color(0x1A4CAF50);
  static const Color warningLight = Color(0x1AFFC107);
  static const Color errorLight = Color(0x1AE53935);
  static const Color infoLight = Color(0x1A2196F3);
  
  // Accessibility
  static const Color focusRing = Color(0x801E88E5);
  static const Color overlay = Color(0x66000000);
}
