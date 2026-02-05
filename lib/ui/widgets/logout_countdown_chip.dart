import 'package:flutter/material.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          width: 1.2,
          color: warn ? Colors.orange : Colors.grey.shade400,
        ),
        color: warn ? Colors.orange.withOpacity(0.12) : Colors.grey.withOpacity(0.08),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: warn ? Colors.orange.shade800 : Colors.black87,
        ),
      ),
    );
  }
}