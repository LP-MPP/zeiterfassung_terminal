import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/absence_helpers.dart';
import '../../../core/holidays_bw.dart';
import '../../../data/absence.dart';
import '../../../ui/screens/admin/admin_helpers.dart';

class AddAbsenceDialog {
  static Future<void> show(
    BuildContext context, {
    required String employeeId,
    Absence? existing,
  }) async {
    final db = FirebaseFirestore.instance;
    final isEdit = existing != null;

    String type = existing?.type ?? AbsenceType.urlaub;
    String dayPart = existing?.startDayPart ?? AbsenceDayPart.full;
    DateTimeRange? dateRange = (existing != null)
        ? DateTimeRange(
            start: DateTime.tryParse(existing.startDate) ?? DateTime.now(),
            end: DateTime.tryParse(existing.endDate) ?? DateTime.now(),
          )
        : null;
    final reasonCtrl = TextEditingController(text: existing?.reason ?? '');
    bool autoApprove = existing?.status == AbsenceStatus.approved;
    String? error;

    // Load holidays for calculation
    final currentYear = DateTime.now().year;
    final holidays = <String>{};
    for (var y = currentYear - 1; y <= currentYear + 2; y++) {
      holidays.addAll(getPublicHolidaysBW(y));
    }

    // Load current balance for display
    final balDoc = await db
        .collection('vacation_balances')
        .doc('${employeeId}_$currentYear')
        .get();
    final remaining = (balDoc.data()?['remaining'] ?? 25).toDouble();

    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            double workDays = 0;
            if (dateRange != null) {
              workDays = calculateAbsenceDays(
                startDate: dayKeyLocal(dateRange!.start),
                endDate: dayKeyLocal(dateRange!.end),
                holidays: holidays,
                startDayPart: dayPart,
                endDayPart: dayPart,
                type: type,
              );
            }

            return AlertDialog(
              title: Text(
                isEdit ? 'Abwesenheit bearbeiten' : 'Neue Abwesenheit',
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Type dropdown
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(
                        labelText: 'Typ',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: AbsenceType.urlaub,
                          child: Text('Urlaub'),
                        ),
                        DropdownMenuItem(
                          value: AbsenceType.krankheit,
                          child: Text('Krankheit'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setD(() {
                            type = v;
                            if (v == AbsenceType.krankheit) {
                              autoApprove = true;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Date range
                    InkWell(
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: ctx,
                          firstDate: DateTime(currentYear - 1, 1, 1),
                          lastDate: DateTime(currentYear + 2, 12, 31),
                          initialDateRange: dateRange,
                          helpText: 'Zeitraum wählen',
                          saveText: 'Übernehmen',
                          locale: const Locale('de', 'DE'),
                        );
                        if (picked != null) {
                          setD(() {
                            dateRange = picked;
                            if (dayKeyLocal(picked.start) !=
                                dayKeyLocal(picked.end)) {
                              dayPart = AbsenceDayPart.full;
                            }
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                dateRange != null
                                    ? '${_fmtDate(dateRange!.start)} – ${_fmtDate(dateRange!.end)}'
                                    : 'Zeitraum wählen...',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: dateRange != null
                                      ? null
                                      : Colors.black.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (dateRange != null) ...[
                      const SizedBox(height: 8),
                      if (dayKeyLocal(dateRange!.start) ==
                          dayKeyLocal(dateRange!.end)) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Umfang',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.black.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: AbsenceDayPart.full,
                              label: Text('Ganzer Tag'),
                            ),
                            ButtonSegment(
                              value: AbsenceDayPart.morning,
                              label: Text('Vormittag'),
                            ),
                            ButtonSegment(
                              value: AbsenceDayPart.afternoon,
                              label: Text('Nachmittag'),
                            ),
                          ],
                          selected: {dayPart},
                          onSelectionChanged: (selection) =>
                              setD(() => dayPart = selection.first),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: const Color(0xFFF5F5F5),
                        ),
                        child: Text(
                          '${formatAbsenceDays(workDays)} Arbeitstage '
                          '(exkl. Wochenenden + Feiertage)  •  '
                          'Resturlaub: ${formatAbsenceDays(remaining)} Tage',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Grund (optional)',
                        hintText: 'z. B. Sommerurlaub, Arztbesuch',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),

                    const SizedBox(height: 12),
                    if (type == AbsenceType.urlaub)
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Direkt genehmigen',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Switch(
                            value: autoApprove,
                            onChanged: (v) => setD(() => autoApprove = v),
                          ),
                        ],
                      ),

                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (dateRange == null) {
                      setD(() => error = 'Bitte einen Zeitraum wählen.');
                      return;
                    }
                    if (workDays <= 0) {
                      setD(
                        () =>
                            error = 'Der Zeitraum enthaelt keine Arbeitstage.',
                      );
                      return;
                    }
                    Navigator.of(ctx).pop(true);
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    if (res != true || dateRange == null) return;

    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final startKey = dayKeyLocal(dateRange!.start);
    final endKey = dayKeyLocal(dateRange!.end);
    final effectiveDayPart = AbsenceDayPart.normalize(dayPart);
    final workDays = calculateAbsenceDays(
      startDate: startKey,
      endDate: endKey,
      holidays: holidays,
      startDayPart: effectiveDayPart,
      endDayPart: effectiveDayPart,
      type: type,
    );

    final status = (type == AbsenceType.krankheit || autoApprove)
        ? AbsenceStatus.approved
        : AbsenceStatus.pending;

    final payload = <String, dynamic>{
      'employeeId': employeeId,
      'type': type,
      'startDate': startKey,
      'endDate': endKey,
      'startDayPart': effectiveDayPart,
      'endDayPart': effectiveDayPart,
      'status': status,
      'vacationDaysConsumed': workDays,
      'reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      'createdByEmployee': false,
      'adminUid': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status == AbsenceStatus.approved) {
      payload['approvedBy'] = 'Admin';
      payload['approvedAt'] = FieldValue.serverTimestamp();
    }

    try {
      if (isEdit) {
        await db.collection('absences').doc(existing.id).update(payload);
      } else {
        payload['createdAt'] = FieldValue.serverTimestamp();
        await db.collection('absences').add(payload);
      }

      // Recalculate balance for affected years
      final startYear = dateRange!.start.year;
      final endYear = dateRange!.end.year;
      for (var y = startYear; y <= endYear; y++) {
        await recalculateVacationBalance(employeeId, y);
      }

      // Audit log
      try {
        await db.collection('audit').add({
          'action': isEdit ? 'ABSENCE_UPDATED' : 'ABSENCE_CREATED',
          'employeeId': employeeId,
          'adminUid': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
          'payload': {
            'type': type,
            'startDate': startKey,
            'endDate': endKey,
            'startDayPart': effectiveDayPart,
            'endDayPart': effectiveDayPart,
            'status': status,
            'workDays': workDays,
          },
        });
      } catch (_) {}

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AbsenceType.label(type)} gespeichert ($startKey – $endKey).',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  static String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}
