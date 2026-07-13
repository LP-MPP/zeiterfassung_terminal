import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/absence_helpers.dart';
import '../../../core/excel_export.dart';
import '../../../core/holidays_bw.dart';
import '../../../core/web_download.dart';
import '../../../data/absence.dart';
import '../../../data/store.dart';
import '../../../ui/design_tokens.dart';
import '../../../ui/widgets/section_header.dart';
import 'admin_helpers.dart';
import 'approval_section.dart';
import 'day_tile.dart';
import 'edit_day_dialog.dart';
import 'month_totals_card.dart';
import 'week_subtotal_row.dart';

class MonthPane extends StatefulWidget {
  final Employee employee;

  const MonthPane({super.key, required this.employee});

  @override
  State<MonthPane> createState() => _MonthPaneState();
}

class _MonthPaneState extends State<MonthPane> {
  final _db = FirebaseFirestore.instance;
  late DateTime _month;
  final Map<String, Map<String, dynamic>> _optimisticOverrides = {};
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  @override
  void didUpdateWidget(MonthPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employee.id != widget.employee.id) {
      _optimisticOverrides.clear();
    }
  }

  void _prevMonth() {
    setState(() {
      _optimisticOverrides.clear();
      _month = DateTime(_month.year, _month.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _optimisticOverrides.clear();
      _month = DateTime(_month.year, _month.month + 1, 1);
    });
  }

  CollectionReference<Map<String, dynamic>> get _overridesCol => _db.collection('day_overrides');
  CollectionReference<Map<String, dynamic>> get _eventsCol => _db.collection('events');

  Stream<Map<String, Map<String, dynamic>>> _watchOverridesForMonth(String employeeId, DateTime month) {
    final startKey = dayKeyLocal(startOfMonthLocal(month));
    final endKey = dayKeyLocal(endOfMonthLocal(month));

    return _overridesCol.where('employeeId', isEqualTo: employeeId).snapshots().map((snap) {
      final map = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final dkField = d['dayKey']?.toString();
        final dk = (dkField != null && dkField.isNotEmpty)
            ? dkField
            : (doc.id.contains('_') ? doc.id.split('_').last : doc.id);
        if (dk.compareTo(startKey) < 0 || dk.compareTo(endKey) >= 0) continue;
        map[dk] = d;
      }
      return map;
    });
  }

  Stream<List<TimeEvent>> _watchEventsForMonth(String employeeId, DateTime month) {
    final startUtcMs = startOfMonthLocal(month).toUtc().millisecondsSinceEpoch;
    final endUtcMs = endOfMonthLocal(month).toUtc().millisecondsSinceEpoch;

    return _eventsCol
        .where('employeeId', isEqualTo: employeeId)
        .where('timestampUtcMs', isGreaterThanOrEqualTo: startUtcMs)
        .where('timestampUtcMs', isLessThan: endUtcMs)
        .orderBy('timestampUtcMs', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(TimeEvent.fromDoc).toList());
  }

  Stream<Map<String, String>> _watchAbsencesForMonth(String employeeId, DateTime month) {
    final startKey = dayKeyLocal(startOfMonthLocal(month));
    final endKey = dayKeyLocal(endOfMonthLocal(month));

    return _db
        .collection('absences')
        .where('employeeId', isEqualTo: employeeId)
        .snapshots()
        .map((snap) {
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final a = Absence.fromDoc(doc);
        if (a.status != AbsenceStatus.approved && a.status != AbsenceStatus.pending) continue;
        final expanded = expandAbsenceToDayKeys(a);
        for (final entry in expanded.entries) {
          if (entry.key.compareTo(startKey) >= 0 && entry.key.compareTo(endKey) < 0) {
            map[entry.key] = entry.value;
          }
        }
      }
      return map;
    });
  }

  Future<void> _exportExcel(String employeeId, Employee emp) async {
    try {
      // Fetch current month's events
      final startUtcMs = startOfMonthLocal(_month).toUtc().millisecondsSinceEpoch;
      final endUtcMs = endOfMonthLocal(_month).toUtc().millisecondsSinceEpoch;

      final evSnap = await _eventsCol
          .where('employeeId', isEqualTo: employeeId)
          .where('timestampUtcMs', isGreaterThanOrEqualTo: startUtcMs)
          .where('timestampUtcMs', isLessThan: endUtcMs)
          .orderBy('timestampUtcMs', descending: false)
          .get();
      final monthEvents = evSnap.docs.map(TimeEvent.fromDoc).toList();

      // Fetch overrides
      final startKey = dayKeyLocal(startOfMonthLocal(_month));
      final endKey = dayKeyLocal(endOfMonthLocal(_month));
      final ovSnap = await _overridesCol
          .where('employeeId', isEqualTo: employeeId)
          .get();
      final overrides = <String, Map<String, dynamic>>{};
      for (final doc in ovSnap.docs) {
        final d = doc.data();
        final dkField = d['dayKey']?.toString();
        final dk = (dkField != null && dkField.isNotEmpty)
            ? dkField
            : (doc.id.contains('_') ? doc.id.split('_').last : doc.id);
        if (dk.compareTo(startKey) < 0 || dk.compareTo(endKey) >= 0) continue;
        overrides[dk] = d;
      }

      // Fetch approval
      final ym = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
      final approvalDoc = await _db.collection('month_approvals').doc('${employeeId}_$ym').get();
      String? approvedBy;
      DateTime? approvedAt;
      if (approvalDoc.exists) {
        final data = approvalDoc.data()!;
        approvedBy = data['approvedBy']?.toString();
        final ts = data['approvedAt'];
        if (ts is Timestamp) approvedAt = ts.toDate();
      }

      final bytes = buildMonthlyExcelExport(
        employee: emp,
        month: _month,
        monthEvents: monthEvents,
        overrides: overrides,
        approvedBy: approvedBy,
        approvedAt: approvedAt,
      );

      final filename = 'Stundennachweis_${employeeId}_$ym.xlsx';
      downloadBytes(
        bytes: bytes,
        filename: filename,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export gestartet: $filename')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export fehlgeschlagen: $e')),
      );
    }
  }

  String? _friendlyOverridesError(Object? error) {
    if (error == null) return null;
    final msg = error.toString().toLowerCase();
    if (msg.contains('failed-precondition') && msg.contains('requires an index')) return null;
    if (msg.contains('permission-denied')) {
      return 'Overrides derzeit nicht verfügbar (Berechtigung).';
    }
    return 'Overrides konnten nicht geladen werden.';
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.employee;
    final employeeId = emp.id;
    final todayKey = dayKeyLocal(DateTime.now());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.lg),
        child: Column(
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: SectionHeader(
                    title: '${emp.name} (${emp.id})',
                    subtitle: 'Monatsübersicht und Korrekturen',
                  ),
                ),
                IconButton(tooltip: 'Vorheriger Monat', onPressed: _prevMonth, icon: const Icon(Icons.chevron_left)),
                Text(monthLabel(_month), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                IconButton(tooltip: 'Nächster Monat', onPressed: _nextMonth, icon: const Icon(Icons.chevron_right)),
                const SizedBox(width: AppTokens.sm),
                IconButton.filledTonal(
                  tooltip: 'Excel Export',
                  onPressed: () => _exportExcel(employeeId, emp),
                  icon: const Icon(Icons.download),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.md),

            // Approval section
            ApprovalSection(employeeId: employeeId, month: _month),
            const SizedBox(height: AppTokens.md),

            // Events + Overrides StreamBuilders
            Expanded(
              child: StreamBuilder<List<TimeEvent>>(
                stream: _watchEventsForMonth(employeeId, _month),
                builder: (context, evSnap) {
                  if (evSnap.hasError) return Center(child: Text('Fehler Events: ${evSnap.error}'));
                  if (!evSnap.hasData) return const Center(child: CircularProgressIndicator());

                  final monthEvents = evSnap.data!;
                  final byDay = groupEventsByDayKey(monthEvents);

                  return StreamBuilder<Map<String, Map<String, dynamic>>>(
                    stream: _watchOverridesForMonth(employeeId, _month),
                    builder: (context, ovSnap) {
                      return StreamBuilder<Map<String, String>>(
                        stream: _watchAbsencesForMonth(employeeId, _month),
                        builder: (context, abSnap) {
                      final overridesFromDb = ovSnap.hasData ? ovSnap.data! : const <String, Map<String, dynamic>>{};
                      final overrides = <String, Map<String, dynamic>>{};
                      overrides.addAll(overridesFromDb);
                      overrides.addAll(_optimisticOverrides);

                      final absencesByDay = abSnap.hasData ? abSnap.data! : const <String, String>{};

                      // Get holidays for this month's year
                      final holidayNames = getPublicHolidayNamesBW(_month.year);

                      final start = startOfMonthLocal(_month);
                      final end = endOfMonthLocal(_month);
                      final days = <DateTime>[];
                      for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
                        days.add(d);
                      }

                      Duration totalNet = Duration.zero;
                      int absenceVacationDays = 0;
                      int absenceSickDays = 0;
                      int holidayDays = 0;

                      final rows = days.map((day) {
                        final dk = dayKeyLocal(day);
                        final ov = overrides[dk];
                        final autoDayEvents = byDay[dk] ?? const <TimeEvent>[];
                        final absType = absencesByDay[dk];
                        final holName = holidayNames[dk];

                        DaySummary summary;
                        if (ov != null) {
                          summary = summaryFromOverrideMerged(ov, autoDayEvents);
                        } else if (autoDayEvents.isNotEmpty) {
                          summary = summaryFromEventsForDay(autoDayEvents);
                        } else if (absType != null || holName != null) {
                          // Absence or holiday with no events: credit standard hours
                          final stdHours = emp.standardDailyHours;
                          final creditDur = Duration(minutes: (stdHours * 60).round());
                          summary = DaySummary(
                            inTime: null,
                            outTime: null,
                            breakStart: null,
                            breakEnd: null,
                            net: day.weekday < 6 ? creditDur : Duration.zero,
                            sourceLabel: absType != null ? 'ABWESEND' : 'FEIERTAG',
                          );
                        } else {
                          summary = summaryFromEventsForDay(autoDayEvents);
                        }

                        totalNet += summary.net;

                        if (absType == 'URLAUB' && day.weekday < 6) absenceVacationDays++;
                        if (absType == 'KRANKHEIT' && day.weekday < 6) absenceSickDays++;
                        if (holName != null && day.weekday < 6) holidayDays++;

                        return DayRow(
                          dayLocal: day,
                          dayKey: dk,
                          summary: summary,
                          override: ov,
                          autoDayEvents: autoDayEvents,
                          absenceType: absType,
                          holidayName: holName,
                        );
                      }).toList();

                      // Count inactive days and build list items
                      final inactiveCount = rows.where((r) {
                        final isWe = r.dayLocal.weekday >= 6;
                        final isHol = r.holidayName != null;
                        final hasAct = r.summary.inTime != null ||
                            r.summary.outTime != null ||
                            r.summary.breakStart != null ||
                            r.summary.breakEnd != null;
                        final hasOv = r.override != null;
                        final hasAbs = r.absenceType != null;
                        return (isWe || isHol) && !hasAct && !hasOv && !hasAbs;
                      }).length;

                      final listItems = _buildListWithWeekSubtotals(rows, _showInactive);

                      final overrideError = _friendlyOverridesError(ovSnap.error);

                      return Column(
                        children: [
                          if (overrideError != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppTokens.md),
                              decoration: BoxDecoration(
                                borderRadius: AppTokens.borderRadiusMd,
                                color: AppTokens.errorBg,
                                border: Border.all(color: AppTokens.errorBorder),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: AppTokens.errorFg),
                                  const SizedBox(width: AppTokens.sm),
                                  Expanded(child: Text('Hinweis: $overrideError', style: const TextStyle(fontWeight: FontWeight.w800))),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppTokens.md),
                          ],
                          MonthTotalsCard(
                            totalNet: totalNet,
                            overrideCount: overrides.length,
                            eventCount: monthEvents.length,
                            vacationDays: absenceVacationDays,
                            sickDays: absenceSickDays,
                            holidayDays: holidayDays,
                          ),
                          const SizedBox(height: AppTokens.md),

                          // Toggle for inactive weekends/holidays
                          if (inactiveCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppTokens.sm),
                              child: Row(
                                children: [
                                  Text(
                                    '$inactiveCount Tage ausgeblendet',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTokens.onSurfaceMuted,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => setState(() => _showInactive = !_showInactive),
                                    icon: Icon(
                                      _showInactive ? Icons.unfold_less : Icons.unfold_more,
                                      size: 18,
                                    ),
                                    label: Text(_showInactive ? 'Kompakt' : 'Alle anzeigen'),
                                    style: TextButton.styleFrom(
                                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Table header
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.md,
                              vertical: AppTokens.sm,
                            ),
                            decoration: BoxDecoration(
                              color: AppTokens.surfaceMuted,
                              border: Border(
                                bottom: BorderSide(color: AppTokens.outline, width: 1),
                              ),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTokens.radiusSm)),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 28), // warning col
                                SizedBox(width: 100, child: Text('Datum', style: _headerStyle)),
                                SizedBox(width: 80, child: Text('Status', style: _headerStyle)),
                                SizedBox(width: 60, child: Text('Kommen', style: _headerStyle)),
                                SizedBox(width: 60, child: Text('Gehen', style: _headerStyle)),
                                SizedBox(width: 60, child: Text('Pause', style: _headerStyle)),
                                SizedBox(
                                  width: 70,
                                  child: Text('Netto', style: _headerStyle, textAlign: TextAlign.right),
                                ),
                                const SizedBox(width: AppTokens.sm),
                                const SizedBox(width: 44 + 36), // ADM + edit
                              ],
                            ),
                          ),

                          Expanded(
                            child: ListView.builder(
                              itemCount: listItems.length,
                              itemBuilder: (_, i) {
                                final item = listItems[i];
                                if (item is _WeekSubtotalItem) {
                                  return WeekSubtotalRow(weekNumber: item.weekNumber, totalNet: item.totalNet);
                                }
                                final dayItem = item as _DayItem;
                                return DayTile(
                                  employeeId: employeeId,
                                  row: dayItem.row,
                                  todayKey: todayKey,
                                  isEven: dayItem.visibleIndex.isEven,
                                  onEdit: () => EditDayDialog.show(
                                    context,
                                    employeeId: employeeId,
                                    dayLocal: dayItem.row.dayLocal,
                                    existingOverride: dayItem.row.override,
                                    autoDayEvents: dayItem.row.autoDayEvents,
                                    onSaved: () {
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
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

  static final TextStyle _headerStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppTokens.onSurfaceMuted,
  );

  bool _isDayInactive(DayRow row) {
    final isWe = row.dayLocal.weekday >= 6;
    final isHol = row.holidayName != null;
    final hasAct = row.summary.inTime != null ||
        row.summary.outTime != null ||
        row.summary.breakStart != null ||
        row.summary.breakEnd != null;
    final hasOv = row.override != null;
    final hasAbs = row.absenceType != null;
    return (isWe || isHol) && !hasAct && !hasOv && !hasAbs;
  }

  List<Object> _buildListWithWeekSubtotals(List<DayRow> rows, bool showInactive) {
    if (rows.isEmpty) return [];

    final items = <Object>[];
    int? currentWeek;
    Duration weekNet = Duration.zero;
    int visibleDayIndex = 0;

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final wk = isoWeekNumber(row.dayLocal);

      if (currentWeek != null && wk != currentWeek) {
        items.add(_WeekSubtotalItem(weekNumber: currentWeek, totalNet: weekNet));
        weekNet = Duration.zero;
      }

      currentWeek = wk;
      // Always count net for week subtotals (even if row is hidden)
      weekNet += row.summary.net;

      // Only add visible rows
      final inactive = _isDayInactive(row);
      if (!inactive || showInactive) {
        items.add(_DayItem(row: row, visibleIndex: visibleDayIndex));
        visibleDayIndex++;
      }
    }

    // Final week subtotal
    if (currentWeek != null) {
      items.add(_WeekSubtotalItem(weekNumber: currentWeek, totalNet: weekNet));
    }

    return items;
  }
}

class _WeekSubtotalItem {
  final int weekNumber;
  final Duration totalNet;
  _WeekSubtotalItem({required this.weekNumber, required this.totalNet});
}

class _DayItem {
  final DayRow row;
  final int visibleIndex;
  _DayItem({required this.row, required this.visibleIndex});
}
