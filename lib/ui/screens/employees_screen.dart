import 'package:flutter/material.dart';

import '../../core/security.dart';
import '../../data/store.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final _store = InMemoryStore.instance;

  @override
  Widget build(BuildContext context) {
    final emps = _store.listEmployees();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mitarbeiter'),
        actions: [
          IconButton(
            tooltip: 'Neu',
            onPressed: () async {
              final changed = await showDialog<bool>(
                context: context,
                builder: (_) => const _EmployeeEditDialog(mode: _EmployeeEditMode.create),
              );
              if (changed == true && mounted) setState(() {});
            },
            icon: const Icon(Icons.person_add),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                _headerRow(),
                const SizedBox(height: 12),

                if (emps.isEmpty)
                  const _EmptyState()
                else
                  ...emps.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _employeeRow(e),
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerRow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Mitarbeiterverwaltung',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.2),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              final changed = await showDialog<bool>(
                context: context,
                builder: (_) => const _EmployeeEditDialog(mode: _EmployeeEditMode.create),
              );
              if (changed == true && mounted) setState(() {});
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Neu anlegen'),
          ),
        ],
      ),
    );
  }

  Widget _employeeRow(Employee e) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.black.withOpacity(0.04),
            ),
            child: Icon(Icons.person, color: Colors.black.withOpacity(0.55)),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                ),
                const SizedBox(height: 3),
                Text(
                  e.id,
                  style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Active toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.active ? 'Aktiv' : 'Inaktiv',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: e.active ? Colors.black.withOpacity(0.70) : Colors.black.withOpacity(0.40),
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: e.active,
                onChanged: (v) {
                  setState(() => _store.setActive(e.id, v));
                },
              ),
            ],
          ),

          const SizedBox(width: 8),

          // Edit
          OutlinedButton.icon(
            onPressed: () async {
              final changed = await showDialog<bool>(
                context: context,
                builder: (_) => _EmployeeEditDialog(mode: _EmployeeEditMode.edit, employeeId: e.id),
              );
              if (changed == true && mounted) setState(() {});
            },
            icon: const Icon(Icons.edit),
            label: const Text('Bearbeiten'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: const Text(
        'Keine Mitarbeiter vorhanden.\nLege oben rechts einen neuen Mitarbeiter an.',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

enum _EmployeeEditMode { create, edit }

class _EmployeeEditDialog extends StatefulWidget {
  final _EmployeeEditMode mode;
  final String? employeeId;

  const _EmployeeEditDialog({
    required this.mode,
    this.employeeId,
  });

  @override
  State<_EmployeeEditDialog> createState() => _EmployeeEditDialogState();
}

class _EmployeeEditDialogState extends State<_EmployeeEditDialog> {
  final _store = InMemoryStore.instance;

  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  bool _active = true;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();

    if (widget.mode == _EmployeeEditMode.edit) {
      final id = widget.employeeId!;
      final emp = _store.employees[id];
      if (emp != null) {
        _idCtrl.text = emp.id;
        _nameCtrl.text = emp.name;
        _active = emp.active;
      }
      // PIN bleibt leer => unverändert
    }
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  String _normalizeId(String s) => s.trim().toUpperCase();

  bool _isValidId(String id) {
    // akzeptiert E001, E1, MA01 etc. – Hauptsache nicht leer/zu lang
    if (id.isEmpty) return false;
    if (id.length > 16) return false;
    return true;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      if (!_formKey.currentState!.validate()) return;

      final id = _normalizeId(_idCtrl.text);
      final name = _nameCtrl.text.trim();
      final pin = _pinCtrl.text.trim();

      if (widget.mode == _EmployeeEditMode.create) {
        if (pin.isEmpty) {
          setState(() => _err = 'PIN ist erforderlich (bei Neuanlage).');
          return;
        }
        if (_store.employees.containsKey(id)) {
          setState(() => _err = 'ID existiert bereits: $id');
          return;
        }

        _store.upsertEmployee(
          id: id,
          name: name,
          pinHash: hashPin(id, pin),
          active: _active,
        );

        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      // Edit mode
      final existing = _store.employees[id];
      if (existing == null) {
        setState(() => _err = 'Mitarbeiter nicht gefunden.');
        return;
      }

      // Falls ID geändert werden soll: wir erlauben das NICHT stillschweigend
      // (sonst stimmen alte Events nicht mehr). Deshalb: ID Field ist readOnly.
      // -> id ist immer gleich existing.id

      final newHash = pin.isEmpty ? existing.pinHash : hashPin(id, pin);

      _store.upsertEmployee(
        id: id,
        name: name,
        pinHash: newHash,
        active: _active,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.mode == _EmployeeEditMode.create;

    return AlertDialog(
      title: Text(isCreate ? 'Mitarbeiter anlegen' : 'Mitarbeiter bearbeiten'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _idCtrl,
                readOnly: !isCreate, // ID nicht editieren (Events)
                decoration: InputDecoration(
                  labelText: 'ID (z. B. E006)',
                  helperText: isCreate ? 'Eindeutig, wird für Events verwendet.' : 'ID kann nicht geändert werden.',
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) {
                  final id = _normalizeId(v ?? '');
                  if (!_isValidId(id)) return 'Bitte gültige ID eingeben.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return 'Bitte Name eingeben.';
                  if ((v ?? '').trim().length > 40) return 'Name zu lang.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinCtrl,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  helperText: isCreate ? 'Pflichtfeld (z. B. 1234).' : 'Leer lassen = PIN unverändert.',
                ),
                keyboardType: TextInputType.number,
                obscureText: true,
                validator: (v) {
                  final pin = (v ?? '').trim();
                  if (isCreate && pin.isEmpty) return 'PIN ist erforderlich.';
                  if (pin.isNotEmpty && (pin.length < 4 || pin.length > 8)) {
                    return 'PIN: 4–8 Ziffern.';
                  }
                  if (pin.isNotEmpty && !RegExp(r'^\d+$').hasMatch(pin)) {
                    return 'PIN darf nur Ziffern enthalten.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Aktiv', style: TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Switch(
                    value: _active,
                    onChanged: _busy ? null : (v) => setState(() => _active = v),
                  ),
                ],
              ),
              if (_err != null) ...[
                const SizedBox(height: 8),
                Text(_err!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(isCreate ? 'Anlegen' : 'Speichern'),
        ),
      ],
    );
  }
}