import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flipperlib/flipperlib.dart' hide File;

import 'animation_files.dart';
import 'binary_sources.dart';
import 'catalog_api.dart';
import 'catalog_context.dart';
import 'catalog_mode.dart';
import 'device_source.dart';
import 'dolphin_registry.dart';
import 'install_engine.dart';
import 'manifest_registry.dart';
import 'models/card.dart';
import 'update_registry.dart';
import '../../../services/guarded.dart';

export 'catalog_context.dart' show kAppsRoot, kManifestsRoot, kTaskCooldown;

class AppsBackend {
  AppsBackend._() {
    client.connectionStream.listen(_onConnection);
  }

  static final AppsBackend instance = AppsBackend._();

  final FlipperClient client = FlipperOneClient().get();
  final AppsCatalogApi api = AppsCatalogApi();

  late final CatalogContext catalog = CatalogContext(client: client, api: api);

  late final ManifestRegistry manifests = ManifestRegistry(client: client);
  late final DolphinRegistry dolphin = DolphinRegistry(client: client);
  late final ManifestRegistry styleManifests = ManifestRegistry(
    client: client,
    root: kMenuStyleManifestsRoot,
    cached: false,
  );
  bool _menuStylesWanted = false;
  late final AnimationFiles animationFiles = AnimationFiles(api: api);
  late final CatalogBinarySource source = CatalogBinarySource(
    api: api,
    catalog: catalog,
  );
  late final InstallEngine engine = InstallEngine(
    client: client,
    api: api,
    manifests: manifests,
    catalog: catalog,
    source: source,
    onInstalled: _adoptInstalled,
    dolphin: dolphin,
    styleManifests: styleManifests,
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

  Future<void> resolveMode({bool force = false}) =>
      catalog.resolveMode(force: force);

  Future<void> watchMenuStyles() {
    _menuStylesWanted = true;
    return styleManifests.ensureFresh();
  }

  Future<void> loadPreference() => catalog.loadPreference();
  Future<void> setServer(String server) async {
    await loadPreference();
    final previous = api.server;
    await catalog.setServer(server);
    if (previous != api.server) {
      updates.handleDeviceChange();
      if (isReady) await updates.refresh(force: true);
    }
  }

  Future<void> setPreference(CatalogModePreference value) =>
      catalog.setPreference(value);

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
    // Answered before the link state and regardless of it. A switch is a switch
    // whether or not the new Flipper has RPC up yet, and the guard below drops
    // everything that has not - which is how a switch arriving on, say, a CLI
    // event would leave the whole section describing the previous device.
    if (state.event == FlipperConnectionEvent.deviceChanged) {
      catalog.resetDeviceState();
      catalog.resolvedForDeviceId = null;
      manifests.handleDeviceChange();
      dolphin.handleDeviceChange();
      styleManifests.handleDeviceChange();
      device.handleDeviceChange();
      updates.handleDeviceChange();
      engine.handleDeviceChange();
    }
    if (!state.rpcReady) {
      catalog.resetDeviceState();
      catalog.resolvedForDeviceId = null;
      catalog.mode.value = CatalogMode.normal;
      manifests.handleDisconnect();
      dolphin.handleDisconnect();
      styleManifests.handleDisconnect();
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
    dolphin.handleConnect();
    if (_menuStylesWanted) {
      unawaited(
        guarded('[AppsBackend] read menu styles', styleManifests.ensureFresh),
      );
    }
    if (state.event != FlipperConnectionEvent.deviceChanged) {
      device.handleConnect();
      engine.handleConnect();
    }
    if (catalog.resolvedForDeviceId != client.scopedDeviceId &&
        !catalog.isResolving) {
      catalog.mode.value = CatalogMode.resolving;
      unawaited(
        guarded(
          '[AppsBackend] resolve mode',
          () => catalog.resolveMode(force: true),
        ),
      );
    }
  }
}
