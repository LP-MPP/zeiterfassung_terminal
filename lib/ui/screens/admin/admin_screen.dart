import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../data/store.dart';
import 'absence_pane.dart';
import 'admin_dashboard.dart';
import 'employee_pane.dart';
import 'month_pane.dart';

enum _DetailTab { zeiterfassung, abwesenheiten }

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _db = FirebaseFirestore.instance;
  String? _selectedEmployeeId;
  _DetailTab _tab = _DetailTab.zeiterfassung;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin-Panel'),
        actions: [
          if (_selectedEmployeeId != null)
            TextButton.icon(
              onPressed: () => setState(() => _selectedEmployeeId = null),
              icon: const Icon(Icons.grid_view),
              label: const Text('Übersicht'),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Abmelden',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('employees').orderBy('id').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Fehler: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final employees = snap.data!.docs.map(Employee.fromDoc).toList();

          // Stream employee presence from employee_state collection
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('employee_state').snapshots(),
            builder: (context, stateSnap) {
              // Build presence map: employeeId → lastEventType
              final presenceMap = <String, String>{};
              if (stateSnap.hasData) {
                for (final doc in stateSnap.data!.docs) {
                  final d = doc.data();
                  final empId = (d['employeeId'] ?? doc.id).toString();
                  final lastEvent = (d['lastEventType'] ?? '').toString();
                  if (empId.isNotEmpty && lastEvent.isNotEmpty) {
                    presenceMap[empId] = lastEvent;
                  }
                }
              }

              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: Employee list
                    SizedBox(
                      width: 300,
                      child: EmployeePane(
                        employees: employees,
                        selectedId: _selectedEmployeeId,
                        presenceMap: presenceMap,
                        onSelect: (id) => setState(() {
                          _selectedEmployeeId = id;
                          _tab = _DetailTab.zeiterfassung;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Right: Detail or overview
                    Expanded(
                      child: _selectedEmployeeId != null
                          ? _buildDetailPane(employees)
                          : AdminDashboard(
                              employees: employees,
                              presenceMap: presenceMap,
                              onSelectEmployee: (id) => setState(() {
                                _selectedEmployeeId = id;
                                _tab = _DetailTab.zeiterfassung;
                              }),
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDetailPane(List<Employee> employees) {
    final emp = employees.firstWhere(
      (e) => e.id == _selectedEmployeeId,
      orElse: () => employees.first,
    );

    return Column(
      children: [
        // Tab toggle
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SegmentedButton<_DetailTab>(
            segments: const [
              ButtonSegment(
                value: _DetailTab.zeiterfassung,
                label: Text('Zeiterfassung'),
                icon: Icon(Icons.access_time),
              ),
              ButtonSegment(
                value: _DetailTab.abwesenheiten,
                label: Text('Abwesenheiten'),
                icon: Icon(Icons.event_busy),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        // Content
        Expanded(
          child: _tab == _DetailTab.zeiterfassung
              ? MonthPane(key: ValueKey('month_$_selectedEmployeeId'), employee: emp)
              : AbsencePane(key: ValueKey('absence_$_selectedEmployeeId'), employee: emp),
        ),
      ],
    );
  }
}
