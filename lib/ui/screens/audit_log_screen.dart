import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/store.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _store = InMemoryStore.instance;

  String _query = '';
  bool _onlyAdminEdits = true;

  @override
  Widget build(BuildContext context) {
    final items = _loadItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit-Log'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _filters(),
                const SizedBox(height: 12),
                Expanded(
                  child: items.isEmpty
                      ? _card(child: const Text('Keine Audit-Einträge gefunden.'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _auditRow(items[i]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return _card(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Suche (MA-ID, Typ, Reason, Tag)',
                    hintText: 'z. B. E001 oder reason',
                  ),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  const Text('Nur ADMIN', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Switch(
                    value: _onlyAdminEdits,
                    onChanged: (v) => setState(() => _onlyAdminEdits = v),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
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

  // Erwartete Struktur deines Events (aus deinem Store):
  // - employeeId (String)
  // - eventType (String)
  // - timestampUtcMs (int)
  // - terminalId (String)
  // - source (String)
  // - note (String?)
  //
  // Falls dein Store die Liste anders benannt hat, passe _store.events entsprechend an.

  List<dynamic> _loadItems() {
    // Reverse sort: neueste zuerst
    final all = List<dynamic>.from(_store.events);
    all.sort((a, b) => (b.timestampUtcMs as int).compareTo(a.timestampUtcMs as int));

    Iterable<dynamic> it = all;

    if (_onlyAdminEdits) {
      it = it.where((e) => (e.source ?? '') == 'ADMIN' || (e.terminalId ?? '') == 'ADMIN');
    }

    if (_query.isNotEmpty) {
      it = it.where((e) {
        final emp = (e.employeeId ?? '').toString().toLowerCase();
        final type = (e.eventType ?? '').toString().toLowerCase();
        final note = (e.note ?? '').toString().toLowerCase();
        final day = DateFormat('yyyy-MM-dd').format(
          DateTime.fromMillisecondsSinceEpoch(e.timestampUtcMs as int, isUtc: true).toLocal(),
        );
        final hay = '$emp $type $note $day';
        return hay.contains(_query);
      });
    }

    return it.toList();
    }

  Widget _auditRow(dynamic e) {
    final local = DateTime.fromMillisecondsSinceEpoch(e.timestampUtcMs as int, isUtc: true).toLocal();
    final ts = DateFormat('dd.MM.yyyy HH:mm:ss').format(local);

    final emp = (e.employeeId ?? '').toString();
    final type = (e.eventType ?? '').toString();
    final src = (e.source ?? '').toString();
    final term = (e.terminalId ?? '').toString();
    final note = (e.note ?? '').toString();

    return _card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$emp · $type',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                ),
              ),
              Text(
                ts,
                style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Quelle: $src · Terminal: $term',
            style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}