import 'dart:async';

import 'package:flipperlib/flipperlib.dart';

import '../connection/known_devices.dart';
import '../logging.dart';

/// The bare link a home-screen widget needs: the last remembered BLE device,
/// connected and answering a ping. Nothing else is requested — no device
/// info, no battery, no archive — so the file goes out as soon as the radio
/// is up. When the app is opened later, the device page finds the live
/// session and fills in the rest.
class ColdLink {
  ColdLink._();

  static final ColdLink instance = ColdLink._();

  static const Duration _connectingWait = Duration(seconds: 15);
  static const Duration _scanTimeout = Duration(seconds: 8);

  Future<bool>? _inFlight;

  Future<bool> ensureConnected(FlipperClient client) {
    if (client.isConnected) return Future.value(true);
    return _inFlight ??= _connect(client).whenComplete(() => _inFlight = null);
  }

  Future<bool> _connect(FlipperClient client) async {
    if (client.isConnecting) {
      return _awaitConnected(client);
    }

    final known = KnownDevicesStore.instance;
    await known.load();
    final last = known.lastDevice;
    if (last == null) {
      LogService.log('[ColdLink] no remembered device');
      return false;
    }

    try {
      await client.refreshBleKnown();
    } catch (e) {
      LogService.log('[ColdLink] known refresh failed: $e');
    }
    var device = _find(client, last);
    if (device == null) {
      // The library keeps scanning a while after the first Flipper shows up,
      // to list them all; the widget only wants this one, so the scan ends
      // the moment it appears.
      final seen = client.devicesStream.listen((_) {
        if (_find(client, last) != null) unawaited(client.stopScan());
      });
      try {
        await client.scanBle(timeout: _scanTimeout);
      } catch (e) {
        LogService.log('[ColdLink] scan failed: $e');
      } finally {
        await seen.cancel();
      }
      device = _find(client, last);
    }
    if (device == null) {
      LogService.log('[ColdLink] ${last.name} not found');
      return false;
    }

    try {
      await client.connect(device);
      await client.ping(PingRequest(data: const [0x51, 0x55]));
    } catch (e) {
      LogService.log('[ColdLink] connect failed: $e');
      return false;
    }
    return client.isConnected;
  }

  Future<bool> _awaitConnected(FlipperClient client) async {
    try {
      final state = await client.connectionStream
          .firstWhere((s) => !s.connecting)
          .timeout(_connectingWait);
      return state.connected;
    } catch (_) {
      return client.isConnected;
    }
  }

  FlipperDevice? _find(FlipperClient client, KnownDevice known) {
    for (final device in client.devices) {
      if (known.matches(device)) return device;
    }
    return null;
  }
}
