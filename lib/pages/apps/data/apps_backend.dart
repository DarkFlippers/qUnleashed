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
    client.connectionStream.listen(_onConnection);
  }

  static final AppsBackend instance = AppsBackend._();

  final FlipperClient client = FlipperOneClient().get();
  final AppsCatalogApi api = AppsCatalogApi();
  final AtpSource atp = AtpSource.instance;

  late final CatalogContext catalog = CatalogContext(client: client, api: api);

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

  bool get isReady => client.isRpcReady;

  ValueNotifier<CatalogMode> get mode => catalog.mode;
  String? get deviceApi => catalog.deviceApi;
  String? get deviceTarget => catalog.deviceTarget;
  List<AppSdk> get serverSdks => catalog.serverSdks;
  String? get serverApi => catalog.serverApi;
  String? get compatApi => catalog.compatApi;
  bool get catalogOffline => catalog.catalogOffline;
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

  Future<void> _adoptInstalled({
    required DeviceToken token,
    required String alias,
    required String devicePath,
    required List<int> fapBytes,
  }) {
    return device.adoptInstalled(
      token: token,
      alias: alias,
      devicePath: devicePath,
      fapBytes: fapBytes,
    );
  }

  void _onConnection(FlipperConnectionState state) {
    // Answered before the link state and regardless of it. A switch is a switch
    // whether or not the new Flipper has RPC up yet, and the guard below drops
    // everything that has not - which is how a switch arriving on, say, a CLI
    // event would leave the whole section describing the previous device.
    if (state.event == FlipperConnectionEvent.deviceChanged) {
      catalog.resetDeviceState();
      catalog.resolvedForDeviceId = null;
      manifests.handleDeviceChange();
      device.handleDeviceChange();
      updates.handleDeviceChange();
      engine.handleDeviceChange();
    }
    if (!state.rpcReady) {
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
    // Not after a switch: the caches were just emptied for the new Flipper, and
    // handleConnect exists to re-check a device that may have changed while the
    // link was down - a different question, already answered.
    if (state.event != FlipperConnectionEvent.deviceChanged) {
      device.handleConnect();
      engine.handleConnect();
    }
    if (catalog.resolvedForDeviceId != client.scopedDeviceId &&
        !catalog.isResolving) {
      catalog.mode.value = CatalogMode.resolving;
      unawaited(catalog.resolveMode(force: true));
    }
  }
}
