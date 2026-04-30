import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flipperzero/flipperzero.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:universal_ble/universal_ble.dart' as uble;
import 'package:usb_serial/usb_serial.dart';

import '../models/discovered_device.dart';
import '../services/log_service.dart';

enum FlipperLink { usb, ble }

enum FlipperMode { disconnected, cli, rpc }

class FlipperDevice {
  final String id;
  final String name;
  final FlipperLink link;
  final DiscoveredDevice source;
  final int? vendorId;
  final int? productId;
  final String? serialNumber;
  final int? rssi;

  const FlipperDevice({
    required this.id,
    required this.name,
    required this.link,
    required this.source,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.rssi,
  });

  bool get isUsb => link == FlipperLink.usb;

  bool get isBle => link == FlipperLink.ble;
}

class FlipperRpcBatch<T extends $pb.GeneratedMessage> {
  final int commandId;
  final Main request;
  final List<Main> frames;
  final List<T> items;

  const FlipperRpcBatch({
    required this.commandId,
    required this.request,
    required this.frames,
    required this.items,
  });

  T get single => items.single;

  T? get firstOrNull => items.isEmpty ? null : items.first;
}

class FlipperConnectionState {
  final FlipperMode mode;
  final FlipperDevice? device;
  final bool connected;

  const FlipperConnectionState({
    required this.mode,
    required this.device,
    required this.connected,
  });
}

class FlipperClient {
  static const String _bleServiceUuid = '8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000';
  static const String _bleRxUuid = '19ed82ae-ed21-4c9d-4145-228e61fe0000';
  static const String _bleTxUuid = '19ed82ae-ed21-4c9d-4145-228e62fe0000';
  static const String _cliPrompt = '\r\n\r\n>: ';
  static const String _startRpcSession = 'start_rpc_session\r';

  final _devicesCtrl = StreamController<List<FlipperDevice>>.broadcast();
  final _connectionCtrl = StreamController<FlipperConnectionState>.broadcast();
  final _modeCtrl = StreamController<FlipperMode>.broadcast();
  final _rawCtrl = StreamController<List<int>>.broadcast();
  final _textCtrl = StreamController<String>.broadcast();
  final _messageCtrl = StreamController<Main>.broadcast();

  final Map<String, FlipperDevice> _devices = {};
  final Map<int, _PendingRpc> _pendingRpc = {};
  final _frameBuffer = _FrameBuffer();
  final _utf8Decoder = const Utf8Decoder(allowMalformed: true);

  StreamSubscription<List<int>>? _transportSub;
  _Transport? _transport;
  FlipperDevice? _connectedDevice;
  FlipperMode _mode = FlipperMode.disconnected;
  int _nextCommandId = 1;
  bool _scanning = false;

  Stream<List<FlipperDevice>> get devicesStream => _devicesCtrl.stream;

  Stream<FlipperConnectionState> get connectionStream => _connectionCtrl.stream;

  Stream<FlipperMode> get modeStream => _modeCtrl.stream;

  Stream<List<int>> get rawBytesStream => _rawCtrl.stream;

  Stream<String> get textStream => _textCtrl.stream;

  Stream<Main> get messageStream => _messageCtrl.stream;

  List<FlipperDevice> get devices => List.unmodifiable(_devices.values.toList());

  FlipperDevice? get connectedDevice => _connectedDevice;

  FlipperMode get mode => _mode;

  bool get isConnected => _transport != null;

  bool get isScanning => _scanning;

  int nextCommandId() => _nextCommandId++;

  Future<void> initialize() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _requestBlePermissions();
    }
  }

  Future<List<FlipperDevice>> refreshDevices({
    Duration bleTimeout = const Duration(seconds: 10),
  }) async {
    _devices.clear();
    await _loadUsbDevices();
    _emitDevices();
    await scanBle(timeout: bleTimeout);
    return devices;
  }

  Future<List<FlipperDevice>> searchDevices({
    Duration bleTimeout = const Duration(seconds: 10),
  }) {
    return refreshDevices(bleTimeout: bleTimeout);
  }

  List<FlipperDevice> listDevices() => devices;

  Future<void> scanBle({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_scanning) return;

    final state = await uble.UniversalBle.getBluetoothAvailabilityState();
    if (state != uble.AvailabilityState.poweredOn) {
      LogService.log('[FlipperClient] BLE adapter state: $state');
      return;
    }

    _scanning = true;

    uble.UniversalBle.onScanResult = (device) {
      final wrapped = BleDiscoveredDevice(device);
      _rememberDevice(_fromDiscovered(wrapped));
    };

    await uble.UniversalBle.startScan();
    await Future.delayed(timeout);
    await uble.UniversalBle.stopScan();
    uble.UniversalBle.onScanResult = null;
    _scanning = false;
    _emitDevices();
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    await uble.UniversalBle.stopScan();
    uble.UniversalBle.onScanResult = null;
    _scanning = false;
    _emitDevices();
  }

  Future<FlipperDevice> connectById(
    String id, {
    FlipperLink? link,
  }) async {
    FlipperDevice? device;
    for (final candidate in devices) {
      if (candidate.id != id) continue;
      if (link != null && candidate.link != link) continue;
      device = candidate;
      break;
    }

    if (device == null) {
      throw StateError('Device not found: $id');
    }

    return connect(device);
  }

  Future<FlipperDevice> connect(FlipperDevice device) async {
    await disconnect();

    final transport = await _openTransport(device);
    _transport = transport;
    _connectedDevice = device;
    _transportSub = transport.bytesStream.listen(
      _onTransportBytes,
      onError: _onTransportError,
      onDone: _onTransportDone,
    );

    await transport.open();

    final initialMode = device.isBle ? FlipperMode.rpc : FlipperMode.cli;
    _setMode(initialMode);
    return device;
  }

  Future<void> disconnect() async {
    final transport = _transport;
    _transport = null;
    _frameBuffer.clear();

    await _transportSub?.cancel();
    _transportSub = null;

    for (final pending in _pendingRpc.values) {
      pending.completeError(StateError('Disconnected'));
    }
    _pendingRpc.clear();

    if (transport != null) {
      await transport.close();
    }

    _connectedDevice = null;
    _setMode(FlipperMode.disconnected);
  }

  Future<void> switchToRpcMode() async {
    final transport = _requireTransport();
    if (_mode == FlipperMode.rpc) return;
    if (_connectedDevice?.isBle == true) {
      _setMode(FlipperMode.rpc);
      return;
    }

    final sub = textStream.listen((_) {});
    try {
      await _ensureCliPrompt();
      await transport.writeAscii(_startRpcSession);
      await _waitForText(
        (text) => text.contains('start_rpc_session'),
        timeout: const Duration(seconds: 4),
      );
      _frameBuffer.clear();
      _setMode(FlipperMode.rpc);
    } finally {
      await sub.cancel();
    }
  }

  Future<void> enterRpcMode() => switchToRpcMode();

  Future<void> switchToCliMode() async {
    final device = _connectedDevice;
    if (device == null) {
      throw StateError('No device connected');
    }
    if (!device.isUsb) {
      throw UnsupportedError('CLI mode is only available over USB');
    }
    if (_mode == FlipperMode.cli) return;

    await disconnect();
    await connect(device);
    await _ensureCliPrompt();
  }

  Future<void> enterCliMode() => switchToCliMode();

  Future<String> executeCli(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_connectedDevice?.isUsb != true) {
      throw UnsupportedError('CLI is only available over USB');
    }
    if (_mode != FlipperMode.cli) {
      await switchToCliMode();
    }

    final transport = _requireTransport();
    final chunks = <String>[];
    final completer = Completer<String>();

    late final StreamSubscription<String> sub;
    sub = textStream.listen((chunk) {
      chunks.add(chunk);
      final full = chunks.join();
      if (full.contains(_cliPrompt) && !completer.isCompleted) {
        completer.complete(_trimCliResult(full, command));
      }
    });

    try {
      await transport.writeAscii('\r');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await transport.writeAscii('$command\r');
      return await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  Future<String> executeCliCommand(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    return executeCli(command, timeout: timeout);
  }

  Future<void> sendRpc(Main message) async {
    if (_mode != FlipperMode.rpc) {
      await switchToRpcMode();
    }
    final transport = _requireTransport();
    if (message.commandId == 0) {
      message.commandId = nextCommandId();
    }
    await transport.write(_Protocol.encode(message));
  }

  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final commandId = request.commandId == 0 ? nextCommandId() : request.commandId;
    request.commandId = commandId;

    final pending = _PendingRpc();
    _pendingRpc[commandId] = pending;

    try {
      await sendRpc(request);
      return await pending.future.timeout(timeout, onTimeout: () {
        _pendingRpc.remove(commandId);
        throw TimeoutException('RPC timeout for commandId=$commandId');
      });
    } finally {
      _pendingRpc.remove(commandId);
    }
  }

  Future<FlipperRpcBatch<T>> callRpc<T extends $pb.GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final frames = await callRpcFrames(request, timeout: timeout);
    final items = <T>[];
    for (final frame in frames) {
      final item = pick(frame);
      if (item != null) {
        items.add(item);
      }
    }
    return FlipperRpcBatch<T>(
      commandId: request.commandId,
      request: request,
      frames: frames,
      items: items,
    );
  }

  Stream<T> select<T extends $pb.GeneratedMessage>(
    T? Function(Main frame) pick,
  ) {
    return messageStream.transform(
      StreamTransformer<Main, T>.fromHandlers(
        handleData: (frame, sink) {
          final selected = pick(frame);
          if (selected != null) {
            sink.add(selected);
          }
        },
      ),
    );
  }

  Future<List<FlipperDevice>> _loadUsbDevices() async {
    final result = <FlipperDevice>[];

    if (Platform.isAndroid) {
      final devices = await UsbSerial.listDevices();
      for (final device in devices) {
        result.add(
          FlipperDevice(
            id: '${device.vid}:${device.pid}',
            name: (device.productName?.isNotEmpty == true)
                ? device.productName!
                : 'USB VID:0x${device.vid?.toRadixString(16) ?? '?'} PID:0x${device.pid?.toRadixString(16) ?? '?'}',
            link: FlipperLink.usb,
            source: AndroidUsbDiscoveredDevice(device),
            vendorId: device.vid,
            productId: device.pid,
            serialNumber: null,
          ),
        );
      }
    } else {
      final ports = SerialPort.availablePorts;
      for (final portName in ports) {
        final port = SerialPort(portName);
        try {
          result.add(
            FlipperDevice(
              id: portName,
              name: (port.description?.isNotEmpty == true)
                  ? port.description!
                  : portName,
              link: FlipperLink.usb,
              source: DesktopUsbDiscoveredDevice(
                portName,
                port.description ?? '',
                vendorId: port.vendorId,
                productId: port.productId,
                serialNumber: port.serialNumber,
              ),
              vendorId: port.vendorId,
              productId: port.productId,
              serialNumber: port.serialNumber,
            ),
          );
        } finally {
          port.dispose();
        }
      }
    }

    for (final device in result) {
      _rememberDevice(device);
    }

    return result;
  }

  FlipperDevice _fromDiscovered(DiscoveredDevice device) {
    if (device is BleDiscoveredDevice) {
      return FlipperDevice(
        id: device.id,
        name: device.name,
        link: FlipperLink.ble,
        source: device,
        rssi: device.rssi,
      );
    }
    if (device is DesktopUsbDiscoveredDevice) {
      return FlipperDevice(
        id: device.id,
        name: device.name,
        link: FlipperLink.usb,
        source: device,
        vendorId: device.vendorId,
        productId: device.productId,
        serialNumber: device.serialNumber,
      );
    }
    if (device is AndroidUsbDiscoveredDevice) {
      return FlipperDevice(
        id: device.id,
        name: device.name,
        link: FlipperLink.usb,
        source: device,
        vendorId: device.usbDevice.vid,
        productId: device.usbDevice.pid,
      );
    }
    throw UnsupportedError('Unsupported device: ${device.runtimeType}');
  }

  Future<_Transport> _openTransport(FlipperDevice device) {
    if (device.source is BleDiscoveredDevice) {
      return _BleTransport.create(device.source as BleDiscoveredDevice);
    }
    if (device.source is AndroidUsbDiscoveredDevice) {
      return _AndroidUsbTransport.create(device.source as AndroidUsbDiscoveredDevice);
    }
    if (device.source is DesktopUsbDiscoveredDevice) {
      return _DesktopUsbTransport.create(device.source as DesktopUsbDiscoveredDevice);
    }
    throw UnsupportedError('Unsupported device source: ${device.source.runtimeType}');
  }

  void _onTransportBytes(List<int> chunk) {
    _rawCtrl.add(chunk);

    if (_mode == FlipperMode.rpc) {
      final frames = _frameBuffer.push(chunk);
      for (final frame in frames) {
        _messageCtrl.add(frame);
        final pending = _pendingRpc[frame.commandId];
        if (pending != null) {
          pending.add(frame);
          if (!frame.hasNext) {
            pending.complete();
          }
        }
      }
      return;
    }

    _textCtrl.add(_utf8Decoder.convert(chunk));
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    LogService.log('[FlipperClient] transport error: $error');
    _connectionCtrl.add(
      FlipperConnectionState(
        mode: _mode,
        device: _connectedDevice,
        connected: false,
      ),
    );
  }

  void _onTransportDone() {
    _connectionCtrl.add(
      FlipperConnectionState(
        mode: _mode,
        device: _connectedDevice,
        connected: false,
      ),
    );
  }

  Future<void> _requestBlePermissions() async {
    if (Platform.isIOS) {
      await Permission.bluetooth.request();
      return;
    }
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _ensureCliPrompt() async {
    final transport = _requireTransport();
    final completer = Completer<void>();
    final chunks = <String>[];

    late final StreamSubscription<String> sub;
    sub = textStream.listen((chunk) {
      chunks.add(chunk);
      if (chunks.join().contains(_cliPrompt) && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await transport.nudgeCli();
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('CLI prompt timeout'),
      );
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _waitForText(
    bool Function(String text) test, {
    required Duration timeout,
  }) async {
    final completer = Completer<void>();
    final chunks = <String>[];

    late final StreamSubscription<String> sub;
    sub = textStream.listen((chunk) {
      chunks.add(chunk);
      if (test(chunks.join()) && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  String _trimCliResult(String raw, String command) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final commandIndex = normalized.indexOf(command);
    final body = commandIndex >= 0
        ? normalized.substring(commandIndex + command.length)
        : normalized;
    final bodyPromptIndex = body.lastIndexOf('>: ');
    return (bodyPromptIndex >= 0 ? body.substring(0, bodyPromptIndex) : body)
        .trim();
  }

  void _rememberDevice(FlipperDevice device) {
    _devices['${device.link.name}:${device.id}'] = device;
    _emitDevices();
  }

  void _emitDevices() {
    final list = _devices.values.toList()
      ..sort((a, b) {
        final byLink = a.link.index.compareTo(b.link.index);
        if (byLink != 0) return byLink;
        return a.name.compareTo(b.name);
      });
    _devicesCtrl.add(List.unmodifiable(list));
  }

  _Transport _requireTransport() {
    final transport = _transport;
    if (transport == null) {
      throw StateError('No active transport');
    }
    return transport;
  }

  void _setMode(FlipperMode mode) {
    _mode = mode;
    _modeCtrl.add(mode);
    _connectionCtrl.add(
      FlipperConnectionState(
        mode: mode,
        device: _connectedDevice,
        connected: mode != FlipperMode.disconnected,
      ),
    );
  }

  Future<void> dispose() async {
    await disconnect();
    await stopScan();
    await _devicesCtrl.close();
    await _connectionCtrl.close();
    await _modeCtrl.close();
    await _rawCtrl.close();
    await _textCtrl.close();
    await _messageCtrl.close();
  }
}

extension FlipperClientRpcApi on FlipperClient {
  Future<FlipperRpcBatch<PingResponse>> ping(
    PingRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemPingRequest: request),
      (frame) => frame.hasSystemPingResponse() ? frame.systemPingResponse : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<ProtobufVersionResponse>> protobufVersion({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemProtobufVersionRequest: ProtobufVersionRequest()),
      (frame) => frame.hasSystemProtobufVersionResponse()
          ? frame.systemProtobufVersionResponse
          : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<DeviceInfoResponse>> deviceInfo({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemDeviceInfoRequest: DeviceInfoRequest()),
      (frame) => frame.hasSystemDeviceInfoResponse()
          ? frame.systemDeviceInfoResponse
          : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<PowerInfoResponse>> powerInfo({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemPowerInfoRequest: PowerInfoRequest()),
      (frame) => frame.hasSystemPowerInfoResponse()
          ? frame.systemPowerInfoResponse
          : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<GetDateTimeResponse>> getDateTime({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemGetDatetimeRequest: GetDateTimeRequest()),
      (frame) => frame.hasSystemGetDatetimeResponse()
          ? frame.systemGetDatetimeResponse
          : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> setDateTime(
    SetDateTimeRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemSetDatetimeRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> reboot(
    RebootRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemRebootRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> update(
    UpdateRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemUpdateRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<UpdateResponse>> updateStatus({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemUpdateRequest: UpdateRequest()),
      (frame) => frame.hasSystemUpdateResponse() ? frame.systemUpdateResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> factoryReset(
    FactoryResetRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemFactoryResetRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> playAudiovisualAlert(
    PlayAudiovisualAlertRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemPlayAudiovisualAlertRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<ListResponse>> storageList(
    ListRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageListRequest: request),
      (frame) => frame.hasStorageListResponse() ? frame.storageListResponse : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<ReadResponse>> storageRead(
    ReadRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageReadRequest: request),
      (frame) => frame.hasStorageReadResponse() ? frame.storageReadResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> storageWrite(
    WriteRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageWriteRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> storageDelete(
    DeleteRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageDeleteRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> storageMkdir(
    MkdirRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageMkdirRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<Md5sumResponse>> storageMd5sum(
    Md5sumRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageMd5sumRequest: request),
      (frame) => frame.hasStorageMd5sumResponse() ? frame.storageMd5sumResponse : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<StatResponse>> storageStat(
    StatRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageStatRequest: request),
      (frame) => frame.hasStorageStatResponse() ? frame.storageStatResponse : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<InfoResponse>> storageInfo(
    InfoRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageInfoRequest: request),
      (frame) => frame.hasStorageInfoResponse() ? frame.storageInfoResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> storageRename(
    RenameRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageRenameRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> storageBackupCreate(
    BackupCreateRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageBackupCreateRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> storageBackupRestore(
    BackupRestoreRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageBackupRestoreRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<TimestampResponse>> storageTimestamp(
    TimestampRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageTimestampRequest: request),
      (frame) => frame.hasStorageTimestampResponse()
          ? frame.storageTimestampResponse
          : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> storageTarExtract(
    TarExtractRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageTarExtractRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> appStart(
    StartRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appStartRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<LockStatusResponse>> appLockStatus({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(appLockStatusRequest: LockStatusRequest()),
      (frame) => frame.hasAppLockStatusResponse() ? frame.appLockStatusResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> appExit(
    AppExitRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appExitRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> appLoadFile(
    AppLoadFileRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appLoadFileRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> appButtonPress(
    AppButtonPressRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appButtonPressRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> appButtonRelease(
    AppButtonReleaseRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appButtonReleaseRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> appButtonPressRelease(
    AppButtonPressReleaseRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appButtonPressReleaseRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<GetErrorResponse>> appGetError({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(appGetErrorRequest: GetErrorRequest()),
      (frame) => frame.hasAppGetErrorResponse() ? frame.appGetErrorResponse : null,
      timeout: timeout,
    );
  }

  Stream<AppStateResponse> appStateStream() {
    return select(
      (frame) => frame.hasAppStateResponse() ? frame.appStateResponse : null,
    );
  }

  Future<List<Main>> appDataExchange(
    DataExchangeRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appDataExchangeRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> guiStartScreenStream({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiStartScreenStreamRequest: StartScreenStreamRequest()),
      timeout: timeout,
    );
  }

  Future<List<Main>> guiStopScreenStream({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiStopScreenStreamRequest: StopScreenStreamRequest()),
      timeout: timeout,
    );
  }

  Future<List<Main>> guiStartVirtualDisplay(
    StartVirtualDisplayRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiStartVirtualDisplayRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> guiStopVirtualDisplay({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiStopVirtualDisplayRequest: StopVirtualDisplayRequest()),
      timeout: timeout,
    );
  }

  Future<List<Main>> guiSendInput(
    SendInputEventRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiSendInputEventRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> gpioSetPinMode(
    SetPinMode request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(gpioSetPinMode: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> gpioSetInputPull(
    SetInputPull request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(gpioSetInputPull: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<GetPinModeResponse>> gpioGetPinMode(
    GetPinMode request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(gpioGetPinMode: request),
      (frame) => frame.hasGpioGetPinModeResponse()
          ? frame.gpioGetPinModeResponse
          : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<ReadPinResponse>> gpioReadPin(
    ReadPin request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(gpioReadPin: request),
      (frame) => frame.hasGpioReadPinResponse() ? frame.gpioReadPinResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> gpioWritePin(
    WritePin request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(gpioWritePin: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<GetOtgModeResponse>> gpioGetOtgMode({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(gpioGetOtgMode: GetOtgMode()),
      (frame) => frame.hasGpioGetOtgModeResponse()
          ? frame.gpioGetOtgModeResponse
          : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> gpioSetOtgMode(
    SetOtgMode request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(gpioSetOtgMode: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<GetResponse>> propertyGet(
    GetRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(propertyGetRequest: request),
      (frame) => frame.hasPropertyGetResponse() ? frame.propertyGetResponse : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<Status>> desktopStatus({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(desktopIsLockedRequest: IsLockedRequest()),
      (frame) => frame.hasDesktopStatus() ? frame.desktopStatus : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> desktopUnlock(
    UnlockRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(desktopUnlockRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> desktopStatusSubscribe({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(desktopStatusSubscribeRequest: StatusSubscribeRequest()),
      timeout: timeout,
    );
  }

  Future<List<Main>> desktopStatusUnsubscribe({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(desktopStatusUnsubscribeRequest: StatusUnsubscribeRequest()),
      timeout: timeout,
    );
  }
}

class _PendingRpc {
  final List<Main> frames = [];
  final Completer<List<Main>> _completer = Completer<List<Main>>();

  _PendingRpc();

  Future<List<Main>> get future => _completer.future;

  void add(Main frame) {
    frames.add(frame);
  }

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete(List.unmodifiable(frames));
    }
  }

  void completeError(Object error) {
    if (!_completer.isCompleted) {
      _completer.completeError(error);
    }
  }
}

abstract class _Transport {
  final _bytesCtrl = StreamController<List<int>>.broadcast();

  Stream<List<int>> get bytesStream => _bytesCtrl.stream;

  void addBytes(List<int> bytes) => _bytesCtrl.add(bytes);

  Future<void> open();

  Future<void> write(Uint8List bytes);

  Future<void> writeAscii(String text) => write(Uint8List.fromList(ascii.encode(text)));

  Future<void> nudgeCli();

  Future<void> close();
}

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

    final services = await uble.UniversalBle.discoverServices(_device.device.deviceId);
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
        if (sid == FlipperClient._bleServiceUuid) {
          if (cid == FlipperClient._bleTxUuid) {
            txSvc = service.uuid;
            txChar = char.uuid;
            txWithResponse = char.properties.contains(uble.CharacteristicProperty.write);
          }
          if (cid == FlipperClient._bleRxUuid) {
            rxSvc = service.uuid;
            rxChar = char.uuid;
            rxUsesIndicate = char.properties.contains(uble.CharacteristicProperty.indicate);
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
            txWithResponse = char.properties.contains(uble.CharacteristicProperty.write);
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
  Future<void> nudgeCli() async {}

  @override
  Future<void> close() async {
    uble.UniversalBle.onValueChange = null;
    await uble.UniversalBle.disconnect(_device.device.deviceId);
    await _bytesCtrl.close();
  }
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

class _Protocol {
  static Uint8List encode(Main message) {
    final payload = message.writeToBuffer();
    final prefix = _encodeVarint(payload.length);
    final buffer = Uint8List(prefix.length + payload.length);
    buffer.setRange(0, prefix.length, prefix);
    buffer.setRange(prefix.length, buffer.length, payload);
    return buffer;
  }

  static List<int> _encodeVarint(int value) {
    final bytes = <int>[];
    while (value > 0x7F) {
      bytes.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    bytes.add(value & 0x7F);
    return bytes;
  }
}

class _FrameBuffer {
  final List<int> _buffer = [];

  List<Main> push(List<int> chunk) {
    _buffer.addAll(chunk);
    final messages = <Main>[];
    while (true) {
      final frame = _tryParse();
      if (frame == null) return messages;
      messages.add(frame);
    }
  }

  void clear() => _buffer.clear();

  Main? _tryParse() {
    if (_buffer.isEmpty) return null;

    var length = 0;
    var shift = 0;
    var offset = 0;

    while (offset < _buffer.length) {
      final byte = _buffer[offset++];
      length |= (byte & 0x7F) << shift;
      shift += 7;

      if ((byte & 0x80) == 0) {
        if (length > 65536) {
          _buffer.removeAt(0);
          return null;
        }
        if (_buffer.length < offset + length) {
          return null;
        }

        final payload = Uint8List.fromList(_buffer.sublist(offset, offset + length));
        _buffer.removeRange(0, offset + length);

        try {
          return Main.fromBuffer(payload);
        } catch (error) {
          LogService.log('[FlipperClient] protobuf frame parse error: $error');
          return null;
        }
      }

      if (shift >= 35) {
        _buffer.removeAt(0);
        return null;
      }
    }

    return null;
  }
}
