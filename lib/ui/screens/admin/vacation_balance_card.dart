import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../ui/design_tokens.dart';
import '../../../ui/widgets/metric_chip.dart';

class VacationBalanceCard extends StatelessWidget {
  final String employeeId;
  final int year;

  const VacationBalanceCard({
    super.key,
    required this.employeeId,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('vacation_balances')
          .doc('${employeeId}_$year')
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final entitlement = (data?['entitlement'] ?? 0).toDouble();
        final carryOver = (data?['carryOver'] ?? 0).toDouble();
        final used = (data?['used'] ?? 0).toDouble();
        final planned = (data?['planned'] ?? 0).toDouble();
        final remaining = (data?['remaining'] ?? entitlement).toDouble();
        final sickDays = (data?['sickDays'] ?? 0).toDouble();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTokens.lg),
          decoration: BoxDecoration(
            borderRadius: AppTokens.borderRadiusMd,
            color: AppTokens.primarySubtle,
            border: Border.all(color: AppTokens.primary.withValues(alpha: 0.15)),
          ),
          child: Wrap(
            spacing: AppTokens.xl,
            runSpacing: AppTokens.md,
            children: [
              MetricChipVertical(
                label: 'Anspruch',
                value: _fmt(entitlement + carryOver),
              ),
              if (carryOver > 0)
                MetricChipVertical(
                  label: 'Übertrag',
                  value: _fmt(carryOver),
                  valueColor: AppTokens.infoFg,
                ),
              MetricChipVertical(
                label: 'Genommen',
                value: _fmt(used),
                valueColor: AppTokens.vacationFg,
              ),
              if (planned > 0)
                MetricChipVertical(
                  label: 'Geplant',
                  value: _fmt(planned),
                  valueColor: AppTokens.pendingFg,
                ),
              MetricChipVertical(
                label: 'Rest',
                value: _fmt(remaining),
                valueColor: remaining < 0 ? AppTokens.errorFg : AppTokens.successFg,
              ),
              MetricChipVertical(
                label: 'Krank',
                value: _fmt(sickDays),
                valueColor: AppTokens.sickFg,
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
