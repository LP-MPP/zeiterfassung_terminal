import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/rules.dart';
import '../../core/security.dart';
import '../../data/store.dart';
import '../widgets/banner.dart';
import '../widgets/clock_header.dart';
import '../widgets/logout_countdown_chip.dart';
import 'idle_clock_screen.dart';

enum _LoginStep { pickEmployee, enterPin }

class PunchScreen extends StatefulWidget {
  const PunchScreen({super.key});

  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> {
  final _store = InMemoryStore.instance;
  final _db = FirebaseFirestore.instance;

  // Employees loaded from Firestore (source of truth for login UI)
  List<Employee> _activeEmps = const [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _empSub;

  bool _loggedIn = false;
  bool _busy = false;

  String? _employeeId;
  String? _employeeName;

  _LoginStep _loginStep = _LoginStep.pickEmployee;
  String? _selectedEmpId;
  String? _selectedEmpName;

  static const int _pinLen = 4;
  String _pinInput = '';

  String? _lastEventType;
  String? _statusText;

  String? _error;
  String? _success;
  DateTime? _successUntil;

  Timer? _autoLogoutTimer;
  DateTime? _autoLogoutAtUtc;
  static const Duration _autoLogoutAfter = Duration(minutes: 2);

  // Idle "Always-On" screen
  bool _idle = false;
  DateTime _lastInteractionLocal = DateTime.now();
  static const Duration _idleAfter = Duration(seconds: 30);

  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _store.init(listenEmployees: false, listenEvents: true);
    // Live clock + idle evaluation
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();

        if (_successUntil != null && DateTime.now().isAfter(_successUntil!)) {
          _success = null;
          _successUntil = null;
        }

        _evaluateIdle();
      });
    });

    // Subscribe active employees from Firestore
    _empSub = _db
        .collection('employees')
        .where('active', isEqualTo: true)
        .snapshots()
        .listen(
      (snap) {
        final emps = snap.docs.map(Employee.fromDoc).toList()
          ..sort((a, b) => a.id.compareTo(b.id));

        if (!mounted) return;
        setState(() {
          _activeEmps = emps;

          // If user is in PIN step and selected employee became inactive/removed
          if (!_loggedIn && _loginStep == _LoginStep.enterPin) {
            final sel = _normId(_selectedEmpId);
            final ok = sel.isNotEmpty && _activeEmps.any((e) => _normId(e.id) == sel);
            if (!ok) {
              _loginStep = _LoginStep.pickEmployee;
              _selectedEmpId = null;
              _selectedEmpName = null;
              _pinInput = '';
              _error = null;
            }
          }
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Mitarbeiter konnten nicht geladen werden (Firestore).';
        });
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _autoLogoutTimer?.cancel();
    _empSub?.cancel();
    super.dispose();
  }

  bool _isCompact(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return h < 820;
  }

  void _markInteraction() {
    _lastInteractionLocal = DateTime.now();
    if (_idle) _idle = false;
  }

  void _evaluateIdle() {
    // Idle only when:
    // - not logged in
    // - in employee picker (not PIN entry)
    // - not busy
    if (_loggedIn) {
      if (_idle) _idle = false;
      return;
    }
    if (_loginStep != _LoginStep.pickEmployee) {
      if (_idle) _idle = false;
      return;
    }
    if (_busy) return;

    final diff = DateTime.now().difference(_lastInteractionLocal);
    final shouldIdle = diff >= _idleAfter;
    if (shouldIdle != _idle) _idle = shouldIdle;
  }

  // -------------------------
  // Auto logout (logged in)
  // -------------------------

  void _startAutoLogoutTimer() {
    _autoLogoutTimer?.cancel();
    _autoLogoutAtUtc = DateTime.now().toUtc().add(_autoLogoutAfter);
    _autoLogoutTimer = Timer(_autoLogoutAfter, () {
      if (!mounted) return;
      _logout();
    });
  }

  void _stopAutoLogoutTimer() {
    _autoLogoutTimer?.cancel();
    _autoLogoutTimer = null;
    _autoLogoutAtUtc = null;
  }

  void _touch() {
    _markInteraction();
    if (_loggedIn) _startAutoLogoutTimer();
  }

  int _secondsToLogout() {
    final at = _autoLogoutAtUtc;
    if (!_loggedIn || at == null) return 0;
    final diff = at.difference(DateTime.now().toUtc());
    return diff.isNegative ? 0 : diff.inSeconds;
  }

  // -------------------------
  // Status
  // -------------------------

  Future<void> _refreshStatus() async {
    if (_employeeId == null) return;
    final last = _store.lastEventType(_employeeId!);
    final state = stateFromLastEvent(last);

    final String status;
    switch (state) {
      case WorkState.off:
        status = 'Nicht eingestempelt';
        break;
      case WorkState.working:
        status = 'Arbeitet';
        break;
      case WorkState.onBreak:
        status = 'Pause';
        break;
    }

    if (!mounted) return;
    setState(() {
      _lastEventType = last;
      _statusText = status;
    });
  }

  String _normId(String? id) => (id ?? '').trim().toUpperCase();

  String _hashPinLocal(String employeeId, String pin) =>
      hashPin(_normId(employeeId), pin.trim());

  void _logout({bool keepBanner = false}) {
    _stopAutoLogoutTimer();
    setState(() {
      _loggedIn = false;
      _busy = false;

      _employeeId = null;
      _employeeName = null;

      _lastEventType = null;
      _statusText = null;

      _error = null;
      if (!keepBanner) {
        _success = null;
        _successUntil = null;
      }

      _loginStep = _LoginStep.pickEmployee;
      _selectedEmpId = null;
      _selectedEmpName = null;
      _pinInput = '';

      _idle = false;
      _lastInteractionLocal = DateTime.now();
    });
  }

  // -------------------------
  // Login flow
  // -------------------------

  void _chooseEmployee(Employee e) {
    _markInteraction();
    setState(() {
      _selectedEmpId = _normId(e.id);
      _selectedEmpName = e.name;
      _pinInput = '';
      _error = null;
      _loginStep = _LoginStep.enterPin;
    });
  }

  void _backToEmployeePick() {
    _markInteraction();
    setState(() {
      _loginStep = _LoginStep.pickEmployee;
      _selectedEmpId = null;
      _selectedEmpName = null;
      _pinInput = '';
      _error = null;
    });
  }

  Future<void> _login() async {
    if (_selectedEmpId == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _successUntil = null;
    });

    try {
      if (_pinInput.length != _pinLen) throw StateError('Bitte $_pinLen-stelligen PIN eingeben.');

      final id = _normId(_selectedEmpId);
      final emp = _activeEmps.where((e) => _normId(e.id) == id).cast<Employee?>().firstOrNull;
      if (emp == null) throw StateError('Mitarbeiter nicht gefunden oder inaktiv.');

      if (emp.pinHash != _hashPinLocal(id, _pinInput)) throw StateError('PIN falsch.');

      setState(() {
        _loggedIn = true;
        _employeeId = _normId(id);
        _employeeName = emp.name;

        _loginStep = _LoginStep.pickEmployee;
        _selectedEmpId = null;
        _selectedEmpName = null;
        _pinInput = '';

        _idle = false;
        _lastInteractionLocal = DateTime.now();
      });

      _startAutoLogoutTimer();
      await _refreshStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('StateError: ', '').replaceFirst('Bad state: ', '');
        _pinInput = '';
      });
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }


  // -------------------------
  // Punch
  // -------------------------

  Future<void> _punch(String eventType) async {
    if (_employeeId == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _successUntil = null;
    });

    try {
      final last = _store.lastEventType(_employeeId!);
      final st = stateFromLastEvent(last);

      if (!isAllowed(st, eventType)) {
        throw StateError('Aktion nicht zulässig (letztes Event: ${last ?? "—"}).');
      }

      final ev = await _store.addEvent(
        employeeId: _employeeId!,
        eventType: eventType,
        terminalId: terminalId,
        source: 'PIN',
      );

      await _refreshStatus();

      final local = DateTime.fromMillisecondsSinceEpoch(ev.timestampUtcMs, isUtc: true).toLocal();
      final t = DateFormat('HH:mm:ss').format(local);

      setState(() {
        _success = '${eventLabel(eventType)} · $t';
        _successUntil = DateTime.now().add(const Duration(seconds: 4));
      });

      // After any successful action, immediately log out back to employee picker.
      _logout(keepBanner: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('StateError: ', '').replaceFirst('Bad state: ', ''));
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  // -------------------------
  // PIN keypad (4-digit + auto login)
  // -------------------------

  void _pinAppend(String digit) {
    if (_busy) return;
    if (_pinInput.length >= _pinLen) return;

    _markInteraction();
    setState(() {
      _error = null;
      _pinInput += digit;
    });

    if (_pinInput.length == _pinLen) {
      Future.microtask(() {
        if (!mounted || _busy) return;
        _login();
      });
    }
  }

  void _pinBackspace() {
    if (_busy) return;
    if (_pinInput.isEmpty) return;
    _markInteraction();
    setState(() {
      _error = null;
      _pinInput = _pinInput.substring(0, _pinInput.length - 1);
    });
  }

  void _pinClear() {
    if (_busy) return;
    _markInteraction();
    setState(() {
      _error = null;
      _pinInput = '';
    });
  }

  // -------------------------
  // UI blocks
  // -------------------------

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
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

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        t,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '•';
    final a = parts[0].isNotEmpty ? parts[0][0] : '';
    final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    final s = (a + b).toUpperCase();
    return s.isEmpty ? '•' : s;
  }

  // -------------------------
  // Build
  // -------------------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    final state = stateFromLastEvent(_lastEventType);
    final canPunchIn = isAllowed(state, 'IN');
    final canPunchOut = isAllowed(state, 'OUT');
    final canBreakStart = isAllowed(state, 'BREAK_START');
    final canBreakEnd = isAllowed(state, 'BREAK_END');

    return MediaQuery(
      data: mq.copyWith(textScaler: const TextScaler.linear(1.0)),
      child: Scaffold(
        appBar: _idle
            ? null
            : AppBar(
          title: const Text('Terminal'),
          // Admin button removed: admin entry is handled by TerminalShell long-press.
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _touch,
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        _card(
                          padding: EdgeInsets.fromLTRB(16, _isCompact(context) ? 12 : 16, 16, 12),
                          child: Column(
                            children: [
                              ClockHeader(nowLocal: _now),
                              const SizedBox(height: 8),
                              Text(
                                'Terminal: $terminalId',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black.withOpacity(0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _loggedIn
                                ? _buildPunchUI(canPunchIn, canPunchOut, canBreakStart, canBreakEnd)
                                : _buildLoginUI(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Idle Overlay (Always-On Look)
              if (_idle)
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: 1.0,
                    child: IdleClockScreen(
                      nowLocal: _now,
                      onWake: () {
                        setState(() {
                          _idle = false;
                          _lastInteractionLocal = DateTime.now();
                        });
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginUI() {
    if (_loginStep == _LoginStep.pickEmployee) {
      return _employeePickerGrid();
    }
    return _pinEntry();
  }

  // -------------------------
  // Employee picker: Grid
  // -------------------------

  Widget _employeePickerGrid() {
    final emps = _activeEmps;

    if (emps.isEmpty) {
      return _card(
        child: InfoBanner(
          text: 'Keine aktiven Mitarbeiter. Bitte im Admin-Bereich aktivieren.',
          kind: BannerKind.error,
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Mitarbeiter auswählen'),
          if (_success != null) ...[
            InfoBanner(text: _success!, kind: BannerKind.success),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            InfoBanner(text: _error!, kind: BannerKind.error),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final cols = w < 520 ? 2 : (w < 820 ? 3 : 4);

                return GridView.count(
                  crossAxisCount: cols,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.9,
                  children: emps.map(_employeeGridTile).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _employeeGridTile(Employee e) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _busy ? null : () => _chooseEmployee(e),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.black.withOpacity(0.04),
              ),
              child: Center(
                child: Text(
                  _initials(e.name),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    e.id,
                    style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.black.withOpacity(0.25)),
          ],
        ),
      ),
    );
  }

  // -------------------------
  // PIN: compact, no login button
  // -------------------------

  Widget _pinEntry() {
    final compact = _isCompact(context);

    return KeyedSubtree(
      key: const ValueKey('pin'),
      child: _card(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _selectedEmpName ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3),
            ),
            const SizedBox(height: 4),
            Text(
              _selectedEmpId ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
            ),
            SizedBox(height: compact ? 10 : 14),

            _pinDisplay(compact: compact),
            SizedBox(height: compact ? 8 : 10),

            if (_error != null) InfoBanner(text: _error!, kind: BannerKind.error),

            SizedBox(height: compact ? 8 : 10),
            Expanded(child: _pinKeypad4(compact: compact)),
            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: _busy ? null : _backToEmployeePick,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Zurück'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinDisplay({required bool compact}) {
    final filled = '●' * _pinInput.length;
    final empty = '○' * (_pinLen - _pinInput.length);
    final show = '$filled$empty';

    return Container(
      padding: EdgeInsets.symmetric(vertical: compact ? 12 : 14, horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: Colors.black.withOpacity(0.10)),
      ),
      child: Text(
        show,
        style: TextStyle(
          fontSize: compact ? 24 : 26,
          fontWeight: FontWeight.w900,
          letterSpacing: compact ? 8 : 10,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _pinKeypad4({required bool compact}) {
    final btnH = compact ? 54.0 : 60.0;
    final gap = compact ? 8.0 : 10.0;

    Widget key(String label, {VoidCallback? onTap, IconData? icon, bool outlined = false}) {
      final child = icon != null
          ? Icon(icon, size: compact ? 20 : 22)
          : Text(label, style: TextStyle(fontSize: compact ? 20 : 22, fontWeight: FontWeight.w900));

      final btn = outlined
          ? OutlinedButton(onPressed: _busy ? null : onTap, child: child)
          : FilledButton.tonal(onPressed: _busy ? null : onTap, child: child);

      return SizedBox(width: 108, height: btnH, child: btn);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          key('1', onTap: () => _pinAppend('1')),
          SizedBox(width: gap),
          key('2', onTap: () => _pinAppend('2')),
          SizedBox(width: gap),
          key('3', onTap: () => _pinAppend('3')),
        ]),
        SizedBox(height: gap),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          key('4', onTap: () => _pinAppend('4')),
          SizedBox(width: gap),
          key('5', onTap: () => _pinAppend('5')),
          SizedBox(width: gap),
          key('6', onTap: () => _pinAppend('6')),
        ]),
        SizedBox(height: gap),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          key('7', onTap: () => _pinAppend('7')),
          SizedBox(width: gap),
          key('8', onTap: () => _pinAppend('8')),
          SizedBox(width: gap),
          key('9', onTap: () => _pinAppend('9')),
        ]),
        SizedBox(height: gap),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          key('C', onTap: _pinClear, outlined: true),
          SizedBox(width: gap),
          key('0', onTap: () => _pinAppend('0')),
          SizedBox(width: gap),
          key('', onTap: _pinBackspace, icon: Icons.backspace_outlined, outlined: true),
        ]),
      ],
    );
  }

  // -------------------------
  // Punch: 2x2 grid
  // -------------------------

  Widget _buildPunchUI(bool canPunchIn, bool canPunchOut, bool canBreakStart, bool canBreakEnd) {
    final compact = _isCompact(context);
    final secs = _secondsToLogout();

    return _card(
      padding: EdgeInsets.all(compact ? 14 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_employeeName ?? ''} (${_employeeId ?? ''})',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                ),
              ),
              LogoutCountdownChip(seconds: secs),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Status: ${_statusText ?? '—'}',
            style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),

          // Point 5: simple warnings based on last event/state
          Builder(
            builder: (_) {
              final s = stateFromLastEvent(_lastEventType);
              String? warn;
              if (s == WorkState.working) {
                warn = 'Hinweis: Eingestempelt (kein Gehen erfasst).';
              } else if (s == WorkState.onBreak) {
                warn = 'Hinweis: Pause läuft (kein Pause Ende erfasst).';
              }
              if (warn == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InfoBanner(text: warn, kind: BannerKind.error),
              );
            },
          ),

          SizedBox(height: compact ? 10 : 12),

          if (_success != null) InfoBanner(text: _success!, kind: BannerKind.success),
          if (_error != null) InfoBanner(text: _error!, kind: BannerKind.error),
          SizedBox(height: compact ? 10 : 12),

          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: compact ? 2.9 : 2.6,
              children: [
                _gridAction(
                  label: 'Kommen',
                  icon: Icons.login,
                  enabled: canPunchIn,
                  compact: compact,
                  onTap: () => _punch('IN'),
                ),
                _gridAction(
                  label: 'Gehen',
                  icon: Icons.logout,
                  enabled: canPunchOut,
                  compact: compact,
                  onTap: () => _punch('OUT'),
                ),
                _gridAction(
                  label: 'Pause Start',
                  icon: Icons.pause,
                  enabled: canBreakStart,
                  compact: compact,
                  onTap: () => _punch('BREAK_START'),
                ),
                _gridAction(
                  label: 'Pause Ende',
                  icon: Icons.play_arrow,
                  enabled: canBreakEnd,
                  compact: compact,
                  onTap: () => _punch('BREAK_END'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridAction({
    required String label,
    required IconData icon,
    required bool enabled,
    required bool compact,
    required VoidCallback onTap,
  }) {
    return FilledButton.tonal(
      onPressed: (_busy || !enabled)
          ? null
          : () {
              _touch();
              onTap();
            },
      style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 10 : 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: compact ? 18 : 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 14 : 15),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
