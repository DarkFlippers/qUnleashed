import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import 'catalog_context.dart';
import 'catalog_api.dart';
import 'catalog_mode.dart';
import 'catalog_state.dart';
import 'install_engine.dart';
import 'manifest_registry.dart';
import 'models/card.dart';
import 'models/manifest.dart';
import '../../../services/logging.dart';

@immutable
class AppUpdate {
  final String alias;
  final AppCard card;
  final AppManifest manifest;

  /// Where the update is installed from: a menu style has its own install.
  final CatalogFamily family;

  const AppUpdate({
    required this.alias,
    required this.card,
    required this.manifest,
    required this.family,
  });

  String get name {
    final full = card.name;
    if (full.isNotEmpty) return full;
    final mf = manifest.fullName;
    return mf != null && mf.isNotEmpty ? mf : alias;
  }

  String? get installedApi => manifest.sdkApi;
}

class UpdateRegistry extends ChangeNotifier {
  UpdateRegistry({
    required this.client,
    required this.api,
    required this.manifests,
    required this.engine,
    required this.catalog,
  }) {
    manifests.addListener(_recompute);
    engine.styleManifests.addListener(_recompute);
    engine.addListener(_onEngineChanged);
  }

  final FlipperClient client;
  final AppsCatalogApi api;
  final ManifestRegistry manifests;
  final InstallEngine engine;
  final CatalogContext catalog;

  final InstalledCards _cards = InstalledCards();

  List<AppUpdate> _updates = const [];
  int get count => _updates.length;

  bool _failed = false;

  /// Whether the last check for updates finished.
  ///
  /// [count] is zero both when everything is current and when nothing could
  /// be checked, and the badge renders only above zero - so a failed check
  /// looks exactly like being up to date. #112.
  bool get failed => _failed;

  /// The card [manifest] was installed from, as the app it installed.
  AppCard? cardFor(AppManifest? manifest) => _cards.cardFor(manifest);
  Set<String> get updatableAliases => _updates.map((u) => u.alias).toSet();

  /// Installed apps whose `.fim` names another catalog than the one in use,
  /// by alias, with that catalog: this one is not asked about them, so they
  /// are neither current nor out of date here.
  Map<String, String> get otherCatalogs => Map.unmodifiable(_otherCatalogs);
  Map<String, String> _otherCatalogs = const {};

  bool _loading = false;
  bool _loaded = false;

  bool get isReady => client.isRpcReady;

  bool get _ignoreSdkMismatch => catalog.ignoreSdkMismatch;

  Future<void> ensureFresh() async {
    if (_loaded || _loading) return;
    await refresh();
  }

  /// Resolves the updates as one background task: the installed set it asks the
  /// catalogue about belongs to one Flipper, so the answer has to come back to
  /// that same one.
  Future<void> refresh({bool force = false}) {
    if (_loading || !isReady) return Future.value();
    if (catalog.mode.value == CatalogMode.managerOnly) {
      _cards.clear();
      _updates = const [];
      _loaded = true;
      notifyListeners();
      return Future.value();
    }
    return client.runTask(
      FlipperRequestPriority.background,
      () => _refresh(force: force),
    );
  }

  Future<void> _refresh({required bool force}) async {
    final token = client.deviceToken;
    final endpoint = api.endpoint;
    _loading = true;
    _failed = false;
    notifyListeners();
    try {
      await catalog.ensureDeviceFilters(required: true);
      for (final registry in _registries) {
        if (force) await registry.refresh(force: true);
        await _awaitManifests(registry);
      }
      if (token.isStale || endpoint != api.endpoint) return;

      final installed = _installedWithUid();

      if (installed.isEmpty) {
        _cards.clear();
        _updates = const [];
        _loaded = true;
        LogService.info('[Updates] no installed apps with UID');
        return;
      }

      // An entry is found only under its own family's root.
      final cards = <AppCard>[];
      for (final group in groupByFamily(installed).entries) {
        cards.addAll(
          await api.fetchAppsByUids(
            group.value.map((m) => m.uid).toSet().toList(),
            family: group.key,
          ),
        );
        if (token.isStale || endpoint != api.endpoint) return;
      }
      _cards.replace(cards);
      _rebuild(installed);
      _loaded = true;
      final withVer = installed.where((m) => m.versionUid != null).length;
      LogService.info(
        '[Updates] installed=${installed.length} withVersionUid=$withVer '
        'cards=${cards.length} updates=${_updates.length}',
      );
    } catch (e) {
      // _updates keeps whatever the last successful refresh left: zero on a
      // cold start, stale afterwards. [failed] is what separates that from
      // an answer, because the count cannot.
      _failed = true;
      LogService.warn('[Updates] refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _awaitManifests(ManifestRegistry manifests) async {
    await manifests.ensureFresh();
    if (!manifests.loading) return;
    final completer = Completer<void>();
    void listener() {
      if (!manifests.loading && !completer.isCompleted) {
        completer.complete();
      }
    }

    manifests.addListener(listener);
    try {
      if (manifests.loading) {
        await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {},
        );
      }
    } finally {
      manifests.removeListener(listener);
    }
  }

  /// The device's manifests the catalog in use is asked about: the menu
  /// styles' only where it has them.
  List<ManifestRegistry> get _registries => [
    manifests,
    if (api.serves(CatalogFamily.menuStyles)) engine.styleManifests,
  ];

  /// Every installed app the catalogue in use can know by uid: what its
  /// `.fim` says came from it, or does not say where it came from. Two entries
  /// of one item (ProtoPirate and ProtoPirate Extra) share the uid, so this is
  /// a list. The rest are kept in [otherCatalogs].
  List<AppManifest> _installedWithUid() {
    final split = splitByCatalog([
      for (final registry in _registries) ...registry.all,
    ], api.server);
    _otherCatalogs = split.elsewhere;
    return split.here;
  }

  void _recompute() {
    if (_cards.isEmpty) return;
    _rebuild(_installedWithUid());
    notifyListeners();
  }

  void _rebuild(List<AppManifest> installed) {
    final out = <AppUpdate>[];
    for (final manifest in installed) {
      // The update is the installed entry's newer version, never a switch
      // to the entry the card happens to lead with.
      final card = cardFor(manifest);
      if (card == null) continue;
      final state = catalogAppState(
        card: card,
        manifest: manifest,
        targetSdk: catalog.targetSdk,
        ignoreSdkMismatch: _ignoreSdkMismatch,
      );
      if (state != CatalogAppState.update) continue;
      out.add(
        AppUpdate(
          alias: _aliasFor(card, manifest),
          card: card,
          manifest: manifest,
          family: catalogFamilyOf(manifest),
        ),
      );
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _updates = out;
  }

  String _aliasFor(AppCard card, AppManifest manifest) {
    if (card.alias.isNotEmpty) return card.alias;
    return manifest.path.isEmpty ? '' : aliasFromFapPath(manifest.path);
  }

  void updateAll() {
    for (final u in _updates) {
      if (u.family == CatalogFamily.menuStyles) {
        engine.installMenuStyle(u.card);
      } else {
        engine.installOrUpdate(u.card);
      }
    }
  }

  void _onEngineChanged() {
    notifyListeners();
  }

  void handleDisconnect() {
    _loaded = false;
    notifyListeners();
  }

  void handleDeviceChange() {
    _cards.clear();
    _updates = const [];
    _otherCatalogs = const {};
    _loaded = false;
    notifyListeners();
  }

  /// Requests go to another catalog now - another server, or another
  /// protocol to the same one: what it says about the installed apps is
  /// asked again. The apps on the Flipper are the same ones, so their
  /// manifests are taken as they were read. Forcing them would read every
  /// `.fim` off the Flipper again, one at a time, and the catalog would show
  /// each app as not installed until its own came back.
  Future<void> handleCatalogChange() async {
    handleDeviceChange();
    await refresh();
  }

  @override
  void dispose() {
    manifests.removeListener(_recompute);
    engine.styleManifests.removeListener(_recompute);
    engine.removeListener(_onEngineChanged);
    super.dispose();
  }
}
