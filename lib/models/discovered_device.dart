import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
    final device = scanResult.device;
    LogService.log('[BLE] connecting to $name...');
    await device.connect(autoConnect: false);
    LogService.log('[BLE] discovering services...');
    final services = await device.discoverServices();
    LogService.log('[BLE] services found: ${services.length}');
    for (final s in services) {
      LogService.log('[BLE]  svc ${s.uuid.str}');
      for (final c in s.characteristics) {
        LogService.log('[BLE]    chr ${c.uuid.str} props=${c.properties}');
      }
    }
    return BleConnectedDevice(device, services);
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
    LogService.log('[USB] creating port for $name...');
    final port = await usbDevice.create();
    if (port == null) throw Exception('Failed to create USB port — permission denied?');

    final opened = await port.open();
    if (!opened) throw Exception('Failed to open USB port');

    await port.setDTR(true);
    await port.setRTS(true);
    await port.setPortParameters(
      230400, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE,
    );
    LogService.log('[USB] port opened at 230400 baud');

    // Flipper Zero USB requires CLI "start_rpc_session" to enter RPC mode
    await Future.delayed(const Duration(milliseconds: 300));
    final cmd = Uint8List.fromList(utf8.encode('start_rpc_session\r\n'));
    await port.write(cmd);
    LogService.log('[USB] sent start_rpc_session');

    // Give device time to switch modes
    await Future.delayed(const Duration(milliseconds: 500));

    return UsbConnectedDevice(usbDevice, port);
  }
}

// ================================================================
// Connected device — common interface
// ================================================================

abstract class ConnectedDevice {
  String get name;
  DeviceTransport get transport;
  Stream<List<int>> get dataStream;
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

    // Fallback to first writable + first notifiable characteristic
    if (tx == null || rx == null) {
      LogService.log('[BLE] Flipper UUIDs not found, using fallback characteristics');
      for (final svc in services) {
        for (final ch in svc.characteristics) {
          if (tx == null && (ch.properties.write || ch.properties.writeWithoutResponse)) {
            tx = ch;
          }
          if (rx == null && ch.properties.notify) rx = ch;
        }
      }
    }

    if (tx == null || rx == null) {
      throw Exception('No suitable BLE characteristics found');
    }

    _tx = tx;
    _rx = rx;
    LogService.log('[BLE] TX=${_tx.uuid.str} RX=${_rx.uuid.str}');

    _rx.setNotifyValue(true).then((_) {
      LogService.log('[BLE] notifications enabled on ${_rx.uuid.str}');
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
  Future<void> sendBytes(Uint8List bytes) async {
    const chunk = 512;
    for (int i = 0; i < bytes.length; i += chunk) {
      final end = (i + chunk).clamp(0, bytes.length);
      await _tx.write(
        bytes.sublist(i, end),
        withoutResponse: _tx.properties.writeWithoutResponse,
      );
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
  final UsbDevice usbDevice;
  final UsbPort port;

  final _ctrl = StreamController<List<int>>.broadcast();

  UsbConnectedDevice(this.usbDevice, this.port) {
    port.inputStream?.listen(
      (d) { LogService.log('[USB RX] ${d.length} bytes'); _ctrl.add(d); },
      onError: (e) => LogService.log('[USB RX error] $e'),
      onDone: () => LogService.log('[USB] stream done'),
    );
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
    await port.write(bytes);
    LogService.log('[USB TX] ${bytes.length} bytes');
  }

  @override
  Future<void> disconnect() async {
    await port.close();
    await _ctrl.close();
    LogService.log('[USB] disconnected');
  }
}
