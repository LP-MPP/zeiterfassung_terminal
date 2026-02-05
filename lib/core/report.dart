// lib/core/report.dart
//
// Reports aus Event-Log:
// - Daily: IN->OUT minus Pausen, plus Flags
// - Monthly Summary per employee: Totals + flags count
// - CSV generators (German Excel: semicolon)

import 'package:intl/intl.dart';
import '../data/store.dart';

class DailyReportRow {
  final String employeeId;
  final DateTime dayLocal; // 00:00 local
  final int workMinutes;   // brutto zwischen IN und OUT
  final int breakMinutes;  // Summe Pausen
  final int netMinutes;    // work - break
  final DateTime? firstInLocal;
  final DateTime? lastOutLocal;
  final String flags;      // comma-separated

  DailyReportRow({
    required this.employeeId,
    required this.dayLocal,
    required this.workMinutes,
    required this.breakMinutes,
    required this.netMinutes,
    required this.firstInLocal,
    required this.lastOutLocal,
    required this.flags,
  });

  List<String> flagsList() {
    if (flags.trim().isEmpty) return const [];
    return flags.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}

class EmployeeMonthlySummary {
  final String employeeId;
  final int workMinutesTotal;
  final int breakMinutesTotal;
  final int netMinutesTotal;
  final int daysCount;
  final int flaggedDaysCount;
  final int missingOutDaysCount;

  EmployeeMonthlySummary({
    required this.employeeId,
    required this.workMinutesTotal,
    required this.breakMinutesTotal,
    required this.netMinutesTotal,
    required this.daysCount,
    required this.flaggedDaysCount,
    required this.missingOutDaysCount,
  });
}

class MonthlyReportResult {
  final List<DailyReportRow> dailyRows;
  final List<EmployeeMonthlySummary> summaries;
  MonthlyReportResult({required this.dailyRows, required this.summaries});
}

MonthlyReportResult buildMonthlyReport({
  required InMemoryStore store,
  required int year,
  required int month, // 1..12
}) {
  final dailyRows = _buildDailyRows(store: store, year: year, month: month);
  final summaries = _buildSummaries(dailyRows);
  return MonthlyReportResult(dailyRows: dailyRows, summaries: summaries);
}

List<DailyReportRow> _buildDailyRows({
  required InMemoryStore store,
  required int year,
  required int month,
}) {
  // UTC month range; day grouping is LOCAL
  final fromUtc = DateTime.utc(year, month, 1);
  final toUtc = DateTime.utc(year, month + 1, 1);
  final events = store.eventsInRangeUtc(
    fromUtc.millisecondsSinceEpoch,
    toUtc.millisecondsSinceEpoch,
  );

  // Group by employee
  final Map<String, List<TimeEvent>> byEmp = {};
  for (final e in events) {
    byEmp.putIfAbsent(e.employeeId, () => []).add(e);
  }

  final List<DailyReportRow> out = [];

  for (final entry in byEmp.entries) {
    final empId = entry.key;
    final empEvents = entry.value
      ..sort((a, b) => a.timestampUtcMs.compareTo(b.timestampUtcMs));

    // Group by local day key
    final Map<String, List<TimeEvent>> byDayKey = {};
    for (final ev in empEvents) {
      final local = DateTime.fromMillisecondsSinceEpoch(ev.timestampUtcMs, isUtc: true).toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      byDayKey.putIfAbsent(key, () => []).add(ev);
    }

    for (final dayEntry in byDayKey.entries) {
      final dayEvents = dayEntry.value
        ..sort((a, b) => a.timestampUtcMs.compareTo(b.timestampUtcMs));

      final firstLocal = DateTime.fromMillisecondsSinceEpoch(dayEvents.first.timestampUtcMs, isUtc: true).toLocal();
      final dayLocal = DateTime(firstLocal.year, firstLocal.month, firstLocal.day);

      final flags = <String>[];

      DateTime? inAt;
      DateTime? breakStartAt;

      DateTime? firstInLocal;
      DateTime? lastOutLocal;

      int workMinutes = 0;
      int breakMinutes = 0;

      for (final ev in dayEvents) {
        final tLocal = DateTime.fromMillisecondsSinceEpoch(ev.timestampUtcMs, isUtc: true).toLocal();

        switch (ev.eventType) {
          case 'IN':
            if (inAt != null) {
              flags.add('DUPLICATE_IN');
            } else {
              inAt = tLocal;
              firstInLocal ??= tLocal;
            }
            break;

          case 'BREAK_START':
            if (inAt == null) {
              flags.add('BREAK_WITHOUT_IN');
              break;
            }
            if (breakStartAt != null) {
              flags.add('DUPLICATE_BREAK_START');
              break;
            }
            breakStartAt = tLocal;
            break;

          case 'BREAK_END':
            if (breakStartAt == null) {
              flags.add('BREAK_END_WITHOUT_START');
              break;
            }
            final mins = _minutesBetween(breakStartAt!, tLocal);
            if (mins < 0) {
              flags.add('BREAK_NEGATIVE_TIME');
            } else {
              breakMinutes += mins;
            }
            breakStartAt = null;
            break;

          case 'OUT':
            if (inAt == null) {
              flags.add('OUT_WITHOUT_IN');
              break;
            }

            // open break -> close at OUT
            if (breakStartAt != null) {
              flags.add('BREAK_NOT_ENDED');
              final mins = _minutesBetween(breakStartAt!, tLocal);
              if (mins >= 0) breakMinutes += mins;
              breakStartAt = null;
            }

            final mins = _minutesBetween(inAt!, tLocal);
            if (mins < 0) {
              flags.add('WORK_NEGATIVE_TIME');
            } else {
              workMinutes += mins;
            }

            lastOutLocal = tLocal;
            inAt = null;
            break;

          default:
            flags.add('UNKNOWN_EVENT_${ev.eventType}');
        }
      }

      if (inAt != null) {
        flags.add('MISSING_OUT');
      }
      if (breakStartAt != null) {
        flags.add('BREAK_NOT_ENDED');
      }

      final netMinutes = (workMinutes - breakMinutes).clamp(0, 1000000);

      out.add(
        DailyReportRow(
          employeeId: empId,
          dayLocal: dayLocal,
          workMinutes: workMinutes,
          breakMinutes: breakMinutes,
          netMinutes: netMinutes,
          firstInLocal: firstInLocal,
          lastOutLocal: lastOutLocal,
          flags: flags.toSet().join(','),
        ),
      );
    }
  }

  out.sort((a, b) {
    final c = a.employeeId.compareTo(b.employeeId);
    if (c != 0) return c;
    return a.dayLocal.compareTo(b.dayLocal);
  });

  return out;
}

List<EmployeeMonthlySummary> _buildSummaries(List<DailyReportRow> dailyRows) {
  final Map<String, List<DailyReportRow>> byEmp = {};
  for (final r in dailyRows) {
    byEmp.putIfAbsent(r.employeeId, () => []).add(r);
  }

  final summaries = <EmployeeMonthlySummary>[];

  for (final entry in byEmp.entries) {
    final empId = entry.key;
    final rows = entry.value;

    int work = 0;
    int brk = 0;
    int net = 0;

    int flaggedDays = 0;
    int missingOutDays = 0;

    for (final r in rows) {
      work += r.workMinutes;
      brk += r.breakMinutes;
      net += r.netMinutes;

      final fl = r.flagsList();
      if (fl.isNotEmpty) flaggedDays++;
      if (fl.contains('MISSING_OUT')) missingOutDays++;
    }

    summaries.add(
      EmployeeMonthlySummary(
        employeeId: empId,
        workMinutesTotal: work,
        breakMinutesTotal: brk,
        netMinutesTotal: net,
        daysCount: rows.length,
        flaggedDaysCount: flaggedDays,
        missingOutDaysCount: missingOutDays,
      ),
    );
  }

  summaries.sort((a, b) => a.employeeId.compareTo(b.employeeId));
  return summaries;
}

// -------- CSV --------

String buildMonthlyDailyReportCsv({
  required InMemoryStore store,
  required int year,
  required int month,
}) {
  final res = buildMonthlyReport(store: store, year: year, month: month);
  final rows = res.dailyRows;

  final dateFmt = DateFormat('yyyy-MM-dd');
  final dtFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  final sb = StringBuffer();

  sb.writeln('employee_id;date;work_hhmm;break_hhmm;net_hhmm;first_in;last_out;flags');

  for (final r in rows) {
    sb.writeln([
      r.employeeId,
      dateFmt.format(r.dayLocal),
      hhmm(r.workMinutes),
      hhmm(r.breakMinutes),
      hhmm(r.netMinutes),
      r.firstInLocal == null ? '' : dtFmt.format(r.firstInLocal!),
      r.lastOutLocal == null ? '' : dtFmt.format(r.lastOutLocal!),
      r.flags,
    ].map(_csvEscape).join(';'));
  }

  return sb.toString();
}

String buildMonthlySummaryCsv({
  required InMemoryStore store,
  required int year,
  required int month,
}) {
  final res = buildMonthlyReport(store: store, year: year, month: month);
  final sums = res.summaries;

  final sb = StringBuffer();
  sb.writeln('employee_id;days;work_total_hhmm;break_total_hhmm;net_total_hhmm;flagged_days;missing_out_days');

  for (final s in sums) {
    sb.writeln([
      s.employeeId,
      s.daysCount.toString(),
      hhmm(s.workMinutesTotal),
      hhmm(s.breakMinutesTotal),
      hhmm(s.netMinutesTotal),
      s.flaggedDaysCount.toString(),
      s.missingOutDaysCount.toString(),
    ].map(_csvEscape).join(';'));
  }

  return sb.toString();
}

// -------- helpers --------

int _minutesBetween(DateTime a, DateTime b) => b.difference(a).inMinutes;

String hhmm(int minutes) {
  final m = minutes.abs();
  final h = m ~/ 60;
  final mm = m % 60;
  return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

String _csvEscape(String v) {
  final needsQuotes = v.contains(';') || v.contains('"') || v.contains('\n') || v.contains('\r');
  if (!needsQuotes) return v;
  final escaped = v.replaceAll('"', '""');
  return '"$escaped"';
}