import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A standardized card with optional glow effect.
///
/// Used across the app for consistent styling:
/// - Terminal punch card (with state glow)
/// - Admin section cards
/// - Dashboard panels
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? glowColor;
  final double glowOpacity;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTokens.lg),
    this.glowColor,
    this.glowOpacity = 0.15,
  });

  @override
  Widget build(BuildContext context) {
    final hasGlow = glowColor != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTokens.surfaceCard,
        borderRadius: AppTokens.borderRadiusLg,
        border: Border.all(
          color: hasGlow
              ? glowColor!.withValues(alpha: 0.35)
              : AppTokens.outlineLight,
        ),
        boxShadow: [
          AppTokens.shadowMd,
          if (hasGlow)
            BoxShadow(
              color: glowColor!.withValues(alpha: glowOpacity),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: child,
    );
  }
}
