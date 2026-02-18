import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SovaColors {
  static const Color bg = Color(0xFFF9FBF9);
  static const Color sage = Color(0xFF8DA399);
  static const Color charcoal = Color(0xFF1A1C20);
  static const Color coral = Color(0xFFFE6D73);
  static const Color navy = Color(0xFF1A2E44); // Deep, Modern Navy
  static const Color softGlass = Color(0xFFF1F4F2);

  static const Color success = Color(0xFF81B29A);
  static const Color danger = Color(0xFFE07A5F);
  static const Color sensorNeutral = Color(0xFFD9E2DF);
}

class SovaTheme {
  static TextTheme get textTheme =>
      GoogleFonts.plusJakartaSansTextTheme().copyWith(
        displayMedium: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w800,
          fontSize: 32,
          color: SovaColors.charcoal,
          height: 1.1,
        ),
        labelMedium: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: 2.0,
          color: SovaColors.sage,
        ),
      );
}
