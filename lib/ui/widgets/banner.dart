import 'package:flutter/material.dart';

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
        border = const Color(0xFF0D6B52);
        bg = const Color(0xFFEAF8F2);
        textColor = const Color(0xFF0A4C3A);
        icon = Icons.check_circle;
        break;
      case BannerKind.error:
        border = const Color(0xFF9B2E35);
        bg = const Color(0xFFFCEEF0);
        textColor = const Color(0xFF5D1A22);
        icon = Icons.error;
        break;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.2),
        color: bg,
      ),
      child: Row(
        children: [
          Icon(icon, color: border),
          const SizedBox(width: 10),
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
