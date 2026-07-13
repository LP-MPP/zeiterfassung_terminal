import 'package:flutter/material.dart';

import '../../../data/store.dart';
import '../../../ui/design_tokens.dart';
import '../../../ui/widgets/status_pill.dart';
import 'employee_dialog.dart';

class EmployeePane extends StatefulWidget {
  final List<Employee> employees;
  final String? selectedId;
  final Map<String, String> presenceMap; // employeeId → lastEventType
  final ValueChanged<String?> onSelect;

  const EmployeePane({
    super.key,
    required this.employees,
    required this.selectedId,
    required this.presenceMap,
    required this.onSelect,
  });

  @override
  State<EmployeePane> createState() => _EmployeePaneState();
}

class _EmployeePaneState extends State<EmployeePane> {
  String _search = '';

  List<Employee> get _filtered {
    if (_search.isEmpty) return widget.employees;
    final q = _search.toLowerCase();
    return widget.employees.where((e) {
      return e.name.toLowerCase().contains(q) || e.id.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Mitarbeiter',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Bearbeiten',
                  onPressed: (widget.selectedId == null)
                      ? null
                      : () {
                          final e = widget.employees
                              .where((x) => x.id == widget.selectedId)
                              .cast<Employee?>()
                              .firstOrNull;
                          if (e != null) EmployeeDialog.show(context, existing: e);
                        },
                  icon: const Icon(Icons.edit, size: 20),
                ),
                const SizedBox(width: AppTokens.xs),
                IconButton.filled(
                  tooltip: 'Neu anlegen',
                  onPressed: () => EmployeeDialog.show(context),
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.md),

            // Search field
            TextField(
              decoration: InputDecoration(
                hintText: 'Suchen...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: AppTokens.borderRadiusMd),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppTokens.borderRadiusMd,
                  borderSide: const BorderSide(color: AppTokens.outlineLight),
                ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: AppTokens.md),

            // Employee list
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _employeeTile(filtered[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _presenceDotColor(Employee e) {
    if (!e.active) return AppTokens.neutralBorder;
    final lastEvent = widget.presenceMap[e.id];
    if (lastEvent == null) return AppTokens.errorFg;
    switch (lastEvent) {
      case 'IN':
      case 'BREAK_END':
        return AppTokens.successFg; // Arbeitet → grün
      case 'BREAK_START':
        return AppTokens.warningFg; // Pause → orange
      case 'OUT':
      default:
        return AppTokens.errorFg; // Nicht da → rot
    }
  }

  Widget _employeeTile(Employee e) {
    final isSel = e.id == widget.selectedId;
    final avatarColor = AppTokens.avatarColorFor(e.id);
    final initials = AppTokens.initialsFor(e.name);

    return InkWell(
      onTap: () => widget.onSelect(e.id),
      borderRadius: AppTokens.borderRadiusMd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.md, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: AppTokens.borderRadiusMd,
          border: Border(
            left: BorderSide(
              color: isSel ? AppTokens.primary : Colors.transparent,
              width: 3,
            ),
          ),
          color: isSel ? AppTokens.primaryLight : null,
        ),
        child: Row(
          children: [
            // Avatar with presence dot
            Stack(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: avatarColor.withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: avatarColor,
                      ),
                    ),
                  ),
                ),
                // Presence dot (green=working, orange=break, red=absent)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _presenceDotColor(e),
                      border: Border.all(color: AppTokens.surfaceCard, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppTokens.md),

            // Name + ID
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSel ? FontWeight.w900 : FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.id,
                    style: TextStyle(
                      color: AppTokens.onSurfaceMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Status pill
            if (!e.active)
              StatusPill.error('INAKTIV'),
          ],
        ),
      ),
    );
  }
}
