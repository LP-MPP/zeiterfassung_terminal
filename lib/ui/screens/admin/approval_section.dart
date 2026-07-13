import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../ui/design_tokens.dart';

class ApprovalSection extends StatefulWidget {
  final String employeeId;
  final DateTime month;

  const ApprovalSection({
    super.key,
    required this.employeeId,
    required this.month,
  });

  @override
  State<ApprovalSection> createState() => _ApprovalSectionState();
}

class _ApprovalSectionState extends State<ApprovalSection> {
  final _db = FirebaseFirestore.instance;
  final _nameCtrl = TextEditingController();
  bool _busy = false;

  String get _yearMonth {
    final y = widget.month.year.toString();
    final m = widget.month.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  String get _docId => '${widget.employeeId}_$_yearMonth';

  DocumentReference<Map<String, dynamic>> get _docRef =>
      _db.collection('month_approvals').doc(_docId);

  CollectionReference<Map<String, dynamic>> get _auditCol =>
      _db.collection('audit');

  Future<void> _approve() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte "Geprueft von" ausfuellen.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      await _docRef.set({
        'employeeId': widget.employeeId,
        'yearMonth': _yearMonth,
        'approvedBy': name,
        'approvedAt': FieldValue.serverTimestamp(),
        'adminUid': adminUid,
      });

      try {
        await _auditCol.add({
          'action': 'MONTH_APPROVED',
          'employeeId': widget.employeeId,
          'yearMonth': _yearMonth,
          'approvedBy': name,
          'adminUid': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    setState(() => _busy = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      await _docRef.delete();

      try {
        await _auditCol.add({
          'action': 'MONTH_APPROVAL_REVOKED',
          'employeeId': widget.employeeId,
          'yearMonth': _yearMonth,
          'adminUid': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      _nameCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _docRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final isApproved = data != null && (data['approvedBy'] ?? '').toString().isNotEmpty;

        if (isApproved) {
          return _buildApproved(data);
        }
        return _buildUnapproved();
      },
    );
  }

  Widget _buildApproved(Map<String, dynamic> data) {
    final approvedBy = data['approvedBy']?.toString() ?? '';
    final approvedAtRaw = data['approvedAt'];
    String approvedAtStr = '—';
    if (approvedAtRaw is Timestamp) {
      approvedAtStr = DateFormat('dd.MM.yyyy').format(approvedAtRaw.toDate());
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusMd,
        color: AppTokens.successBg,
        border: Border.all(color: AppTokens.successBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppTokens.successFg),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Geprueft von: $approvedBy',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppTokens.successFg),
                ),
                const SizedBox(height: 2),
                Text(
                  'Geprueft am: $approvedAtStr',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppTokens.successFg),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _revoke,
            child: const Text('Zurücknehmen'),
          ),
        ],
      ),
    );
  }

  Widget _buildUnapproved() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusMd,
        color: AppTokens.surfaceCard,
        border: Border.all(color: AppTokens.outlineLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Geprueft von',
                hintText: 'Name eingeben',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.md),
          FilledButton.icon(
            onPressed: _busy ? null : _approve,
            icon: const Icon(Icons.check),
            label: const Text('Freigabe erteilen'),
          ),
        ],
      ),
    );
  }
}
