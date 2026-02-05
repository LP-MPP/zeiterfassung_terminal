import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminPinDialog extends StatefulWidget {
  const AdminPinDialog({super.key});

  @override
  State<AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<AdminPinDialog> {
  final _ctrl = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final pin = _ctrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _err = 'PIN eingeben.');
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('terminal')
          .get();
      final storedPin = doc.data()?['adminPin'] as String?;

      if (!mounted) return;

      if (storedPin == null) {
        setState(() {
          _busy = false;
          _err = 'Admin-PIN nicht konfiguriert (config/terminal.adminPin fehlt).';
        });
        return;
      }

      if (pin == storedPin) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _err = 'Admin-PIN falsch.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = 'Fehler beim Laden der PIN: $e';
      });
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
            enabled: !_busy,
          ),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _check,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('OK'),
        ),
      ],
    );
  }
}
