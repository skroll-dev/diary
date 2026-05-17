import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4A90D9),
        brightness: Brightness.light,
        fontFamily: 'Inter',
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4A90D9),
        brightness: Brightness.dark,
        fontFamily: 'Inter',
      );
}
