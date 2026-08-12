import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/design_tokens.dart';
import 'app_update.dart';
import 'app_update_service.dart';

class AppUpdateCoordinator extends StatefulWidget {
  const AppUpdateCoordinator({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppUpdateCoordinator> createState() => _AppUpdateCoordinatorState();
}

class _AppUpdateCoordinatorState extends State<AppUpdateCoordinator>
    with WidgetsBindingObserver {
  final AppUpdateService _service = AppUpdateService();
  Timer? _timer;
  AppUpdate? _available;
  DateTime? _lastCheck;
  bool _checking = false;
  bool _hiddenForSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(hours: 6), (_) => _check());
    Future<void>.delayed(const Duration(seconds: 3), _check);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _service.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastCheck = _lastCheck;
    if (lastCheck == null ||
        DateTime.now().difference(lastCheck) > const Duration(minutes: 15)) {
      _check();
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      final update = await _service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _available = update;
        if (update == null) _hiddenForSession = false;
      });
    } catch (error) {
      debugPrint('Update check skipped: $error');
    } finally {
      _checking = false;
    }
  }

  Future<void> _showUpdateDialog() async {
    final update = _available;
    final context = widget.navigatorKey.currentContext;
    if (update == null || context == null) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !update.mandatory,
      builder: (_) => _UpdateDialog(service: _service, update: update),
    );
  }

  @override
  Widget build(BuildContext context) {
    final update = _available;
    final showBanner = update != null && !_hiddenForSession;

    return Stack(
      children: [
        widget.child,
        if (showBanner)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Material(
                    elevation: 10,
                    color: AppTokens.infoBg,
                    shadowColor: Colors.black26,
                    borderRadius: AppTokens.borderRadiusLg,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTokens.infoBorder),
                        borderRadius: AppTokens.borderRadiusLg,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.system_update_alt_rounded,
                            color: AppTokens.infoFg,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Update ${update.versionName} ist verfügbar',
                              style: const TextStyle(
                                color: AppTokens.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: _showUpdateDialog,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: const Text('Jetzt aktualisieren'),
                          ),
                          if (!update.mandatory)
                            IconButton(
                              tooltip: 'Später',
                              onPressed: () =>
                                  setState(() => _hiddenForSession = true),
                              icon: const Icon(Icons.close_rounded),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.service, required this.update});

  final AppUpdateService service;
  final AppUpdate update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _waitingForPermission = false;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForPermission && !_busy) {
      _downloadAndInstall();
    }
  }

  Future<void> _downloadAndInstall() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final canInstall = await widget.service.canInstallPackages();
      if (!canInstall) {
        _waitingForPermission = true;
        await widget.service.openInstallPermissionSettings();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error =
              'Bitte „Apps aus dieser Quelle zulassen“ aktivieren und danach zurückkehren.';
        });
        return;
      }

      _waitingForPermission = false;
      setState(() => _progress = 0);
      await widget.service.downloadAndInstall(
        widget.update,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
    } on AppUpdateException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Update konnte nicht gestartet werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final percent = progress == null ? null : (progress * 100).round();

    return PopScope(
      canPop: !_busy && !widget.update.mandatory,
      child: AlertDialog(
        icon: const Icon(
          Icons.system_update_alt_rounded,
          color: AppTokens.primary,
          size: 34,
        ),
        title: Text('Update ${widget.update.versionName}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.update.releaseNotes.isEmpty
                    ? 'Eine neue Version der Terminal-App ist verfügbar.'
                    : widget.update.releaseNotes,
              ),
              if (progress != null) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(value: progress == 0 ? null : progress),
                const SizedBox(height: 8),
                Text(
                  progress >= 1
                      ? 'Download geprüft – Android-Installation wird geöffnet …'
                      : 'APK wird heruntergeladen … ${percent ?? 0} %',
                  style: TextStyle(color: AppTokens.onSurfaceMuted),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTokens.errorFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!widget.update.mandatory)
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Später'),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _downloadAndInstall,
            icon: const Icon(Icons.download_rounded),
            label: Text(
              _waitingForPermission ? 'Erneut prüfen' : 'Update laden',
            ),
          ),
        ],
      ),
    );
  }
}
