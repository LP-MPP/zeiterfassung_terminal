import 'package:flutter/material.dart';

import '../../../ui/design_tokens.dart';
import '../../../ui/widgets/metric_chip.dart';
import 'admin_helpers.dart';

class MonthTotalsCard extends StatelessWidget {
  final Duration totalNet;
  final int overrideCount;
  final int eventCount;
  final int vacationDays;
  final int sickDays;
  final int holidayDays;

  const MonthTotalsCard({
    super.key,
    required this.totalNet,
    required this.overrideCount,
    required this.eventCount,
    this.vacationDays = 0,
    this.sickDays = 0,
    this.holidayDays = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusMd,
        color: AppTokens.primarySubtle,
        border: Border.all(color: AppTokens.primary.withValues(alpha: 0.2)),
      ),
      child: Wrap(
        spacing: AppTokens.lg,
        runSpacing: AppTokens.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Total net hours — prominent
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 18, color: AppTokens.primary),
              const SizedBox(width: AppTokens.xs),
              Text(
                '${durHHMM(totalNet)} h',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.primary,
                ),
              ),
            ],
          ),

          MetricChip(label: 'Events', value: '$eventCount'),
          if (overrideCount > 0)
            MetricChip(
              label: 'Korrekturen',
              value: '$overrideCount',
              valueColor: AppTokens.primary,
            ),
          if (vacationDays > 0)
            MetricChip(
              label: 'Urlaub',
              value: '$vacationDays T',
              valueColor: AppTokens.vacationFg,
            ),
          if (sickDays > 0)
            MetricChip(
              label: 'Krank',
              value: '$sickDays T',
              valueColor: AppTokens.sickFg,
            ),
          if (holidayDays > 0)
            MetricChip(
              label: 'Feiertage',
              value: '$holidayDays T',
              valueColor: AppTokens.infoFg,
            ),
        ],
      ),
    );
  }
}
