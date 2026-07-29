import 'package:flutter/material.dart';

/// Centralized design tokens for the entire app.
/// All colors, spacing, radii, and shadows are defined here.
class AppTokens {
  AppTokens._();

  // ─── Brand ───────────────────────────────────────────
  static const Color primary = Color(0xFF1E4A86);
  static const Color primaryLight = Color(0x141E4A86); // 8% alpha
  static const Color primarySubtle = Color(0x0A1E4A86); // 4% alpha

  // ─── Surfaces ────────────────────────────────────────
  static const Color surface = Color(0xFFF3F6FB);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF0F0F4);
  static const Color surfaceOverlay = Color(0xFFEDF2FB);
  static const Color tableRowAlt = Color(0xFFF8FAFD); // Alternating table rows

  // ─── Borders ─────────────────────────────────────────
  static const Color outline = Color(0xFFD8E1EE);
  static const Color outlineLight = Color(0xFFE6ECF5);

  // ─── Text ────────────────────────────────────────────
  static const Color onSurface = Color(0xFF10233E);
  static Color get onSurfaceMuted => onSurface.withValues(alpha: 0.62);
  static Color get onSurfaceFaint => onSurface.withValues(alpha: 0.35);

  // ─── Semantic: Success (green) ───────────────────────
  static const Color successFg = Color(0xFF0D6B52);
  static const Color successBg = Color(0xFFEAF8F2);
  static const Color successBorder = Color(0xFF96D8BF);

  // ─── Semantic: Error (red) ───────────────────────────
  static const Color errorFg = Color(0xFF9B2E35);
  static const Color errorBg = Color(0xFFFCEEF0);
  static const Color errorBorder = Color(0xFFE9A7AE);

  // ─── Semantic: Warning (orange) ──────────────────────
  static const Color warningFg = Color(0xFFE65100);
  static const Color warningBg = Color(0xFFFFF3E0);
  static const Color warningBorder = Color(0xFFFFB74D);

  // ─── Semantic: Info (blue) ───────────────────────────
  static const Color infoFg = Color(0xFF1565C0);
  static const Color infoBg = Color(0xFFE3F2FD);
  static const Color infoBorder = Color(0xFF90CAF9);

  // ─── Semantic: Pending (gold) ────────────────────────
  static const Color pendingFg = Color(0xFFB8860B);
  static const Color pendingBg = Color(0xFFFFF8E1);
  static const Color pendingBorder = Color(0xFFFFCC80);

  // ─── Semantic: Neutral (grey) ────────────────────────
  static const Color neutralFg = Color(0xFF666666);
  static const Color neutralBg = Color(0xFFF5F5F5);
  static const Color neutralBorder = Color(0xFFCCCCCC);

  // ─── Absence type colors ─────────────────────────────
  static const Color vacationFg = successFg;
  static const Color vacationBg = successBg;
  static const Color vacationBorder = successBorder;

  static const Color sickFg = Color(0xFFE67E22);
  static const Color sickBg = Color(0xFFFFF8E1);
  static const Color sickBorder = Color(0xFFFFCC80);

  static const Color specialLeaveFg = Color(0xFF6D28D9);
  static const Color specialLeaveBg = Color(0xFFF3E8FF);
  static const Color specialLeaveBorder = Color(0xFFC4B5FD);

  static const Color holidayFg = infoFg;
  static const Color holidayBg = infoBg;

  // ─── Terminal state glow ─────────────────────────────
  static const Color stateWorkingGlow = Color(0xFF4CAF50);
  static const Color stateBreakGlow = Color(0xFFFFA726);

  // ─── Snackbar ────────────────────────────────────────
  static const Color snackbarBg = Color(0xFF142E53);

  // ─── Spacing ─────────────────────────────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // ─── Border Radii ────────────────────────────────────
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 999;

  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusPill = BorderRadius.circular(
    radiusPill,
  );

  // ─── Shadows ─────────────────────────────────────────
  static const BoxShadow shadowSm = BoxShadow(
    color: Color(0x0A0C2C54),
    blurRadius: 8,
    offset: Offset(0, 2),
  );
  static const BoxShadow shadowMd = BoxShadow(
    color: Color(0x120C2C54),
    blurRadius: 18,
    offset: Offset(0, 8),
  );
  static const BoxShadow shadowLg = BoxShadow(
    color: Color(0x150C2C54),
    blurRadius: 30,
    offset: Offset(0, 12),
  );

  // ─── Avatar colors (deterministic from ID) ──────────
  static const List<Color> avatarColors = [
    Color(0xFF5C6BC0), // indigo
    Color(0xFF26A69A), // teal
    Color(0xFFEF5350), // red
    Color(0xFFAB47BC), // purple
    Color(0xFF42A5F5), // blue
    Color(0xFFFF7043), // deep orange
    Color(0xFF66BB6A), // green
    Color(0xFFEC407A), // pink
  ];

  /// Returns a deterministic avatar color for an employee ID.
  static Color avatarColorFor(String id) {
    var hash = 0;
    for (var i = 0; i < id.length; i++) {
      hash = id.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return avatarColors[hash.abs() % avatarColors.length];
  }

  /// Returns the initials for a name (first letter of first + last name).
  static String initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    final a = parts[0].isNotEmpty ? parts[0][0] : '';
    final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    final s = (a + b).toUpperCase();
    return s.isEmpty ? '?' : s;
  }
}
