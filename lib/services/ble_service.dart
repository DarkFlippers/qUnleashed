import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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

    // Android — request new (API 31+) permissions
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

    // Fallback for Android < 12: request location
    final loc = await Permission.locationWhenInUse.request();
    LogService.log('[BLE] location fallback: $loc');
    return loc.isGranted;
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_scanning) return;

    final state = await FlutterBluePlus.adapterState.first;
    LogService.log('[BLE] adapter state: $state');
    if (state != BluetoothAdapterState.on) {
      LogService.log('[BLE] adapter not ON, aborting scan');
      return;
    }

    _found.clear();
    _scanning = true;
    LogService.log('[BLE] scan started');

    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final prev = _found[r.device.remoteId.str];
        if (prev == null) {
          LogService.log('[BLE] found: ${r.advertisementData.advName} '
              '(${r.device.remoteId.str}) rssi=${r.rssi}');
        }
        _found[r.device.remoteId.str] = BleDiscoveredDevice(r);
      }
      _devicesCtrl.add(List.unmodifiable(_found.values.toList()));
    }, onError: (e) => LogService.log('[BLE scan error] $e'));

    await FlutterBluePlus.startScan(timeout: timeout);
    await sub.cancel();
    _scanning = false;
    LogService.log('[BLE] scan done — ${_found.length} device(s)');
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanning = false;
  }

  List<BleDiscoveredDevice> get currentDevices =>
      List.unmodifiable(_found.values.toList());
}
