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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 560;
            final timeHeight = compact ? 120.0 : 180.0;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: timeHeight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        time,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 128 : 180,
                          fontWeight: FontWeight.w900,
                          letterSpacing: compact ? -6 : -10,
                          height: 1,
                          fontFamily: 'monospace',
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    date,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 16 : 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 18),
                  Text(
                    'Tippen zum Start',
                    style: TextStyle(
                      fontSize: compact ? 14 : 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
