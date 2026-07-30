import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import 'apps_backend.dart';
import 'catalog_api.dart';
import 'catalog_mode.dart';
import 'catalog_state.dart';
import 'install_engine.dart';
import 'manifest_registry.dart';
import 'models/card.dart';
import 'models/manifest.dart';

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
    required this.backend,
  }) {
    manifests.addListener(_recompute);
    engine.addListener(_onEngineChanged);
  }

  final FlipperClient client;
  final AppsCatalogApi api;
  final ManifestRegistry manifests;
  final InstallEngine engine;
  final AppsBackend backend;

  final Map<String, AppCard> _cardsByUid = {};

  List<AppUpdate> _updates = const [];
  List<AppUpdate> get updates => List.unmodifiable(_updates);
  int get count => _updates.length;

  AppCard? cardForUid(String uid) => uid.isEmpty ? null : _cardsByUid[uid];
  Set<String> get updatableAliases => _updates.map((u) => u.alias).toSet();

  bool _loading = false;
  bool get loading => _loading;

  bool _loaded = false;
  bool get loaded => _loaded;

  Object? _error;
  Object? get error => _error;

  bool get isReady => client.isConnected && client.mode == FlipperMode.rpc;

  bool get _ignoreSdkMismatch => backend.ignoreSdkMismatch;

  Future<void> ensureFresh() async {
    if (_loaded || _loading) return;
    await refresh();
  }

  Future<void> refresh({bool force = false}) async {
    if (_loading || !isReady) return;
    if (backend.mode.value == CatalogMode.incompatible) {
      _cardsByUid.clear();
      _updates = const [];
      _loaded = true;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await backend.ensureDeviceFilters(required: true);
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

      final cards = await api.fetchAppsByUids(installed.keys.toList());
      _cardsByUid
        ..clear()
        ..addEntries(
          cards.where((c) => c.id.isNotEmpty).map((c) => MapEntry(c.id, c)),
        );
      _rebuild(installed);
      _loaded = true;
      final withVer =
          installed.values.where((m) => m.versionUid.isNotEmpty).length;
      LogService.log(
        '[Updates] installed=${installed.length} withVersionUid=$withVer '
        'cards=${cards.length} updates=${_updates.length}',
      );
    } catch (e) {
      _error = e;
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
        targetSdk: backend.targetSdk,
        ignoreSdkMismatch: _ignoreSdkMismatch,
      );
      if (state != CatalogAppState.update) continue;
      out.add(AppUpdate(
        alias: _aliasFor(card, manifest),
        card: card,
        manifest: manifest,
      ));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _updates = out;
  }

  String _aliasFor(AppCard card, AppManifest manifest) {
    if (card.alias.isNotEmpty) return card.alias;
    final path = manifest.path;
    if (path.isEmpty) return '';
    final base = path.substring(path.lastIndexOf('/') + 1);
    return base.endsWith('.fap') ? base.substring(0, base.length - 4) : base;
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
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    manifests.removeListener(_recompute);
    engine.removeListener(_onEngineChanged);
    super.dispose();
  }
}
