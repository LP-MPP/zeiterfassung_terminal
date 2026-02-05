import 'package:flutter/material.dart';

class NewEmployeeData {
  final String id;
  final String name;
  final String pin;
  NewEmployeeData(this.id, this.name, this.pin);
}

class NewEmployeeDialog extends StatefulWidget {
  const NewEmployeeDialog({super.key});

  @override
  State<NewEmployeeDialog> createState() => _NewEmployeeDialogState();
}

class _NewEmployeeDialogState extends State<NewEmployeeDialog> {
  final _idCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  String? _err;

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _idCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (id.isEmpty || name.isEmpty || pin.isEmpty) {
      setState(() => _err = 'Bitte alle Felder ausfüllen.');
      return;
    }
    if (!RegExp(r'^E\d{3,}$').hasMatch(id)) {
      setState(() => _err = 'ID-Format z. B. E006.');
      return;
    }
    if (pin.length < 4 || pin.length > 8) {
      setState(() => _err = 'PIN 4–8 Stellen.');
      return;
    }

    Navigator.of(context).pop(NewEmployeeData(id, name, pin));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neuer Mitarbeiter'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _idCtrl,
            decoration: const InputDecoration(
              labelText: 'Mitarbeiter-ID (z. B. E006)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pinCtrl,
            decoration: const InputDecoration(
              labelText: 'PIN (4–8 Stellen)',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
          ),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(onPressed: _submit, child: const Text('Anlegen')),
      ],
    );
  }
}