import 'package:flutter/material.dart';

import '../design_tokens.dart';

enum BannerKind { success, error }

class InfoBanner extends StatelessWidget {
  final String text;
  final BannerKind kind;
  final bool dense;

  const InfoBanner({
    super.key,
    required this.text,
    required this.kind,
    this.dense = false,
  });

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
      margin: EdgeInsets.only(bottom: dense ? AppTokens.xs : AppTokens.sm),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : AppTokens.md,
        vertical: dense ? 8 : AppTokens.md,
      ),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: border, width: 1.2),
        color: bg,
      ),
      child: Row(
        children: [
          Icon(icon, color: border, size: dense ? 19 : 24),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Text(
              text,
              maxLines: dense ? 1 : null,
              overflow: dense ? TextOverflow.ellipsis : null,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: dense ? 13 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
