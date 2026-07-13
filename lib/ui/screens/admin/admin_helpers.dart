import '../../../data/store.dart';

// ────────────────────────────────────────────
// Data classes
// ────────────────────────────────────────────

class DaySummary {
  final DateTime? inTime;
  final DateTime? outTime;
  final DateTime? breakStart;
  final DateTime? breakEnd;
  final Duration net;
  final String sourceLabel; // ADMIN / AUTO
  final String? reason;
  final String? adminUid;

  DaySummary({
    required this.inTime,
    required this.outTime,
    required this.breakStart,
    required this.breakEnd,
    required this.net,
    required this.sourceLabel,
    this.reason,
    this.adminUid,
  });
}

class DayRow {
  final DateTime dayLocal;
  final String dayKey;
  final DaySummary summary;
  final Map<String, dynamic>? override;
  final List<TimeEvent> autoDayEvents;
  final String? absenceType; // URLAUB | KRANKHEIT | null
  final String? holidayName; // e.g. "Karfreitag" | null

  DayRow({
    required this.dayLocal,
    required this.dayKey,
    required this.summary,
    required this.override,
    required this.autoDayEvents,
    this.absenceType,
    this.holidayName,
  });
}

// ────────────────────────────────────────────
// Formatting helpers
// ────────────────────────────────────────────

String hhmm(DateTime? dt) {
  if (dt == null) return '—';
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String durHHMM(Duration d) {
  final totalMin = d.inMinutes;
  final h = (totalMin ~/ 60).toString().padLeft(2, '0');
  final m = (totalMin % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

String dayKeyLocal(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String monthLabel(DateTime m) {
  const names = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ];
  return '${names[m.month - 1]} ${m.year}';
}

DateTime startOfMonthLocal(DateTime m) => DateTime(m.year, m.month, 1);
DateTime endOfMonthLocal(DateTime m) => DateTime(m.year, m.month + 1, 1);

Duration safeDiff(DateTime? a, DateTime? b) {
  if (a == null || b == null) return Duration.zero;
  final d = b.difference(a);
  if (d.isNegative) return Duration.zero;
  return d;
}

DateTime? localFromUtcMs(dynamic v) {
  if (v == null) return null;
  final ms = (v is int) ? v : int.tryParse(v.toString());
  if (ms == null || ms <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
}

int? utcMsFromLocalDateTime(DateTime? localDt) {
  if (localDt == null) return null;
  return localDt.toUtc().millisecondsSinceEpoch;
}

// ────────────────────────────────────────────
// Summary computation
// ────────────────────────────────────────────

DateTime? resolvedOverrideDateTime({
  required Map<String, dynamic> override,
  required String valueKey,
  required DateTime? autoValue,
}) {
  if (!override.containsKey(valueKey)) return autoValue;
  return localFromUtcMs(override[valueKey]) ?? autoValue;
}

Map<String, List<TimeEvent>> groupEventsByDayKey(List<TimeEvent> events) {
  final map = <String, List<TimeEvent>>{};
  for (final e in events) {
    final dk = TimeEvent.dayKeyFromUtcMs(e.timestampUtcMs);
    (map[dk] ??= []).add(e);
  }
  for (final entry in map.entries) {
    entry.value.sort((a, b) => a.timestampUtcMs.compareTo(b.timestampUtcMs));
  }
  return map;
}

DaySummary summaryFromEventsForDay(List<TimeEvent> dayEvents) {
  DateTime? inTime;
  DateTime? outTime;
  DateTime? breakStart;
  DateTime? breakEnd;

  for (final e in dayEvents) {
    final t = DateTime.fromMillisecondsSinceEpoch(e.timestampUtcMs, isUtc: true).toLocal();
    switch (e.eventType) {
      case 'IN':
        inTime ??= t;
        break;
      case 'OUT':
        outTime = t;
        break;
      case 'BREAK_START':
        if (breakStart == null && (inTime == null || t.isAfter(inTime))) breakStart = t;
        break;
      case 'BREAK_END':
        if (breakEnd == null && breakStart != null && t.isAfter(breakStart)) breakEnd = t;
        break;
      default:
        break;
    }
  }

  final workSpan = safeDiff(inTime, outTime);
  final breakSpan = safeDiff(breakStart, breakEnd);
  final net = workSpan - breakSpan;

  return DaySummary(
    inTime: inTime,
    outTime: outTime,
    breakStart: breakStart,
    breakEnd: breakEnd,
    net: net.isNegative ? Duration.zero : net,
    sourceLabel: 'AUTO',
  );
}

DaySummary summaryFromOverrideMerged(Map<String, dynamic> o, List<TimeEvent> autoDayEvents) {
  final auto = summaryFromEventsForDay(autoDayEvents);

  final inTime = resolvedOverrideDateTime(override: o, valueKey: 'inUtcMs', autoValue: auto.inTime);
  final outTime = resolvedOverrideDateTime(override: o, valueKey: 'outUtcMs', autoValue: auto.outTime);
  final breakStart = resolvedOverrideDateTime(override: o, valueKey: 'breakStartUtcMs', autoValue: auto.breakStart);
  final breakEnd = resolvedOverrideDateTime(override: o, valueKey: 'breakEndUtcMs', autoValue: auto.breakEnd);

  final workSpan = safeDiff(inTime, outTime);
  final breakSpan = safeDiff(breakStart, breakEnd);
  final net = workSpan - breakSpan;

  return DaySummary(
    inTime: inTime,
    outTime: outTime,
    breakStart: breakStart,
    breakEnd: breakEnd,
    net: net.isNegative ? Duration.zero : net,
    sourceLabel: 'ADMIN',
    reason: o['reason']?.toString(),
    adminUid: o['adminUid']?.toString(),
  );
}

// ────────────────────────────────────────────
// ISO week number
// ────────────────────────────────────────────

int isoWeekNumber(DateTime date) {
  // ISO 8601: Week starts Monday, week 1 contains Jan 4
  final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
  final weekday = date.weekday; // 1=Mon, 7=Sun
  final woy = ((dayOfYear - weekday + 10) ~/ 7);
  if (woy < 1) return isoWeekNumber(DateTime(date.year - 1, 12, 31));
  if (woy > 52) {
    final dec31Weekday = DateTime(date.year, 12, 31).weekday;
    if (dec31Weekday < 4) return 1;
  }
  return woy;
}
