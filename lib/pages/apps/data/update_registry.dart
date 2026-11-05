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

  const AppUpdate({
    required this.alias,
    required this.card,
    required this.manifest,
  });

  String get name {
    final full = card.name;
    if (full.isNotEmpty) return full;
    final mf = manifest.fullName;
    return mf.isNotEmpty ? mf : alias;
  }

  String get installedApi => manifest.sdkApi;
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
    engine.addListener(_onEngineChanged);
  }

  final FlipperClient client;
  final AppsCatalogApi api;
  final ManifestRegistry manifests;
  final InstallEngine engine;
  final CatalogContext catalog;

  final Map<String, AppCard> _cardsByUid = {};

  List<AppUpdate> _updates = const [];
  int get count => _updates.length;

  bool _failed = false;

  /// Whether the last check for updates finished.
  ///
  /// [count] is zero both when everything is current and when nothing could
  /// be checked, and the badge renders only above zero - so a failed check
  /// looks exactly like being up to date. #112.
  bool get failed => _failed;

  AppCard? cardForUid(String uid) => uid.isEmpty ? null : _cardsByUid[uid];
  Set<String> get updatableAliases => _updates.map((u) => u.alias).toSet();

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
      _cardsByUid.clear();
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
    final server = api.server;
    _loading = true;
    _failed = false;
    notifyListeners();
    try {
      await catalog.ensureDeviceFilters(required: true);
      if (force) {
        await manifests.refresh(force: true);
      }
      await _awaitManifests();
      if (token.isStale || server != api.server) return;

      final installed = _installedWithUid();

      if (installed.isEmpty) {
        _cardsByUid.clear();
        _updates = const [];
        _loaded = true;
        LogService.info('[Updates] no installed apps with UID');
        return;
      }

      final cards = await api.fetchAppsByUids(
        installed.map((m) => m.uid).toSet().toList(),
      );
      if (token.isStale || server != api.server) return;
      _cardsByUid
        ..clear()
        ..addEntries(
          cards.where((c) => c.id.isNotEmpty).map((c) => MapEntry(c.id, c)),
        );
      _rebuild(installed);
      _loaded = true;
      final withVer = installed.where((m) => m.versionUid.isNotEmpty).length;
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

  Future<void> _awaitManifests() async {
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

  /// Every installed app the catalogue knows by uid. Two entries of one item
  /// (ProtoPirate and ProtoPirate Extra) share the uid, so this is a list.
  List<AppManifest> _installedWithUid() => [
    for (final m in manifests.all)
      if (m.uid.isNotEmpty) m,
  ];

  void _recompute() {
    if (_cardsByUid.isEmpty) return;
    _rebuild(_installedWithUid());
    notifyListeners();
  }

  void _rebuild(List<AppManifest> installed) {
    final out = <AppUpdate>[];
    for (final manifest in installed) {
      final listed = _cardsByUid[manifest.uid];
      if (listed == null) continue;
      // The update is the installed entry's newer version, never a switch
      // to the entry the card happens to lead with.
      final entry = installedApp(listed, manifest);
      final card = entry == null ? listed : listed.forApp(entry);
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
      engine.installOrUpdate(u.card);
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
    _cardsByUid.clear();
    _updates = const [];
    _loaded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    manifests.removeListener(_recompute);
    engine.removeListener(_onEngineChanged);
    super.dispose();
  }
}
