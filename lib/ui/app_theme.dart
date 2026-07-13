import 'package:flutter/material.dart';

import 'design_tokens.dart';

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppTokens.primary),
  );

  final cs = base.colorScheme.copyWith(
    primary: AppTokens.primary,
    surface: AppTokens.surface,
    onSurface: AppTokens.onSurface,
    outline: AppTokens.outline,
    outlineVariant: AppTokens.outlineLight,
  );

  return base.copyWith(
    colorScheme: cs,
    scaffoldBackgroundColor: AppTokens.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: AppTokens.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppTokens.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      iconTheme: const IconThemeData(color: AppTokens.onSurface),
    ),
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppTokens.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusLg,
        side: const BorderSide(color: AppTokens.outline, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(color: AppTokens.outlineLight),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppTokens.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: AppTokens.lg, horizontal: AppTokens.lg),
        shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusMd),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTokens.onSurface,
        padding: const EdgeInsets.symmetric(vertical: AppTokens.lg, horizontal: AppTokens.lg),
        shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusMd),
        side: const BorderSide(color: AppTokens.outline),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTokens.snackbarBg,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusMd),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppTokens.surfaceCard,
      border: OutlineInputBorder(
        borderRadius: AppTokens.borderRadiusMd,
        borderSide: const BorderSide(color: AppTokens.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppTokens.borderRadiusMd,
        borderSide: const BorderSide(color: AppTokens.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppTokens.borderRadiusMd,
        borderSide: const BorderSide(color: AppTokens.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}
