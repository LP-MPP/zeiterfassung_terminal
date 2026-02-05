import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _db = FirebaseFirestore.instance;

  String? _selectedEmployeeId;
  late DateTime _month; // local month anchor (1st day)

  @override
  void initState() {
    super.initState();

    // Guard: only non-anonymous users may access admin
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }

    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  Future<void> _logoutAdmin() async {
    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInAnonymously();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _prevMonth() => setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
  void _nextMonth() => setState(() => _month = DateTime(_month.year, _month.month + 1, 1));

  String _monthLabel(DateTime m) {
    const names = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember'
    ];
    return '${names[m.month - 1]} ${m.year}';
  }

  DateTime _startOfMonthLocal(DateTime m) => DateTime(m.year, m.month, 1);
  DateTime _endOfMonthLocal(DateTime m) => DateTime(m.year, m.month + 1, 1);

  String _dayKeyLocal(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _hhmm(DateTime? dt) {
    if (dt == null) return '—';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Duration _safeDiff(DateTime? a, DateTime? b) {
    if (a == null || b == null) return Duration.zero;
    final d = b.difference(a);
    if (d.isNegative) return Duration.zero;
    return d;
  }

  String _durHHMM(Duration d) {
    final totalMin = d.inMinutes;
    final h = (totalMin ~/ 60).toString().padLeft(2, '0');
    final m = (totalMin % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ---------------- Employees (Create/Edit) ----------------

  String _hashPin(String employeeId, String pin) {
    // Must match tool/hash_pin.dart (employeeId + ':' + pin) SHA-256
    final bytes = utf8.encode('$employeeId:$pin');
    return sha256.convert(bytes).toString();
  }

  Future<void> _showEmployeeDialog({Employee? existing}) async {
    final isEdit = existing != null;

    final idCtrl = TextEditingController(text: existing?.id ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final pinCtrl = TextEditingController(text: '');
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
                        labelText: isEdit ? 'Neuer PIN (optional)' : 'PIN (4–8 Ziffern)',
                        hintText: isEdit ? 'leer lassen = unverändert' : 'z. B. 1234',
                        border: const OutlineInputBorder(),
                      ),
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
                    if (!isEdit) {
                      if (pin.isEmpty) {
                        setD(() => error = 'Bitte einen PIN vergeben.');
                        return;
                      }
                    }
                    if (pin.isNotEmpty) {
                      final okDigits = RegExp(r'^[0-9]{4,8}$').hasMatch(pin);
                      if (!okDigits) {
                        setD(() => error = 'PIN muss 4–8 Ziffern haben.');
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

    // Build update payload
    final update = <String, dynamic>{
      'id': id,
      'name': name,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!isEdit) {
      update['createdAt'] = FieldValue.serverTimestamp();
    }
    if (pin.isNotEmpty) {
      update['pinHash'] = _hashPin(id, pin);
    }

    // Write employee
    await _db.collection('employees').doc(id).set(update, SetOptions(merge: true));

    // Audit
    await _auditCol.add({
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

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isEdit ? 'Mitarbeiter gespeichert ($id).' : 'Mitarbeiter angelegt ($id).')),
    );
  }

  // ---------------- Overrides ----------------

  String _overrideDocId(String employeeId, String dayKey) => '${employeeId}_$dayKey';

  CollectionReference<Map<String, dynamic>> get _overridesCol => _db.collection('day_overrides');
  CollectionReference<Map<String, dynamic>> get _auditCol => _db.collection('audit');
  CollectionReference<Map<String, dynamic>> get _eventsCol => _db.collection('events');

  Stream<Map<String, Map<String, dynamic>>> _watchOverridesForMonth(String employeeId, DateTime month) {
    final startKey = _dayKeyLocal(_startOfMonthLocal(month));
    final endKey = _dayKeyLocal(_endOfMonthLocal(month));

    final q = _overridesCol
        .where('employeeId', isEqualTo: employeeId)
        .where('dayKey', isGreaterThanOrEqualTo: startKey)
        .where('dayKey', isLessThan: endKey);

    return q.snapshots().map((snap) {
      final map = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final dk = (d['dayKey'] ?? doc.id).toString();
        map[dk] = d;
      }
      return map;
    });
  }

  Stream<List<TimeEvent>> _watchEventsForMonth(String employeeId, DateTime month) {
    final startUtcMs = _startOfMonthLocal(month).toUtc().millisecondsSinceEpoch;
    final endUtcMs = _endOfMonthLocal(month).toUtc().millisecondsSinceEpoch;

    final q = _eventsCol
        .where('employeeId', isEqualTo: employeeId)
        .where('timestampUtcMs', isGreaterThanOrEqualTo: startUtcMs)
        .where('timestampUtcMs', isLessThan: endUtcMs)
        .orderBy('timestampUtcMs', descending: false);

    return q.snapshots().map((snap) => snap.docs.map(TimeEvent.fromDoc).toList());
  }

  // ---------------- Helpers for summaries ----------------

  DateTime? _localFromUtcMs(dynamic v) {
    if (v == null) return null;
    final ms = (v is int) ? v : int.tryParse(v.toString());
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }

  int? _utcMsFromLocalDateTime(DateTime? localDt) {
    if (localDt == null) return null;
    return localDt.toUtc().millisecondsSinceEpoch;
  }

  Map<String, List<TimeEvent>> _groupEventsByDayKey(List<TimeEvent> events) {
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

  _DaySummary _summaryFromEventsForDay(List<TimeEvent> dayEvents) {
    DateTime? inTime;
    DateTime? outTime;
    DateTime? breakStart;
    DateTime? breakEnd;

    for (final e in dayEvents) {
      final t = DateTime.fromMillisecondsSinceEpoch(e.timestampUtcMs, isUtc: true).toLocal();
      switch (e.eventType) {
        case 'IN':
          inTime ??= t; // first IN
          break;
        case 'OUT':
          outTime = t; // last OUT wins
          break;
        case 'BREAK_START':
          if (breakStart == null && (inTime == null || t.isAfter(inTime!))) breakStart = t;
          break;
        case 'BREAK_END':
          if (breakEnd == null && breakStart != null && t.isAfter(breakStart!)) breakEnd = t;
          break;
        default:
          break;
      }
    }

    final workSpan = _safeDiff(inTime, outTime);
    final breakSpan = _safeDiff(breakStart, breakEnd);
    final net = workSpan - breakSpan;

    return _DaySummary(
      inTime: inTime,
      outTime: outTime,
      breakStart: breakStart,
      breakEnd: breakEnd,
      net: net.isNegative ? Duration.zero : net,
      sourceLabel: 'AUTO',
    );
  }

  _DaySummary _summaryFromOverride(Map<String, dynamic> o) {
    final inTime = _localFromUtcMs(o['inUtcMs']);
    final outTime = _localFromUtcMs(o['outUtcMs']);
    final breakStart = _localFromUtcMs(o['breakStartUtcMs']);
    final breakEnd = _localFromUtcMs(o['breakEndUtcMs']);

    final workSpan = _safeDiff(inTime, outTime);
    final breakSpan = _safeDiff(breakStart, breakEnd);
    final net = workSpan - breakSpan;

    return _DaySummary(
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

  Future<void> _editDay(
    String employeeId,
    DateTime dayLocal,
    Map<String, dynamic>? existingOverride,
    List<TimeEvent> autoDayEvents,
  ) async {
    final dayKey = _dayKeyLocal(dayLocal);

    DateTime? inTime;
    DateTime? outTime;
    DateTime? breakStart;
    DateTime? breakEnd;

    if (existingOverride != null) {
      inTime = _localFromUtcMs(existingOverride['inUtcMs']);
      outTime = _localFromUtcMs(existingOverride['outUtcMs']);
      breakStart = _localFromUtcMs(existingOverride['breakStartUtcMs']);
      breakEnd = _localFromUtcMs(existingOverride['breakEndUtcMs']);
    } else {
      final auto = _summaryFromEventsForDay(autoDayEvents);
      inTime = auto.inTime;
      outTime = auto.outTime;
      breakStart = auto.breakStart;
      breakEnd = auto.breakEnd;
    }

    final reasonCtrl = TextEditingController(text: existingOverride?['reason']?.toString() ?? '');
    String? error;

    Future<DateTime?> pickTime(DateTime? current) async {
      final initial = current ?? DateTime(dayLocal.year, dayLocal.month, dayLocal.day, 8, 0);
      final tod = await showTimePicker(
        context: context,
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
                          border: Border.all(color: Colors.black.withOpacity(0.15)),
                        ),
                        child: Text(_hhmm(value), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Löschen',
                    onPressed: onClear,
                    icon: const Icon(Icons.clear),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Text('Tag bearbeiten – $dayKey'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    row(
                      'Kommen',
                      inTime,
                      () async {
                        final t = await pickTime(inTime);
                        setD(() => inTime = t);
                      },
                      () => setD(() => inTime = null),
                    ),
                    const SizedBox(height: 10),
                    row(
                      'Gehen',
                      outTime,
                      () async {
                        final t = await pickTime(outTime);
                        setD(() => outTime = t);
                      },
                      () => setD(() => outTime = null),
                    ),
                    const SizedBox(height: 10),
                    row(
                      'Pause Start',
                      breakStart,
                      () async {
                        final t = await pickTime(breakStart);
                        setD(() => breakStart = t);
                      },
                      () => setD(() => breakStart = null),
                    ),
                    const SizedBox(height: 10),
                    row(
                      'Pause Ende',
                      breakEnd,
                      () async {
                        final t = await pickTime(breakEnd);
                        setD(() => breakEnd = t);
                      },
                      () => setD(() => breakEnd = null),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Grund (Pflicht)',
                        hintText: 'z. B. „Mitarbeiter hat vergessen zu stempeln“',
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
                      setD(() => error = '„Gehen“ darf nicht vor „Kommen“ liegen.');
                      return;
                    }
                    if (breakStart != null && breakEnd != null && breakEnd!.isBefore(breakStart!)) {
                      setD(() => error = '„Pause Ende“ darf nicht vor „Pause Start“ liegen.');
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

    final overrideDoc = _overridesCol.doc(_overrideDocId(employeeId, dayKey));

    final payload = <String, dynamic>{
      'employeeId': employeeId,
      'dayKey': dayKey,
      'inUtcMs': _utcMsFromLocalDateTime(inTime),
      'outUtcMs': _utcMsFromLocalDateTime(outTime),
      'breakStartUtcMs': _utcMsFromLocalDateTime(breakStart),
      'breakEndUtcMs': _utcMsFromLocalDateTime(breakEnd),
      'reason': reason,
      'adminUid': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    await overrideDoc.set(payload, SetOptions(merge: true));

    await _auditCol.add({
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

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Override gespeichert ($dayKey).')));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const Scaffold(body: Center(child: Text('Kein Admin-Login.')));
    }

    final employeesStream = _db.collection('employees').snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin – Übersicht & Korrektur'),
        actions: [
          IconButton(
            tooltip: 'Abmelden',
            onPressed: _logoutAdmin,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: employeesStream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Fehler: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final emps = snap.data!.docs.map(Employee.fromDoc).toList()..sort((a, b) => a.id.compareTo(b.id));

          if (emps.isNotEmpty && (_selectedEmployeeId == null || !emps.any((e) => e.id == _selectedEmployeeId))) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _selectedEmployeeId = emps.first.id);
            });
          }

          final selId = _selectedEmployeeId;
          final selEmp = (selId == null) ? null : emps.where((e) => e.id == selId).cast<Employee?>().first;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(width: 320, child: _employeePane(emps, selId)),
                const SizedBox(width: 16),
                Expanded(
                  child: (selEmp == null) ? const Center(child: Text('Bitte Mitarbeiter auswählen.')) : _monthPane(selEmp),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _employeePane(List<Employee> emps, String? selectedId) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Mitarbeiter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                IconButton.filledTonal(
                  tooltip: 'Mitarbeiter bearbeiten',
                  onPressed: (selectedId == null)
                      ? null
                      : () {
                          final e = emps.where((x) => x.id == selectedId).cast<Employee?>().first;
                          if (e != null) _showEmployeeDialog(existing: e);
                        },
                  icon: const Icon(Icons.edit),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Mitarbeiter anlegen',
                  onPressed: () => _showEmployeeDialog(),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: emps.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final e = emps[i];
                  final isSel = e.id == selectedId;
                  return InkWell(
                    onTap: () => setState(() => _selectedEmployeeId = e.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black.withOpacity(isSel ? 0.35 : 0.12)),
                        color: isSel ? Colors.black.withOpacity(0.06) : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 2),
                                Text(
                                  e.id,
                                  style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          _pill(e.active ? 'AKTIV' : 'INAKTIV', e.active),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: ok ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12),
        border: Border.all(color: ok ? Colors.green.withOpacity(0.35) : Colors.red.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w900, color: ok ? Colors.green.shade800 : Colors.red.shade800),
      ),
    );
  }

  Widget _monthPane(Employee emp) {
    final employeeId = emp.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${emp.name} (${emp.id})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                IconButton(tooltip: 'Vorheriger Monat', onPressed: _prevMonth, icon: const Icon(Icons.chevron_left)),
                Text(_monthLabel(_month), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                IconButton(tooltip: 'Nächster Monat', onPressed: _nextMonth, icon: const Icon(Icons.chevron_right)),
              ],
            ),
            const SizedBox(height: 10),

            Expanded(
              child: StreamBuilder<List<TimeEvent>>(
                stream: _watchEventsForMonth(employeeId, _month),
                builder: (context, evSnap) {
                  if (evSnap.hasError) return Center(child: Text('Fehler Events: ${evSnap.error}'));
                  if (!evSnap.hasData) return const Center(child: CircularProgressIndicator());

                  final monthEvents = evSnap.data!;
                  final byDay = _groupEventsByDayKey(monthEvents);

                  return StreamBuilder<Map<String, Map<String, dynamic>>>(
                    stream: _watchOverridesForMonth(employeeId, _month),
                    builder: (context, ovSnap) {
                      final overrides = ovSnap.data ?? const <String, Map<String, dynamic>>{};

                      final start = _startOfMonthLocal(_month);
                      final end = _endOfMonthLocal(_month);
                      final days = <DateTime>[];
                      for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
                        days.add(d);
                      }

                      Duration totalNet = Duration.zero;

                      final rows = days.map((day) {
                        final dk = _dayKeyLocal(day);
                        final ov = overrides[dk];
                        final autoDayEvents = (byDay[dk] ?? const <TimeEvent>[]);
                        final summary = (ov != null) ? _summaryFromOverride(ov) : _summaryFromEventsForDay(autoDayEvents);
                        totalNet += summary.net;
                        return _DayRow(dayLocal: day, dayKey: dk, summary: summary, override: ov, autoDayEvents: autoDayEvents);
                      }).toList();

                      return Column(
                        children: [
                          _monthTotalsCard(totalNet, overrides.length, monthEvents.length),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ListView.separated(
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _dayTile(employeeId, rows[i]),
                            ),
                          ),
                        ],
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

  Widget _monthTotalsCard(Duration totalNet, int overrideCount, int eventCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black.withOpacity(0.04),
        border: Border.all(color: Colors.black.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Monatssumme: ${_durHHMM(totalNet)} h',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            'Events: $eventCount · Overrides: $overrideCount',
            style: TextStyle(color: Colors.black.withOpacity(0.65), fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _dayTile(String employeeId, _DayRow row) {
    final day = row.dayLocal;
    final dowNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final dow = dowNames[(day.weekday - 1).clamp(0, 6)];
    final dateLabel = '$dow, ${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.';

    final s = row.summary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  s.sourceLabel == 'ADMIN' ? 'ADMIN' : 'AUTO',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: s.sourceLabel == 'ADMIN' ? Colors.blueGrey.shade700 : Colors.black.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _kv('Kommen', _hhmm(s.inTime)),
                _kv('Gehen', _hhmm(s.outTime)),
                _kv('Pause', '${_hhmm(s.breakStart)}–${_hhmm(s.breakEnd)}'),
                _kv('Netto', '${_durHHMM(s.net)} h'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Bearbeiten',
            onPressed: () => _editDay(employeeId, day, row.override, row.autoDayEvents),
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _DaySummary {
  final DateTime? inTime;
  final DateTime? outTime;
  final DateTime? breakStart;
  final DateTime? breakEnd;
  final Duration net;
  final String sourceLabel; // ADMIN / AUTO
  final String? reason;
  final String? adminUid;

  _DaySummary({
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

class _DayRow {
  final DateTime dayLocal;
  final String dayKey;
  final _DaySummary summary;
  final Map<String, dynamic>? override;
  final List<TimeEvent> autoDayEvents;

  _DayRow({
    required this.dayLocal,
    required this.dayKey,
    required this.summary,
    required this.override,
    required this.autoDayEvents,
  });
}