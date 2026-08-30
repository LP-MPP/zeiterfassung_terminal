import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/absence_helpers.dart';
import '../../core/constants.dart';
import '../../core/holidays_bw.dart';
import '../../core/rules.dart';
import '../../data/absence.dart';
import '../../data/store.dart';
import '../design_tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/banner.dart';
import '../widgets/logout_countdown_chip.dart';
import '../widgets/metric_chip.dart';
import '../widgets/punch_action_grid.dart';
import '../widgets/status_pill.dart';
import 'idle_clock_screen.dart';

enum _LoginStep { pickEmployee, enterPin }

class PunchScreen extends StatefulWidget {
  const PunchScreen({super.key});

  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> {
  static const _uuid = Uuid();
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

  List<Employee> _activeEmps = const [];
  bool _empsLoaded = false;
  Map<String, String> _presenceMap = const {}; // employeeId → lastEventType
  StreamSubscription? _presenceSub;

  bool _loggedIn = false;
  bool _busy = false;
  String? _savingPunchEventType;
  String? _retryPunchEventType;
  String? _retryPunchRequestId;

  String? _employeeId;
  String? _employeeName;
  String? _sessionId;
  String? _employmentType;

  _LoginStep _loginStep = _LoginStep.pickEmployee;
  String? _selectedEmpId;
  String? _selectedEmpName;

  static const int _pinLen = 4;
  String _pinInput = '';

  String? _lastEventType;

  // Vacation info (loaded after login)
  double? _vacRemaining;
  double? _vacUsed;
  double? _vacPlanned;
  double? _sickDays;
  int? _vacEntitlement;
  int _pendingRequests = 0;

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

  String _mapBackendError(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'permission-denied':
          return 'PIN oder Berechtigung ist ungültig.';
        case 'unavailable':
          return 'Keine Verbindung zum Backend.';
        case 'unauthenticated':
          return 'Nicht authentifiziert. Bitte App neu starten.';
        case 'deadline-exceeded':
          return 'Backend-Timeout. Bitte Verbindung pruefen.';
        case 'resource-exhausted':
          return 'Zu viele Versuche. Bitte kurz warten.';
        case 'failed-precondition':
          return error.message ?? 'Aktion derzeit nicht zulässig.';
        case 'invalid-argument':
          return error.message ?? 'Ungültige Eingabe.';
        case 'already-exists':
          return error.message ??
              'Für diesen Zeitraum besteht bereits ein Eintrag.';
      }
      return error.message ?? 'Backend-Fehler: ${error.code}';
    }
    return 'Unbekannter Backend-Fehler.';
  }

  @override
  void initState() {
    super.initState();
    _loadActiveEmployees();
    _startPresenceListener();

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
  }

  void _startPresenceListener() {
    _presenceSub = FirebaseFirestore.instance
        .collection('employee_state')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final map = <String, String>{};
          for (final doc in snap.docs) {
            final d = doc.data();
            final empId = (d['employeeId'] ?? doc.id).toString();
            final lastEvent = (d['lastEventType'] ?? '').toString();
            if (empId.isNotEmpty && lastEvent.isNotEmpty) {
              map[empId] = lastEvent;
            }
          }
          setState(() => _presenceMap = map);
        });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _autoLogoutTimer?.cancel();
    _presenceSub?.cancel();
    super.dispose();
  }

  Future<void> _loadActiveEmployees() async {
    try {
      final result = await _functions
          .httpsCallable('listActiveEmployeesPublic')
          .call();
      final raw = (result.data is List)
          ? (result.data as List)
          : ((result.data is Map &&
                    (result.data as Map).containsKey('employees'))
                ? ((result.data as Map)['employees'] as List? ?? const [])
                : const []);

      final emps =
          raw
              .whereType<Map>()
              .map(
                (rawEmp) => Employee(
                  id: (rawEmp['id'] ?? '').toString(),
                  name: (rawEmp['name'] ?? '').toString(),
                  pinHash: '',
                  active: (rawEmp['active'] ?? true) == true,
                ),
              )
              .where((e) => e.id.isNotEmpty && e.active)
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));

      if (!mounted) return;
      setState(() {
        _activeEmps = emps;
        _empsLoaded = true;

        if (!_loggedIn && _loginStep == _LoginStep.enterPin) {
          final sel = _normId(_selectedEmpId);
          final ok =
              sel.isNotEmpty && _activeEmps.any((e) => _normId(e.id) == sel);
          if (!ok) {
            _loginStep = _LoginStep.pickEmployee;
            _selectedEmpId = null;
            _selectedEmpName = null;
            _pinInput = '';
            _error = null;
          }
        }
      });
    } catch (e, stackTrace) {
      debugPrint('Backend employee load error: $e');
      debugPrintStack(
        label: 'Backend employee load stack trace',
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _empsLoaded = true;
        _error =
            'Mitarbeiter konnten nicht geladen werden. ${_mapBackendError(e)}';
      });
    }
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

  String _normId(String? id) => (id ?? '').trim().toUpperCase();

  void _logout({bool keepBanner = false}) {
    _stopAutoLogoutTimer();
    setState(() {
      _loggedIn = false;
      _busy = false;
      _savingPunchEventType = null;
      _retryPunchEventType = null;
      _retryPunchRequestId = null;

      _employeeId = null;
      _employeeName = null;
      _sessionId = null;
      _employmentType = null;

      _lastEventType = null;
      _clearVacationInfo();

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

  // ── Login flow ──

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
      if (_pinInput.length != _pinLen)
        throw StateError('Bitte $_pinLen-stelligen PIN eingeben.');

      final id = _normId(_selectedEmpId);
      final emp = _activeEmps
          .where((e) => _normId(e.id) == id)
          .cast<Employee?>()
          .firstOrNull;
      if (emp == null)
        throw StateError('Mitarbeiter nicht gefunden oder inaktiv.');

      final result = await _functions
          .httpsCallable('authenticateEmployeePin')
          .call({
            'employeeId': id,
            'pin': _pinInput.trim(),
            'terminalId': terminalId,
          });

      final data = Map<String, dynamic>.from((result.data as Map?) ?? const {});
      final sessionId = data['sessionId']?.toString();
      final lastEventType = data['lastEventType']?.toString();
      if (sessionId == null || sessionId.isEmpty) {
        throw StateError('Login konnte nicht bestätigt werden.');
      }

      final loggedInEmpId = data['employeeId']?.toString() ?? _normId(id);
      setState(() {
        _loggedIn = true;
        _employeeId = loggedInEmpId;
        _employeeName = data['employeeName']?.toString() ?? emp.name;
        _sessionId = sessionId;
        _employmentType =
            data['employmentType']?.toString() ?? 'FESTANSTELLUNG';
        _lastEventType = lastEventType;

        _loginStep = _LoginStep.pickEmployee;
        _selectedEmpId = null;
        _selectedEmpName = null;
        _pinInput = '';

        _idle = false;
        _lastInteractionLocal = DateTime.now();
      });

      _startAutoLogoutTimer();
      _loadVacationInfo();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is StateError) {
          _error = e
              .toString()
              .replaceFirst('StateError: ', '')
              .replaceFirst('Bad state: ', '');
        } else {
          _error = _mapBackendError(e);
        }
        _pinInput = '';
      });
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  // ── Vacation info ──

  Future<void> _loadVacationInfo() async {
    try {
      final year = DateTime.now().year;
      final result = await _functions
          .httpsCallable('getEmployeeVacationOverview')
          .call({
            'sessionId': _sessionId,
            'terminalId': terminalId,
            'year': year,
          });
      final data = Map<String, dynamic>.from((result.data as Map?) ?? const {});
      final balance = Map<String, dynamic>.from(
        (data['balance'] as Map?) ?? const {},
      );
      final absences = (data['absences'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _vacRemaining = (balance['remaining'] ?? 0).toDouble();
        _vacUsed = (balance['used'] ?? 0).toDouble();
        _vacPlanned = (balance['planned'] ?? 0).toDouble();
        _sickDays = (balance['sickDays'] ?? 0).toDouble();
        _vacEntitlement = (balance['entitlement'] ?? 25).toInt();
        _pendingRequests = absences
            .where((a) => a is Map && a['status'] == AbsenceStatus.pending)
            .length;
      });
    } catch (e) {
      debugPrint('Could not load vacation info: $e');
      if (!mounted) return;
      setState(() {
        _vacRemaining = 25;
        _vacUsed = 0;
        _vacPlanned = 0;
        _sickDays = 0;
        _vacEntitlement = 25;
      });
    }
  }

  void _clearVacationInfo() {
    _vacRemaining = null;
    _vacUsed = null;
    _vacPlanned = null;
    _sickDays = null;
    _vacEntitlement = null;
    _pendingRequests = 0;
  }

  // ── Punch ──

  Future<String?> _askForActivityNote() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Was hast du heute gemacht?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Die Angabe ist optional und wird zusammen mit dem Auschecken gespeichert.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Tätigkeit (optional)',
                hintText: 'z. B. Bestellungen verpackt und Lager aufgeräumt',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            icon: const Icon(Icons.logout),
            label: const Text('Auschecken'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _handlePunch(String eventType) async {
    if (_busy) return;
    if (eventType == 'OUT' && _employmentType == 'MINIJOB') {
      final note = await _askForActivityNote();
      if (note == null || !mounted) return;
      await _punch(eventType, note: note);
      return;
    }
    await _punch(eventType);
  }

  Future<void> _punch(String eventType, {String? note}) async {
    if (_busy || _employeeId == null || _sessionId == null) return;

    final requestId =
        _retryPunchEventType == eventType && _retryPunchRequestId != null
        ? _retryPunchRequestId!
        : _uuid.v4();
    _retryPunchEventType = eventType;
    _retryPunchRequestId = requestId;

    setState(() {
      _busy = true;
      _savingPunchEventType = eventType;
      _error = null;
      _success = null;
      _successUntil = null;
    });

    try {
      final result = await _functions.httpsCallable('createPunchEvent').call({
        'sessionId': _sessionId,
        'eventType': eventType,
        'terminalId': terminalId,
        'requestId': requestId,
        if (note != null) 'note': note,
      });

      final data = Map<String, dynamic>.from((result.data as Map?) ?? const {});
      final utcMs = (data['timestampUtcMs'] is int)
          ? data['timestampUtcMs'] as int
          : int.tryParse((data['timestampUtcMs'] ?? '').toString());
      if (utcMs == null) {
        throw StateError('Zeitstempel konnte nicht gelesen werden.');
      }

      final local = DateTime.fromMillisecondsSinceEpoch(
        utcMs,
        isUtc: true,
      ).toLocal();
      final t = DateFormat('HH:mm:ss').format(local);

      setState(() {
        _success = '${eventLabel(eventType)} · $t';
        _successUntil = DateTime.now().add(const Duration(seconds: 4));
        _retryPunchEventType = null;
        _retryPunchRequestId = null;
      });

      _logout(keepBanner: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is StateError) {
          _error = e
              .toString()
              .replaceFirst('StateError: ', '')
              .replaceFirst('Bad state: ', '');
        } else {
          _error = _mapBackendError(e);
        }
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _savingPunchEventType = null;
      });
    }
  }

  // ── PIN keypad ──

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

  // ── Glow color for current state ──

  Color? _currentGlowColor() {
    final state = stateFromLastEvent(_lastEventType);
    switch (state) {
      case WorkState.working:
        return AppTokens.stateWorkingGlow;
      case WorkState.onBreak:
        return AppTokens.stateBreakGlow;
      case WorkState.off:
        return null;
    }
  }

  Color _gradientTopColor() {
    final state = stateFromLastEvent(_lastEventType);
    switch (state) {
      case WorkState.working:
        return AppTokens.stateWorkingGlow.withValues(alpha: 0.10);
      case WorkState.onBreak:
        return AppTokens.stateBreakGlow.withValues(alpha: 0.10);
      case WorkState.off:
        return AppTokens.primary.withValues(alpha: 0.08);
    }
  }

  StatusPill _statusPillForState() {
    final state = stateFromLastEvent(_lastEventType);
    switch (state) {
      case WorkState.working:
        return StatusPill.success('Arbeitet', icon: Icons.circle);
      case WorkState.onBreak:
        return StatusPill.warning('Pause', icon: Icons.pause_circle);
      case WorkState.off:
        return StatusPill.neutral('Nicht eingestempelt');
    }
  }

  // ── Terminal header ──

  Widget _terminalHeader(bool compact) {
    final time = DateFormat('HH:mm').format(_now);
    final date = DateFormat('EEE, dd.MM.yyyy', 'de_DE').format(_now);

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                time,
                style: TextStyle(
                  fontSize: compact ? 64 : 78,
                  fontWeight: FontWeight.w900,
                  letterSpacing: compact ? -1.8 : -2.4,
                  height: 0.95,
                  fontFamily: 'monospace',
                  color: AppTokens.onSurface,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.sm),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Terminal: $terminalId',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTokens.onSurfaceFaint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hideAppBarForSpace =
        mq.size.height < 780 || mq.orientation == Orientation.landscape;
    final headerCompact =
        mq.size.height < 720 || mq.orientation == Orientation.landscape;

    final state = stateFromLastEvent(_lastEventType);
    final canPunchIn = isAllowed(state, 'IN');
    final canPunchOut = isAllowed(state, 'OUT');
    final canBreakStart = isAllowed(state, 'BREAK_START');
    final canBreakEnd = isAllowed(state, 'BREAK_END');

    return MediaQuery(
      data: mq.copyWith(textScaler: const TextScaler.linear(1.0)),
      child: Scaffold(
        appBar: (_idle || hideAppBarForSpace)
            ? null
            : AppBar(title: const Text('Terminal')),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _loggedIn
                    ? _gradientTopColor()
                    : AppTokens.primary.withValues(alpha: 0.08),
                AppTokens.surface,
                AppTokens.surface,
              ],
            ),
          ),
          child: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _touch,
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          14,
                          hideAppBarForSpace ? 8 : 14,
                          14,
                          12,
                        ),
                        child: Column(
                          children: [
                            AppCard(
                              padding: EdgeInsets.fromLTRB(
                                14,
                                headerCompact ? 8 : 12,
                                14,
                                headerCompact ? 8 : 10,
                              ),
                              child: _terminalHeader(headerCompact),
                            ),
                            const SizedBox(height: AppTokens.sm),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: _loggedIn
                                    ? _buildPunchUI(
                                        canPunchIn,
                                        canPunchOut,
                                        canBreakStart,
                                        canBreakEnd,
                                      )
                                    : _buildLoginUI(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Idle overlay
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

  // ── Employee picker ──

  Widget _employeePickerGrid() {
    final emps = _activeEmps;

    if (!_empsLoaded) {
      return const AppCard(child: Center(child: CircularProgressIndicator()));
    }

    if (emps.isEmpty && _error != null) {
      return AppCard(
        child: InfoBanner(text: _error!, kind: BannerKind.error),
      );
    }

    if (emps.isEmpty) {
      return const AppCard(
        child: InfoBanner(
          text: 'Keine aktiven Mitarbeiter. Bitte im Admin-Bereich aktivieren.',
          kind: BannerKind.error,
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Mitarbeiter auswählen',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: AppTokens.md),
          if (_success != null) ...[
            InfoBanner(text: _success!, kind: BannerKind.success),
            const SizedBox(height: AppTokens.sm),
          ],
          if (_error != null) ...[
            InfoBanner(text: _error!, kind: BannerKind.error),
            const SizedBox(height: AppTokens.sm),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final cols = w < 520 ? 2 : (w < 820 ? 3 : 4);

                return GridView.count(
                  crossAxisCount: cols,
                  physics: const BouncingScrollPhysics(),
                  crossAxisSpacing: AppTokens.sm,
                  mainAxisSpacing: AppTokens.sm,
                  childAspectRatio: c.maxHeight < 420 ? 2.4 : 1.9,
                  children: emps.map(_employeeGridTile).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _presenceDotColorFor(String empId) {
    final lastEvent = _presenceMap[empId];
    if (lastEvent == null) return AppTokens.errorFg;
    switch (lastEvent) {
      case 'IN':
      case 'BREAK_END':
        return AppTokens.successFg;
      case 'BREAK_START':
        return AppTokens.warningFg;
      case 'OUT':
      default:
        return AppTokens.errorFg;
    }
  }

  Widget _employeeGridTile(Employee e) {
    final avatarColor = AppTokens.avatarColorFor(e.id);
    final initials = AppTokens.initialsFor(e.name);

    return InkWell(
      borderRadius: AppTokens.borderRadiusLg,
      onTap: _busy ? null : () => _chooseEmployee(e),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.md,
          vertical: AppTokens.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: AppTokens.borderRadiusLg,
          color: AppTokens.surfaceCard,
          border: Border.all(color: AppTokens.outlineLight),
        ),
        child: Row(
          children: [
            // Round avatar with presence dot
            Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: avatarColor.withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: avatarColor,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _presenceDotColorFor(e.id),
                      border: Border.all(
                        color: AppTokens.surfaceCard,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppTokens.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: AppTokens.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: AppTokens.borderRadiusPill,
                      color: AppTokens.primaryLight,
                    ),
                    child: Text(
                      e.id,
                      style: const TextStyle(
                        color: AppTokens.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PIN entry ──

  Widget _pinEntry() {
    final compact = _isCompact(context);

    return KeyedSubtree(
      key: const ValueKey('pin'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final veryTightHeight = constraints.maxHeight < 430;
          final topGap = veryTightHeight ? 6.0 : (compact ? 10.0 : 14.0);
          final midGap = veryTightHeight ? 6.0 : (compact ? 8.0 : 10.0);

          return AppCard(
            padding: EdgeInsets.all(compact ? 14 : AppTokens.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _selectedEmpName ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: AppTokens.xs),
                Text(
                  _selectedEmpId ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTokens.onSurfaceMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: topGap),

                _pinDisplay(compact: compact),
                SizedBox(height: midGap),

                if (_error != null)
                  InfoBanner(text: _error!, kind: BannerKind.error),

                SizedBox(height: midGap),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, keypadConstraints) {
                      return _pinKeypad4(
                        compact: compact,
                        maxHeight: keypadConstraints.maxHeight,
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppTokens.sm),

                SizedBox(
                  height: compact ? 44 : 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _busy ? null : _backToEmployeePick,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text(
                      'Zurück',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pinKeypad4({required bool compact, required double maxHeight}) {
    final targetBtnH = compact ? 54.0 : 60.0;
    final minBtnH = compact ? 38.0 : 42.0;
    final targetGap = compact ? 8.0 : 10.0;

    final computedBtnH = ((maxHeight - (targetGap * 3)) / 4).clamp(
      minBtnH,
      targetBtnH,
    );
    final btnH = computedBtnH.toDouble();
    final gap = ((maxHeight - (btnH * 4)) / 3).clamp(4.0, targetGap).toDouble();

    return LayoutBuilder(
      builder: (context, c) {
        final btnW = ((c.maxWidth - (gap * 2)) / 3)
            .clamp(76.0, 108.0)
            .toDouble();

        Widget key(
          String label, {
          VoidCallback? onTap,
          IconData? icon,
          bool outlined = false,
        }) {
          final child = icon != null
              ? Icon(icon, size: compact ? 20 : 22)
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 20 : 22,
                    fontWeight: FontWeight.w900,
                  ),
                );

          final commonStyle = ButtonStyle(
            minimumSize: WidgetStateProperty.all(Size(btnW, btnH)),
            padding: WidgetStateProperty.all(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );

          final btn = outlined
              ? OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(btnW, btnH),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _busy ? null : onTap,
                  child: child,
                )
              : FilledButton.tonal(
                  style: commonStyle,
                  onPressed: _busy ? null : onTap,
                  child: child,
                );

          return SizedBox(width: btnW, height: btnH, child: btn);
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                key('1', onTap: () => _pinAppend('1')),
                SizedBox(width: gap),
                key('2', onTap: () => _pinAppend('2')),
                SizedBox(width: gap),
                key('3', onTap: () => _pinAppend('3')),
              ],
            ),
            SizedBox(height: gap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                key('4', onTap: () => _pinAppend('4')),
                SizedBox(width: gap),
                key('5', onTap: () => _pinAppend('5')),
                SizedBox(width: gap),
                key('6', onTap: () => _pinAppend('6')),
              ],
            ),
            SizedBox(height: gap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                key('7', onTap: () => _pinAppend('7')),
                SizedBox(width: gap),
                key('8', onTap: () => _pinAppend('8')),
                SizedBox(width: gap),
                key('9', onTap: () => _pinAppend('9')),
              ],
            ),
            SizedBox(height: gap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                key('C', onTap: _pinClear, outlined: true),
                SizedBox(width: gap),
                key('0', onTap: () => _pinAppend('0')),
                SizedBox(width: gap),
                key(
                  '',
                  onTap: _pinBackspace,
                  icon: Icons.backspace_outlined,
                  outlined: true,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _pinDisplay({required bool compact}) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 12 : 14,
        horizontal: 14,
      ),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusLg,
        color: AppTokens.surfaceCard,
        border: Border.all(color: AppTokens.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLen, (i) {
          final filled = i < _pinInput.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            margin: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
            width: filled ? (compact ? 18 : 20) : (compact ? 14 : 16),
            height: filled ? (compact ? 18 : 20) : (compact ? 14 : 16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? AppTokens.primary : Colors.transparent,
              border: Border.all(
                color: filled ? AppTokens.primary : AppTokens.outline,
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Punch UI ──

  Widget _buildPunchUI(
    bool canPunchIn,
    bool canPunchOut,
    bool canBreakStart,
    bool canBreakEnd,
  ) {
    final compact = _isCompact(context);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final dense = compact || landscape;
    final secs = _secondsToLogout();
    final glowColor = _currentGlowColor();

    return AppCard(
      padding: EdgeInsets.all(dense ? 10 : AppTokens.lg),
      glowColor: glowColor,
      glowOpacity: 0.18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: dense
                    ? Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${_employeeName ?? ''} (${_employeeId ?? ''})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTokens.sm),
                          _statusPillForState(),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_employeeName ?? ''} (${_employeeId ?? ''})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: AppTokens.xs),
                          _statusPillForState(),
                        ],
                      ),
              ),
              const SizedBox(width: AppTokens.sm),
              LogoutCountdownChip(seconds: secs),
            ],
          ),
          SizedBox(height: dense ? AppTokens.xs : AppTokens.sm),

          // Vacation info bar
          if (_vacRemaining != null) _vacationInfoBar(dense: dense),
          if (_vacRemaining != null)
            SizedBox(height: dense ? AppTokens.xs : AppTokens.sm),

          // Warnings
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
              return InfoBanner(
                text: warn,
                kind: BannerKind.error,
                dense: dense,
              );
            },
          ),

          SizedBox(height: dense ? AppTokens.xs : AppTokens.sm),

          if (_success != null)
            InfoBanner(text: _success!, kind: BannerKind.success, dense: dense),
          if (_error != null)
            InfoBanner(text: _error!, kind: BannerKind.error, dense: dense),
          SizedBox(height: dense ? AppTokens.xs : AppTokens.sm),

          Expanded(
            child: PunchActionGrid(
              canPunchIn: canPunchIn,
              canPunchOut: canPunchOut,
              canBreakStart: canBreakStart,
              canBreakEnd: canBreakEnd,
              busy: _busy,
              pendingEventType: _savingPunchEventType,
              compact: dense,
              onPunchIn: () {
                _touch();
                _handlePunch('IN');
              },
              onPunchOut: () {
                _touch();
                _handlePunch('OUT');
              },
              onBreakStart: () {
                _touch();
                _handlePunch('BREAK_START');
              },
              onBreakEnd: () {
                _touch();
                _handlePunch('BREAK_END');
              },
            ),
          ),
          SizedBox(height: dense ? 6 : AppTokens.md),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: dense ? 38 : 44,
                  child: OutlinedButton.icon(
                    style: _compactOutlinedActionStyle(dense),
                    onPressed: _busy ? null : _showAbsenceOverview,
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: Text(
                      'Urlaub Übersicht',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: dense ? 12 : 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.sm),
              Expanded(
                child: SizedBox(
                  height: dense ? 38 : 44,
                  child: OutlinedButton.icon(
                    style: _compactOutlinedActionStyle(dense),
                    onPressed: _busy ? null : _showVacationRequest,
                    icon: const Icon(Icons.event_busy, size: 18),
                    label: Text(
                      'Urlaub beantragen',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: dense ? 12 : 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.sm),
              SizedBox(
                height: dense ? 38 : 44,
                child: OutlinedButton.icon(
                  style: _compactOutlinedActionStyle(dense),
                  onPressed: _busy ? null : _showChangePinDialog,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: Text(
                    'PIN',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: dense ? 12 : 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: dense ? 6 : AppTokens.md),
          SizedBox(
            width: double.infinity,
            height: dense ? 38 : 44,
            child: FilledButton.icon(
              onPressed: _busy ? null : _logout,
              icon: const Icon(Icons.exit_to_app, size: 18),
              label: Text(
                'Abmelden',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: dense ? 13 : 14,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTokens.onSurface.withValues(alpha: 0.08),
                foregroundColor: AppTokens.onSurface,
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 12 : AppTokens.lg,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _compactOutlinedActionStyle(bool dense) {
    if (!dense) return const ButtonStyle();
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _showAbsenceOverview() async {
    _touch();
    final empId = _employeeId;
    final empName = _employeeName;
    if (empId == null) return;

    final year = DateTime.now().year;
    List<Absence> absences = [];
    double remaining = 0;
    double used = 0;
    double planned = 0;
    double sick = 0;
    double specialLeave = 0;
    int entitlement = 25;
    double carryOver = 0;

    try {
      final result = await _functions
          .httpsCallable('getEmployeeVacationOverview')
          .call({
            'sessionId': _sessionId,
            'terminalId': terminalId,
            'year': year,
          });
      final data = Map<String, dynamic>.from((result.data as Map?) ?? const {});
      final balance = Map<String, dynamic>.from(
        (data['balance'] as Map?) ?? const {},
      );
      final rawAbsences = (data['absences'] as List?) ?? const [];
      absences = rawAbsences.whereType<Map>().map((raw) {
        final map = Map<String, dynamic>.from(raw);
        return Absence.fromMap((map['id'] ?? '').toString(), map);
      }).toList();
      remaining = (balance['remaining'] ?? 0).toDouble();
      used = (balance['used'] ?? 0).toDouble();
      planned = (balance['planned'] ?? 0).toDouble();
      sick = (balance['sickDays'] ?? 0).toDouble();
      specialLeave = (balance['specialLeaveDays'] ?? 0).toDouble();
      entitlement = (balance['entitlement'] ?? 25).toInt();
      carryOver = (balance['carryOver'] ?? 0).toDouble();
    } catch (e) {
      debugPrint('Could not load absences: $e');
    }

    // Filter to current year (overlapping)
    final yearStart = '$year-01-01';
    final yearEnd = '$year-12-31';
    final thisYear = absences.where((a) {
      if (a.endDate.compareTo(yearStart) < 0) return false;
      if (a.startDate.compareTo(yearEnd) > 0) return false;
      return true;
    }).toList();

    // Sort: pending first, then by start date descending
    thisYear.sort((a, b) {
      final aPriority = a.status == AbsenceStatus.pending
          ? 0
          : (a.status == AbsenceStatus.approved ? 1 : 2);
      final bPriority = b.status == AbsenceStatus.pending
          ? 0
          : (b.status == AbsenceStatus.approved ? 1 : 2);
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);
      return b.startDate.compareTo(a.startDate);
    });

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(AppTokens.lg),
          shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Abwesenheiten $year',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              empName ?? empId,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTokens.onSurfaceMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.lg),

                  // Balance summary card
                  _absenceBalanceCard(
                    entitlement: entitlement,
                    carryOver: carryOver,
                    used: used,
                    planned: planned,
                    remaining: remaining,
                    sick: sick,
                    specialLeave: specialLeave,
                  ),
                  const SizedBox(height: AppTokens.lg),

                  // Section title
                  Row(
                    children: [
                      Text(
                        'Eintraege',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTokens.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(width: AppTokens.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: AppTokens.borderRadiusPill,
                          color: AppTokens.primaryLight,
                        ),
                        child: Text(
                          '${thisYear.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppTokens.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.sm),

                  // Absences list
                  Expanded(
                    child: thisYear.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.event_available,
                                  size: 48,
                                  color: AppTokens.onSurfaceFaint,
                                ),
                                const SizedBox(height: AppTokens.sm),
                                Text(
                                  'Keine Abwesenheiten in $year',
                                  style: TextStyle(
                                    color: AppTokens.onSurfaceMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: thisYear.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) => _absenceRow(thisYear[i]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _absenceBalanceCard({
    required int entitlement,
    required double carryOver,
    required double used,
    required double planned,
    required double remaining,
    required double sick,
    required double specialLeave,
  }) {
    final isLow = remaining <= 3;
    final total = entitlement + carryOver;
    final usedFrac = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final plannedFrac = total > 0
        ? (planned / total).clamp(0.0, 1.0 - usedFrac)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppTokens.lg),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusMd,
        color: AppTokens.surfaceCard,
        border: Border.all(color: AppTokens.outlineLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Big remaining number
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatAbsenceDays(remaining),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: isLow ? AppTokens.errorFg : AppTokens.successFg,
                ),
              ),
              const SizedBox(width: AppTokens.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Tage Resturlaub',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.onSurfaceMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.md),

          // Progress bar
          ClipRRect(
            borderRadius: AppTokens.borderRadiusPill,
            child: SizedBox(
              height: 12,
              child: Stack(
                children: [
                  Container(color: AppTokens.neutralBg),
                  FractionallySizedBox(
                    widthFactor: usedFrac + plannedFrac,
                    child: Row(
                      children: [
                        Expanded(
                          flex: (usedFrac * 100).round().clamp(1, 100),
                          child: Container(
                            color: AppTokens.successFg.withValues(alpha: 0.7),
                          ),
                        ),
                        if (plannedFrac > 0)
                          Expanded(
                            flex: (plannedFrac * 100).round().clamp(1, 100),
                            child: Container(
                              color: AppTokens.pendingFg.withValues(alpha: 0.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.md),

          // Metrics
          Wrap(
            spacing: AppTokens.xl,
            runSpacing: AppTokens.sm,
            children: [
              _balanceMetric('Anspruch', '$entitlement', AppTokens.primary),
              if (carryOver > 0)
                _balanceMetric(
                  'Übertrag',
                  '+${formatAbsenceDays(carryOver)}',
                  AppTokens.infoFg,
                ),
              _balanceMetric(
                'Genommen',
                formatAbsenceDays(used),
                AppTokens.successFg,
              ),
              _balanceMetric(
                'Geplant',
                formatAbsenceDays(planned),
                AppTokens.pendingFg,
              ),
              if (sick > 0)
                _balanceMetric(
                  'Krankheitstage',
                  formatAbsenceDays(sick),
                  AppTokens.sickFg,
                ),
              if (specialLeave > 0)
                _balanceMetric(
                  'Sonderurlaub',
                  formatAbsenceDays(specialLeave),
                  AppTokens.specialLeaveFg,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balanceMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTokens.onSurfaceMuted,
          ),
        ),
      ],
    );
  }

  Widget _absenceRow(Absence a) {
    // Type info
    final isVacation = a.type == AbsenceType.urlaub;
    final isSpecialLeave = a.type == AbsenceType.sonderurlaub;
    final typeLabel = AbsenceType.label(a.type);
    final typeBg = isVacation
        ? AppTokens.successBg
        : isSpecialLeave
        ? AppTokens.specialLeaveBg
        : AppTokens.sickBg;
    final typeFg = isVacation
        ? AppTokens.successFg
        : isSpecialLeave
        ? AppTokens.specialLeaveFg
        : AppTokens.sickFg;
    final typeIcon = isVacation
        ? Icons.beach_access
        : isSpecialLeave
        ? Icons.card_giftcard
        : Icons.medical_services;

    // Status pill
    StatusPill statusPill;
    switch (a.status) {
      case AbsenceStatus.approved:
        statusPill = StatusPill.success('Genehmigt');
        break;
      case AbsenceStatus.pending:
        statusPill = StatusPill.warning('Offen');
        break;
      case AbsenceStatus.rejected:
        statusPill = StatusPill.error('Abgelehnt');
        break;
      default:
        statusPill = StatusPill.neutral(AbsenceStatus.label(a.status));
    }

    // Date formatting
    final startParts = a.startDate.split('-');
    final endParts = a.endDate.split('-');
    String dateRange;
    if (startParts.length == 3 && endParts.length == 3) {
      dateRange =
          '${startParts[2]}.${startParts[1]}. – ${endParts[2]}.${endParts[1]}.${endParts[0]}';
    } else {
      dateRange = '${a.startDate} – ${a.endDate}';
    }

    final days = a.vacationDaysConsumed;
    final daysLabel = days == 1.0 ? '1 Tag' : '${formatAbsenceDays(days)} Tage';
    final dayPartLabel =
        a.startDate == a.endDate && a.startDayPart != AbsenceDayPart.full
        ? AbsenceDayPart.label(a.startDayPart)
        : null;

    // Is upcoming?
    final now = DateTime.now();
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final isUpcoming = a.startDate.compareTo(todayKey) > 0;
    final isCurrent =
        a.startDate.compareTo(todayKey) <= 0 &&
        a.endDate.compareTo(todayKey) >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
      child: Row(
        children: [
          // Type icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: typeBg),
            child: Icon(typeIcon, size: 18, color: typeFg),
          ),
          const SizedBox(width: AppTokens.md),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: AppTokens.sm),
                    if (isCurrent)
                      StatusPill.info('Aktuell')
                    else if (isUpcoming)
                      StatusPill.neutral('Kommend'),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  dateRange,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.onSurfaceMuted,
                  ),
                ),
                if (isSpecialLeave &&
                    SpecialLeaveCategory.label(
                      a.specialLeaveCategory,
                    ).isNotEmpty)
                  Text(
                    SpecialLeaveCategory.label(a.specialLeaveCategory),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTokens.specialLeaveFg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (dayPartLabel != null)
                  Text(
                    dayPartLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTokens.onSurfaceMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (a.rejectionReason != null &&
                    a.rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Grund: ${a.rejectionReason}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTokens.errorFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Days count
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                daysLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              statusPill,
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePinDialog() async {
    _touch();
    if (_sessionId == null || _employeeId == null) return;

    String newPin = '';
    String confirmPin = '';
    String? dialogError;
    bool dialogBusy = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              scrollable: true,
              title: const Text('PIN ändern'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Neuen 4-stelligen PIN eingeben:',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTokens.onSurfaceMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppTokens.md),
                    TextField(
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      decoration: InputDecoration(
                        labelText: 'Neuer PIN',
                        border: OutlineInputBorder(
                          borderRadius: AppTokens.borderRadiusMd,
                        ),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      onChanged: (v) => newPin = v.trim(),
                    ),
                    const SizedBox(height: AppTokens.sm),
                    TextField(
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      decoration: InputDecoration(
                        labelText: 'PIN bestätigen',
                        border: OutlineInputBorder(
                          borderRadius: AppTokens.borderRadiusMd,
                        ),
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      onChanged: (v) => confirmPin = v.trim(),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: AppTokens.sm),
                      Text(
                        dialogError!,
                        style: const TextStyle(
                          color: AppTokens.errorFg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (dialogBusy) ...[
                      const SizedBox(height: AppTokens.sm),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: dialogBusy
                      ? null
                      : () => Navigator.of(ctx).pop(false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton.icon(
                  onPressed: dialogBusy
                      ? null
                      : () async {
                          if (newPin.length < 4) {
                            setD(
                              () => dialogError =
                                  'PIN muss mindestens 4 Ziffern haben.',
                            );
                            return;
                          }
                          if (!RegExp(r'^[0-9]{4,8}$').hasMatch(newPin)) {
                            setD(
                              () => dialogError =
                                  'PIN darf nur Ziffern enthalten (4-8 Stellen).',
                            );
                            return;
                          }
                          if (newPin != confirmPin) {
                            setD(
                              () => dialogError = 'PINs stimmen nicht überein.',
                            );
                            return;
                          }

                          setD(() {
                            dialogError = null;
                            dialogBusy = true;
                          });

                          try {
                            await _functions
                                .httpsCallable('changeEmployeePin')
                                .call({
                                  'sessionId': _sessionId,
                                  'terminalId': terminalId,
                                  'newPin': newPin,
                                });
                            if (ctx.mounted) Navigator.of(ctx).pop(true);
                          } catch (e) {
                            setD(() {
                              dialogBusy = false;
                              dialogError = _mapBackendError(e);
                            });
                          }
                        },
                  icon: const Icon(Icons.check),
                  label: const Text('PIN ändern'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      setState(() {
        _success = 'PIN wurde erfolgreich geändert.';
        _successUntil = DateTime.now().add(const Duration(seconds: 5));
        _error = null;
      });
    }
  }

  Future<void> _showVacationRequest() async {
    _touch();
    final empId = _employeeId;
    if (empId == null) return;

    final currentYear = DateTime.now().year;
    final holidays = getPublicHolidaysBW(currentYear).toSet()
      ..addAll(getPublicHolidaysBW(currentYear + 1));

    final remaining = _vacRemaining ?? 25;

    if (!mounted) return;

    DateTimeRange? dateRange;
    String dayPart = AbsenceDayPart.full;
    String? dialogError;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            double workDays = 0;
            if (dateRange != null) {
              final startKey = _dayKeyLocal(dateRange!.start);
              final endKey = _dayKeyLocal(dateRange!.end);
              workDays = calculateAbsenceDays(
                startDate: startKey,
                endDate: endKey,
                holidays: holidays,
                startDayPart: dayPart,
                endDayPart: dayPart,
              );
            }

            return AlertDialog(
              title: const Text('Urlaub beantragen'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () async {
                        _touch();
                        final picked = await showDateRangePicker(
                          context: ctx,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(currentYear + 1, 12, 31),
                          initialDateRange: dateRange,
                          helpText: 'Urlaubszeitraum wählen',
                          saveText: 'Übernehmen',
                          locale: const Locale('de', 'DE'),
                        );
                        if (picked != null) {
                          setD(() {
                            dateRange = picked;
                            if (picked.start != picked.end)
                              dayPart = AbsenceDayPart.full;
                          });
                        }
                      },
                      borderRadius: AppTokens.borderRadiusMd,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppTokens.lg),
                        decoration: BoxDecoration(
                          borderRadius: AppTokens.borderRadiusMd,
                          border: Border.all(color: AppTokens.outline),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range, size: 28),
                            const SizedBox(width: AppTokens.md),
                            Expanded(
                              child: Text(
                                dateRange != null
                                    ? '${_fmtDate(dateRange!.start)} – ${_fmtDate(dateRange!.end)}'
                                    : 'Zeitraum wählen...',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: dateRange != null
                                      ? null
                                      : AppTokens.onSurfaceFaint,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (dateRange != null) ...[
                      const SizedBox(height: AppTokens.md),
                      if (_dayKeyLocal(dateRange!.start) ==
                          _dayKeyLocal(dateRange!.end)) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Umfang',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTokens.onSurfaceMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTokens.sm),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: AbsenceDayPart.full,
                              label: Text('Ganzer Tag'),
                            ),
                            ButtonSegment(
                              value: AbsenceDayPart.morning,
                              label: Text('Vormittag'),
                            ),
                            ButtonSegment(
                              value: AbsenceDayPart.afternoon,
                              label: Text('Nachmittag'),
                            ),
                          ],
                          selected: {dayPart},
                          onSelectionChanged: (selection) =>
                              setD(() => dayPart = selection.first),
                        ),
                        const SizedBox(height: AppTokens.md),
                      ],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppTokens.md),
                        decoration: BoxDecoration(
                          borderRadius: AppTokens.borderRadiusMd,
                          color: AppTokens.neutralBg,
                        ),
                        child: Wrap(
                          spacing: AppTokens.lg,
                          runSpacing: AppTokens.sm,
                          children: [
                            MetricChip(
                              label: 'Arbeitstage',
                              value: formatAbsenceDays(workDays),
                              valueColor: AppTokens.primary,
                            ),
                            MetricChip(
                              label: 'Resturlaub',
                              value: formatAbsenceDays(remaining.toDouble()),
                              valueColor: remaining < workDays
                                  ? AppTokens.errorFg
                                  : AppTokens.successFg,
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (dialogError != null) ...[
                      const SizedBox(height: AppTokens.sm),
                      Text(
                        dialogError!,
                        style: const TextStyle(
                          color: AppTokens.errorFg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (dateRange == null) {
                      setD(() => dialogError = 'Bitte einen Zeitraum wählen.');
                      return;
                    }
                    if (workDays <= 0) {
                      setD(
                        () => dialogError = 'Keine Arbeitstage im Zeitraum.',
                      );
                      return;
                    }
                    Navigator.of(ctx).pop(true);
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('Antrag senden'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || dateRange == null) return;

    try {
      final startKey = _dayKeyLocal(dateRange!.start);
      final endKey = _dayKeyLocal(dateRange!.end);
      final workDays = calculateAbsenceDays(
        startDate: startKey,
        endDate: endKey,
        holidays: holidays,
        startDayPart: dayPart,
        endDayPart: dayPart,
      );

      await _functions.httpsCallable('createEmployeeVacationRequest').call({
        'sessionId': _sessionId,
        'terminalId': terminalId,
        'startDate': startKey,
        'endDate': endKey,
        'startDayPart': dayPart,
        'endDayPart': dayPart,
      });

      if (!mounted) return;
      _logout(keepBanner: true);
      setState(() {
        _success =
            'Urlaubsantrag über ${formatAbsenceDays(workDays)} Tage eingereicht. Wartet auf Genehmigung.';
        _successUntil = DateTime.now().add(const Duration(seconds: 6));
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Urlaubsantrag fehlgeschlagen: ${_mapBackendError(e)}';
        _success = null;
      });
    }
  }

  static String _dayKeyLocal(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Widget _vacationInfoBar({bool dense = false}) {
    final remaining = _vacRemaining ?? 0;
    final used = _vacUsed ?? 0;
    final planned = _vacPlanned ?? 0;
    final sick = _sickDays ?? 0;
    final entitlement = _vacEntitlement ?? 25;
    final year = DateTime.now().year;

    final isLow = remaining <= 3;
    final usedFrac = entitlement > 0
        ? (used / entitlement).clamp(0.0, 1.0)
        : 0.0;
    final plannedFrac = entitlement > 0
        ? (planned / entitlement).clamp(0.0, 1.0 - usedFrac)
        : 0.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dense ? 8 : AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusMd,
        color: AppTokens.surfaceCard,
        border: Border.all(color: AppTokens.outlineLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                Icons.beach_access,
                size: 18,
                color: AppTokens.onSurfaceMuted,
              ),
              const SizedBox(width: AppTokens.sm),
              Text(
                'Urlaubsübersicht $year',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.onSurfaceMuted,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  borderRadius: AppTokens.borderRadiusPill,
                  color: isLow ? AppTokens.errorBg : AppTokens.successBg,
                  border: Border.all(
                    color: isLow
                        ? AppTokens.errorBorder
                        : AppTokens.successBorder,
                  ),
                ),
                child: Text(
                  '${formatAbsenceDays(remaining)} Tage Rest',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: isLow ? AppTokens.errorFg : AppTokens.successFg,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: dense ? 5 : AppTokens.sm),

          // Progress bar
          ClipRRect(
            borderRadius: AppTokens.borderRadiusPill,
            child: SizedBox(
              height: dense ? 7 : 10,
              child: Stack(
                children: [
                  // Background
                  Container(color: AppTokens.neutralBg),
                  // Used (green)
                  FractionallySizedBox(
                    widthFactor: usedFrac + plannedFrac,
                    child: Row(
                      children: [
                        Expanded(
                          flex: (usedFrac * 100).round().clamp(0, 100),
                          child: Container(
                            color: AppTokens.successFg.withValues(alpha: 0.7),
                          ),
                        ),
                        if (plannedFrac > 0)
                          Expanded(
                            flex: (plannedFrac * 100).round().clamp(0, 100),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTokens.pendingFg.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: dense ? 5 : AppTokens.sm),

          // Metrics row
          Wrap(
            spacing: dense ? AppTokens.md : AppTokens.lg,
            runSpacing: dense ? 2 : AppTokens.xs,
            children: [
              MetricChip(
                label: 'Anspruch',
                value: '$entitlement',
                valueColor: AppTokens.primary,
              ),
              MetricChip(
                label: 'Genommen',
                value: formatAbsenceDays(used),
                valueColor: AppTokens.successFg,
              ),
              MetricChip(
                label: 'Geplant',
                value: formatAbsenceDays(planned),
                valueColor: AppTokens.pendingFg,
              ),
              if (sick > 0)
                MetricChip(
                  label: 'Krank',
                  value: formatAbsenceDays(sick),
                  valueColor: AppTokens.sickFg,
                ),
              if (_pendingRequests > 0)
                MetricChip(
                  label: 'Offene Antraege',
                  value: '$_pendingRequests',
                  valueColor: AppTokens.infoFg,
                ),
            ],
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
