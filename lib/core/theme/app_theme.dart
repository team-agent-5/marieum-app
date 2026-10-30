import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';

abstract final class AppTheme {
  static ThemeData light() {
    final colors = ColorScheme.fromSeed(
      seedColor: AppTokens.primary,
      primary: AppTokens.primaryStrong,
      onPrimary: AppTokens.surface,
      primaryContainer: AppTokens.primarySoft,
      onPrimaryContainer: AppTokens.onTonal,
      surface: AppTokens.surface,
      onSurface: AppTokens.ink,
      error: AppTokens.danger,
      onError: AppTokens.surface,
      outline: AppTokens.lineStrong,
      outlineVariant: AppTokens.line,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: AppTokens.fontFamily,
      scaffoldBackgroundColor: AppTokens.bg,
      focusColor: AppTokens.focus,
      textTheme: const TextTheme(
        headlineSmall: AppTokens.title,
        bodyLarge: TextStyle(fontSize: 18, height: 1.5),
        bodyMedium: AppTokens.copy,
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppTokens.bg,
        foregroundColor: AppTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 60,
        titleTextStyle: TextStyle(
          fontFamily: AppTokens.fontFamily,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: AppTokens.ink,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppTokens.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.buttonRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppTokens.surface,
        contentPadding: const EdgeInsets.all(15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
          borderSide: const BorderSide(color: AppTokens.lineStrong),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppTokens.line),
    );
  }
}
