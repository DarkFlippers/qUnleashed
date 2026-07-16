import 'package:flutter/material.dart';

import '../../../components/icon.dart';
import '../../../theme/theme.dart';
import 'package:qunleashed/components/appbar.dart';
import '../../../widgets/notification.dart';
import '../../tools/remote/desktop/page.dart';
import '../models/key.dart';
import 'service.dart';

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
    if (widget.flipperKey.category.launchOnApp) {
      final result = await _service.launchApp(widget.flipperKey);
      if (!mounted) return;
      if (result.error == EmulateError.busy) {
        _openRemoteControlBusy();
        return;
      }
      if (result.isOk) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RemoteControlPage()),
        );
        return;
      }
      setState(() {
        _starting = false;
        _running = false;
        _error = result.error;
      });
      return;
    }

    final result = await _service.start(widget.flipperKey);
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
  }

  void _openRemoteControlBusy() {
    context.showNotification(
      'Device is busy',
      type: QNotificationType.error,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RemoteControlPage()),
    );
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
        return 'Device is not connected';
      case EmulateError.notEmulatable:
        return 'This file type cannot be opened on the device';
      case EmulateError.appStartFailed:
        return 'Could not open the app on the device';
      case EmulateError.loadFileFailed:
        return 'Could not load the file into the app';
      case EmulateError.busy:
        return 'Device is busy';
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
          title: 'Open on device · ${k.category.title}',
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
                if (_running && k.category.rpcHoldToSend) ...[
                  Listener(
                    onPointerDown: (_) => _onSendDown(),
                    onPointerUp: (_) => _onSendUp(),
                    onPointerCancel: (_) => _onSendUp(),
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: Icon(
                        _sending ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                      ),
                      label: Text(_sending ? 'Sending…' : 'Hold to Send'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _sending ? colors.accent : colors.card,
                        foregroundColor:
                            _sending ? colors.onAccent : colors.textPrimary,
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
                    label: const Text('Stop'),
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
                    child: const Text('Close'),
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
              'Opening app on the device...',
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
            'File loaded on the device',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.flipperKey.category.rpcHoldToSend
                ? 'Hold “Send” to transmit.\nStop will close the app.'
                : 'Use the device buttons to run it.\nStop will close the app.',
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
