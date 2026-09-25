import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../services/connection/device_info_watch.dart';
import '../../../services/connection/known_devices.dart';
import '../../../services/connection/link_service.dart';
import '../../../services/logging.dart';
import '../../../theme/theme.dart';
import '../models/connection_state.dart';
import '../models/device_info.dart';

class DeviceController extends ChangeNotifier {
  /// [client] is the one the app built at its composition root.
  ///
  /// Optional, and falling back to the global, because the two entry points in
  /// `main.dart` are not the only builders - ADR 0002 converts a site when a
  /// change is already touching it, rather than all at once. What the
  /// parameter buys today is that a widget test can hand this a fake instead
  /// of a client that opens real BLE streams for the length of the run.
  DeviceController({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get() {
    _device = _client.connectedDevice;
    _connectionSub = _client.connectionStream.listen(_onConnectionState);
    _sessionsSub = _client.sessionsStream.listen((_) => _notify());
    _releasedSub = _links.activeReleased.listen((_) => _resetSession());
    _dfuPresentSub = _dfuDetector.presence.listen(setDfuPresent);
    _dfuDetector.start();
    // A session a home-screen widget brought up cold has no device data yet;
    // collect it now that the full app is here.
    if (_device != null) _ensureDataLoading();
  }

  final FlipperClient _client;
  final DfuDetector _dfuDetector = DfuDetector();
  final KnownDevicesStore _knownDevices = KnownDevicesStore.instance;
  final LinkService _links = LinkService.instance;

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
  String? _loadedForDeviceId;

  StreamSubscription<FlipperConnectionState>? _connectionSub;
  StreamSubscription<List<FlipperSessionInfo>>? _sessionsSub;
  StreamSubscription<FlipperDevice>? _releasedSub;
  StreamSubscription<Map<String, String>>? _infoStreamSub;
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

  void synchronize() => _startDataLoading();

  Future<void> reboot() async {
    if (_device == null || _deviceDisconnected) return;
    try {
      await _client.reboot(RebootRequest(mode: RebootRequest_RebootMode.OS));
    } catch (e) {
      // Two throws reach here and flipperlib logs neither: a teardown that
      // fails inside the disconnect reboot() performs itself, and the
      // synchronous StateError when the session went away between the guard
      // above and the call. The RPC's own outcome never does - #120.
      LogService.warn('[DeviceController] reboot failed: $e');
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
      // flipperlib keeps the 8s timeout at error, but not a firmware
      // status: ERROR_APP_SYSTEM_LOCKED, the Flipper busy running an app,
      // which is when someone reaches for this. The page has one string for
      // every cause, so the toast does not narrow it either.
      LogService.warn('[DeviceController] play alert failed: $e');
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
    _links.suspended = recovering;
    if (recovering) {
      _dfuDetector.stop();
    } else {
      _dfuDetector.start();
    }
    _notify();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _cancelDataStreams();
    _connectionSub?.cancel();
    _sessionsSub?.cancel();
    _releasedSub?.cancel();
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
    _loadedForDeviceId = null;
    _infoRequestGeneration++;
    _notify();
  }

  // Loading is (re)started when the active device changed or the previous
  // session's data died with a disconnect; a load already in flight for this
  // device is left alone.
  void _ensureDataLoading() {
    final device = _device;
    if (device == null) return;
    if (_loadedForDeviceId == device.id &&
        (_deviceLoading || _deviceInfoConnected)) {
      return;
    }
    _startDataLoading();
  }

  void _startDataLoading() {
    _loadedForDeviceId = _device?.id;
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
    }, onError: (e) => LogService.info('[DeviceController] info stream: $e'));

    DeviceInfoWatchService.instance.start(_client);
  }

  void _onConnectionState(FlipperConnectionState state) {
    // An in-flight connect attempt is not a session change: ignore it so the
    // page does not flip to the disconnected view while connecting.
    if (state.connecting) return;
    if (state.connected) {
      final incoming = state.device;
      if (incoming != null) _device = incoming;
      _deviceDisconnected = false;
      // Covers the transitions the controller does not drive itself: a warm
      // session promoted to active after a disconnect, an activation swap and
      // a restored link after an automatic reconnect.
      _ensureDataLoading();
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
    DeviceInfoWatchService.instance.stop();
  }
}
