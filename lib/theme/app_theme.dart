import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4169E1)),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        foregroundColor: base.colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: base.textTheme.bodyMedium,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
