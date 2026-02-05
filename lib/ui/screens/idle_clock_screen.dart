import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class IdleClockScreen extends StatelessWidget {
  final DateTime nowLocal;
  final VoidCallback onWake;

  const IdleClockScreen({
    super.key,
    required this.nowLocal,
    required this.onWake,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(nowLocal);
    final date = DateFormat('EEEE, dd. MMMM yyyy', 'de_DE').format(nowLocal);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onWake,
      child: Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 180,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -10,
                  height: 1,
                  fontFamily: 'monospace',
                  color: Colors.white.withOpacity(0.95),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                date,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Tippen zum Start',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}