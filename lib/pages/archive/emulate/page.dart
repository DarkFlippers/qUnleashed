import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../components/icon.dart';
import '../../../components/navigation.dart';
import '../../../theme/theme.dart';
import 'package:qunleashed/components/appbar.dart';
import '../../../components/notification.dart';
import '../../../components/archive/category.dart';
import '../../../components/archive/models/key.dart';
import '../../../services/emulate/service.dart';

class EmulatePage extends StatefulWidget {
  const EmulatePage({super.key, required this.flipperKey});

  final ArchiveKey flipperKey;

  @override
  State<EmulatePage> createState() => _EmulatePageState();
}

class _EmulatePageState extends State<EmulatePage> {
  final EmulateService _service = EmulateService();
  bool _starting = true;
  bool _running = false;
  bool _closing = false;
  bool _sending = false;
  EmulateError? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final k = widget.flipperKey;
    final cat = k.category;
    var method = k.launchMethod;
    if (cat.launch.hasProtocolRules && k.protocol == null) {
      final proto = await _service.fetchProtocol(k);
      if (!mounted) return;
      method = cat.launch.resolve(protocol: proto, meta: k.meta);
    }

    switch (method) {
      case LaunchMethod.app:
        final result = await _service.launchApp(k);
        if (!mounted) return;
        if (result.error == EmulateError.busy) {
          _openRemoteControlBusy();
          return;
        }
        if (result.isOk) {
          openRoute(context, AppRoute.remoteControl, replace: true);
          return;
        }
        setState(() {
          _starting = false;
          _running = false;
          _error = result.error;
        });
      case LaunchMethod.rpc:
        final result = await _service.start(k);
        if (!mounted) return;
        if (result.error == EmulateError.busy) {
          _openRemoteControlBusy();
          return;
        }
        setState(() {
          _starting = false;
          _running = result.isOk;
          _error = result.error;
        });
      case LaunchMethod.none:
        setState(() {
          _starting = false;
          _running = false;
          _error = EmulateError.notEmulatable;
        });
    }
  }

  void _openRemoteControlBusy() {
    context.showNotification(context.l10n.fmDeviceBusy, type: QNotificationType.error);
    openRoute(context, AppRoute.remoteControl, replace: true);
  }

  Future<void> _stopAndClose() async {
    if (_closing) return;
    _closing = true;
    await _service.stop();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _onSendDown() async {
    if (!_running || _closing) return;
    setState(() => _sending = true);
    await _service.sendPress();
  }

  Future<void> _onSendUp() async {
    if (!mounted) {
      await _service.sendRelease();
      return;
    }
    setState(() => _sending = false);
    await _service.sendRelease();
  }

  @override
  void dispose() {
    if (_running) {
      _service.stop();
    }
    super.dispose();
  }

  String _errorMessage(EmulateError? e) {
    switch (e) {
      case EmulateError.notConnected:
        return context.l10n.emuNotConnected;
      case EmulateError.notEmulatable:
        return context.l10n.emuUnsupportedType;
      case EmulateError.appStartFailed:
        return context.l10n.emuAppOpenFailed;
      case EmulateError.loadFileFailed:
        return context.l10n.emuLoadFailed;
      case EmulateError.busy:
        return context.l10n.fmDeviceBusy;
      case null:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final k = widget.flipperKey;

    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _stopAndClose();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: QPageAppBar(
          title: l10n.emuOpenOnDevice(k.category.title),
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      QIconBadge(
                        asset: k.category.asset,
                        color: k.category.color,
                        size: 56,
                        iconSize: 32,
                        borderRadius: 12,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              k.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              k.remotePath,
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(child: _buildStatus(context)),
                if (_running && k.category.holdToSend) ...[
                  Listener(
                    onPointerDown: (_) => _onSendDown(),
                    onPointerUp: (_) => _onSendUp(),
                    onPointerCancel: (_) => _onSendUp(),
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: Icon(
                        _sending
                            ? Icons.wifi_tethering
                            : Icons.wifi_tethering_off,
                      ),
                      label: Text(_sending ? context.l10n.emuSending : context.l10n.emuHoldToSend),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _sending ? colors.accent : colors.card,
                        foregroundColor: _sending
                            ? colors.onAccent
                            : colors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_running)
                  ElevatedButton.icon(
                    onPressed: _stopAndClose,
                    icon: const Icon(Icons.stop),
                    label: Text(context.l10n.emuStop),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.danger,
                      foregroundColor: colors.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.card,
                      foregroundColor: colors.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(context.l10n.commonClose),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final colors = context.appColors;
    if (_starting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colors.accent),
            const SizedBox(height: 16),
            Text(
              context.l10n.emuOpening,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              _errorMessage(_error),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contactless, size: 64, color: colors.accent),
          const SizedBox(height: 16),
          Text(
            context.l10n.emuLoaded,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.flipperKey.category.holdToSend
                ? context.l10n.emuHintHold
                : context.l10n.emuHintButtons,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
