import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/security.dart';
import '../../../data/store.dart';

class EmployeeDialog {
  static Future<void> show(BuildContext context, {Employee? existing}) async {
    final db = FirebaseFirestore.instance;
    final isEdit = existing != null;

    final idCtrl = TextEditingController(text: existing?.id ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final pinCtrl = TextEditingController(text: '');
    final vacDaysCtrl = TextEditingController(text: (existing?.vacationDaysPerYear ?? 25).toString());
    final dailyHoursCtrl = TextEditingController(text: (existing?.standardDailyHours ?? 8.0).toString());
    bool active = existing?.active ?? true;

    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: Text(isEdit ? 'Mitarbeiter bearbeiten' : 'Mitarbeiter anlegen'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: idCtrl,
                      enabled: !isEdit,
                      decoration: const InputDecoration(
                        labelText: 'Mitarbeiter-ID',
                        hintText: 'z. B. E002',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'Vorname Nachname',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: isEdit ? 'Neuer PIN (optional)' : 'PIN (4-8 Ziffern)',
                        hintText: isEdit ? 'leer lassen = unveraendert' : 'z. B. 1234',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: vacDaysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Urlaubstage / Jahr',
                              hintText: '25',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: dailyHoursCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Sollstunden / Tag',
                              hintText: '8.0',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Aktiv', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        Switch(
                          value: active,
                          onChanged: (v) => setD(() => active = v),
                        ),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
                FilledButton.icon(
                  onPressed: () {
                    final id = idCtrl.text.trim().toUpperCase();
                    final name = nameCtrl.text.trim();
                    final pin = pinCtrl.text.trim();

                    if (id.isEmpty) {
                      setD(() => error = 'Bitte eine Mitarbeiter-ID angeben.');
                      return;
                    }
                    if (name.isEmpty) {
                      setD(() => error = 'Bitte einen Namen angeben.');
                      return;
                    }
                    if (!isEdit && pin.isEmpty) {
                      setD(() => error = 'Bitte einen PIN vergeben.');
                      return;
                    }
                    if (pin.isNotEmpty) {
                      final okDigits = RegExp(r'^[0-9]{4,8}$').hasMatch(pin);
                      if (!okDigits) {
                        setD(() => error = 'PIN muss 4-8 Ziffern haben.');
                        return;
                      }
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

    if (ok != true) return;

    final id = idCtrl.text.trim().toUpperCase();
    final name = nameCtrl.text.trim();
    final pin = pinCtrl.text.trim();
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

    final vacDays = int.tryParse(vacDaysCtrl.text.trim()) ?? 25;
    final dailyHours = double.tryParse(dailyHoursCtrl.text.trim()) ?? 8.0;

    final update = <String, dynamic>{
      'id': id,
      'name': name,
      'active': active,
      'vacationDaysPerYear': vacDays,
      'standardDailyHours': dailyHours,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!isEdit) {
      update['createdAt'] = FieldValue.serverTimestamp();
    }
    if (pin.isNotEmpty) {
      update['pinHash'] = hashPin(id, pin);
    }

    await db.collection('employees').doc(id).set(update, SetOptions(merge: true));

    await db.collection('audit').add({
      'action': isEdit ? 'EMPLOYEE_UPDATED' : 'EMPLOYEE_CREATED',
      'employeeId': id,
      'adminUid': adminUid,
      'createdAt': FieldValue.serverTimestamp(),
      'payload': {
        'name': name,
        'active': active,
        'pinChanged': pin.isNotEmpty,
      },
    });

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isEdit ? 'Mitarbeiter gespeichert ($id).' : 'Mitarbeiter angelegt ($id).')),
    );
  }
}
