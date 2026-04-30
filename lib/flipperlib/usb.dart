part of flipper_client_impl;

extension FlipperUsbApi on FlipperClient {
  Stream<FlipperDevice> get usbDevicesStream => devicesStream.asyncExpand(
        (devices) => Stream.fromIterable(
          devices.where((device) => device.isUsb),
        ),
      );
}

class _AndroidUsbTransport extends _Transport {
  final UsbPort _port;
  StreamSubscription<Uint8List>? _inputSub;

  _AndroidUsbTransport._(this._port);

  static Future<_AndroidUsbTransport> create(
    AndroidUsbDiscoveredDevice device,
  ) async {
    final port = await device.usbDevice.create();
    if (port == null) {
      throw StateError('USB permission denied or port unavailable');
    }
    final opened = await port.open();
    if (!opened) {
      throw StateError('Failed to open USB port');
    }
    await port.setPortParameters(
      230400,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    return _AndroidUsbTransport._(port);
  }

  @override
  Future<void> open() async {
    _inputSub = _port.inputStream?.listen(
      addBytes,
      onError: (Object error, StackTrace stackTrace) {
        LogService.log('[FlipperClient] Android USB read error: $error');
      },
    );
  }

  @override
  Future<void> write(Uint8List bytes) async {
    await _port.write(bytes);
  }

  @override
  Future<void> nudgeCli() async {
    await _port.setDTR(false);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _port.setDTR(true);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await writeAscii('\r');
  }

  @override
  Future<void> close() async {
    await _inputSub?.cancel();
    await _port.close();
    await _bytesCtrl.close();
  }
}

class _DesktopUsbTransport extends _Transport {
  final SerialPort _port;
  Timer? _pollTimer;
  bool _closed = false;

  _DesktopUsbTransport._(this._port);

  static Future<_DesktopUsbTransport> create(
    DesktopUsbDiscoveredDevice device,
  ) async {
    final port = SerialPort(device.portName);
    if (!port.openReadWrite()) {
      port.dispose();
      throw StateError('Failed to open ${device.portName}');
    }
    final config = SerialPortConfig()
      ..baudRate = 230400
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none;
    port.config = config;
    return _DesktopUsbTransport._(port);
  }

  @override
  Future<void> open() async {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (_closed) return;
      try {
        final bytes = _port.read(65536);
        if (bytes.isNotEmpty) {
          addBytes(bytes);
        }
      } catch (_) {}
    });
  }

  @override
  Future<void> write(Uint8List bytes) async {
    _port.write(bytes);
  }

  @override
  Future<void> nudgeCli() async {
    try {
      final config = _port.config;
      config.dtr = 0;
      _port.config = config;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      config.dtr = 1;
      _port.config = config;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await writeAscii('\r');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pollTimer?.cancel();
    await _bytesCtrl.close();
    _port.close();
    _port.dispose();
  }
}
