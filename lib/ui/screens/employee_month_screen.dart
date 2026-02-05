import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/store.dart';
import '../../core/report.dart';
import '../dialogs/admin_pin_dialog.dart';

class EmployeeMonthScreen extends StatefulWidget {
  final String employeeId;
  final int year;
  final int month;

  const EmployeeMonthScreen({
    super.key,
    required this.employeeId,
    required this.year,
    required this.month,
  });

  @override
  State<EmployeeMonthScreen> createState() => _EmployeeMonthScreenState();
}

class _EmployeeMonthScreenState extends State<EmployeeMonthScreen> {
  final _store = InMemoryStore.instance;

  late int _year;
  late int _month;

  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _year = widget.year;
    _month = widget.month;
  }

  MonthlyReportResult get _report => buildMonthlyReport(store: _store, year: _year, month: _month);

  EmployeeMonthlySummary? get _summary {
    final s = _report.summaries.where((x) => x.employeeId == widget.employeeId).toList();
    if (s.isEmpty) return null;
    return s.first;
  }

  List<DailyReportRow> get _days {
    final rows = _report.dailyRows.where((r) => r.employeeId == widget.employeeId).toList();
    rows.sort((a, b) => a.dayLocal.compareTo(b.dayLocal));
    return rows;
  }

  void _prevMonth() {
    setState(() {
      final d = DateTime(_year, _month, 1);
      final p = DateTime(d.year, d.month - 1, 1);
      _year = p.year;
      _month = p.month;
      _msg = null;
    });
  }

  void _nextMonth() {
    setState(() {
      final d = DateTime(_year, _month, 1);
      final n = DateTime(d.year, d.month + 1, 1);
      _year = n.year;
      _month = n.month;
      _msg = null;
    });
  }

  Future<void> _openEditDay(DailyReportRow r) async {
    final res = await showDialog<_DayEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DayEditDialog(dayRow: r),
    );

    if (res == null) return;

    // Admin-PIN muss nochmal bestätigt werden
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AdminPinDialog(),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _msg = null;
    });

    try {
      final reason = res.reason.trim();
      final dayStr = DateFormat('yyyy-MM-dd').format(r.dayLocal);

      Future<void> addIfSelected(String eventType, TimeOfDay? t) async {
        if (t == null) return;
        final local = DateTime(r.dayLocal.year, r.dayLocal.month, r.dayLocal.day, t.hour, t.minute);

        // Rechtssicher: nur zusätzliche Events, nichts löschen/überschreiben.
        await _store.addEventAt(
          employeeId: r.employeeId,
          eventType: eventType,
          timestampUtcMs: local.toUtc().millisecondsSinceEpoch,
          terminalId: 'ADMIN',
          source: 'ADMIN',
          note: 'ADMIN_EDIT; day=$dayStr; reason="$reason"',
        );
      }

      await addIfSelected('IN', res.inTime);
      await addIfSelected('BREAK_START', res.breakStartTime);
      await addIfSelected('BREAK_END', res.breakEndTime);
      await addIfSelected('OUT', res.outTime);

      setState(() {
        _msg = 'Korrektur gespeichert: ${DateFormat('dd.MM.yyyy').format(r.dayLocal)}';
      });

      setState(() {}); // refresh
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(DateTime(_year, _month, 1));
    final summary = _summary;
    final days = _days;

    return Scaffold(
      appBar: AppBar(
        title: Text('MA ${widget.employeeId}'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                _card(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(onPressed: _busy ? null : _prevMonth, icon: const Icon(Icons.chevron_left)),
                          Expanded(
                            child: Text(
                              monthLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                            ),
                          ),
                          IconButton(onPressed: _busy ? null : _nextMonth, icon: const Icon(Icons.chevron_right)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (summary == null)
                        Text(
                          'Keine Daten in diesem Monat.',
                          style: TextStyle(color: Colors.black.withOpacity(0.60), fontWeight: FontWeight.w700),
                        )
                      else
                        Row(
                          children: [
                            Expanded(child: _metric('Work', hhmm(summary.workMinutesTotal))),
                            const SizedBox(width: 10),
                            Expanded(child: _metric('Pause', hhmm(summary.breakMinutesTotal))),
                            const SizedBox(width: 10),
                            Expanded(child: _metric('Netto', hhmm(summary.netMinutesTotal))),
                            const SizedBox(width: 10),
                            Expanded(child: _metric('Flags', '${summary.flaggedDaysCount}')),
                          ],
                        ),
                      if (_msg != null) ...[
                        const SizedBox(height: 10),
                        Text(_msg!, style: TextStyle(color: Colors.black.withOpacity(0.65), fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionTitle('Tage'),
                const SizedBox(height: 10),
                if (days.isEmpty)
                  _card(child: const Text('Keine Tage vorhanden.'))
                else
                  ...days.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _dayRow(r),
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(18)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: child,
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black.withOpacity(0.03),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  String _fmtHm(DateTime? dt) => dt == null ? '—' : DateFormat('HH:mm').format(dt);

  Widget _dayRow(DailyReportRow r) {
    final date = DateFormat('EEE, dd.MM.yyyy', 'de_DE').format(r.dayLocal);
    final flags = r.flagsList();
    final warn = flags.isNotEmpty;

    return _card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  date,
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _openEditDay(r),
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _kv('IN', _fmtHm(r.firstInLocal))),
              const SizedBox(width: 10),
              Expanded(child: _kv('OUT', _fmtHm(r.lastOutLocal))),
              const SizedBox(width: 10),
              Expanded(child: _kv('Work', hhmm(r.workMinutes))),
              const SizedBox(width: 10),
              Expanded(child: _kv('Netto', hhmm(r.netMinutes))),
            ],
          ),
          if (warn) ...[
            const SizedBox(height: 10),
            Text(
              'Flags: ${flags.join(', ')}',
              style: TextStyle(color: Colors.red.withOpacity(0.75), fontWeight: FontWeight.w800),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        color: Colors.white,
      ),
      child: Column(
        children: [
          Text(k, style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

// ---------------------
// Dialog
// ---------------------

class _DayEditResult {
  final TimeOfDay? inTime;
  final TimeOfDay? breakStartTime;
  final TimeOfDay? breakEndTime;
  final TimeOfDay? outTime;
  final String reason;

  _DayEditResult({
    required this.inTime,
    required this.breakStartTime,
    required this.breakEndTime,
    required this.outTime,
    required this.reason,
  });
}

class _DayEditDialog extends StatefulWidget {
  final DailyReportRow dayRow;
  const _DayEditDialog({required this.dayRow});

  @override
  State<_DayEditDialog> createState() => _DayEditDialogState();
}

class _DayEditDialogState extends State<_DayEditDialog> {
  TimeOfDay? _in;
  TimeOfDay? _breakStart;
  TimeOfDay? _breakEnd;
  TimeOfDay? _out;

  final _reasonCtrl = TextEditingController();
  String? _err;

  @override
  void initState() {
    super.initState();

    if (widget.dayRow.firstInLocal != null) {
      final dt = widget.dayRow.firstInLocal!;
      _in = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }
    if (widget.dayRow.lastOutLocal != null) {
      final dt = widget.dayRow.lastOutLocal!;
      _out = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<TimeOfDay?> _pick(TimeOfDay initial) async {
    return showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Uhrzeit wählen',
      cancelText: 'Abbrechen',
      confirmText: 'OK',
    );
  }

  int? _toMin(TimeOfDay? t) => t == null ? null : t.hour * 60 + t.minute;

  void _submit() {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _err = 'Begründung ist Pflicht (rechtssicher).');
      return;
    }

    if (_in == null && _breakStart == null && _breakEnd == null && _out == null) {
      setState(() => _err = 'Bitte mindestens ein Feld setzen.');
      return;
    }

    final inM = _toMin(_in);
    final bsM = _toMin(_breakStart);
    final beM = _toMin(_breakEnd);
    final outM = _toMin(_out);

    String? orderErr;
    if (inM != null && outM != null && outM < inM) orderErr = 'OUT darf nicht vor IN liegen.';
    if (bsM != null && beM != null && beM < bsM) orderErr = 'Pause Ende darf nicht vor Pause Start liegen.';
    if (inM != null && bsM != null && bsM < inM) orderErr = 'Pause Start darf nicht vor IN liegen.';
    if (outM != null && bsM != null && bsM > outM) orderErr = 'Pause Start darf nicht nach OUT liegen.';
    if (outM != null && beM != null && beM > outM) orderErr = 'Pause Ende darf nicht nach OUT liegen.';

    if (orderErr != null) {
      setState(() => _err = orderErr);
      return;
    }

    Navigator.of(context).pop(
      _DayEditResult(
        inTime: _in,
        breakStartTime: _breakStart,
        breakEndTime: _breakEnd,
        outTime: _out,
        reason: reason,
      ),
    );
  }

  String _fmt(TimeOfDay? t) => t == null ? '—' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final d = widget.dayRow.dayLocal;
    final title = 'Edit · ${DateFormat('dd.MM.yyyy').format(d)}';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _timeLine('IN', _in, onSet: () async {
              final t = await _pick(_in ?? const TimeOfDay(hour: 8, minute: 0));
              if (t != null) setState(() => _in = t);
            }, onClear: () => setState(() => _in = null)),
            const SizedBox(height: 10),
            _timeLine('Pause Start', _breakStart, onSet: () async {
              final t = await _pick(_breakStart ?? const TimeOfDay(hour: 12, minute: 0));
              if (t != null) setState(() => _breakStart = t);
            }, onClear: () => setState(() => _breakStart = null)),
            const SizedBox(height: 10),
            _timeLine('Pause Ende', _breakEnd, onSet: () async {
              final t = await _pick(_breakEnd ?? const TimeOfDay(hour: 13, minute: 0));
              if (t != null) setState(() => _breakEnd = t);
            }, onClear: () => setState(() => _breakEnd = null)),
            const SizedBox(height: 10),
            _timeLine('OUT', _out, onSet: () async {
              final t = await _pick(_out ?? const TimeOfDay(hour: 18, minute: 0));
              if (t != null) setState(() => _out = t);
            }, onClear: () => setState(() => _out = null)),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Begründung (Pflicht)',
                helperText: 'z. B. "MA hat Stempel vergessen, telefonisch bestätigt"',
              ),
              maxLines: 2,
            ),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Abbrechen')),
        FilledButton(onPressed: _submit, child: const Text('Speichern')),
      ],
    );
  }

  Widget _timeLine(
    String label,
    TimeOfDay? value, {
    required Future<void> Function() onSet,
    required VoidCallback onClear,
  }) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withOpacity(0.08)),
            ),
            child: Text(_fmt(value), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(onPressed: onSet, child: const Text('Setzen')),
        const SizedBox(width: 8),
        TextButton(onPressed: onClear, child: const Text('Clear')),
      ],
    );
  }
}
