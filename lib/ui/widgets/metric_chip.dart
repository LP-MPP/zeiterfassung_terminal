import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A compact label + value pair, used in balance cards and info bars.
class MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final double fontSize;

  const MetricChip({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            color: (valueColor ?? AppTokens.onSurface).withValues(alpha: 0.65),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: fontSize,
            color: valueColor ?? AppTokens.onSurface,
          ),
        ),
      ],
    );
  }
}

/// A larger metric chip for balance cards — label on top, value below.
class MetricChipVertical extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const MetricChipVertical({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppTokens.onSurfaceFaint,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: valueColor ?? AppTokens.onSurface,
          ),
        ),
      ],
    );
  }
}
