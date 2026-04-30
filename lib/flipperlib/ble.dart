part of flipper_client_impl;

class _BleTransport extends _Transport {
  final BleDiscoveredDevice _device;

  late final String _txSvcId;
  late final String _txCharId;
  late final String _rxSvcId;
  late final String _rxCharId;
  late final bool _txWithResponse;
  late final bool _rxUsesIndicate;

  _BleTransport._(this._device);

  static Future<_BleTransport> create(BleDiscoveredDevice device) async {
    final transport = _BleTransport._(device);
    await transport._configure();
    return transport;
  }

  Future<void> _configure() async {
    await uble.UniversalBle.connect(_device.device.deviceId);
    try {
      await uble.UniversalBle.requestMtu(_device.device.deviceId, 256);
    } catch (_) {}

    final services =
        await uble.UniversalBle.discoverServices(_device.device.deviceId);
    String? txSvc;
    String? txChar;
    String? rxSvc;
    String? rxChar;
    var txWithResponse = true;
    var rxUsesIndicate = false;

    for (final service in services) {
      final sid = service.uuid.toLowerCase();
      for (final char in service.characteristics) {
        final cid = char.uuid.toLowerCase();
        if (sid == FlipperClient.bleServiceUuid) {
          if (cid == FlipperClient.bleTxUuid) {
            txSvc = service.uuid;
            txChar = char.uuid;
            txWithResponse =
                char.properties.contains(uble.CharacteristicProperty.write);
          }
          if (cid == FlipperClient.bleRxUuid) {
            rxSvc = service.uuid;
            rxChar = char.uuid;
            rxUsesIndicate =
                char.properties.contains(uble.CharacteristicProperty.indicate);
          }
        }
      }
    }

    if (txSvc == null || txChar == null || rxSvc == null || rxChar == null) {
      for (final service in services) {
        for (final char in service.characteristics) {
          if (txSvc == null &&
              (char.properties.contains(uble.CharacteristicProperty.write) ||
                  char.properties.contains(
                    uble.CharacteristicProperty.writeWithoutResponse,
                  ))) {
            txSvc = service.uuid;
            txChar = char.uuid;
            txWithResponse =
                char.properties.contains(uble.CharacteristicProperty.write);
          }
          if (rxSvc == null &&
              char.properties.contains(uble.CharacteristicProperty.indicate)) {
            rxSvc = service.uuid;
            rxChar = char.uuid;
            rxUsesIndicate = true;
          } else if (rxSvc == null &&
              char.properties.contains(uble.CharacteristicProperty.notify)) {
            rxSvc = service.uuid;
            rxChar = char.uuid;
            rxUsesIndicate = false;
          }
        }
      }
    }

    if (txSvc == null || txChar == null || rxSvc == null || rxChar == null) {
      throw StateError('No suitable BLE characteristics');
    }

    _txSvcId = txSvc;
    _txCharId = txChar;
    _rxSvcId = rxSvc;
    _rxCharId = rxChar;
    _txWithResponse = txWithResponse;
    _rxUsesIndicate = rxUsesIndicate;
  }

  @override
  Future<void> open() async {
    uble.UniversalBle.onValueChange = (deviceId, charId, value, mtu) {
      if (deviceId != _device.device.deviceId) return;
      if (charId.toLowerCase() != _rxCharId.toLowerCase()) return;
      addBytes(value);
    };

    if (_rxUsesIndicate) {
      await uble.UniversalBle.subscribeIndications(
        _device.device.deviceId,
        _rxSvcId,
        _rxCharId,
      );
    } else {
      await uble.UniversalBle.subscribeNotifications(
        _device.device.deviceId,
        _rxSvcId,
        _rxCharId,
      );
    }
  }

  @override
  Future<void> write(Uint8List bytes) async {
    const chunkSize = 512;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, bytes.length);
      await uble.UniversalBle.writeValue(
        _device.device.deviceId,
        _txSvcId,
        _txCharId,
        bytes.sublist(i, end),
        _txWithResponse
            ? uble.BleOutputProperty.withResponse
            : uble.BleOutputProperty.withoutResponse,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  @override
  Future<void> nudgeCli() async {
    throw FlipperUnsupportedModeError(
      'CLI mode is not available over BLE connections',
    );
  }

  @override
  Future<void> close() async {
    uble.UniversalBle.onValueChange = null;
    await uble.UniversalBle.disconnect(_device.device.deviceId);
    await _bytesCtrl.close();
  }
}

extension FlipperBleApi on FlipperClient {
  Stream<FlipperDevice> get bleDevicesStream => devicesStream.asyncExpand(
        (devices) => Stream.fromIterable(
          devices.where((device) => device.isBle),
        ),
      );
}
