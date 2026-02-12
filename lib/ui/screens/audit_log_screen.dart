import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/store.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _db = FirebaseFirestore.instance;

  String _query = '';
  bool _onlyAdminEdits = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit-Log'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primary.withValues(alpha: 0.08), cs.surface, cs.surface],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _filters(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _db.collection('events').orderBy('timestampUtcMs', descending: true).snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return _card(child: Text('Fehler beim Laden: ${snap.error}'));
                        }
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final events = snap.data!.docs.map(TimeEvent.fromDoc).toList();
                        final items = _loadItems(events);

                        if (items.isEmpty) {
                          return _card(child: const Text('Keine Audit-Einträge gefunden.'));
                        }

                        return ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _auditRow(items[i]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return _card(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final search = TextField(
            decoration: const InputDecoration(
              labelText: 'Suche (MA-ID, Typ, Reason, Tag)',
              hintText: 'z. B. E001 oder reason',
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          );

          final adminToggle = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Nur ADMIN', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Switch(
                value: _onlyAdminEdits,
                onChanged: (v) => setState(() => _onlyAdminEdits = v),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 10),
                adminToggle,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              adminToggle,
            ],
          );
        },
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(18)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120C2C54),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
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

  List<TimeEvent> _loadItems(List<TimeEvent> all) {
    Iterable<TimeEvent> it = all;

    if (_onlyAdminEdits) {
      it = it.where((e) => e.source == 'ADMIN' || e.terminalId == 'ADMIN');
    }

    if (_query.isNotEmpty) {
      it = it.where((e) {
        final emp = e.employeeId.toLowerCase();
        final type = e.eventType.toLowerCase();
        final note = (e.note ?? '').toLowerCase();
        final day = DateFormat('yyyy-MM-dd').format(
          DateTime.fromMillisecondsSinceEpoch(e.timestampUtcMs, isUtc: true).toLocal(),
        );
        final hay = '$emp $type $note $day';
        return hay.contains(_query);
      });
    }

    return it.toList();
  }

  Widget _auditRow(TimeEvent e) {
    final local = DateTime.fromMillisecondsSinceEpoch(e.timestampUtcMs, isUtc: true).toLocal();
    final ts = DateFormat('dd.MM.yyyy HH:mm:ss').format(local);

    final emp = e.employeeId;
    final type = e.eventType;
    final src = e.source;
    final term = e.terminalId;
    final note = e.note ?? '';

    return _card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.event_note,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$emp · $type',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                ),
              ),
              Text(
                ts,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Quelle: $src · Terminal: $term',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Text(
                note,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
