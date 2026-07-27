import 'package:flutter/foundation.dart';
import 'package:flipperlib/flipperlib.dart' hide File;

import 'catalog_api.dart';
import 'device_source.dart';
import 'install_engine.dart';
import 'manifest_registry.dart';

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

  String? _deviceId;

  bool get isReady => client.isConnected && client.mode == FlipperMode.rpc;

  bool apiFallbackEnabled = false;

  final ValueNotifier<int> compatibilityNeeded = ValueNotifier(0);
  String? fallbackApi;

  void flagCompatibilityNeeded(String buildApi) {
    fallbackApi = buildApi;
    if (!apiFallbackEnabled) compatibilityNeeded.value++;
  }

  void enableApiFallback() {
    apiFallbackEnabled = true;
  }

  (int, int)? get targetSdk {
    final a = api.api;
    if (a == null || a.isEmpty) return null;
    final parts = a.split('.');
    final major = int.tryParse(parts[0]);
    if (major == null) return null;
    final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (major, minor);
  }

  void _onConnection(FlipperConnectionState state) {
    if (!state.connected || state.mode != FlipperMode.rpc) {
      api.target = null;
      api.api = null;
      manifests.handleDisconnect();
      device.handleDisconnect();
      return;
    }
    final id = state.device?.id;
    if (id != null && id != _deviceId) {
      _deviceId = id;
      api.target = null;
      api.api = null;
      api.apiRejectedByCatalog = false;
      manifests.handleDeviceChange();
      device.handleDeviceChange();
    }
  }

  Future<void> ensureDeviceFilters({bool required = false}) async {
    if (api.target != null && api.api != null) return;
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
      if (target != null) api.target = 'f$target';
      if (major != null) api.api = '$major.${minor ?? '0'}';
    } catch (e) {
      LogService.log('[AppsBackend] deviceInfo failed: $e');
    }
    if (required && (api.target == null || api.api == null)) {
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
