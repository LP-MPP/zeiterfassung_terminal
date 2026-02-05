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
    final IconData icon;

    switch (kind) {
      case BannerKind.success:
        border = Colors.green.shade700;
        bg = Colors.green.withOpacity(0.12);
        icon = Icons.check_circle;
        break;
      case BannerKind.error:
        border = Colors.red.shade700;
        bg = Colors.red.withOpacity(0.12);
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
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}