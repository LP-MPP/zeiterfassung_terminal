// lib/ui/widgets/clock_header.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ClockHeader extends StatelessWidget {
  final DateTime nowLocal;

  const ClockHeader({super.key, required this.nowLocal});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(nowLocal);
    final date = DateFormat('EEEE, dd. MMMM yyyy', 'de_DE').format(nowLocal);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Big, clean, monospace time
        Text(
          time,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 92,
            fontWeight: FontWeight.w900,
            letterSpacing: -2.8,
            height: 0.95,
            fontFamily: 'monospace',
            color: Colors.black,
          ),
        ),

        const SizedBox(height: 10),

        // Subtle date
        Text(
          date,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: Colors.black.withOpacity(0.45),
          ),
        ),
      ],
    );
  }
}