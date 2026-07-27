import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flipperlib/flipperlib.dart' hide File;

import 'catalog_api.dart';
import 'catalog_mode.dart';
import 'device_source.dart';
import 'install_engine.dart';
import 'manifest_registry.dart';
import 'models/card.dart';
import 'update_registry.dart';

const String kAppsRoot = '/ext/apps';
const String kManifestsRoot = '/ext/apps_manifests';
const Duration kTaskCooldown = Duration(seconds: 1);

class AppsBackend {
  AppsBackend._() {
    _deviceId = client.activeDevice?.id;
    client.connectionStream.listen(_onConnection);
  }

  static final AppsBackend instance = AppsBackend._();

  final FlipperClient client = FlipperOneClient().get();
  final AppsCatalogApi api = AppsCatalogApi();

  late final ManifestRegistry manifests = ManifestRegistry(client: client);
  late final InstallEngine engine = InstallEngine(
    client: client,
    api: api,
    manifests: manifests,
    backend: this,
  );
  late final DeviceSource device = DeviceSource(
    client: client,
    api: api,
    manifests: manifests,
    engine: engine,
    backend: this,
  );
  late final UpdateRegistry updates = UpdateRegistry(
    client: client,
    api: api,
    manifests: manifests,
    engine: engine,
    backend: this,
  );

  String? _deviceId;

  bool get isReady => client.isConnected && client.mode == FlipperMode.rpc;

  final ValueNotifier<CatalogMode> mode =
      ValueNotifier(CatalogMode.resolving);

  String? _deviceApi;
  String? _deviceTarget;
  String? get deviceApi => _deviceApi;
  String? get deviceTarget => _deviceTarget;

  List<AppSdk> serverSdks = const [];
  AppSdk? serverLatestSdk;
  String? get serverApi => serverLatestSdk?.api;

  String? _compatApi;
  String? get compatApi => _compatApi;

  bool _modeResolving = false;
  String? _resolvedForDeviceId;

  bool get apiFallbackEnabled => mode.value == CatalogMode.compatibility;

  bool get ignoreSdkMismatch =>
      mode.value == CatalogMode.compatibility || api.unfiltered;

  final ValueNotifier<int> compatibilityNeeded = ValueNotifier(0);
  String? fallbackApi;

  void flagCompatibilityNeeded(String buildApi) {
    fallbackApi = buildApi;
    if (!apiFallbackEnabled) compatibilityNeeded.value++;
  }

  (int, int)? get targetSdk => parseApi(_deviceApi);

  Future<void> resolveMode({bool force = false}) async {
    if (_modeResolving) return;
    if (!force &&
        mode.value != CatalogMode.resolving &&
        mode.value != CatalogMode.mismatch) {
      return;
    }
    _modeResolving = true;
    if (force) mode.value = CatalogMode.resolving;
    try {
      await ensureDeviceFilters();

      try {
        serverSdks = await api.fetchSdks();
      } catch (e) {
        LogService.log('[AppsBackend] fetchSdks failed: $e');
      }

      final target = _deviceTarget;
      final targetSdks = target == null
          ? serverSdks
          : serverSdks.where((s) => s.target == target).toList();
      serverLatestSdk = latestSdk(targetSdks);

      if (_deviceApi == null || _deviceTarget == null || targetSdks.isEmpty) {
        api.api = _deviceApi;
        api.target = _deviceTarget;
        api.unfiltered = false;
        _compatApi = null;
        mode.value = CatalogMode.normal;
        return;
      }

      if (serverHasApi(targetSdks, _deviceApi)) {
        api.api = _deviceApi;
        api.target = _deviceTarget;
        api.unfiltered = false;
        _compatApi = null;
        mode.value = CatalogMode.normal;
      } else {
        _compatApi = pickCompatApi(targetSdks, _deviceApi);
        mode.value = CatalogMode.mismatch;
      }
      LogService.log(
        '[AppsBackend] mode=${mode.value.name} device=$_deviceApi '
        'server=$serverApi compat=$_compatApi',
      );
    } finally {
      _modeResolving = false;
      if (mode.value != CatalogMode.resolving) {
        _resolvedForDeviceId = _deviceId;
      }
    }
  }

  void chooseCompatibility() {
    final compat = _compatApi;
    if (compat == null || _deviceTarget == null) {
      api.api = null;
      api.target = null;
      api.unfiltered = true;
    } else {
      api.api = compat;
      api.target = _deviceTarget;
      api.unfiltered = false;
    }
    mode.value = CatalogMode.compatibility;
  }

  void declineCatalog() {
    mode.value = CatalogMode.disabled;
  }

  void _onConnection(FlipperConnectionState state) {
    if (!state.connected || state.mode != FlipperMode.rpc) {
      _resetDeviceState();
      _resolvedForDeviceId = null;
      mode.value = CatalogMode.normal;
      manifests.handleDisconnect();
      device.handleDisconnect();
      updates.handleDisconnect();
      return;
    }
    final id = state.device?.id;
    if (id != null && id != _deviceId) {
      _deviceId = id;
      _resetDeviceState();
      _resolvedForDeviceId = null;
      manifests.handleDeviceChange();
      device.handleDeviceChange();
      updates.handleDeviceChange();
    }
    if (_resolvedForDeviceId != _deviceId && !_modeResolving) {
      mode.value = CatalogMode.resolving;
      unawaited(resolveMode(force: true));
    }
  }

  void _resetDeviceState() {
    api.target = null;
    api.api = null;
    api.unfiltered = false;
    _deviceApi = null;
    _deviceTarget = null;
    _compatApi = null;
  }

  Future<void> ensureDeviceFilters({bool required = false}) async {
    if (_deviceApi != null && _deviceTarget != null) return;
    if (!isReady && !required) return;
    try {
      final info =
          await client.awaitDeviceInfo().timeout(const Duration(seconds: 20));
      final target = _firstInfoValue(info, const [
        'hardware_target',
        'hardware.target',
        'target',
      ]);
      final major = _firstInfoValue(info, const [
        'firmware_api_major',
        'firmware.api.major',
        'api.major',
        'api_major',
      ]);
      final minor = _firstInfoValue(info, const [
        'firmware_api_minor',
        'firmware.api.minor',
        'api.minor',
        'api_minor',
      ]);
      if (target != null) _deviceTarget = 'f$target';
      if (major != null) _deviceApi = '$major.${minor ?? '0'}';
      if (_deviceTarget != null && api.target == null) api.target = _deviceTarget;
      if (_deviceApi != null && api.api == null) api.api = _deviceApi;
    } catch (e) {
      LogService.log('[AppsBackend] deviceInfo failed: $e');
    }
    if (required && (_deviceTarget == null || _deviceApi == null)) {
      throw StateError(
        'Could not read the firmware target/API from the device; '
        'reconnect the Flipper and try again',
      );
    }
  }

  String? _firstInfoValue(Map<String, String> info, List<String> keys) {
    for (final key in keys) {
      final value = info[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
