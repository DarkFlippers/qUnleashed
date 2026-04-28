import 'package:usb_serial/usb_serial.dart';

import '../models/discovered_device.dart';
import 'log_service.dart';

class UsbService {
  static final UsbService _instance = UsbService._();
  factory UsbService() => _instance;
  UsbService._();

  Future<List<UsbDiscoveredDevice>> listDevices() async {
    final devices = await UsbSerial.listDevices();
    LogService.log('[USB] found ${devices.length} device(s)');
    for (final d in devices) {
      LogService.log('[USB] VID=0x${d.vid?.toRadixString(16)} '
          'PID=0x${d.pid?.toRadixString(16)} '
          'product="${d.productName}" '
          'manufacturer="${d.manufacturerName}"');
    }
    return devices.map(UsbDiscoveredDevice.new).toList();
  }
}
