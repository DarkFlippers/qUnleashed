import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../theme/theme.dart';
import '../models/device_info.dart';

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
  StreamSubscription<Map<String, String>>? _infoStreamSub;

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
    _resetSession();
  }

  void synchronize() => _startDataLoading();

  Future<void> reboot() async {
    if (_device == null || _deviceDisconnected) return;
    try {
      await _client.reboot(RebootRequest(mode: RebootRequest_RebootMode.OS));
    } catch (e) {
      LogService.log('[DeviceController] reboot failed: $e');
    }
    _resetSession();
  }

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

  void _resetSession() {
    _device = null;
    _deviceDisconnected = false;
    _deviceLoading = false;
    _deviceInfoConnected = false;
    _info = {};
    _infoRequestGeneration++;
    _notify();
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

    _infoStreamSub = _client.deviceInfoUpdates.listen((data) {
      if (generation != _infoRequestGeneration || data.isEmpty) return;
      _info = {..._info, ...data};
      _deviceInfoConnected = true;
      if (_deviceLoading) {
        _deviceLoading = false;
      }
      if (data.keys.any(
        (k) => k.startsWith('firmware') || k == 'software_revision',
      )) {
        QAppThemeController.instance.syncFirmwareFromDeviceInfo(_info);
      }
      _notify();
    }, onError: (e) => LogService.log('[DeviceController] info stream: $e'));

    _client.startDeviceInfoCollection();
  }

  void _onConnectionState(FlipperConnectionState state) {
    // An in-flight connect attempt is not a session change: ignore it so the
    // page does not flip to the disconnected view while connecting.
    if (state.connecting) return;
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
    _infoStreamSub?.cancel();
    _infoStreamSub = null;
    _client.stopDeviceInfoCollection();
  }
}
