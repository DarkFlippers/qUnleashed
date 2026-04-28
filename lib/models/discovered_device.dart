import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:usb_serial/usb_serial.dart';

import '../services/log_service.dart';

enum DeviceTransport { ble, usb }

abstract class DiscoveredDevice {
  String get id;
  String get name;
  DeviceTransport get transport;
  Future<ConnectedDevice> connect();
}

// ── BLE discovered ────────────────────────────────────────────────

class BleDiscoveredDevice implements DiscoveredDevice {
  final ScanResult scanResult;
  const BleDiscoveredDevice(this.scanResult);

  @override
  String get id => scanResult.device.remoteId.str;

  @override
  String get name {
    final n = scanResult.advertisementData.advName;
    return n.isNotEmpty ? n : scanResult.device.remoteId.str;
  }

  @override
  DeviceTransport get transport => DeviceTransport.ble;
  int get rssi => scanResult.rssi;

  @override
  Future<ConnectedDevice> connect() async {
    LogService.log('[BLE] connecting to $name...');
    await scanResult.device.connect(autoConnect: false);
    LogService.log('[BLE] discovering services...');
    final services = await scanResult.device.discoverServices();
    for (final s in services) {
      LogService.log('[BLE]  svc ${s.uuid.str}');
      for (final c in s.characteristics) {
        LogService.log('[BLE]    chr ${c.uuid.str} props=${c.properties}');
      }
    }
    return BleConnectedDevice(scanResult.device, services);
  }
}

// ── USB discovered ────────────────────────────────────────────────

class UsbDiscoveredDevice implements DiscoveredDevice {
  final UsbDevice usbDevice;
  const UsbDiscoveredDevice(this.usbDevice);

  @override
  String get id => '${usbDevice.vid}:${usbDevice.pid}';

  @override
  String get name {
    final p = usbDevice.productName;
    if (p != null && p.isNotEmpty) return p;
    return 'USB VID:0x${usbDevice.vid?.toRadixString(16) ?? '?'} '
        'PID:0x${usbDevice.pid?.toRadixString(16) ?? '?'}';
  }

  @override
  DeviceTransport get transport => DeviceTransport.usb;

  @override
  Future<ConnectedDevice> connect() async {
    LogService.log('[USB] opening port for $name...');
    final port = await usbDevice.create();
    if (port == null) throw Exception('USB permission denied or port unavailable');
    final opened = await port.open();
    if (!opened) throw Exception('Failed to open USB port');
    // No DTR/RTS — Flipper Zero CDC ACM does not need hardware flow control
    await port.setPortParameters(
      230400, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE,
    );
    LogService.log('[USB] port opened');
    // UsbConnectedDevice subscribes to inputStream immediately in its constructor.
    // init() is called later from the screen (after log subscription is active).
    return UsbConnectedDevice(usbDevice, port);
  }
}

// ================================================================
// Connected device abstraction
// ================================================================

abstract class ConnectedDevice {
  String get name;
  DeviceTransport get transport;
  Stream<List<int>> get dataStream;

  /// Called once from DeviceInfoScreen.initState after subscriptions are ready.
  Future<void> init() async {}

  Future<void> sendBytes(Uint8List bytes);
  Future<void> disconnect();
}

// ── BLE connected ─────────────────────────────────────────────────

class BleConnectedDevice implements ConnectedDevice {
  static const _svcUuid = '8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000';
  static const _rxUuid  = '19ed82ae-ed21-4c9d-4145-228e61fe0000';
  static const _txUuid  = '19ed82ae-ed21-4c9d-4145-228e62fe0000';

  final BluetoothDevice device;
  final List<BluetoothService> services;

  late final BluetoothCharacteristic _tx;
  late final BluetoothCharacteristic _rx;

  final _ctrl = StreamController<List<int>>.broadcast();

  BleConnectedDevice(this.device, this.services) {
    _setup();
  }

  void _setup() {
    BluetoothCharacteristic? tx, rx;
    for (final svc in services) {
      final sid = svc.uuid.str.toLowerCase();
      for (final ch in svc.characteristics) {
        final cid = ch.uuid.str.toLowerCase();
        if (sid == _svcUuid) {
          if (cid == _txUuid) tx = ch;
          if (cid == _rxUuid) rx = ch;
        }
      }
    }
    if (tx == null || rx == null) {
      LogService.log('[BLE] Flipper UUIDs not found — trying fallback');
      for (final svc in services) {
        for (final ch in svc.characteristics) {
          if (tx == null && (ch.properties.write || ch.properties.writeWithoutResponse)) tx = ch;
          if (rx == null && ch.properties.notify) rx = ch;
        }
      }
    }
    if (tx == null || rx == null) throw Exception('No suitable BLE characteristics');
    _tx = tx;
    _rx = rx;
    LogService.log('[BLE] TX=${_tx.uuid.str} RX=${_rx.uuid.str}');
    _rx.setNotifyValue(true).then((_) {
      LogService.log('[BLE] notifications enabled');
      _rx.onValueReceived.listen(
        (d) { LogService.log('[BLE RX] ${d.length} bytes'); _ctrl.add(d); },
        onError: (e) => LogService.log('[BLE RX error] $e'),
      );
    });
  }

  @override
  String get name {
    final n = device.platformName;
    return n.isNotEmpty ? n : device.remoteId.str;
  }

  @override
  DeviceTransport get transport => DeviceTransport.ble;

  @override
  Stream<List<int>> get dataStream => _ctrl.stream;

  @override
  Future<void> init() async {
    LogService.log('[BLE] init — no extra step needed for BLE');
  }

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    const chunk = 512;
    for (int i = 0; i < bytes.length; i += chunk) {
      final end = (i + chunk).clamp(0, bytes.length);
      await _tx.write(bytes.sublist(i, end),
          withoutResponse: _tx.properties.writeWithoutResponse);
      LogService.log('[BLE TX] ${end - i} bytes');
    }
  }

  @override
  Future<void> disconnect() async {
    await _ctrl.close();
    await device.disconnect();
    LogService.log('[BLE] disconnected');
  }
}

// ── USB connected ─────────────────────────────────────────────────

class UsbConnectedDevice implements ConnectedDevice {
  static const _cliPrompt = '\r\n\r\n>: ';
  static const _startRpcCmd = 'start_rpc_session\r';

  final UsbDevice usbDevice;
  final UsbPort port;

  void Function(List<int>)? _initHandler;
  bool _rpcReady = false;

  final _ctrl = StreamController<List<int>>.broadcast();

  UsbConnectedDevice(this.usbDevice, this.port) {
    // Subscribe to inputStream IMMEDIATELY in constructor — before anything is sent
    port.inputStream?.listen(
      (data) {
        if (_initHandler != null) {
          _initHandler!(data);
          return;
        }
        if (!_rpcReady) {
          LogService.log('[USB] discard ${data.length} bytes (not ready)');
          return;
        }
        if (_looksLikeCliNoise(data)) {
          LogService.log('[USB] drop CLI noise ${data.length} bytes: ${_escapeAscii(data)}');
          return;
        }
        final hex = data.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        LogService.log('[USB RX] ${data.length} bytes: $hex');
        _ctrl.add(data);
      },
      onError: (e) => LogService.log('[USB RX error] $e'),
      onDone: () => LogService.log('[USB] stream done'),
    );
  }

  /// Send `start_rpc_session`, wait for CLI echo to settle, then open RPC gate.
  /// Called from DeviceInfoScreen.initState AFTER log subscription is active.
  @override
  Future<void> init() async {
    if (_rpcReady) return;

    final initBuffer = <int>[];
    _initHandler = (data) {
      initBuffer.addAll(data);
      LogService.log('[USB INIT] ${data.length} bytes: ${_escapeAscii(data)}');
    };

    try {
      await _enterCli(initBuffer);
      await _startRpc(initBuffer);
      await Future.delayed(const Duration(milliseconds: 100));
      _rpcReady = true;
      LogService.log('[USB] RPC gate OPEN — ready for protobuf');
    } finally {
      _initHandler = null;
    }
  }

  @override
  String get name => usbDevice.productName?.isNotEmpty == true
      ? usbDevice.productName!
      : 'USB Device';

  @override
  DeviceTransport get transport => DeviceTransport.usb;

  @override
  Stream<List<int>> get dataStream => _ctrl.stream;

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    final hex = bytes.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    LogService.log('[USB TX] ${bytes.length} bytes: $hex');
    await port.write(bytes);
  }

  @override
  Future<void> disconnect() async {
    await port.close();
    await _ctrl.close();
    LogService.log('[USB] disconnected');
  }

  bool _looksLikeCliNoise(List<int> data) {
    if (data.isEmpty) return false;
    for (final b in data) {
      final printable = b >= 0x20 && b <= 0x7E;
      const allowedControl = {0x07, 0x08, 0x09, 0x0A, 0x0D};
      if (!printable && !allowedControl.contains(b)) return false;
    }
    final text = String.fromCharCodes(data);
    return text.contains('>:') ||
        text.contains('^C') ||
        text.contains('start_rpc_session');
  }

  String _escapeAscii(List<int> data) {
    return String.fromCharCodes(data)
        .replaceAll('\r', '\\r')
        .replaceAll('\n', '\\n');
  }

  Future<void> _enterCli(List<int> initBuffer) async {
    LogService.log('[USB] entering CLI session...');

    await port.setDTR(false);
    await Future.delayed(const Duration(milliseconds: 50));
    await port.setDTR(true);

    final cliReady = Completer<void>();
    Timer? timeout;
    timeout = Timer(const Duration(seconds: 3), () {
      if (!cliReady.isCompleted) {
        cliReady.completeError(Exception('Timeout waiting for Flipper CLI prompt'));
      }
    });

    Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (cliReady.isCompleted) {
        timer.cancel();
        return;
      }
      if (_asciiBuffer(initBuffer).contains(_cliPrompt)) {
        cliReady.complete();
        timer.cancel();
      }
    });

    try {
      await cliReady.future;
      LogService.log('[USB] CLI prompt detected');
    } finally {
      timeout.cancel();
    }
  }

  Future<void> _startRpc(List<int> initBuffer) async {
    initBuffer.clear();
    final cmd = Uint8List.fromList(utf8.encode(_startRpcCmd));
    await port.write(cmd);
    LogService.log('[USB] → start_rpc_session sent (${cmd.length} bytes)');

    final rpcReady = Completer<void>();
    Timer? timeout;
    timeout = Timer(const Duration(seconds: 3), () {
      if (!rpcReady.isCompleted) {
        rpcReady.completeError(Exception('Timeout waiting for start_rpc_session echo'));
      }
    });

    Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (rpcReady.isCompleted) {
        timer.cancel();
        return;
      }
      if (_asciiBuffer(initBuffer).endsWith('$_startRpcCmd\n')) {
        rpcReady.complete();
        timer.cancel();
      }
    });

    try {
      await rpcReady.future;
      LogService.log('[USB] RPC start echo detected');
    } finally {
      timeout.cancel();
    }
  }

  String _asciiBuffer(List<int> bytes) => String.fromCharCodes(bytes);
}
