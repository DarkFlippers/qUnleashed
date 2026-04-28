import 'dart:async';
import 'dart:io';

import 'package:universal_ble/universal_ble.dart' as uble;
import 'package:permission_handler/permission_handler.dart';

import '../models/discovered_device.dart';
import 'log_service.dart';

class BleService {
  static final BleService _instance = BleService._();
  factory BleService() => _instance;
  BleService._();

  final _devicesCtrl = StreamController<List<BleDiscoveredDevice>>.broadcast();
  Stream<List<BleDiscoveredDevice>> get devicesStream => _devicesCtrl.stream;

  final Map<String, BleDiscoveredDevice> _found = {};
  bool _scanning = false;
  bool get isScanning => _scanning;

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (Platform.isIOS) {
      final s = await Permission.bluetooth.request();
      LogService.log('[BLE] iOS bluetooth: $s');
      return s.isGranted;
    }

    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    LogService.log('[BLE] bluetoothScan=${results[Permission.bluetoothScan]}'
        ' bluetoothConnect=${results[Permission.bluetoothConnect]}');

    final coreGranted = results.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
    if (coreGranted) return true;

    final loc = await Permission.locationWhenInUse.request();
    LogService.log('[BLE] location fallback: $loc');
    return loc.isGranted;
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_scanning) return;

    final state = await uble.UniversalBle.getBluetoothAvailabilityState();
    LogService.log('[BLE] adapter state: $state');
    if (state != uble.AvailabilityState.poweredOn) {
      LogService.log('[BLE] adapter not ON, aborting scan');
      return;
    }

    _found.clear();
    _scanning = true;
    LogService.log('[BLE] scan started');

    uble.UniversalBle.onScanResult = (device) {
      final isNew = !_found.containsKey(device.deviceId);
      if (isNew) {
        LogService.log(
            '[BLE] found: ${device.name} (${device.deviceId}) rssi=${device.rssi}');
      }
      _found[device.deviceId] = BleDiscoveredDevice(device);
      _devicesCtrl.add(List.unmodifiable(_found.values.toList()));
    };

    await uble.UniversalBle.startScan();
    await Future.delayed(timeout);
    await stopScan();
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    await uble.UniversalBle.stopScan();
    uble.UniversalBle.onScanResult = null;
    _scanning = false;
    LogService.log('[BLE] scan done — ${_found.length} device(s)');
  }

  List<BleDiscoveredDevice> get currentDevices =>
      List.unmodifiable(_found.values.toList());
}
