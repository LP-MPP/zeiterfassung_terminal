import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/absence_helpers.dart';
import '../../../core/holidays_bw.dart';
import '../../../data/absence.dart';
import '../../../data/store.dart';
import '../../../ui/design_tokens.dart';
import '../../../ui/widgets/empty_state.dart';
import '../../../ui/widgets/metric_chip.dart';
import '../../../ui/widgets/section_header.dart';
import '../../../ui/widgets/status_pill.dart';
import 'add_absence_dialog.dart';
import 'vacation_balance_card.dart';

class AbsencePane extends StatefulWidget {
  final Employee employee;

  const AbsencePane({super.key, required this.employee});

  @override
  State<AbsencePane> createState() => _AbsencePaneState();
}

class _AbsencePaneState extends State<AbsencePane> {
  final _db = FirebaseFirestore.instance;
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    _ensureHolidaysSeeded();
  }

  Future<void> _ensureHolidaysSeeded() async {
    for (final y in [_year, _year + 1]) {
      final check = await _db.collection('public_holidays').doc('$y-01-01').get();
      if (!check.exists) {
        await seedPublicHolidaysBW(y);
      }
    }
  }

  void _prevYear() => setState(() => _year--);
  void _nextYear() => setState(() => _year++);

  Stream<List<Absence>> _watchAbsences() {
    return _db
        .collection('absences')
        .where('employeeId', isEqualTo: widget.employee.id)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Absence.fromDoc).toList();
      final yearStart = '$_year-01-01';
      final yearEnd = '$_year-12-31';
      final filtered = list.where((a) {
        return a.endDate.compareTo(yearStart) >= 0 && a.startDate.compareTo(yearEnd) <= 0;
      }).toList();
      // Group: PENDING first, then APPROVED, then rest — each sorted by startDate
      filtered.sort((a, b) {
        final aPriority = _statusPriority(a.status);
        final bPriority = _statusPriority(b.status);
        if (aPriority != bPriority) return aPriority.compareTo(bPriority);
        return a.startDate.compareTo(b.startDate);
      });
      return filtered;
    });
  }

  int _statusPriority(String status) {
    switch (status) {
      case AbsenceStatus.pending:
        return 0;
      case AbsenceStatus.approved:
        return 1;
      case AbsenceStatus.rejected:
        return 2;
      case AbsenceStatus.cancelled:
        return 3;
      default:
        return 4;
    }
  }

  Future<void> _approve(Absence a) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    await _db.collection('absences').doc(a.id).update({
      'status': AbsenceStatus.approved,
      'adminUid': adminUid,
      'approvedBy': 'Admin',
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final startYear = DateTime.tryParse(a.startDate)?.year ?? _year;
    final endYear = DateTime.tryParse(a.endDate)?.year ?? _year;
    for (var y = startYear; y <= endYear; y++) {
      await recalculateVacationBalance(widget.employee.id, y);
    }

    try {
      await _db.collection('audit').add({
        'action': 'ABSENCE_APPROVED',
        'employeeId': widget.employee.id,
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
        'payload': {'absenceId': a.id, 'type': a.type, 'startDate': a.startDate, 'endDate': a.endDate},
      });
    } catch (_) {}
  }

  Future<void> _reject(Absence a) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    await _db.collection('absences').doc(a.id).update({
      'status': AbsenceStatus.rejected,
      'adminUid': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final startYear = DateTime.tryParse(a.startDate)?.year ?? _year;
    final endYear = DateTime.tryParse(a.endDate)?.year ?? _year;
    for (var y = startYear; y <= endYear; y++) {
      await recalculateVacationBalance(widget.employee.id, y);
    }

    try {
      await _db.collection('audit').add({
        'action': 'ABSENCE_REJECTED',
        'employeeId': widget.employee.id,
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
        'payload': {'absenceId': a.id, 'type': a.type},
      });
    } catch (_) {}
  }

  Future<void> _cancel(Absence a) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    await _db.collection('absences').doc(a.id).update({
      'status': AbsenceStatus.cancelled,
      'adminUid': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final startYear = DateTime.tryParse(a.startDate)?.year ?? _year;
    final endYear = DateTime.tryParse(a.endDate)?.year ?? _year;
    for (var y = startYear; y <= endYear; y++) {
      await recalculateVacationBalance(widget.employee.id, y);
    }

    try {
      await _db.collection('audit').add({
        'action': 'ABSENCE_CANCELLED',
        'employeeId': widget.employee.id,
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
        'payload': {'absenceId': a.id, 'type': a.type},
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.employee;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.lg),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: SectionHeader(
                    title: '${emp.name} (${emp.id})',
                    subtitle: 'Abwesenheiten und Urlaubskonto',
                    padding: EdgeInsets.zero,
                  ),
                ),
                IconButton(tooltip: 'Vorheriges Jahr', onPressed: _prevYear, icon: const Icon(Icons.chevron_left)),
                Text('$_year', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                IconButton(tooltip: 'Naechstes Jahr', onPressed: _nextYear, icon: const Icon(Icons.chevron_right)),
              ],
            ),
            const SizedBox(height: AppTokens.md),

            // Balance card
            VacationBalanceCard(employeeId: emp.id, year: _year),
            const SizedBox(height: AppTokens.md),

            // Add button
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => AddAbsenceDialog.show(context, employeeId: emp.id),
                icon: const Icon(Icons.add),
                label: const Text('Neue Abwesenheit'),
              ),
            ),
            const SizedBox(height: AppTokens.md),

            // Absence list
            Expanded(
              child: StreamBuilder<List<Absence>>(
                stream: _watchAbsences(),
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Text('Fehler: ${snap.error}'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                  final absences = snap.data!;
                  if (absences.isEmpty) {
                    return EmptyState(
                      icon: Icons.event_available,
                      title: 'Keine Abwesenheiten in $_year',
                      subtitle: 'Neue Abwesenheit oben anlegen',
                    );
                  }

                  return ListView.separated(
                    itemCount: absences.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppTokens.sm),
                    itemBuilder: (_, i) => _absenceRow(context, absences[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _absenceRow(BuildContext context, Absence a) {
    final startDt = DateTime.tryParse(a.startDate);
    final endDt = DateTime.tryParse(a.endDate);
    final dateLabel = (startDt != null && endDt != null)
        ? '${DateFormat('dd.MM.yyyy').format(startDt)} – ${DateFormat('dd.MM.yyyy').format(endDt)}'
        : '${a.startDate} – ${a.endDate}';

    final isCancelledOrRejected =
        a.status == AbsenceStatus.rejected || a.status == AbsenceStatus.cancelled;

    return Container(
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(
          color: a.status == AbsenceStatus.pending
              ? AppTokens.pendingBorder
              : AppTokens.outlineLight,
        ),
        color: isCancelledOrRejected ? AppTokens.neutralBg : AppTokens.surfaceCard,
      ),
      child: Row(
        children: [
          // Type + Status pills
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _typePill(a.type),
              const SizedBox(height: AppTokens.xs),
              _statusPill(a.status),
            ],
          ),
          const SizedBox(width: AppTokens.lg),
          // Date + details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    MetricChip(
                      label: 'Tage',
                      value: _fmtDays(a.vacationDaysConsumed),
                    ),
                    if (a.reason != null && a.reason!.isNotEmpty) ...[
                      const SizedBox(width: AppTokens.md),
                      Flexible(
                        child: Text(
                          a.reason!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTokens.onSurfaceMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    if (a.createdByEmployee) ...[
                      const SizedBox(width: AppTokens.sm),
                      StatusPill.neutral('MA-Antrag'),
                    ],
                  ],
                ),
                if (a.approvedBy != null && a.status == AbsenceStatus.approved) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Genehmigt von ${a.approvedBy}${a.approvedAt != null ? ' am ${DateFormat('dd.MM.yyyy').format(a.approvedAt!)}' : ''}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTokens.successFg),
                  ),
                ],
              ],
            ),
          ),
          // Actions
          if (a.status == AbsenceStatus.pending) ...[
            IconButton.filled(
              tooltip: 'Genehmigen',
              onPressed: () => _approve(a),
              style: IconButton.styleFrom(
                backgroundColor: AppTokens.successBg,
                foregroundColor: AppTokens.successFg,
              ),
              icon: const Icon(Icons.check, size: 20),
            ),
            const SizedBox(width: AppTokens.xs),
            IconButton.filled(
              tooltip: 'Ablehnen',
              onPressed: () => _reject(a),
              style: IconButton.styleFrom(
                backgroundColor: AppTokens.errorBg,
                foregroundColor: AppTokens.errorFg,
              ),
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
          if (a.status == AbsenceStatus.approved || a.status == AbsenceStatus.pending) ...[
            const SizedBox(width: AppTokens.xs),
            IconButton(
              tooltip: 'Stornieren',
              onPressed: () => _cancel(a),
              icon: Icon(Icons.delete_outline, color: AppTokens.onSurfaceFaint),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typePill(String type) {
    final isUrlaub = type == AbsenceType.urlaub;
    if (isUrlaub) {
      return StatusPill(
        text: AbsenceType.label(type),
        fg: AppTokens.vacationFg,
        bg: AppTokens.vacationBg,
        border: AppTokens.vacationBorder,
      );
    }
    return StatusPill(
      text: AbsenceType.label(type),
      fg: AppTokens.sickFg,
      bg: AppTokens.sickBg,
      border: AppTokens.sickBorder,
    );
  }

  Widget _statusPill(String status) {
    switch (status) {
      case AbsenceStatus.approved:
        return StatusPill.success(AbsenceStatus.label(status), icon: Icons.check);
      case AbsenceStatus.pending:
        return StatusPill.pending(AbsenceStatus.label(status), icon: Icons.schedule);
      case AbsenceStatus.rejected:
        return StatusPill.error(AbsenceStatus.label(status), icon: Icons.close);
      default:
        return StatusPill.neutral(AbsenceStatus.label(status));
    }
  }

  String _fmtDays(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
