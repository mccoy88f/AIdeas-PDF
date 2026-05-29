import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Dark
  static const bg       = Color(0xFF0b0e14);
  static const s1       = Color(0xFF141820);
  static const s2       = Color(0xFF1c2130);
  static const s3       = Color(0xFF252d3d);
  static const border   = Color(0xFF2e3850);
  static const textCol  = Color(0xFFd4daf0);
  static const muted    = Color(0xFF6b7898);
  static const accent   = Color(0xFF4f8ef7);
  static const accent2  = Color(0xFF00d4a0);
  static const danger   = Color(0xFFf06060);

  // Light
  static const lbg      = Color(0xFFf0f2f7);
  static const ls1      = Color(0xFFffffff);
  static const ls2      = Color(0xFFf5f6fa);
  static const lborder  = Color(0xFFd0d4e4);
  static const ltext    = Color(0xFF1a1d2e);
  static const lmuted   = Color(0xFF7a82a0);

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accent2,
      error: danger,
      surface: s1,
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.dark().textTheme,
    ).apply(bodyColor: textCol, displayColor: textCol),
    appBarTheme: const AppBarTheme(
      backgroundColor: s1,
      foregroundColor: textCol,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerColor: border,
    cardColor: s2,
  );

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lbg,
    colorScheme: const ColorScheme.light(
      primary: accent,
      secondary: accent2,
      error: danger,
      surface: ls1,
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.light().textTheme,
    ).apply(bodyColor: ltext, displayColor: ltext),
    appBarTheme: const AppBarTheme(
      backgroundColor: ls1,
      foregroundColor: ltext,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerColor: lborder,
    cardColor: ls2,
  );
}
