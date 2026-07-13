import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A KPI card for dashboard display.
///
/// Shows an icon, label, value, and optional accent color.
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? accentColor;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTokens.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: AppTokens.borderRadiusLg,
      child: Container(
        padding: const EdgeInsets.all(AppTokens.lg),
        decoration: BoxDecoration(
          color: AppTokens.surfaceCard,
          borderRadius: AppTokens.borderRadiusLg,
          border: Border.all(color: AppTokens.outlineLight),
          boxShadow: const [AppTokens.shadowSm],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: AppTokens.borderRadiusMd,
                color: accent.withValues(alpha: 0.1),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(height: AppTokens.md),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            const SizedBox(height: AppTokens.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTokens.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
