import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../controllers/device.dart';
import '../firmware/directory.dart';
import 'recovery_bundle.dart';
import 'recovery_state.dart';

class RecoveryController extends ChangeNotifier {
  RecoveryController(this._device);

  final DeviceController _device;

  RecoveryState _state = const RecoveryIdle();
  RecoveryState get state => _state;

  bool _busy = false;
  bool get isBusy => _busy;

  StreamSubscription<RecoveryMessage>? _sub;
  bool _disposed = false;

  Future<void> repair({
    required FirmwareParser parser,
    required String channelId,
    String target = 'f7',
  }) async {
    if (_busy) return;
    _busy = true;
    _device.setRecovering(true);
    try {
      if (!DfuUsb.instance.available) {
        throw const RecoveryBundleException(
          'Raw USB recovery is not available on this platform',
        );
      }

      if (_device.isConnected) {
        _set(const RecoveryEnteringDfu());
        await _enterDfu();
      } else if (!DfuUsb.instance.isPresent()) {
        throw const RecoveryBundleException('No device in DFU mode found');
      }

      _set(const RecoveryFetching(0));
      final request = await RecoveryBundle.fetch(
        parser: parser,
        channelId: channelId,
        target: target,
        onProgress: (p) => _set(RecoveryFetching(p)),
      );

      final done = Completer<void>();
      _sub = runRecovery(request).listen(
        (message) {
          switch (message) {
            case RecoveryProgress(:final step, :final percent):
              _set(RecoveryRunning(step, percent));
            case RecoveryLog(:final message):
              LogService.log('[Recovery] $message');
            case RecoveryDone():
              _set(const RecoveryDoneState());
              if (!done.isCompleted) done.complete();
            case RecoveryFailed(:final error):
              _set(RecoveryErrorState(error));
              if (!done.isCompleted) done.complete();
          }
        },
        onError: (Object e) {
          _set(RecoveryErrorState(e.toString()));
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future;
    } catch (e) {
      LogService.log('[Recovery] repair failed: $e');
      _set(RecoveryErrorState(e.toString()));
    } finally {
      await _sub?.cancel();
      _sub = null;
      _busy = false;
      _device.setRecovering(false);
    }
  }

  void reset() {
    if (_busy) return;
    _set(const RecoveryIdle());
  }

  Future<void> _enterDfu() async {
    try {
      await _device.client.reboot(
        RebootRequest(mode: RebootRequest_RebootMode.DFU),
      );
    } catch (e) {
      LogService.log('[Recovery] reboot-to-DFU returned: $e');
    }
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < const Duration(seconds: 20)) {
      if (DfuUsb.instance.isPresent()) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw const RecoveryBundleException('Device did not enter DFU mode');
  }

  void _set(RecoveryState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
