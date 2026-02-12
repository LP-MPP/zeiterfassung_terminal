import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const seed = Color(0xFF1E4A86);
  const surface = Color(0xFFF3F6FB);
  const surfaceCard = Color(0xFFFFFFFF);
  const outline = Color(0xFFD8E1EE);

  final base = ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed));
  final cs = base.colorScheme.copyWith(
    primary: seed,
    surface: surface,
    onSurface: const Color(0xFF10233E),
    outline: outline,
    outlineVariant: const Color(0xFFE6ECF5),
  );

  return base.copyWith(
    colorScheme: cs,
    scaffoldBackgroundColor: surface,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: cs.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: cs.onSurface),
    ),
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1),
    ),
    cardTheme: CardThemeData(
      color: surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: outline, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: cs.outline),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF142E53),
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}
