import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../theme.dart';
import 'models/device_info.dart';

class DeviceController extends ChangeNotifier {
  DeviceController() {
    _device = _client.connectedDevice;
    _connectionSub = _client.connectionStream.listen(_onConnectionState);
  }

  final FlipperClient _client = FlipperOneClient().get();

  FlipperDevice? _device;
  bool _deviceDisconnected = false;
  bool _deviceLoading = false;
  bool _deviceInfoConnected = false;
  bool _alertPlaying = false;
  Map<String, String> _info = {};
  int _infoRequestGeneration = 0;
  bool _disposed = false;

  StreamSubscription<FlipperConnectionState>? _connectionSub;
  StreamSubscription<Map<String, String>>? _batteryStreamSub;
  StreamSubscription<Map<String, String>>? _storageStreamSub;

  // ── Getters ──────────────────────────────────────────────────────────────

  FlipperClient get client => _client;
  FlipperDevice? get device => _device;
  bool get deviceLoading => _deviceLoading;
  bool get deviceInfoConnected => _deviceInfoConnected;
  bool get alertPlaying => _alertPlaying;
  Map<String, String> get info => _info;

  bool get isConnected => _device != null && !_deviceDisconnected;

  String get firmwareVersion => DeviceInfoReader.firmwareVersion(_info);
  String get buildDate => DeviceInfoReader.buildDate(_info);
  String get deviceName => DeviceInfoReader.deviceName(_info);
  List<MapEntry<String, String>> get deviceInfoEntries =>
      DeviceInfoReader.infoEntries(_info);

  String buildExportDump() => DeviceInfoReader.buildExportDump(_info);

  // ── Public actions ────────────────────────────────────────────────────────

  /// Connects to [device]. Throws on failure.
  Future<void> connect(FlipperDevice device) async {
    final connected = await _client.connect(device);
    _setupDevice(connected);
  }

  Future<void> disconnect() async {
    await _client.disconnect();
    _device = null;
    _deviceDisconnected = false;
    _deviceLoading = false;
    _deviceInfoConnected = false;
    _info = {};
    _infoRequestGeneration++;
    _notify();
  }

  void synchronize() => _startDataLoading();

  /// Returns true on success, false on failure.
  Future<bool> playAlert() async {
    if (_device == null || _deviceDisconnected || _alertPlaying) return false;
    _alertPlaying = true;
    _notify();
    try {
      await _client.playAudiovisualAlert(
        PlayAudiovisualAlertRequest(),
        timeout: const Duration(seconds: 8),
      );
      return true;
    } catch (e) {
      LogService.log('[DeviceController] play alert failed: $e');
      return false;
    } finally {
      _alertPlaying = false;
      _notify();
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _cancelDataStreams();
    _connectionSub?.cancel();
    super.dispose();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setupDevice(FlipperDevice device) {
    _device = device;
    _deviceDisconnected = false;
    _notify();
    _startDataLoading();
  }

  void _startDataLoading() {
    _cancelDataStreams();
    _deviceLoading = true;
    _deviceInfoConnected = false;
    _info = {};
    _notify();

    final generation = ++_infoRequestGeneration;
    var pending = 5;
    var batteryFirstDone = false;
    var storageFirstDone = false;

    void onPartDone() {
      if (generation != _infoRequestGeneration) return;
      pending--;
      if (pending > 0) return;
      _deviceLoading = false;
      _deviceInfoConnected = _info.isNotEmpty;
      _notify();
    }

    void mergeInfo(Map<String, String> data) {
      if (generation != _infoRequestGeneration || data.isEmpty) return;
      _info = {..._info, ...data};
      _deviceInfoConnected = true;
      if (data.keys.any(
        (k) => k.startsWith('firmware') || k == 'software_revision',
      )) {
        QAppThemeController.instance.syncFirmwareFromDeviceInfo(_info);
      }
      _notify();
    }

    _batteryStreamSub = _client.watchBattery().listen(
      (data) {
        mergeInfo(data);
        if (!batteryFirstDone) {
          batteryFirstDone = true;
          onPartDone();
        }
      },
      onError: (e) => LogService.log('[DeviceController] battery: $e'),
    );

    _storageStreamSub = _client.watchStorage().listen(
      (data) {
        mergeInfo(data);
        if (!storageFirstDone) {
          storageFirstDone = true;
          onPartDone();
        }
      },
      onError: (e) => LogService.log('[DeviceController] storage: $e'),
    );

    Future<void> loadStatic(
      String label,
      Future<Map<String, String>> Function() loader,
    ) async {
      try {
        mergeInfo(await loader());
      } catch (e) {
        LogService.log('[DeviceController] $label failed: $e');
      } finally {
        onPartDone();
      }
    }

    unawaited(loadStatic('protobuf', _loadProtobufVersion));
    unawaited(loadStatic('device info', _client.awaitDeviceInfo));
    unawaited(loadStatic('datetime', _loadDateTime));
  }

  Future<Map<String, String>> _loadProtobufVersion() async {
    final v = await _client.protobufVersion(
      timeout: const Duration(seconds: 15),
    );
    final major = v.single.major;
    final minor = v.single.minor;
    return {
      'protobuf_version': '$major.$minor',
      'protobuf_version_major': '$major',
      'protobuf_version_minor': '$minor',
    };
  }

  Future<Map<String, String>> _loadDateTime() async {
    final response = await _client.getDateTime(
      timeout: const Duration(seconds: 15),
    );
    final dt = response.single.datetime;
    return {
      'datetime':
          '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}',
    };
  }

  void _onConnectionState(FlipperConnectionState state) {
    if (state.connected) {
      _device = state.device;
      _deviceDisconnected = false;
      _notify();
      return;
    }
    _cancelDataStreams();
    _deviceDisconnected = true;
    _deviceLoading = false;
    _deviceInfoConnected = false;
    _infoRequestGeneration++;
    _notify();
  }

  void _cancelDataStreams() {
    _batteryStreamSub?.cancel();
    _batteryStreamSub = null;
    _storageStreamSub?.cancel();
    _storageStreamSub = null;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
