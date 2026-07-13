import 'package:flutter/material.dart';

import '../../../ui/design_tokens.dart';
import '../../../ui/widgets/status_pill.dart';
import 'admin_helpers.dart';

class DayTile extends StatelessWidget {
  final String employeeId;
  final DayRow row;
  final String todayKey;
  final bool isEven;
  final VoidCallback onEdit;

  const DayTile({
    super.key,
    required this.employeeId,
    required this.row,
    required this.todayKey,
    required this.isEven,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final day = row.dayLocal;
    final dowNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final dow = dowNames[(day.weekday - 1).clamp(0, 6)];
    final dateLabel =
        '$dow, ${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.';

    final s = row.summary;
    final dk = row.dayKey;

    final hasActivity = s.inTime != null ||
        s.outTime != null ||
        s.breakStart != null ||
        s.breakEnd != null;
    final missingOut = hasActivity && s.inTime != null && s.outTime == null;
    final missingBreakEnd =
        hasActivity && s.breakStart != null && s.breakEnd == null;
    final hasWarning = missingOut || missingBreakEnd;

    final isWeekend = day.weekday >= 6;
    final isToday = dk == todayKey;
    final isFuture = day.isAfter(DateTime.now());
    final hasOverride = row.override != null;

    final absenceType = row.absenceType;
    final holidayName = row.holidayName;
    final isHoliday = holidayName != null;
    final isAbsence = absenceType != null;

    // Row background: semantic override > alternating
    Color bgColor;
    if (absenceType == 'URLAUB') {
      bgColor = AppTokens.vacationBg;
    } else if (absenceType == 'KRANKHEIT') {
      bgColor = AppTokens.sickBg;
    } else if (isHoliday) {
      bgColor = AppTokens.infoBg;
    } else if (missingOut || missingBreakEnd) {
      bgColor = AppTokens.errorBg;
    } else {
      bgColor = isEven ? AppTokens.surfaceCard : AppTokens.tableRowAlt;
    }

    // Compact time display
    final inLabel = hhmm(s.inTime);
    final outLabel = hhmm(s.outTime);
    final breakDur = safeDiff(s.breakStart, s.breakEnd);
    final breakLabel =
        breakDur > Duration.zero ? '${breakDur.inMinutes} min' : '—';
    final netLabel = '${durHHMM(s.net)} h';

    // Status pill
    Widget? statusWidget;
    if (isHoliday) {
      statusWidget = StatusPill.info('Feiertag');
    } else if (absenceType == 'URLAUB') {
      statusWidget = StatusPill.success('Urlaub');
    } else if (absenceType == 'KRANKHEIT') {
      statusWidget = StatusPill.warning('Krank');
    }

    final isInactiveWeekend = isWeekend && !hasActivity && !hasOverride && !isAbsence;
    final verticalPad = isInactiveWeekend ? 6.0 : 10.0;

    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTokens.md,
        vertical: verticalPad,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: AppTokens.outlineLight, width: 1),
        ),
      ),
      foregroundDecoration: isToday
          ? const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppTokens.primary, width: 3),
              ),
            )
          : null,
      child: Row(
        children: [
          // Warning icon column
          SizedBox(
            width: 28,
            child: hasWarning
                ? const Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppTokens.errorFg)
                : null,
          ),

          // Date column
          SizedBox(
            width: 100,
            child: Text(
              dateLabel,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isWeekend
                    ? AppTokens.onSurfaceMuted
                    : AppTokens.onSurface,
              ),
            ),
          ),

          // Status column
          SizedBox(
            width: 80,
            child: statusWidget,
          ),

          // Kommen column
          SizedBox(
            width: 60,
            child: Text(
              inLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppTokens.onSurface,
              ),
            ),
          ),

          // Gehen column
          SizedBox(
            width: 60,
            child: Text(
              outLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: missingOut ? AppTokens.errorFg : AppTokens.onSurface,
              ),
            ),
          ),

          // Pause column
          SizedBox(
            width: 60,
            child: Text(
              breakLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: missingBreakEnd
                    ? AppTokens.errorFg
                    : AppTokens.onSurfaceMuted,
              ),
            ),
          ),

          // Netto column
          SizedBox(
            width: 70,
            child: Text(
              netLabel,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),

          const SizedBox(width: AppTokens.sm),

          // ADM column
          SizedBox(
            width: 44,
            child: hasOverride
                ? StatusPill(
                    text: 'ADM',
                    fg: AppTokens.primary,
                    bg: AppTokens.primarySubtle,
                    border: AppTokens.primary.withValues(alpha: 0.3),
                  )
                : null,
          ),

          // Edit button column
          SizedBox(
            width: 36,
            child: !isFuture
                ? IconButton(
                    tooltip: 'Bearbeiten',
                    onPressed: onEdit,
                    icon: Icon(Icons.edit_outlined,
                        size: 16, color: AppTokens.onSurfaceMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 16,
                  )
                : null,
          ),
        ],
      ),
    );

    if (isFuture) {
      return Opacity(opacity: 0.4, child: content);
    }
    return content;
  }
}
