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
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final timeHeight = compact ? 62.0 : 84.0;
        final timeStyle = TextStyle(
          fontSize: compact ? 72 : 92,
          fontWeight: FontWeight.w900,
          letterSpacing: compact ? -2.0 : -2.8,
          height: 0.95,
          fontFamily: 'monospace',
          color: cs.onSurface,
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: timeHeight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  time,
                  textAlign: TextAlign.center,
                  style: timeStyle,
                ),
              ),
            ),
            SizedBox(height: compact ? 6 : 10),
            Text(
              date,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        );
      },
    );
  }
}
