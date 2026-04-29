import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:universal_ble/universal_ble.dart' as uble;
import 'package:usb_serial/usb_serial.dart';

import '../services/log_service.dart';

enum DeviceTransport { ble, usb }

abstract class DiscoveredDevice {
  String get id;
  String get name;
  DeviceTransport get transport;
  Future<ConnectedDevice> connect();
}

// ── USB discovered (abstract) ─────────────────────────────────────

abstract class UsbDiscoveredDevice implements DiscoveredDevice {
  @override
  DeviceTransport get transport => DeviceTransport.usb;
}

// ── BLE discovered ────────────────────────────────────────────────

class BleDiscoveredDevice implements DiscoveredDevice {
  final uble.BleDevice device;
  const BleDiscoveredDevice(this.device);

  @override
  String get id => device.deviceId;

  @override
  String get name =>
      (device.name?.isNotEmpty == true) ? device.name! : device.deviceId;

  @override
  DeviceTransport get transport => DeviceTransport.ble;

  int get rssi => device.rssi?.toInt() ?? 0;

  @override
  Future<ConnectedDevice> connect() async {
    LogService.log('[BLE] connecting to $name...');
    await uble.UniversalBle.connect(device.deviceId);
    try {
      final mtu = await uble.UniversalBle.requestMtu(device.deviceId, 256);
      LogService.log('[BLE] mtu negotiated: $mtu');
    } catch (e) {
      LogService.log('[BLE] mtu request failed (non-fatal): $e');
    }
    LogService.log('[BLE] discovering services...');
    final services = await uble.UniversalBle.discoverServices(device.deviceId);
    for (final s in services) {
      LogService.log('[BLE]  svc ${s.uuid}');
      for (final c in s.characteristics) {
        LogService.log('[BLE]    chr ${c.uuid} props=${c.properties}');
      }
    }
    return BleConnectedDevice(device.deviceId, name, services);
  }
}

// ── Android USB discovered ────────────────────────────────────────

class AndroidUsbDiscoveredDevice extends UsbDiscoveredDevice {
  final UsbDevice usbDevice;
  AndroidUsbDiscoveredDevice(this.usbDevice);

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
  Future<ConnectedDevice> connect() async {
    LogService.log('[USB] opening port for $name...');
    final port = await usbDevice.create();
    if (port == null) throw Exception('USB permission denied or port unavailable');
    final opened = await port.open();
    if (!opened) throw Exception('Failed to open USB port');
    await port.setPortParameters(
      230400, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE,
    );
    LogService.log('[USB] port opened');
    return AndroidUsbConnectedDevice(usbDevice, port);
  }
}

// ── Desktop USB discovered (Windows / macOS / Linux) ─────────────

class DesktopUsbDiscoveredDevice extends UsbDiscoveredDevice {
  final String portName;
  final String description;
  final int? vendorId;
  final int? productId;
  final String? serialNumber;

  DesktopUsbDiscoveredDevice(this.portName, this.description, {
    this.vendorId,
    this.productId,
    this.serialNumber,
  });

  @override
  String get id => portName;

  @override
  String get name => description.isNotEmpty ? description : portName;

  @override
  Future<ConnectedDevice> connect() async {
    LogService.log('[USB] opening $portName...');
    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      port.dispose();
      throw Exception(
          'Failed to open $portName: ${SerialPort.lastError?.message}');
    }
    final config = SerialPortConfig()
      ..baudRate = 230400
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none;
    port.config = config;
    LogService.log('[USB] $portName opened at 230400/8N1');
    return DesktopUsbConnectedDevice(portName, port);
  }
}

// ================================================================
// Connected device abstraction
// ================================================================

abstract class ConnectedDevice {
  String get name;
  DeviceTransport get transport;
  Stream<List<int>> get dataStream;

  Future<void> init() async {}

  Future<void> sendBytes(Uint8List bytes);
  Future<void> disconnect();
}

// ── BLE connected ─────────────────────────────────────────────────

class BleConnectedDevice implements ConnectedDevice {
  static const _svcUuid = '8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000';
  static const _rxUuid  = '19ed82ae-ed21-4c9d-4145-228e61fe0000';
  static const _txUuid  = '19ed82ae-ed21-4c9d-4145-228e62fe0000';

  final String deviceId;
  final String _name;
  final List<uble.BleService> _services;

  late final String _txSvcId, _txCharId, _rxSvcId, _rxCharId;
  late final bool _txWithResponse, _rxUsesIndicate;

  Uint8List? _lastRx;
  DateTime? _lastRxAt;

  final _ctrl = StreamController<List<int>>.broadcast();

  BleConnectedDevice(this.deviceId, this._name, this._services) {
    _setup();
  }

  void _setup() {
    String? txSvc, txChar, rxSvc, rxChar;
    bool txWithResponse = true;
    bool rxIndicate = false;

    for (final svc in _services) {
      final sid = svc.uuid.toLowerCase();
      for (final ch in svc.characteristics) {
        final cid = ch.uuid.toLowerCase();
        if (sid == _svcUuid) {
          if (cid == _txUuid) {
            txSvc = sid;
            txChar = cid;
            txWithResponse = ch.properties.contains(uble.CharacteristicProperty.write);
          }
          if (cid == _rxUuid) {
            rxSvc = sid;
            rxChar = cid;
            rxIndicate = ch.properties.contains(uble.CharacteristicProperty.indicate);
          }
        }
      }
    }

    if (txSvc == null || rxSvc == null) {
      LogService.log('[BLE] Flipper UUIDs not found — trying fallback');
      for (final svc in _services) {
        for (final ch in svc.characteristics) {
          if (txSvc == null &&
              (ch.properties.contains(uble.CharacteristicProperty.write) ||
               ch.properties.contains(uble.CharacteristicProperty.writeWithoutResponse))) {
            txSvc = svc.uuid;
            txChar = ch.uuid;
            txWithResponse = ch.properties.contains(uble.CharacteristicProperty.write);
          }
          if (rxSvc == null &&
              ch.properties.contains(uble.CharacteristicProperty.indicate)) {
            rxSvc = svc.uuid;
            rxChar = ch.uuid;
            rxIndicate = true;
          } else if (rxSvc == null &&
              ch.properties.contains(uble.CharacteristicProperty.notify)) {
            rxSvc = svc.uuid;
            rxChar = ch.uuid;
            rxIndicate = false;
          }
        }
      }
    }

    if (txSvc == null || rxSvc == null) throw Exception('No suitable BLE characteristics');

    _txSvcId = txSvc;
    _txCharId = txChar!;
    _rxSvcId = rxSvc;
    _rxCharId = rxChar!;
    _txWithResponse = txWithResponse;
    _rxUsesIndicate = rxIndicate;
    LogService.log('[BLE] TX=$_txSvcId/$_txCharId RX=$_rxSvcId/$_rxCharId indicate=$_rxUsesIndicate writeRsp=$_txWithResponse');

    uble.UniversalBle.onValueChange = (devId, charId, value, mtu) {
      if (devId != deviceId || charId.toLowerCase() != _rxCharId.toLowerCase()) {
        return;
      }
      final now = DateTime.now();
      if (_lastRx != null &&
          _sameBytes(_lastRx!, value) &&
          _lastRxAt != null &&
          now.difference(_lastRxAt!) < const Duration(milliseconds: 150)) {
        LogService.log('[BLE] drop duplicate chunk ${value.length} bytes');
        return;
      }
      _lastRx = Uint8List.fromList(value);
      _lastRxAt = now;
      LogService.log('[BLE RX] ${value.length} bytes');
      _ctrl.add(value);
    };

    if (_rxUsesIndicate) {
      uble.UniversalBle.subscribeIndications(deviceId, _rxSvcId, _rxCharId)
          .then((_) => LogService.log('[BLE] subscribed (indicate)'))
          .catchError((e) => LogService.log('[BLE] subscribeIndications error: $e'));
    } else {
      uble.UniversalBle.subscribeNotifications(deviceId, _rxSvcId, _rxCharId)
          .then((_) => LogService.log('[BLE] subscribed (notify)'))
          .catchError((e) => LogService.log('[BLE] subscribeNotifications error: $e'));
    }
  }

  @override
  String get name => _name;

  @override
  DeviceTransport get transport => DeviceTransport.ble;

  @override
  Stream<List<int>> get dataStream => _ctrl.stream;

  @override
  Future<void> init() async {}

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    const chunk = 512;
    for (int i = 0; i < bytes.length; i += chunk) {
      final end = (i + chunk).clamp(0, bytes.length);
      await uble.UniversalBle.writeValue(
        deviceId,
        _txSvcId,
        _txCharId,
        bytes.sublist(i, end),
        _txWithResponse
            ? uble.BleOutputProperty.withResponse
            : uble.BleOutputProperty.withoutResponse,
      );
      LogService.log('[BLE TX] ${end - i} bytes');
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  @override
  Future<void> disconnect() async {
    uble.UniversalBle.onValueChange = null;
    await _ctrl.close();
    await uble.UniversalBle.disconnect(deviceId);
    LogService.log('[BLE] disconnected');
  }

  bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ── Android USB connected ─────────────────────────────────────────

class AndroidUsbConnectedDevice implements ConnectedDevice {
  static const _cliPrompt = '\r\n\r\n>: ';
  static const _startRpcCmd = 'start_rpc_session\r';

  final UsbDevice usbDevice;
  final UsbPort port;

  void Function(List<int>)? _initHandler;
  bool _rpcReady = false;

  final _ctrl = StreamController<List<int>>.broadcast();

  AndroidUsbConnectedDevice(this.usbDevice, this.port) {
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

// ── Desktop USB connected (Windows / macOS / Linux) ───────────────

class DesktopUsbConnectedDevice implements ConnectedDevice {
  static const _cliPrompt = '\r\n\r\n>: ';
  static const _startRpcCmd = 'start_rpc_session\r';

  final String portName;
  final SerialPort _port;

  // Data that arrives before init() calls are buffered here, not discarded.
  final _preInitBuffer = <int>[];

  void Function(Uint8List)? _initHandler;
  bool _rpcReady = false;
  bool _closed = false;

  Timer? _pollTimer;
  final _ctrl = StreamController<List<int>>.broadcast();

  DesktopUsbConnectedDevice(this.portName, this._port) {
    // SerialPortReader uses an isolate that is unreliable on Windows.
    // Use a 10 ms non-blocking poll (sp_nonblocking_read) instead.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 10), _poll);
  }

  void _poll(Timer _) {
    if (_closed) return;
    Uint8List data;
    try {
      data = _port.read(65536);
    } catch (_) {
      return;
    }
    if (data.isEmpty) return;

    if (_initHandler != null) {
      _initHandler!(data);
      return;
    }
    if (!_rpcReady) {
      // Buffer instead of discard — init() will replay this
      _preInitBuffer.addAll(data);
      LogService.log('[USB PRE-INIT] ${data.length} bytes: ${_escapeAscii(data)}');
      return;
    }
    if (_looksLikeCliNoise(data)) {
      LogService.log('[USB] drop CLI noise ${data.length} bytes');
      return;
    }
    final hex = data.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    LogService.log('[USB RX] ${data.length} bytes: $hex');
    _ctrl.add(data);
  }

  @override
  Future<void> init() async {
    if (_rpcReady) return;

    final initBuffer = <int>[];
    _initHandler = (data) {
      initBuffer.addAll(data);
      LogService.log('[USB INIT] ${data.length} bytes: ${_escapeAscii(data)}');
    };

    // Replay data that arrived before init() was called
    if (_preInitBuffer.isNotEmpty) {
      LogService.log('[USB] replaying ${_preInitBuffer.length} pre-init bytes');
      _initHandler!(Uint8List.fromList(_preInitBuffer));
      _preInitBuffer.clear();
    }

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
  String get name => portName;

  @override
  DeviceTransport get transport => DeviceTransport.usb;

  @override
  Stream<List<int>> get dataStream => _ctrl.stream;

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    final hex = bytes.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    LogService.log('[USB TX] ${bytes.length} bytes: $hex');
    _port.write(bytes);
  }

  @override
  Future<void> disconnect() async {
    if (_closed) return;
    _closed = true;
    _pollTimer?.cancel();
    await _ctrl.close();
    LogService.log('[USB] disconnected');
    Future.delayed(Duration.zero, () {
      _port.close();
      _port.dispose();
    });
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

  String _escapeAscii(List<int> data) => String.fromCharCodes(data)
      .replaceAll('\r', '\\r')
      .replaceAll('\n', '\\n');

  Future<void> _enterCli(List<int> initBuffer) async {
    LogService.log('[USB] entering CLI session...');

    // Reuse the same config instance so libserialport does not free/recreate
    // native config objects during Flutter's frame lifecycle on Windows.
    try {
      final config = _port.config;
      config.dtr = 0;
      _port.config = config;
      await Future.delayed(const Duration(milliseconds: 100));
      config.dtr = 1;
      _port.config = config;
    } catch (e) {
      LogService.log('[USB] DTR toggle failed (non-fatal): $e');
    }

    final cliReady = Completer<void>();
    Timer? timeout;
    Timer? crTimer;

    timeout = Timer(const Duration(seconds: 8), () {
      if (!cliReady.isCompleted) {
        cliReady.completeError(Exception('Timeout waiting for Flipper CLI prompt'));
      }
    });

    // Send CR every 300 ms in case DTR alone wasn't enough
    crTimer = Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (cliReady.isCompleted) { t.cancel(); return; }
      _port.write(Uint8List.fromList([0x0D]));
    });

    Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (cliReady.isCompleted) { timer.cancel(); return; }
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
      crTimer.cancel();
    }
  }

  Future<void> _startRpc(List<int> initBuffer) async {
    initBuffer.clear();
    final cmd = Uint8List.fromList(utf8.encode(_startRpcCmd));
    _port.write(cmd);
    LogService.log('[USB] → start_rpc_session sent (${cmd.length} bytes)');
    await Future.delayed(const Duration(milliseconds: 500));
    if (initBuffer.isNotEmpty) {
      LogService.log('[USB] RPC start response: ${_escapeAscii(initBuffer)}');
      initBuffer.clear();
    }
  }

  String _asciiBuffer(List<int> bytes) => String.fromCharCodes(bytes);
}
