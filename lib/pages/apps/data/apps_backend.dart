import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flipperlib/flipperlib.dart' hide File;

import 'atp/atp_source.dart';
import 'binary_sources.dart';
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
  final AtpSource atp = AtpSource.instance;

  late final CatalogContext catalog = CatalogContext(
    client: client,
    api: api,
    currentDeviceId: () => _deviceId,
  );

  late final ManifestRegistry manifests = ManifestRegistry(client: client);
  late final AppSourceRegistry sources = AppSourceRegistry(
    catalog: CatalogBinarySource(api: api, catalog: catalog),
    atp: AtpBinarySource(atp),
  );
  late final InstallEngine engine = InstallEngine(
    client: client,
    api: api,
    manifests: manifests,
    catalog: catalog,
    sources: sources,
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
  bool get catalogOffline => catalog.catalogOffline;
  bool get apiFallbackEnabled => catalog.apiFallbackEnabled;
  bool get sourceBuildEnabled => catalog.sourceBuildEnabled;
  bool get ignoreSdkMismatch => catalog.ignoreSdkMismatch;
  CatalogModePreference get preference => catalog.preference;
  (int, int)? get targetSdk => catalog.targetSdk;

  Future<void> resolveMode({bool force = false}) async {
    await catalog.resolveMode(force: force);
    await ensureIndex();
  }

  Future<void> ensureIndex() async {
    atp.bindTarget(deviceTarget);
    await atp.ensureLoaded();
  }

  Future<void> loadPreference() => catalog.loadPreference();
  Future<void> setPreference(CatalogModePreference value) =>
      catalog.setPreference(value);
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
      // A link that is coming back — a reconnect, a connect attempt or a mode
      // switch on a live session — keeps the install queue, everything else
      // ends it.
      engine.handleDisconnect(
        reconnecting: state.connected || state.reconnecting || state.connecting,
      );
      return;
    }
    final id = state.device?.id;
    if (id != null && id != _deviceId) {
      _deviceId = id;
      catalog.resetDeviceState();
      catalog.resolvedForDeviceId = null;
      manifests.handleDeviceChange();
      device.handleDeviceChange();
      updates.handleDeviceChange();
      engine.handleDeviceChange();
    } else {
      device.handleConnect();
      engine.handleConnect();
    }
    if (catalog.resolvedForDeviceId != _deviceId && !catalog.isResolving) {
      catalog.mode.value = CatalogMode.resolving;
      unawaited(catalog.resolveMode(force: true));
    }
  }
}
