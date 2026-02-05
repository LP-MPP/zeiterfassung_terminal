import 'package:flutter/material.dart';
import '../../core/constants.dart';

class AdminPinDialog extends StatefulWidget {
  const AdminPinDialog({super.key});

  @override
  State<AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<AdminPinDialog> {
  final _ctrl = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _check() {
    final pin = _ctrl.text.trim();
    if (pin == adminPin) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _err = 'Admin-PIN falsch.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Admin'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              labelText: 'Admin-PIN',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _check(),
          ),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
        FilledButton(onPressed: _check, child: const Text('OK')),
      ],
    );
  }
}