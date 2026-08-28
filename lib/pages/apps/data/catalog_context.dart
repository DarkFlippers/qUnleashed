import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../components/codec/fap/api_version.dart';
import '../../../components/path.dart';
import '../../../services/assembler/controller.dart';
import '../../../services/logging.dart';
import 'catalog_api.dart';
import 'catalog_mode.dart';
import 'models/card.dart';

const String kAppsRoot = '/ext/apps';
const String kManifestsRoot = '/ext/apps_manifests';
const Duration kTaskCooldown = Duration(seconds: 1);

/// How long the catalog has to answer before the apps manager takes over.
const Duration kCatalogTimeout = Duration(seconds: 15);

/// `/ext/apps/Tools/foo.fap` -> `foo`.
String aliasFromFapPath(String path) {
  final base = basename(path);
  return base.endsWith('.fap') ? base.substring(0, base.length - 4) : base;
}

/// The link is up and speaks RPC — the precondition for every device call the
/// apps module makes.
extension FlipperRpcReady on FlipperClient {
  bool get isRpcReady => isConnected && mode == FlipperMode.rpc;
}

/// Which catalog the device may talk to: the firmware API/target read from the
/// Flipper, the SDKs the server offers and the compatibility mode resolved from
/// both. Owned by `AppsBackend`; the registries and the install engine read it
/// instead of reaching back into the backend.
class CatalogContext {
  CatalogContext({
    required this.client,
    required this.api,
    required this.currentDeviceId,
  });

  final FlipperClient client;
  final AppsCatalogApi api;

  /// Id of the device the backend is currently bound to, read at the moment a
  /// mode resolution finishes.
  final String? Function() currentDeviceId;

  bool get isReady => client.isRpcReady;

  final ValueNotifier<CatalogMode> mode = ValueNotifier(CatalogMode.resolving);

  String? _deviceApi;
  String? _deviceTarget;
  String? get deviceApi => _deviceApi;
  String? get deviceTarget => _deviceTarget;

  List<AppSdk> serverSdks = const [];
  AppSdk? serverLatestSdk;
  String? get serverApi => serverLatestSdk?.api;

  String? _compatApi;
  String? get compatApi => _compatApi;

  bool _catalogOffline = false;

  /// Set when the catalog itself failed to answer, so the manager-only mode can
  /// tell a dead catalog from a firmware the catalog cannot serve.
  bool get catalogOffline => _catalogOffline;

  bool _builderAvailable = false;

  bool _modeResolving = false;
  bool get isResolving => _modeResolving;
  String? resolvedForDeviceId;

  bool get apiFallbackEnabled => mode.value == CatalogMode.nearestApi;

  bool get sourceBuildEnabled => mode.value == CatalogMode.sourceBuild;

  bool get ignoreSdkMismatch =>
      apiFallbackEnabled || sourceBuildEnabled || api.unfiltered;

  static const String _prefMode = 'apps_catalog_mode';

  CatalogModePreference _preference = CatalogModePreference.auto;
  CatalogModePreference get preference => _preference;
  bool _preferenceLoaded = false;

  Future<void> loadPreference() async {
    if (_preferenceLoaded) return;
    _preferenceLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    _preference = CatalogModePreference.parse(prefs.getString(_prefMode));
  }

  Future<void> setPreference(CatalogModePreference value) async {
    if (_preference == value) return;
    _preference = value;
    _preferenceLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, value.name);
    await resolveMode(force: true);
  }

  (int, int)? get targetSdk => parseApi(_deviceApi);

  Future<void> resolveMode({bool force = false}) async {
    if (_modeResolving) return;
    if (!force &&
        mode.value != CatalogMode.resolving &&
        mode.value != CatalogMode.managerOnly) {
      return;
    }
    _modeResolving = true;
    if (force) mode.value = CatalogMode.resolving;
    try {
      await loadPreference();
      await ensureDeviceFilters();

      var offline = false;
      try {
        serverSdks = await api.fetchSdks().timeout(kCatalogTimeout);
      } catch (e) {
        LogService.log('[AppsBackend] fetchSdks failed: $e');
        offline = true;
      }
      _catalogOffline = offline;

      final target = _deviceTarget;
      final targetSdks = target == null
          ? serverSdks
          : serverSdks.where((s) => s.target == target).toList();
      serverLatestSdk = latestSdk(targetSdks);

      if (offline) {
        _useManagerOnly();
        return;
      }

      if (_deviceApi == null || _deviceTarget == null || targetSdks.isEmpty) {
        _useCatalog(_deviceApi);
        return;
      }

      final res = resolveCatalogApi(targetSdks, _deviceApi);
      // Probing the build server costs a round trip, so it only runs when the
      // answer can change the mode.
      final needsBuilder =
          res.verdict != ApiVerdict.normal ||
          _preference == CatalogModePreference.sourceBuild;
      _builderAvailable = needsBuilder
          ? await AssemblerController.instance.builderAvailable()
          : false;
      final next = resolveCatalogMode(
        verdict: res.verdict,
        hasNearestApi: res.api != null,
        builderAvailable: _builderAvailable,
        preference: _preference,
      );
      switch (next) {
        case CatalogMode.normal:
          _useCatalog(res.api ?? _deviceApi);
        case CatalogMode.nearestApi:
          _useNearestApi(res.api);
        case CatalogMode.sourceBuild:
          _useSourceBuild();
        case CatalogMode.managerOnly:
          _useManagerOnly();
        case CatalogMode.resolving:
          break;
      }
      LogService.log(
        '[AppsBackend] mode=${mode.value.name} device=$_deviceApi '
        'server=$serverApi picked=${res.api} verdict=${res.verdict.name} '
        'builder=$_builderAvailable pref=${_preference.name}',
      );
    } finally {
      _modeResolving = false;
      if (mode.value != CatalogMode.resolving) {
        resolvedForDeviceId = currentDeviceId();
      }
    }
  }

  void _useCatalog(String? catalogApi) {
    api.api = catalogApi;
    api.target = _deviceTarget;
    api.unfiltered = false;
    _compatApi = null;
    mode.value = CatalogMode.normal;
  }

  void _useSourceBuild() {
    api.api = null;
    api.target = null;
    api.unfiltered = true;
    _compatApi = null;
    mode.value = CatalogMode.sourceBuild;
  }

  void _useNearestApi(String? nearestApi) {
    _compatApi = nearestApi;
    if (nearestApi == null || _deviceTarget == null) {
      api.api = null;
      api.target = null;
      api.unfiltered = true;
    } else {
      api.api = nearestApi;
      api.target = _deviceTarget;
      api.unfiltered = false;
    }
    mode.value = CatalogMode.nearestApi;
  }

  void _useManagerOnly() {
    api.api = _deviceApi;
    api.target = _deviceTarget;
    api.unfiltered = false;
    _compatApi = null;
    mode.value = CatalogMode.managerOnly;
  }

  void resetDeviceState() {
    api.target = null;
    api.api = null;
    api.unfiltered = false;
    _deviceApi = null;
    _deviceTarget = null;
    _compatApi = null;
    _catalogOffline = false;
  }

  Future<void> ensureDeviceFilters({bool required = false}) async {
    if (_deviceApi != null && _deviceTarget != null) return;
    if (!isReady && !required) return;
    try {
      final info = await client.awaitDeviceInfo().timeout(
        const Duration(seconds: 20),
      );
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
      if (_deviceTarget != null && api.target == null) {
        api.target = _deviceTarget;
      }
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
