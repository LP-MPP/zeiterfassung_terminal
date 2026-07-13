import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A small colored pill badge for status display.
///
/// Usage:
/// ```dart
/// StatusPill.success('AKTIV')
/// StatusPill.error('INAKTIV')
/// StatusPill.warning('OFFEN')
/// StatusPill.custom('KRANKHEIT', fg: sickFg, bg: sickBg, border: sickBorder)
/// ```
class StatusPill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  final Color border;
  final IconData? icon;
  final double fontSize;

  const StatusPill({
    super.key,
    required this.text,
    required this.fg,
    required this.bg,
    required this.border,
    this.icon,
    this.fontSize = 11,
  });

  factory StatusPill.success(String text, {IconData? icon}) => StatusPill(
        text: text,
        fg: AppTokens.successFg,
        bg: AppTokens.successBg,
        border: AppTokens.successBorder,
        icon: icon,
      );

  factory StatusPill.error(String text, {IconData? icon}) => StatusPill(
        text: text,
        fg: AppTokens.errorFg,
        bg: AppTokens.errorBg,
        border: AppTokens.errorBorder,
        icon: icon,
      );

  factory StatusPill.warning(String text, {IconData? icon}) => StatusPill(
        text: text,
        fg: AppTokens.warningFg,
        bg: AppTokens.warningBg,
        border: AppTokens.warningBorder,
        icon: icon,
      );

  factory StatusPill.info(String text, {IconData? icon}) => StatusPill(
        text: text,
        fg: AppTokens.infoFg,
        bg: AppTokens.infoBg,
        border: AppTokens.infoBorder,
        icon: icon,
      );

  factory StatusPill.neutral(String text, {IconData? icon}) => StatusPill(
        text: text,
        fg: AppTokens.neutralFg,
        bg: AppTokens.neutralBg,
        border: AppTokens.neutralBorder,
        icon: icon,
      );

  factory StatusPill.pending(String text, {IconData? icon}) => StatusPill(
        text: text,
        fg: AppTokens.pendingFg,
        bg: AppTokens.pendingBg,
        border: AppTokens.pendingBorder,
        icon: icon,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusPill,
        color: bg,
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
