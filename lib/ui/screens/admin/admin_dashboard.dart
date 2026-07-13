import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/absence_helpers.dart';
import '../../../core/holidays_bw.dart';
import '../../../data/absence.dart';
import '../../../data/store.dart';
import '../../../ui/design_tokens.dart';
import '../../../ui/widgets/empty_state.dart';
import '../../../ui/widgets/metric_chip.dart';
import '../../../ui/widgets/section_header.dart';
import '../../../ui/widgets/stat_card.dart';
import '../../../ui/widgets/status_pill.dart';
import 'admin_helpers.dart';

class AdminDashboard extends StatefulWidget {
  final List<Employee> employees;
  final Map<String, String> presenceMap; // employeeId → lastEventType
  final ValueChanged<String> onSelectEmployee;

  const AdminDashboard({
    super.key,
    required this.employees,
    required this.presenceMap,
    required this.onSelectEmployee,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _db = FirebaseFirestore.instance;

  // Subscriptions
  StreamSubscription? _eventsSub;
  StreamSubscription? _pendingSub;
  StreamSubscription? _approvalsSub;
  StreamSubscription? _overridesSub;
  StreamSubscription? _absencesSub;
  StreamSubscription? _balancesSub;
  StreamSubscription? _pendingCountsSub;

  // State
  late DateTime _month;
  int _presentToday = 0;
  List<Absence> _pendingAbsences = [];
  int _unapprovedMonths = 0;
  bool _loaded = false;

  // Per-employee detailed data
  List<_EmployeeRow> _employeeRows = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _startListening();
  }

  @override
  void didUpdateWidget(AdminDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employees.length != widget.employees.length) {
      _recomputeRows();
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _pendingSub?.cancel();
    _approvalsSub?.cancel();
    _overridesSub?.cancel();
    _absencesSub?.cancel();
    _balancesSub?.cancel();
    _pendingCountsSub?.cancel();
    super.dispose();
  }

  void _prevMonth() {
    _cancelAllSubs();
    setState(() {
      _loaded = false;
      _month = DateTime(_month.year, _month.month - 1, 1);
    });
    _startListening();
  }

  void _nextMonth() {
    _cancelAllSubs();
    setState(() {
      _loaded = false;
      _month = DateTime(_month.year, _month.month + 1, 1);
    });
    _startListening();
  }

  void _cancelAllSubs() {
    _eventsSub?.cancel();
    _pendingSub?.cancel();
    _approvalsSub?.cancel();
    _overridesSub?.cancel();
    _absencesSub?.cancel();
    _balancesSub?.cancel();
    _pendingCountsSub?.cancel();
  }

  // ── Raw data caches (filled by subscriptions, combined in _recomputeRows) ──

  List<TimeEvent> _rawEvents = [];
  Map<String, Map<String, Map<String, dynamic>>> _rawOverrides = {};
  Map<String, bool> _rawApprovals = {};
  Map<String, Map<String, String>> _rawAbsences = {};
  Map<String, Map<String, double>> _rawBalances = {};
  Map<String, int> _rawPendingCounts = {};
  String _todayKey = '';

  void _startListening() {
    _todayKey = dayKeyLocal(DateTime.now());
    final startUtcMs = startOfMonthLocal(_month).toUtc().millisecondsSinceEpoch;
    final endUtcMs = endOfMonthLocal(_month).toUtc().millisecondsSinceEpoch;
    final startKey = dayKeyLocal(startOfMonthLocal(_month));
    final endKey = dayKeyLocal(endOfMonthLocal(_month));
    final ym = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

    // 1. Events
    _eventsSub = _db
        .collection('events')
        .where('timestampUtcMs', isGreaterThanOrEqualTo: startUtcMs)
        .where('timestampUtcMs', isLessThan: endUtcMs)
        .orderBy('timestampUtcMs', descending: false)
        .snapshots()
        .listen((snap) {
      _rawEvents = snap.docs.map(TimeEvent.fromDoc).toList();
      _recomputeRows();
    });

    // 2. Pending absences (for the top section)
    _pendingSub = _db
        .collection('absences')
        .where('status', isEqualTo: AbsenceStatus.pending)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _pendingAbsences = snap.docs.map(Absence.fromDoc).toList()
          ..sort((a, b) => a.createdAt?.compareTo(b.createdAt ?? DateTime(2000)) ?? 0);
      });
    });

    // 3. Approvals
    _approvalsSub = _db
        .collection('month_approvals')
        .where('yearMonth', isEqualTo: ym)
        .snapshots()
        .listen((snap) {
      _rawApprovals = {};
      for (final doc in snap.docs) {
        final eid = doc.data()['employeeId']?.toString() ?? '';
        if (eid.isNotEmpty) _rawApprovals[eid] = true;
      }
      _recomputeRows();
    });

    // 4. Overrides
    _overridesSub = _db.collection('day_overrides').snapshots().listen((snap) {
      _rawOverrides = {};
      for (final doc in snap.docs) {
        final d = doc.data();
        final eid = d['employeeId']?.toString() ?? '';
        if (eid.isEmpty) continue;
        final dkField = d['dayKey']?.toString();
        final dk = (dkField != null && dkField.isNotEmpty)
            ? dkField
            : (doc.id.contains('_') ? doc.id.split('_').last : doc.id);
        if (dk.compareTo(startKey) < 0 || dk.compareTo(endKey) >= 0) continue;
        (_rawOverrides[eid] ??= {})[dk] = d;
      }
      _recomputeRows();
    });

    // 5. Absences (for per-employee U/K columns)
    _absencesSub = _db.collection('absences').snapshots().listen((snap) {
      _rawAbsences = {};
      for (final doc in snap.docs) {
        final a = Absence.fromDoc(doc);
        if (a.status != AbsenceStatus.approved && a.status != AbsenceStatus.pending) continue;
        final expanded = expandAbsenceToDayKeys(a);
        for (final entry in expanded.entries) {
          if (entry.key.compareTo(startKey) >= 0 && entry.key.compareTo(endKey) < 0) {
            (_rawAbsences[a.employeeId] ??= {})[entry.key] = entry.value;
          }
        }
      }
      _recomputeRows();
    });

    // 6. Vacation balances
    _balancesSub = _db
        .collection('vacation_balances')
        .where('year', isEqualTo: _month.year)
        .snapshots()
        .listen((snap) {
      _rawBalances = {};
      for (final doc in snap.docs) {
        final d = doc.data();
        final eid = d['employeeId']?.toString() ?? '';
        if (eid.isEmpty) continue;
        _rawBalances[eid] = {
          'remaining': (d['remaining'] ?? 0).toDouble(),
          'used': (d['used'] ?? 0).toDouble(),
          'planned': (d['planned'] ?? 0).toDouble(),
          'entitlement': (d['entitlement'] ?? 25).toDouble(),
          'sickDays': (d['sickDays'] ?? 0).toDouble(),
        };
      }
      _recomputeRows();
    });

    // 7. Pending counts per employee
    _pendingCountsSub = _db
        .collection('absences')
        .where('status', isEqualTo: AbsenceStatus.pending)
        .snapshots()
        .listen((snap) {
      _rawPendingCounts = {};
      for (final doc in snap.docs) {
        final eid = doc.data()['employeeId']?.toString() ?? '';
        if (eid.isEmpty) continue;
        _rawPendingCounts[eid] = (_rawPendingCounts[eid] ?? 0) + 1;
      }
      _recomputeRows();
    });
  }

  void _recomputeRows() {
    if (!mounted) return;

    final holidayNames = getPublicHolidayNamesBW(_month.year);

    // Group events by employee
    final byEmployee = <String, List<TimeEvent>>{};
    for (final ev in _rawEvents) {
      (byEmployee[ev.employeeId] ??= []).add(ev);
    }

    // Present today
    int presentCount = 0;
    for (final emp in widget.employees) {
      if (!emp.active) continue;
      final empEvents = byEmployee[emp.id] ?? [];
      final todayEvents = empEvents.where((e) {
        return TimeEvent.dayKeyFromUtcMs(e.timestampUtcMs) == _todayKey;
      }).toList();
      if (todayEvents.isEmpty) continue;
      final lastEvent = todayEvents.last;
      if (lastEvent.eventType == 'IN' ||
          lastEvent.eventType == 'BREAK_START' ||
          lastEvent.eventType == 'BREAK_END') {
        presentCount++;
      }
    }

    // Build per-employee rows
    final rows = <_EmployeeRow>[];
    for (final emp in widget.employees) {
      final empEvents = byEmployee[emp.id] ?? [];
      final byDay = groupEventsByDayKey(empEvents);
      final empOverrides = _rawOverrides[emp.id] ?? const {};
      final empAbsences = _rawAbsences[emp.id] ?? const {};
      final empBalance = _rawBalances[emp.id];

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
        isApproved: _rawApprovals[emp.id] == true,
        monthVacationDays: monthVacationDays,
        monthSickDays: monthSickDays,
        monthHolidayDays: monthHolidayDays,
        vacationRemaining: empBalance?['remaining'],
        pendingRequests: _rawPendingCounts[emp.id] ?? 0,
      ));
    }

    // Unapproved count
    final activeIds = widget.employees.where((e) => e.active).map((e) => e.id).toSet();
    final approvedActiveCount = _rawApprovals.keys.where((id) => activeIds.contains(id)).length;
    final unapproved = activeIds.length - approvedActiveCount;

    setState(() {
      _presentToday = presentCount;
      _employeeRows = rows;
      _unapprovedMonths = unapproved;
      _loaded = true;
    });
  }

  String _employeeName(String empId) {
    return widget.employees
        .where((e) => e.id == empId)
        .map((e) => e.name)
        .firstOrNull ?? empId;
  }

  Future<void> _approveAbsence(Absence a) async {
    try {
      await _db.collection('absences').doc(a.id).update({
        'status': AbsenceStatus.approved,
        'approvedBy': 'Admin',
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final startYear = DateTime.tryParse(a.startDate)?.year ?? DateTime.now().year;
      final endYear = DateTime.tryParse(a.endDate)?.year ?? startYear;
      for (var y = startYear; y <= endYear; y++) {
        await recalculateVacationBalance(a.employeeId, y);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  Future<void> _rejectAbsence(Absence a) async {
    try {
      await _db.collection('absences').doc(a.id).update({
        'status': AbsenceStatus.rejected,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final startYear = DateTime.tryParse(a.startDate)?.year ?? DateTime.now().year;
      final endYear = DateTime.tryParse(a.endDate)?.year ?? startYear;
      for (var y = startYear; y <= endYear; y++) {
        await recalculateVacationBalance(a.employeeId, y);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMonthHours = _employeeRows.fold<Duration>(
      Duration.zero,
      (acc, r) => acc + r.totalNet,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.lg),
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Header with month navigation ──
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Dashboard',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Vorheriger Monat',
                        onPressed: _prevMonth,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        monthLabel(_month),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      IconButton(
                        tooltip: 'Nächster Monat',
                        onPressed: _nextMonth,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.md),

                  // ── KPI Cards ──
                  Expanded(
                    child: ListView(
                      children: [
                        LayoutBuilder(
                          builder: (context, c) {
                            final cardWidth = ((c.maxWidth - AppTokens.md * 3) / 4).clamp(140.0, 220.0);
                            return Wrap(
                              spacing: AppTokens.md,
                              runSpacing: AppTokens.md,
                              children: [
                                SizedBox(
                                  width: cardWidth,
                                  child: StatCard(
                                    icon: Icons.people,
                                    label: 'Anwesend heute',
                                    value: '$_presentToday',
                                    accentColor: AppTokens.successFg,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: StatCard(
                                    icon: Icons.schedule,
                                    label: 'Offene Antraege',
                                    value: '${_pendingAbsences.length}',
                                    accentColor: _pendingAbsences.isNotEmpty
                                        ? AppTokens.warningFg
                                        : AppTokens.successFg,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: StatCard(
                                    icon: Icons.access_time,
                                    label: 'Monatsstunden',
                                    value: durHHMM(totalMonthHours),
                                    accentColor: AppTokens.primary,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: StatCard(
                                    icon: Icons.verified,
                                    label: 'Nicht geprueft',
                                    value: '$_unapprovedMonths',
                                    accentColor: _unapprovedMonths > 0
                                        ? AppTokens.warningFg
                                        : AppTokens.successFg,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: AppTokens.xl),

                        // ── Pending Requests ──
                        if (_pendingAbsences.isNotEmpty) ...[
                          SectionHeader(
                            title: 'Offene Antraege',
                            trailing: StatusPill.warning(
                              '${_pendingAbsences.length}',
                              icon: Icons.schedule,
                            ),
                          ),
                          const SizedBox(height: AppTokens.sm),
                          ..._pendingAbsences.map(_pendingRow),
                          const SizedBox(height: AppTokens.xl),
                        ],

                        // ── Employee Table ──
                        const SectionHeader(
                          title: 'Mitarbeiter',
                          padding: EdgeInsets.only(bottom: AppTokens.md),
                        ),
                        _buildEmployeeTable(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _pendingRow(Absence a) {
    final empName = _employeeName(a.employeeId);
    final typeLabel = AbsenceType.label(a.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.sm),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.md),
        decoration: BoxDecoration(
          borderRadius: AppTokens.borderRadiusMd,
          color: AppTokens.warningBg,
          border: Border.all(color: AppTokens.warningBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        empName,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      const SizedBox(width: AppTokens.sm),
                      Text(
                        '(${a.employeeId})',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppTokens.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(width: AppTokens.sm),
                      StatusPill(
                        text: typeLabel,
                        fg: a.type == AbsenceType.urlaub ? AppTokens.vacationFg : AppTokens.sickFg,
                        bg: a.type == AbsenceType.urlaub ? AppTokens.vacationBg : AppTokens.sickBg,
                        border: a.type == AbsenceType.urlaub ? AppTokens.vacationBorder : AppTokens.sickBorder,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.xs),
                  Row(
                    children: [
                      MetricChip(
                        label: 'Zeitraum',
                        value: '${_fmtDate(a.startDate)} – ${_fmtDate(a.endDate)}',
                      ),
                      const SizedBox(width: AppTokens.lg),
                      MetricChip(
                        label: 'Tage',
                        value: a.vacationDaysConsumed.toStringAsFixed(0),
                        valueColor: AppTokens.warningFg,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.sm),
            IconButton.filled(
              tooltip: 'Genehmigen',
              onPressed: () => _approveAbsence(a),
              style: IconButton.styleFrom(
                backgroundColor: AppTokens.successBg,
                foregroundColor: AppTokens.successFg,
              ),
              icon: const Icon(Icons.check, size: 20),
            ),
            const SizedBox(width: AppTokens.xs),
            IconButton.filled(
              tooltip: 'Ablehnen',
              onPressed: () => _rejectAbsence(a),
              style: IconButton.styleFrom(
                backgroundColor: AppTokens.errorBg,
                foregroundColor: AppTokens.errorFg,
              ),
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  // ── Full employee table with all columns ──

  Widget _buildEmployeeTable() {
    if (_employeeRows.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'Keine Mitarbeiter',
      );
    }

    return Column(
      children: [
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.md, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: AppTokens.borderRadiusSm,
            color: AppTokens.primarySubtle,
          ),
          child: Row(
            children: [
              const SizedBox(width: 46), // avatar space
              const SizedBox(width: AppTokens.sm),
              const Expanded(
                flex: 3,
                child: Text('Name', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              ),
              const SizedBox(
                width: 80,
                child: Text('Netto h', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13), textAlign: TextAlign.right),
              ),
              const SizedBox(
                width: 45,
                child: Text('Tage', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13), textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 35,
                child: Text('U', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTokens.vacationFg), textAlign: TextAlign.center),
              ),
              SizedBox(
                width: 35,
                child: Text('K', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTokens.sickFg), textAlign: TextAlign.center),
              ),
              SizedBox(
                width: 35,
                child: Text('F', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTokens.infoFg), textAlign: TextAlign.center),
              ),
              const SizedBox(
                width: 70,
                child: Text('Rest', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13), textAlign: TextAlign.right),
              ),
              const SizedBox(
                width: 50,
                child: Text('Flag', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13), textAlign: TextAlign.right),
              ),
              const SizedBox(
                width: 45,
                child: Center(child: Icon(Icons.verified_outlined, size: 16)),
              ),
              const SizedBox(width: 24), // chevron space
            ],
          ),
        ),
        const SizedBox(height: AppTokens.xs),

        // Data rows
        ..._employeeRows.map(_employeeTableRow),
      ],
    );
  }

  Color _presenceDotColor(Employee emp) {
    if (!emp.active) return AppTokens.neutralBorder;
    final lastEvent = widget.presenceMap[emp.id];
    if (lastEvent == null) return AppTokens.errorFg;
    switch (lastEvent) {
      case 'IN':
      case 'BREAK_END':
        return AppTokens.successFg;
      case 'BREAK_START':
        return AppTokens.warningFg;
      case 'OUT':
      default:
        return AppTokens.errorFg;
    }
  }

  Widget _employeeTableRow(_EmployeeRow r) {
    final emp = r.employee;
    final avatarColor = AppTokens.avatarColorFor(emp.id);
    final initials = AppTokens.initialsFor(emp.name);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.xs),
      child: InkWell(
        onTap: () => widget.onSelectEmployee(emp.id),
        borderRadius: AppTokens.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.md, vertical: AppTokens.sm),
          decoration: BoxDecoration(
            borderRadius: AppTokens.borderRadiusMd,
            border: Border.all(color: AppTokens.outlineLight),
          ),
          child: Row(
            children: [
              // Avatar with presence dot
              Stack(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: avatarColor.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: avatarColor,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _presenceDotColor(emp),
                        border: Border.all(color: AppTokens.surfaceCard, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppTokens.sm),

              // Name + ID + badges
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            emp.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        if (!emp.active) ...[
                          const SizedBox(width: AppTokens.xs),
                          StatusPill.error('INAKTIV'),
                        ],
                        if (r.pendingRequests > 0) ...[
                          const SizedBox(width: AppTokens.xs),
                          StatusPill.pending(
                            '${r.pendingRequests} offen',
                            icon: Icons.schedule,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      emp.id,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppTokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // Net hours
              SizedBox(
                width: 80,
                child: Text(
                  '${durHHMM(r.totalNet)} h',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.right,
                ),
              ),

              // Work days
              SizedBox(
                width: 45,
                child: Text(
                  '${r.workDays}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.right,
                ),
              ),

              // Urlaub (month)
              SizedBox(
                width: 35,
                child: Text(
                  r.monthVacationDays > 0 ? '${r.monthVacationDays}' : '—',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: r.monthVacationDays > 0 ? AppTokens.vacationFg : AppTokens.onSurfaceFaint,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Krankheit (month)
              SizedBox(
                width: 35,
                child: Text(
                  r.monthSickDays > 0 ? '${r.monthSickDays}' : '—',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: r.monthSickDays > 0 ? AppTokens.sickFg : AppTokens.onSurfaceFaint,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Feiertage (month)
              SizedBox(
                width: 35,
                child: Text(
                  r.monthHolidayDays > 0 ? '${r.monthHolidayDays}' : '—',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: r.monthHolidayDays > 0 ? AppTokens.infoFg : AppTokens.onSurfaceFaint,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Vacation remaining (year)
              SizedBox(
                width: 70,
                child: r.vacationRemaining != null
                    ? Text(
                        '${r.vacationRemaining!.toStringAsFixed(0)} T',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: r.vacationRemaining! <= 3 ? AppTokens.errorFg : AppTokens.successFg,
                        ),
                        textAlign: TextAlign.right,
                      )
                    : Text(
                        '—',
                        style: TextStyle(color: AppTokens.onSurfaceFaint),
                        textAlign: TextAlign.right,
                      ),
              ),

              // Flagged days
              SizedBox(
                width: 50,
                child: Text(
                  r.flaggedDays > 0 ? '${r.flaggedDays}' : '—',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: r.flaggedDays > 0 ? AppTokens.errorFg : AppTokens.onSurfaceFaint,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),

              // Approved check
              SizedBox(
                width: 45,
                child: Center(
                  child: r.isApproved
                      ? const Icon(Icons.check_circle, color: AppTokens.successFg, size: 22)
                      : Text('—', style: TextStyle(color: AppTokens.onSurfaceFaint)),
                ),
              ),

              // Chevron
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: AppTokens.onSurfaceFaint),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) return dayKey;
    return '${parts[2]}.${parts[1]}.${parts[0]}';
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
    this.pendingRequests = 0,
  });
}
