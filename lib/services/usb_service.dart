import 'dart:io';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:usb_serial/usb_serial.dart';

import '../models/discovered_device.dart';
import 'log_service.dart';

class UsbService {
  static final UsbService _instance = UsbService._();
  factory UsbService() => _instance;
  UsbService._();

  Future<List<UsbDiscoveredDevice>> listDevices() async {
    if (Platform.isAndroid) {
      return _listAndroid();
    }
    return _listDesktop();
  }

  Future<List<UsbDiscoveredDevice>> _listAndroid() async {
    final devices = await UsbSerial.listDevices();
    LogService.log('[USB] found ${devices.length} device(s)');
    for (final d in devices) {
      LogService.log('[USB] VID=0x${d.vid?.toRadixString(16)} '
          'PID=0x${d.pid?.toRadixString(16)} '
          'product="${d.productName}" '
          'manufacturer="${d.manufacturerName}"');
    }
    return devices.map(AndroidUsbDiscoveredDevice.new).toList();
  }

  Future<List<UsbDiscoveredDevice>> _listDesktop() async {
    final portNames = SerialPort.availablePorts;
    LogService.log('[USB] found ${portNames.length} serial port(s)');
    final result = <UsbDiscoveredDevice>[];
    for (final name in portNames) {
      final port = SerialPort(name);
      final desc = port.description ?? '';
      final vid = port.vendorId;
      final pid = port.productId;
      final serial = port.serialNumber;
      LogService.log('[USB] port=$name desc="$desc" '
          'vid=0x${vid?.toRadixString(16)} pid=0x${pid?.toRadixString(16)} serial=$serial');
      port.dispose();
      result.add(DesktopUsbDiscoveredDevice(name, desc,
          vendorId: vid, productId: pid, serialNumber: serial));
    }
    return result;
  }
}
