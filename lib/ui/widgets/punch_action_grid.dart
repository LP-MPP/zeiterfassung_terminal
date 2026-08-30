import 'package:flutter/material.dart';

import '../design_tokens.dart';

class PunchActionGrid extends StatelessWidget {
  const PunchActionGrid({
    required this.canPunchIn,
    required this.canPunchOut,
    required this.canBreakStart,
    required this.canBreakEnd,
    required this.busy,
    required this.pendingEventType,
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
  final String? pendingEventType;
  final bool compact;
  final VoidCallback onPunchIn;
  final VoidCallback onPunchOut;
  final VoidCallback onBreakStart;
  final VoidCallback onBreakEnd;

  @override
  Widget build(BuildContext context) {
    final spacing = compact ? 8.0 : 10.0;
    final maximumGridHeight = compact ? 180.0 : 240.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : maximumGridHeight;
        final gridHeight = availableHeight.clamp(0.0, maximumGridHeight);

        return Center(
          child: SizedBox(
            height: gridHeight,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'Kommen',
                          icon: Icons.login,
                          enabled: canPunchIn,
                          busy: busy,
                          showProgress: pendingEventType == 'IN',
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
                          showProgress: pendingEventType == 'OUT',
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'Pause Start',
                          icon: Icons.pause,
                          enabled: canBreakStart,
                          busy: busy,
                          showProgress: pendingEventType == 'BREAK_START',
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
                          showProgress: pendingEventType == 'BREAK_END',
                          compact: compact,
                          onTap: onBreakEnd,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.busy,
    required this.showProgress,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool busy;
  final bool showProgress;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FilledButton(
        onPressed: busy || !enabled ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? AppTokens.primary : AppTokens.surfaceMuted,
          foregroundColor: enabled ? Colors.white : AppTokens.onSurfaceFaint,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusLg),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy && showProgress)
              SizedBox.square(
                dimension: compact ? 18 : 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTokens.onSurfaceMuted,
                ),
              )
            else
              Icon(icon, size: compact ? 20 : 22),
            SizedBox(width: compact ? 7 : AppTokens.sm),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  busy && showProgress ? 'Wird gespeichert …' : label,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 15 : 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
