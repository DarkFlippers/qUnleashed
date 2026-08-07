import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flipperlib/flipperlib.dart' hide File;

import 'catalog_api.dart';
import 'catalog_context.dart';
import 'catalog_mode.dart';
import 'device_source.dart';
import 'install_engine.dart';
import 'manifest_registry.dart';
import 'models/card.dart';
import 'update_registry.dart';

export 'catalog_context.dart' show kAppsRoot, kManifestsRoot, kTaskCooldown;

class AppsBackend {
  AppsBackend._() {
    _deviceId = client.activeDevice?.id;
    client.connectionStream.listen(_onConnection);
  }

  static final AppsBackend instance = AppsBackend._();

  final FlipperClient client = FlipperOneClient().get();
  final AppsCatalogApi api = AppsCatalogApi();

  late final CatalogContext catalog = CatalogContext(
    client: client,
    api: api,
    currentDeviceId: () => _deviceId,
  );

  late final ManifestRegistry manifests = ManifestRegistry(client: client);
  late final InstallEngine engine = InstallEngine(
    client: client,
    api: api,
    manifests: manifests,
    catalog: catalog,
    onInstalled: _adoptInstalled,
  );
  late final DeviceSource device = DeviceSource(
    client: client,
    api: api,
    manifests: manifests,
    engine: engine,
  );
  late final UpdateRegistry updates = UpdateRegistry(
    client: client,
    api: api,
    manifests: manifests,
    engine: engine,
    catalog: catalog,
  );

  String? _deviceId;

  bool get isReady => client.isConnected && client.mode == FlipperMode.rpc;

  ValueNotifier<CatalogMode> get mode => catalog.mode;
  String? get deviceApi => catalog.deviceApi;
  String? get deviceTarget => catalog.deviceTarget;
  List<AppSdk> get serverSdks => catalog.serverSdks;
  String? get serverApi => catalog.serverApi;
  String? get compatApi => catalog.compatApi;
  ApiVerdict? get incompatibility => catalog.incompatibility;
  bool get apiFallbackEnabled => catalog.apiFallbackEnabled;
  bool get sourceBuildEnabled => catalog.sourceBuildEnabled;
  bool get ignoreSdkMismatch => catalog.ignoreSdkMismatch;
  ValueNotifier<int> get compatibilityNeeded => catalog.compatibilityNeeded;
  String? get fallbackApi => catalog.fallbackApi;
  (int, int)? get targetSdk => catalog.targetSdk;

  Future<void> resolveMode({bool force = false}) =>
      catalog.resolveMode(force: force);
  void chooseSourceBuild() => catalog.chooseSourceBuild();
  void chooseCompatibility() => catalog.chooseCompatibility();
  Future<void> ensureDeviceFilters({bool required = false}) =>
      catalog.ensureDeviceFilters(required: required);

  Future<void> _adoptInstalled({
    required String alias,
    required String devicePath,
    required List<int> fapBytes,
  }) {
    return device.adoptInstalled(
      alias: alias,
      devicePath: devicePath,
      fapBytes: fapBytes,
    );
  }

  void _onConnection(FlipperConnectionState state) {
    if (!state.connected || state.mode != FlipperMode.rpc) {
      catalog.resetDeviceState();
      catalog.resolvedForDeviceId = null;
      catalog.mode.value = CatalogMode.normal;
      manifests.handleDisconnect();
      device.handleDisconnect();
      updates.handleDisconnect();
      return;
    }
    final id = state.device?.id;
    if (id != null && id != _deviceId) {
      _deviceId = id;
      catalog.sourceBuildEnabled = false;
      catalog.resetDeviceState();
      catalog.resolvedForDeviceId = null;
      manifests.handleDeviceChange();
      device.handleDeviceChange();
      updates.handleDeviceChange();
    } else {
      device.handleConnect();
    }
    if (catalog.resolvedForDeviceId != _deviceId && !catalog.isResolving) {
      catalog.mode.value = CatalogMode.resolving;
      unawaited(catalog.resolveMode(force: true));
    }
  }
}
