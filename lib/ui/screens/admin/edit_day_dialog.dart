import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../data/store.dart';
import 'admin_helpers.dart';

class EditDayDialog {
  static Future<void> show(
    BuildContext context, {
    required String employeeId,
    required DateTime dayLocal,
    required Map<String, dynamic>? existingOverride,
    required List<TimeEvent> autoDayEvents,
    required VoidCallback onSaved,
  }) async {
    final db = FirebaseFirestore.instance;
    final dayKey = dayKeyLocal(dayLocal);

    DateTime? inTime;
    DateTime? outTime;
    DateTime? breakStart;
    DateTime? breakEnd;
    bool removeInOverride = false;
    bool removeOutOverride = false;
    bool removeBreakStartOverride = false;
    bool removeBreakEndOverride = false;

    if (existingOverride != null) {
      final auto = summaryFromEventsForDay(autoDayEvents);
      inTime = resolvedOverrideDateTime(override: existingOverride, valueKey: 'inUtcMs', autoValue: auto.inTime);
      outTime = resolvedOverrideDateTime(override: existingOverride, valueKey: 'outUtcMs', autoValue: auto.outTime);
      breakStart = resolvedOverrideDateTime(override: existingOverride, valueKey: 'breakStartUtcMs', autoValue: auto.breakStart);
      breakEnd = resolvedOverrideDateTime(override: existingOverride, valueKey: 'breakEndUtcMs', autoValue: auto.breakEnd);
    } else {
      final auto = summaryFromEventsForDay(autoDayEvents);
      inTime = auto.inTime;
      outTime = auto.outTime;
      breakStart = auto.breakStart;
      breakEnd = auto.breakEnd;
    }

    final reasonCtrl = TextEditingController(text: existingOverride?['reason']?.toString() ?? '');
    String? error;

    Future<DateTime?> pickTime(BuildContext ctx, DateTime? current) async {
      final initial = current ?? DateTime(dayLocal.year, dayLocal.month, dayLocal.day, 8, 0);
      final tod = await showTimePicker(
        context: ctx,
        initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
        helpText: 'Uhrzeit wählen',
      );
      if (tod == null) return current;
      return DateTime(dayLocal.year, dayLocal.month, dayLocal.day, tod.hour, tod.minute);
    }

    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            Widget row(
              String label,
              DateTime? value,
              Future<void> Function() onPick,
              VoidCallback onClear,
            ) {
              return Row(
                children: [
                  SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(
                    child: InkWell(
                      onTap: () async => onPick(),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
                        ),
                        child: Text(hhmm(value), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(tooltip: 'Loeschen', onPressed: onClear, icon: const Icon(Icons.clear)),
                ],
              );
            }

            return AlertDialog(
              title: Text('Tag bearbeiten - $dayKey'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    row('Kommen', inTime, () async {
                      final t = await pickTime(ctx, inTime);
                      setD(() { inTime = t; removeInOverride = false; });
                    }, () => setD(() { inTime = null; removeInOverride = true; })),
                    const SizedBox(height: 10),
                    row('Gehen', outTime, () async {
                      final t = await pickTime(ctx, outTime);
                      setD(() { outTime = t; removeOutOverride = false; });
                    }, () => setD(() { outTime = null; removeOutOverride = true; })),
                    const SizedBox(height: 10),
                    row('Pause Start', breakStart, () async {
                      final t = await pickTime(ctx, breakStart);
                      setD(() { breakStart = t; removeBreakStartOverride = false; });
                    }, () => setD(() { breakStart = null; removeBreakStartOverride = true; })),
                    const SizedBox(height: 10),
                    row('Pause Ende', breakEnd, () async {
                      final t = await pickTime(ctx, breakEnd);
                      setD(() { breakEnd = t; removeBreakEndOverride = false; });
                    }, () => setD(() { breakEnd = null; removeBreakEndOverride = true; })),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Grund (Pflicht)',
                        hintText: 'z. B. Mitarbeiter hat vergessen zu stempeln',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
                FilledButton.icon(
                  onPressed: () {
                    final r = reasonCtrl.text.trim();
                    if (r.isEmpty) {
                      setD(() => error = 'Bitte einen Grund angeben.');
                      return;
                    }
                    if (inTime != null && outTime != null && outTime!.isBefore(inTime!)) {
                      setD(() => error = 'Gehen darf nicht vor Kommen liegen.');
                      return;
                    }
                    if (breakStart != null && breakEnd != null && breakEnd!.isBefore(breakStart!)) {
                      setD(() => error = 'Pause Ende darf nicht vor Pause Start liegen.');
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

    if (res != true) return;

    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final reason = reasonCtrl.text.trim();
    final overrideDocId = '${employeeId}_$dayKey';
    final overrideDoc = db.collection('day_overrides').doc(overrideDocId);

    final payload = <String, dynamic>{
      'employeeId': employeeId,
      'dayKey': dayKey,
      'reason': reason,
      'adminUid': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    void putField({required String key, required DateTime? value, required bool remove}) {
      final ms = utcMsFromLocalDateTime(value);
      if (ms != null) {
        payload[key] = ms;
      } else if (remove) {
        payload[key] = FieldValue.delete();
      }
    }

    putField(key: 'inUtcMs', value: inTime, remove: removeInOverride);
    putField(key: 'outUtcMs', value: outTime, remove: removeOutOverride);
    putField(key: 'breakStartUtcMs', value: breakStart, remove: removeBreakStartOverride);
    putField(key: 'breakEndUtcMs', value: breakEnd, remove: removeBreakEndOverride);

    try {
      await overrideDoc.set(payload, SetOptions(merge: true));

      try {
        await db.collection('audit').add({
          'action': 'DAY_OVERRIDE_SET',
          'employeeId': employeeId,
          'dayKey': dayKey,
          'reason': reason,
          'adminUid': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
          'payload': {
            'inUtcMs': payload['inUtcMs'],
            'outUtcMs': payload['outUtcMs'],
            'breakStartUtcMs': payload['breakStartUtcMs'],
            'breakEndUtcMs': payload['breakEndUtcMs'],
          },
        });
      } catch (_) {}

      onSaved();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Override gespeichert ($dayKey).')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Override nicht gespeichert: $e')),
      );
    }
  }
}
