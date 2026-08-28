import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import 'atp/atp_source.dart';
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

  Future<void> refresh({bool force = false}) async {
    if (_loading || !isReady) return;
    if (catalog.mode.value == CatalogMode.managerOnly) {
      _cardsByUid.clear();
      _updates = const [];
      _loaded = true;
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      await catalog.ensureDeviceFilters(required: true);
      if (force) {
        await manifests.refresh(force: true);
      }
      await _awaitManifests();

      final installed = <String, AppManifest>{};
      for (final m in manifests.all) {
        if (m.uid.isNotEmpty) installed[m.uid] = m;
      }

      if (installed.isEmpty) {
        _cardsByUid.clear();
        _updates = const [];
        _loaded = true;
        LogService.log('[Updates] no installed apps with UID');
        return;
      }

      final catalogUids = installed.keys
          .where((uid) => !uid.startsWith(kAtpUidPrefix))
          .toList();
      final cards = catalogUids.isEmpty
          ? const <AppCard>[]
          : await api.fetchAppsByUids(catalogUids);
      _cardsByUid
        ..clear()
        ..addEntries(
          cards.where((c) => c.id.isNotEmpty).map((c) => MapEntry(c.id, c)),
        )
        ..addEntries(_atpCards(installed.keys));
      _rebuild(installed);
      _loaded = true;
      final withVer = installed.values
          .where((m) => m.versionUid.isNotEmpty)
          .length;
      LogService.log(
        '[Updates] installed=${installed.length} withVersionUid=$withVer '
        'cards=${cards.length} updates=${_updates.length}',
      );
    } catch (e) {
      LogService.log('[Updates] refresh failed: $e');
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

  Iterable<MapEntry<String, AppCard>> _atpCards(Iterable<String> uids) sync* {
    final source = AtpSource.instance;
    final api = source.block?.api ?? '';
    for (final uid in uids) {
      if (!uid.startsWith(kAtpUidPrefix)) continue;
      final entry = source.entryFor(uid.substring(kAtpUidPrefix.length));
      if (entry == null) continue;
      yield MapEntry(uid, AppCard.fromAtp(entry, api: api));
    }
  }

  void _recompute() {
    if (_cardsByUid.isEmpty) return;
    final installed = <String, AppManifest>{};
    for (final m in manifests.all) {
      if (m.uid.isNotEmpty) installed[m.uid] = m;
    }
    _rebuild(installed);
    notifyListeners();
  }

  void _rebuild(Map<String, AppManifest> installed) {
    final out = <AppUpdate>[];
    for (final entry in installed.entries) {
      final card = _cardsByUid[entry.key];
      if (card == null) continue;
      final manifest = entry.value;
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
