import 'package:flutter/material.dart';

import '../../../ui/design_tokens.dart';
import 'admin_helpers.dart';

class WeekSubtotalRow extends StatelessWidget {
  final int weekNumber;
  final Duration totalNet;

  const WeekSubtotalRow({
    super.key,
    required this.weekNumber,
    required this.totalNet,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: AppTokens.sm,
      ),
      decoration: BoxDecoration(
        color: AppTokens.primarySubtle,
        border: Border(
          bottom: BorderSide(color: AppTokens.outlineLight, width: 1),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 28), // warning col
          Text(
            'KW $weekNumber',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTokens.primary,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          // Align with Netto column: 44 (ADM) + 8 (gap) + 36 (edit) from right
          Padding(
            padding: const EdgeInsets.only(right: 44 + AppTokens.sm + 36),
            child: SizedBox(
              width: 70,
              child: Text(
                '${durHHMM(totalNet)} h',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTokens.primary,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
