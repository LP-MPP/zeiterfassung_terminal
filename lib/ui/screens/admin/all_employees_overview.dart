import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/absence_helpers.dart';
import '../../../core/holidays_bw.dart';
import '../../../data/absence.dart';
import '../../../data/store.dart';
import 'admin_helpers.dart';

class AllEmployeesOverview extends StatefulWidget {
  final List<Employee> employees;
  final ValueChanged<String> onSelectEmployee;

  const AllEmployeesOverview({
    super.key,
    required this.employees,
    required this.onSelectEmployee,
  });

  @override
  State<AllEmployeesOverview> createState() => _AllEmployeesOverviewState();
}

class _AllEmployeesOverviewState extends State<AllEmployeesOverview> {
  final _db = FirebaseFirestore.instance;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  void _prevMonth() => setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
  void _nextMonth() => setState(() => _month = DateTime(_month.year, _month.month + 1, 1));

  Stream<List<TimeEvent>> _watchAllEventsForMonth(DateTime month) {
    final startUtcMs = startOfMonthLocal(month).toUtc().millisecondsSinceEpoch;
    final endUtcMs = endOfMonthLocal(month).toUtc().millisecondsSinceEpoch;

    return _db
        .collection('events')
        .where('timestampUtcMs', isGreaterThanOrEqualTo: startUtcMs)
        .where('timestampUtcMs', isLessThan: endUtcMs)
        .orderBy('timestampUtcMs', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(TimeEvent.fromDoc).toList());
  }

  /// Returns map: employeeId -> (dayKey -> override data)
  Stream<Map<String, Map<String, Map<String, dynamic>>>> _watchAllOverridesForMonth(DateTime month) {
    final startKey = dayKeyLocal(startOfMonthLocal(month));
    final endKey = dayKeyLocal(endOfMonthLocal(month));

    return _db.collection('day_overrides').snapshots().map((snap) {
      final result = <String, Map<String, Map<String, dynamic>>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final eid = d['employeeId']?.toString() ?? '';
        if (eid.isEmpty) continue;
        final dkField = d['dayKey']?.toString();
        final dk = (dkField != null && dkField.isNotEmpty)
            ? dkField
            : (doc.id.contains('_') ? doc.id.split('_').last : doc.id);
        if (dk.compareTo(startKey) < 0 || dk.compareTo(endKey) >= 0) continue;
        (result[eid] ??= {})[dk] = d;
      }
      return result;
    });
  }

  Stream<Map<String, bool>> _watchApprovalsForMonth(DateTime month) {
    final ym = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    return _db.collection('month_approvals').where('yearMonth', isEqualTo: ym).snapshots().map((snap) {
      final map = <String, bool>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final eid = d['employeeId']?.toString() ?? '';
        if (eid.isNotEmpty) map[eid] = true;
      }
      return map;
    });
  }

  /// Returns map: employeeId -> (dayKey -> absenceType) for the given month.
  Stream<Map<String, Map<String, String>>> _watchAllAbsencesForMonth(DateTime month) {
    final startKey = dayKeyLocal(startOfMonthLocal(month));
    final endKey = dayKeyLocal(endOfMonthLocal(month));

    return _db.collection('absences').snapshots().map((snap) {
      final result = <String, Map<String, String>>{};
      for (final doc in snap.docs) {
        final a = Absence.fromDoc(doc);
        if (a.status != AbsenceStatus.approved && a.status != AbsenceStatus.pending) continue;
        final expanded = expandAbsenceToDayKeys(a);
        for (final entry in expanded.entries) {
          if (entry.key.compareTo(startKey) >= 0 && entry.key.compareTo(endKey) < 0) {
            (result[a.employeeId] ??= {})[entry.key] = entry.value;
          }
        }
      }
      return result;
    });
  }

  /// Returns map: employeeId -> {remaining, sickDays} for the current year.
  Stream<Map<String, Map<String, double>>> _watchVacationBalances(int year) {
    return _db
        .collection('vacation_balances')
        .where('year', isEqualTo: year)
        .snapshots()
        .map((snap) {
      final result = <String, Map<String, double>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final eid = d['employeeId']?.toString() ?? '';
        if (eid.isEmpty) continue;
        result[eid] = {
          'remaining': (d['remaining'] ?? 0).toDouble(),
          'used': (d['used'] ?? 0).toDouble(),
          'planned': (d['planned'] ?? 0).toDouble(),
          'entitlement': (d['entitlement'] ?? 25).toDouble(),
          'sickDays': (d['sickDays'] ?? 0).toDouble(),
        };
      }
      return result;
    });
  }

  /// Returns map: employeeId -> count of PENDING absences.
  Stream<Map<String, int>> _watchPendingAbsences() {
    return _db
        .collection('absences')
        .where('status', isEqualTo: AbsenceStatus.pending)
        .snapshots()
        .map((snap) {
      final result = <String, int>{};
      for (final doc in snap.docs) {
        final eid = doc.data()['employeeId']?.toString() ?? '';
        if (eid.isEmpty) continue;
        result[eid] = (result[eid] ?? 0) + 1;
      }
      return result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Monatsübersicht alle Mitarbeiter',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(tooltip: 'Vorheriger Monat', onPressed: _prevMonth, icon: const Icon(Icons.chevron_left)),
                Text(monthLabel(_month), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                IconButton(tooltip: 'Nächster Monat', onPressed: _nextMonth, icon: const Icon(Icons.chevron_right)),
              ],
            ),
            const SizedBox(height: 12),

            // Data
            Expanded(
              child: StreamBuilder<List<TimeEvent>>(
                stream: _watchAllEventsForMonth(_month),
                builder: (context, evSnap) {
                  if (evSnap.hasError) return Center(child: Text('Fehler: ${evSnap.error}'));
                  if (!evSnap.hasData) return const Center(child: CircularProgressIndicator());

                  final allEvents = evSnap.data!;

                  return StreamBuilder<Map<String, Map<String, Map<String, dynamic>>>>(
                    stream: _watchAllOverridesForMonth(_month),
                    builder: (context, ovSnap) {
                      final allOverrides = ovSnap.hasData
                          ? ovSnap.data!
                          : const <String, Map<String, Map<String, dynamic>>>{};

                      return StreamBuilder<Map<String, bool>>(
                        stream: _watchApprovalsForMonth(_month),
                        builder: (context, apSnap) {
                          final approvals = apSnap.hasData ? apSnap.data! : const <String, bool>{};

                          return StreamBuilder<Map<String, Map<String, String>>>(
                            stream: _watchAllAbsencesForMonth(_month),
                            builder: (context, abSnap) {
                              final allAbsences = abSnap.hasData
                                  ? abSnap.data!
                                  : const <String, Map<String, String>>{};

                              return StreamBuilder<Map<String, Map<String, double>>>(
                                stream: _watchVacationBalances(_month.year),
                                builder: (context, balSnap) {
                                  final balances = balSnap.hasData
                                      ? balSnap.data!
                                      : const <String, Map<String, double>>{};

                                  return StreamBuilder<Map<String, int>>(
                                    stream: _watchPendingAbsences(),
                                    builder: (context, pendSnap) {
                                      final pendingCounts = pendSnap.hasData
                                          ? pendSnap.data!
                                          : const <String, int>{};

                          // Holiday names for this month's year
                          final holidayNames = getPublicHolidayNamesBW(_month.year);

                          // Group events by employee
                          final byEmployee = <String, List<TimeEvent>>{};
                          for (final ev in allEvents) {
                            (byEmployee[ev.employeeId] ??= []).add(ev);
                          }

                          // Build rows per employee
                          final rows = <_EmployeeRow>[];
                          for (final emp in widget.employees) {
                            final empEvents = byEmployee[emp.id] ?? [];
                            final byDay = groupEventsByDayKey(empEvents);
                            final empOverrides = allOverrides[emp.id] ?? const {};
                            final empAbsences = allAbsences[emp.id] ?? const {};
                            final empBalance = balances[emp.id];

                            Duration totalNet = Duration.zero;
                            int workDays = 0;
                            int flaggedDays = 0;
                            int monthVacationDays = 0;
                            int monthSickDays = 0;
                            int monthHolidayDays = 0;

                            final start = startOfMonthLocal(_month);
                            final end = endOfMonthLocal(_month);
                            for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
                              final dk = dayKeyLocal(d);
                              final ov = empOverrides[dk];
                              final dayEvents = byDay[dk] ?? const [];
                              final absType = empAbsences[dk];
                              final holName = holidayNames[dk];

                              DaySummary summary;
                              if (ov != null) {
                                summary = summaryFromOverrideMerged(ov, dayEvents);
                              } else if (dayEvents.isNotEmpty) {
                                summary = summaryFromEventsForDay(dayEvents);
                              } else if (absType != null || holName != null) {
                                // Credit standard daily hours for absence/holiday
                                final stdHours = emp.standardDailyHours;
                                final creditDur = Duration(minutes: (stdHours * 60).round());
                                summary = DaySummary(
                                  inTime: null,
                                  outTime: null,
                                  breakStart: null,
                                  breakEnd: null,
                                  net: d.weekday < 6 ? creditDur : Duration.zero,
                                  sourceLabel: absType != null ? 'ABWESEND' : 'FEIERTAG',
                                );
                              } else {
                                if (dayEvents.isEmpty && ov == null) continue;
                                summary = summaryFromEventsForDay(dayEvents);
                              }

                              totalNet += summary.net;
                              if (summary.inTime != null) workDays++;
                              final missingOut = summary.inTime != null && summary.outTime == null;
                              final missingBreakEnd = summary.breakStart != null && summary.breakEnd == null;
                              if (missingOut || missingBreakEnd) flaggedDays++;

                              if (absType == AbsenceType.urlaub && d.weekday < 6) monthVacationDays++;
                              if (absType == AbsenceType.krankheit && d.weekday < 6) monthSickDays++;
                              if (holName != null && d.weekday < 6) monthHolidayDays++;
                            }

                            rows.add(_EmployeeRow(
                              employee: emp,
                              totalNet: totalNet,
                              workDays: workDays,
                              flaggedDays: flaggedDays,
                              isApproved: approvals[emp.id] == true,
                              monthVacationDays: monthVacationDays,
                              monthSickDays: monthSickDays,
                              monthHolidayDays: monthHolidayDays,
                              vacationRemaining: empBalance?['remaining'],
                              vacationUsedYear: empBalance?['used'],
                              pendingRequests: pendingCounts[emp.id] ?? 0,
                            ));
                          }

                          return _buildTable(context, rows, cs);
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context, List<_EmployeeRow> rows, ColorScheme cs) {
    return ListView(
      children: [
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: cs.primary.withValues(alpha: 0.06),
          ),
          child: const Row(
            children: [
              SizedBox(width: 60, child: Text('ID', style: TextStyle(fontWeight: FontWeight.w900))),
              Expanded(flex: 3, child: Text('Name', style: TextStyle(fontWeight: FontWeight.w900))),
              SizedBox(width: 90, child: Text('Netto h', style: TextStyle(fontWeight: FontWeight.w900), textAlign: TextAlign.right)),
              SizedBox(width: 55, child: Text('Tage', style: TextStyle(fontWeight: FontWeight.w900), textAlign: TextAlign.right)),
              SizedBox(width: 40, child: Text('U', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0D6B52)), textAlign: TextAlign.center)),
              SizedBox(width: 40, child: Text('K', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFE65100)), textAlign: TextAlign.center)),
              SizedBox(width: 40, child: Text('F', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1565C0)), textAlign: TextAlign.center)),
              SizedBox(width: 80, child: Text('Url. Rest', style: TextStyle(fontWeight: FontWeight.w900), textAlign: TextAlign.right)),
              SizedBox(width: 65, child: Text('Flagged', style: TextStyle(fontWeight: FontWeight.w900), textAlign: TextAlign.right)),
              SizedBox(width: 60, child: Text('Gepr.', style: TextStyle(fontWeight: FontWeight.w900), textAlign: TextAlign.center)),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Data rows
        ...rows.map((r) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: () => widget.onSelectEmployee(r.employee.id),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(r.employee.id, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Flexible(child: Text(r.employee.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                          if (!r.employee.active) ...[
                            const SizedBox(width: 8),
                            _pill('INAKTIV', false),
                          ],
                          if (r.pendingRequests > 0) ...[
                            const SizedBox(width: 8),
                            _pendingPill(r.pendingRequests),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        '${durHHMM(r.totalNet)} h',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    SizedBox(
                      width: 55,
                      child: Text(
                        '${r.workDays}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    // Urlaub (month)
                    SizedBox(
                      width: 40,
                      child: Text(
                        r.monthVacationDays > 0 ? '${r.monthVacationDays}' : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: r.monthVacationDays > 0 ? const Color(0xFF0D6B52) : cs.onSurface.withValues(alpha: 0.3),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Krankheit (month)
                    SizedBox(
                      width: 40,
                      child: Text(
                        r.monthSickDays > 0 ? '${r.monthSickDays}' : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: r.monthSickDays > 0 ? const Color(0xFFE65100) : cs.onSurface.withValues(alpha: 0.3),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Feiertage (month)
                    SizedBox(
                      width: 40,
                      child: Text(
                        r.monthHolidayDays > 0 ? '${r.monthHolidayDays}' : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: r.monthHolidayDays > 0 ? const Color(0xFF1565C0) : cs.onSurface.withValues(alpha: 0.3),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Urlaub Rest (year)
                    SizedBox(
                      width: 80,
                      child: r.vacationRemaining != null
                          ? Text(
                              '${r.vacationRemaining!.toStringAsFixed(0)} Tage',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: r.vacationRemaining! <= 3 ? const Color(0xFF9B2E35) : const Color(0xFF0D6B52),
                              ),
                              textAlign: TextAlign.right,
                            )
                          : Text(
                              '—',
                              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.3)),
                              textAlign: TextAlign.right,
                            ),
                    ),
                    // Flagged
                    SizedBox(
                      width: 65,
                      child: Text(
                        r.flaggedDays > 0 ? '${r.flaggedDays}' : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: r.flaggedDays > 0 ? const Color(0xFF9B2E35) : cs.onSurface.withValues(alpha: 0.3),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    // Geprueft
                    SizedBox(
                      width: 60,
                      child: Center(
                        child: r.isApproved
                            ? const Icon(Icons.check_circle, color: Color(0xFF0D6B52), size: 22)
                            : Text('—', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.3))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _pendingPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFFFFF3E0),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, size: 12, color: Color(0xFFE65100)),
          const SizedBox(width: 4),
          Text(
            '$count Antrag${count > 1 ? 'e' : ''} offen',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFFE65100),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: ok ? const Color(0xFFEAF8F2) : const Color(0xFFFCEEF0),
        border: Border.all(color: ok ? const Color(0xFF96D8BF) : const Color(0xFFE9A7AE)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: ok ? const Color(0xFF0D6B52) : const Color(0xFF9B2E35),
        ),
      ),
    );
  }
}

class _EmployeeRow {
  final Employee employee;
  final Duration totalNet;
  final int workDays;
  final int flaggedDays;
  final bool isApproved;
  final int monthVacationDays;
  final int monthSickDays;
  final int monthHolidayDays;
  final double? vacationRemaining;
  final double? vacationUsedYear;
  final int pendingRequests;

  _EmployeeRow({
    required this.employee,
    required this.totalNet,
    required this.workDays,
    required this.flaggedDays,
    required this.isApproved,
    this.monthVacationDays = 0,
    this.monthSickDays = 0,
    this.monthHolidayDays = 0,
    this.vacationRemaining,
    this.vacationUsedYear,
    this.pendingRequests = 0,
  });
}
