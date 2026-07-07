import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../services/connection/known_devices.dart';
import '../../../theme/theme.dart';
import '../models/connection_state.dart';
import '../models/device_info.dart';

class DeviceController extends ChangeNotifier {
  DeviceController() {
    _device = _client.connectedDevice;
    _connectionSub = _client.connectionStream.listen(_onConnectionState);
    _usbEventsSub = _client.usbEvents.listen((_) => _scheduleAutoConnect());
    _dfuPresentSub = _dfuDetector.presence.listen(setDfuPresent);
    _devicesSub = _client.devicesStream.listen((_) => _notify());
    _dfuDetector.start();
    _knownDevices.addListener(_notify);
    _knownDevices.load().whenComplete(_scheduleAutoConnect);
  }

  static const Duration _autoConnectDebounce = Duration(milliseconds: 500);

  final FlipperClient _client = FlipperOneClient().get();
  final DfuDetector _dfuDetector = DfuDetector();
  final KnownDevicesStore _knownDevices = KnownDevicesStore.instance;

  FlipperDevice? _device;
  bool _deviceDisconnected = false;
  bool _deviceLoading = false;
  bool _deviceInfoConnected = false;
  bool _alertPlaying = false;
  Map<String, String> _info = {};
  int _infoRequestGeneration = 0;
  bool _disposed = false;

  bool _dfuPresent = false;
  bool _recovering = false;

  String? _userDisconnectedId;
  String? _connectingKnownId;
  bool _bleAutoScanDone = false;
  final Set<String> _autoConnectAttemptedIds = {};
  Timer? _autoConnectTimer;

  StreamSubscription<FlipperConnectionState>? _connectionSub;
  StreamSubscription<List<FlipperDevice>>? _devicesSub;
  StreamSubscription<Map<String, String>>? _infoStreamSub;
  StreamSubscription<void>? _usbEventsSub;
  StreamSubscription<bool>? _dfuPresentSub;

  // ── Getters ──────────────────────────────────────────────────────────────

  FlipperClient get client => _client;
  FlipperDevice? get device => _device;
  bool get deviceLoading => _deviceLoading;
  bool get deviceInfoConnected => _deviceInfoConnected;
  bool get alertPlaying => _alertPlaying;
  bool get dfuPresent => _dfuPresent;
  bool get recovering => _recovering;
  Map<String, String> get info => _info;

  bool get isConnected => _device != null && !_deviceDisconnected;

  List<KnownDevice> get knownDevices => _knownDevices.devices;
  String? get connectingKnownId => _connectingKnownId;

  bool isKnownPresent(KnownDevice known) => _findPresent(known) != null;

  DeviceConnectionState get connectionState {
    if (_recovering) return DeviceConnectionState.recovering;
    if (isConnected) return DeviceConnectionState.connected;
    if (_client.isConnecting) return DeviceConnectionState.connecting;
    if (_dfuPresent) return DeviceConnectionState.dfu;
    return DeviceConnectionState.disconnected;
  }

  String get firmwareVersion => DeviceInfoReader.firmwareVersion(_info);
  String get buildDate => DeviceInfoReader.buildDate(_info);
  String get deviceName => DeviceInfoReader.deviceName(_info);
  List<MapEntry<String, String>> get deviceInfoEntries =>
      DeviceInfoReader.infoEntries(_info);

  String buildExportDump() => DeviceInfoReader.buildExportDump(_info);

  // ── Public actions ────────────────────────────────────────────────────────

  /// Connects to [device]. Throws on failure.
  Future<void> connect(FlipperDevice device) async {
    if (_userDisconnectedId == device.id) _userDisconnectedId = null;
    final connected = await _client.connect(device);
    _setupDevice(connected);
  }

  Future<void> disconnect() async {
    _userDisconnectedId = _device?.id;
    await _client.disconnect();
    _resetSession();
  }

  /// Connects to a remembered device, re-discovering it first when it is not
  /// in the current device list. Throws on failure.
  Future<void> connectKnown(KnownDevice known) async {
    if (isConnected || _client.isConnecting || _connectingKnownId != null) {
      return;
    }
    _connectingKnownId = known.id;
    _notify();
    try {
      final device = await _resolveKnown(known);
      if (device == null) {
        throw StateError('Device not found: ${known.name}');
      }
      await connect(device);
    } finally {
      _connectingKnownId = null;
      _notify();
    }
  }

  Future<void> forgetKnown(KnownDevice known) => _knownDevices.forget(known);

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

  void setDfuPresent(bool present) {
    if (_dfuPresent == present) return;
    _dfuPresent = present;
    _notify();
  }

  void setRecovering(bool recovering) {
    if (_recovering == recovering) return;
    _recovering = recovering;
    if (recovering) {
      _dfuDetector.stop();
    } else {
      _dfuDetector.start();
    }
    _notify();
  }

  void _scheduleAutoConnect() {
    _autoConnectTimer?.cancel();
    _autoConnectTimer = Timer(_autoConnectDebounce, _tryAutoConnect);
  }

  Future<void> _tryAutoConnect() async {
    if (_disposed || _recovering) return;
    if (isConnected || _client.isConnecting) return;

    final last = _knownDevices.lastDevice;
    try {
      await _client.refreshUsbOnly();
      if (last != null) {
        await _client.refreshBleKnown();
        if (_findPresent(last) == null && !_bleAutoScanDone) {
          _bleAutoScanDone = true;
          await _client.scanBle(timeout: const Duration(seconds: 8));
        }
      }
    } catch (e) {
      LogService.log('[DeviceController] auto-connect discovery failed: $e');
    }
    if (_disposed || isConnected || _client.isConnecting) return;

    final present = _client.devices;
    final presentIds = present.map((d) => d.id).toSet();
    _autoConnectAttemptedIds.removeWhere((id) => !presentIds.contains(id));
    if (_userDisconnectedId != null &&
        !presentIds.contains(_userDisconnectedId)) {
      _userDisconnectedId = null;
    }

    final candidate = _autoConnectCandidate(present, last);
    if (candidate == null) return;

    _autoConnectAttemptedIds.add(candidate.id);
    LogService.log('[DeviceController] auto-connecting to ${candidate.name}');
    try {
      await connect(candidate);
    } catch (e) {
      LogService.log('[DeviceController] auto-connect failed: $e');
    }
  }

  // A plugged-in USB Flipper always wins: the cable is an explicit user
  // action. With no USB present, the last remembered BLE device connects;
  // an unknown BLE device never does.
  FlipperDevice? _autoConnectCandidate(
    List<FlipperDevice> present,
    KnownDevice? last,
  ) {
    bool eligible(FlipperDevice d) =>
        d.id != _userDisconnectedId &&
        !_autoConnectAttemptedIds.contains(d.id);

    for (final d in present) {
      if (d.isUsb && eligible(d) && _client.isFlipperDevice(d)) return d;
    }
    if (last != null) {
      for (final d in present) {
        if (last.matches(d) && eligible(d)) return d;
      }
    }
    return null;
  }

  Future<FlipperDevice?> _resolveKnown(KnownDevice known) async {
    final present = _findPresent(known);
    if (present != null) return present;
    await _client.refreshBleKnown();
    final found = _findPresent(known);
    if (found != null) return found;
    await _client.scanBle(timeout: const Duration(seconds: 8));
    return _findPresent(known);
  }

  FlipperDevice? _findPresent(KnownDevice known) {
    for (final device in _client.devices) {
      if (known.matches(device)) return device;
    }
    return null;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _knownDevices.removeListener(_notify);
    _autoConnectTimer?.cancel();
    _cancelDataStreams();
    _connectionSub?.cancel();
    _devicesSub?.cancel();
    _usbEventsSub?.cancel();
    _dfuPresentSub?.cancel();
    _dfuDetector.dispose();
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
    _knownDevices.remember(device);
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
      final hardwareName = _info['hardware_name']?.trim();
      final connected = _device;
      if (connected != null &&
          hardwareName != null &&
          hardwareName.isNotEmpty) {
        _knownDevices.updateName(connected, hardwareName);
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
