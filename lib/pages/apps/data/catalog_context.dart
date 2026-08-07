import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../../../components/codec/api_version.dart';
import '../../../services/logging.dart';
import 'catalog_api.dart';
import 'catalog_mode.dart';
import 'models/card.dart';

const String kAppsRoot = '/ext/apps';
const String kManifestsRoot = '/ext/apps_manifests';
const Duration kTaskCooldown = Duration(seconds: 1);

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

  bool get isReady => client.isConnected && client.mode == FlipperMode.rpc;

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

  ApiVerdict? _incompatibility;
  ApiVerdict? get incompatibility => _incompatibility;

  bool _modeResolving = false;
  bool get isResolving => _modeResolving;
  String? resolvedForDeviceId;

  bool get apiFallbackEnabled => mode.value == CatalogMode.compatibility;

  bool sourceBuildEnabled = false;

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
        mode.value != CatalogMode.mismatch &&
        mode.value != CatalogMode.incompatible) {
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
        _incompatibility = null;
        mode.value = CatalogMode.normal;
        return;
      }

      final res = resolveCatalogApi(targetSdks, _deviceApi);
      if (res.verdict == ApiVerdict.normal) {
        api.api = res.api ?? _deviceApi;
        api.target = _deviceTarget;
        api.unfiltered = false;
        _compatApi = null;
        _incompatibility = null;
        mode.value = CatalogMode.normal;
      } else if (res.verdict == ApiVerdict.mismatch) {
        _compatApi = res.api;
        _incompatibility = null;
        mode.value = CatalogMode.mismatch;
      } else {
        _compatApi = null;
        _incompatibility = res.verdict;
        mode.value = CatalogMode.incompatible;
      }
      // A reconnect must not drop the source build the user already picked,
      // otherwise the dialog comes back and installs fall to the API fallback.
      if (sourceBuildEnabled && res.verdict != ApiVerdict.normal) {
        chooseSourceBuild();
      }
      LogService.log(
        '[AppsBackend] mode=${mode.value.name} device=$_deviceApi '
        'server=$serverApi picked=${res.api} compat=$_compatApi',
      );
    } finally {
      _modeResolving = false;
      if (mode.value != CatalogMode.resolving) {
        resolvedForDeviceId = currentDeviceId();
      }
    }
  }

  void chooseSourceBuild() {
    sourceBuildEnabled = true;
    api.api = null;
    api.target = null;
    api.unfiltered = true;
    mode.value = CatalogMode.compatibility;
  }

  void chooseCompatibility() {
    sourceBuildEnabled = false;
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

  void resetDeviceState() {
    api.target = null;
    api.api = null;
    api.unfiltered = false;
    _deviceApi = null;
    _deviceTarget = null;
    _compatApi = null;
    _incompatibility = null;
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
