import 'package:flutter/material.dart';

import '../design_tokens.dart';

enum BannerKind { success, error }

class InfoBanner extends StatelessWidget {
  final String text;
  final BannerKind kind;

  const InfoBanner({super.key, required this.text, required this.kind});

  @override
  Widget build(BuildContext context) {
    final Color border;
    final Color bg;
    final Color textColor;
    final IconData icon;

    switch (kind) {
      case BannerKind.success:
        border = AppTokens.successFg;
        bg = AppTokens.successBg;
        textColor = const Color(0xFF0A4C3A);
        icon = Icons.check_circle;
        break;
      case BannerKind.error:
        border = AppTokens.errorFg;
        bg = AppTokens.errorBg;
        textColor = const Color(0xFF5D1A22);
        icon = Icons.error;
        break;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppTokens.sm),
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: border, width: 1.2),
        color: bg,
      ),
      child: Row(
        children: [
          Icon(icon, color: border),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
