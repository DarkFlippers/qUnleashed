import 'dart:async';

import 'package:flipperlib/flipperlib.dart';

import '../connection/known_devices.dart';
import '../logging.dart';

/// The bare link a home-screen widget needs: the last remembered BLE device,
/// dialled straight by its address and answering a ping. Nothing is scanned
/// for and nothing else is requested — no device info, no battery, no
/// archive — so the file goes out as soon as the radio is up. When the app is
/// opened later, the device page finds the live session and fills in the rest.
class ColdLink {
  ColdLink._();

  static final ColdLink instance = ColdLink._();

  static const Duration _connectingWait = Duration(seconds: 15);

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
      LogService.info('[ColdLink] no remembered device');
      return false;
    }

    try {
      await client.connectBleAddress(last.id, name: last.name);
      await client.ping(PingRequest(data: const [0x51, 0x55]));
    } catch (e) {
      LogService.info('[ColdLink] connect failed: $e');
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
}
