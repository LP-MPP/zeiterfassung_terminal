import 'package:flutter/material.dart';

import '../design_tokens.dart';

class LogoutCountdownChip extends StatelessWidget {
  final int seconds;
  const LogoutCountdownChip({super.key, required this.seconds});

  @override
  Widget build(BuildContext context) {
    final warn = seconds <= 20;
    final mm = (seconds ~/ 60).toString().padLeft(1, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    final label = 'Abmeldung in $mm:$ss';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.sm, vertical: AppTokens.sm),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusPill,
        border: Border.all(
          width: 1.2,
          color: warn ? AppTokens.warningBorder : AppTokens.neutralBorder,
        ),
        color: warn ? AppTokens.warningBg : AppTokens.neutralBg,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: warn ? AppTokens.warningFg : AppTokens.onSurface,
        ),
      ),
    );
  }
}
