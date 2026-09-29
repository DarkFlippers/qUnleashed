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
      // The only way a home-screen widget reaches a Flipper, and it runs in
      // the headless isolate where there is no UI to put anything in - the
      // widget just draws its "no device" face, which is the same face it
      // draws when none is remembered. The false below is the whole report,
      // and it says nothing about which of the two happened.
      LogService.warn('[ColdLink] connect failed: $e');
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
