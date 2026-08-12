import 'package:flutter/material.dart';

import '../design_tokens.dart';

class PunchActionGrid extends StatelessWidget {
  const PunchActionGrid({
    required this.canPunchIn,
    required this.canPunchOut,
    required this.canBreakStart,
    required this.canBreakEnd,
    required this.busy,
    required this.compact,
    required this.onPunchIn,
    required this.onPunchOut,
    required this.onBreakStart,
    required this.onBreakEnd,
    super.key,
  });

  final bool canPunchIn;
  final bool canPunchOut;
  final bool canBreakStart;
  final bool canBreakEnd;
  final bool busy;
  final bool compact;
  final VoidCallback onPunchIn;
  final VoidCallback onPunchOut;
  final VoidCallback onBreakStart;
  final VoidCallback onBreakEnd;

  @override
  Widget build(BuildContext context) {
    final spacing = compact ? 8.0 : 10.0;

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Kommen',
                  icon: Icons.login,
                  enabled: canPunchIn,
                  busy: busy,
                  compact: compact,
                  onTap: onPunchIn,
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: _ActionButton(
                  label: 'Gehen',
                  icon: Icons.logout,
                  enabled: canPunchOut,
                  busy: busy,
                  compact: compact,
                  onTap: onPunchOut,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Pause Start',
                  icon: Icons.pause,
                  enabled: canBreakStart,
                  busy: busy,
                  compact: compact,
                  onTap: onBreakStart,
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: _ActionButton(
                  label: 'Pause Ende',
                  icon: Icons.play_arrow,
                  enabled: canBreakEnd,
                  busy: busy,
                  compact: compact,
                  onTap: onBreakEnd,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.busy,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool busy;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy || !enabled ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: enabled ? AppTokens.primary : AppTokens.surfaceMuted,
        foregroundColor: enabled ? Colors.white : AppTokens.onSurfaceFaint,
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusLg),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: compact ? 17 : 20),
          SizedBox(width: compact ? 6 : AppTokens.sm),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 13 : 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
