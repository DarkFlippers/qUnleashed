import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import '../data/apps_backend.dart';
import '../data/catalog_api.dart';
import '../data/catalog_mode.dart';
import '../data/catalog_state.dart';
import '../data/install_engine.dart';
import '../data/manifest_registry.dart';
import '../data/models/card.dart';
import '../data/models/category.dart';
import '../icons/icon_resolver.dart';

export '../data/catalog_mode.dart' show CatalogMode, ApiVerdict;
export '../data/catalog_state.dart' show CatalogAppState;
export '../data/install_engine.dart' show AppAction, AppActionType, AppActionStage;

class AppsCatalogController extends ChangeNotifier {
  AppsCatalogController({this.pageSize = 48}) {
    _backend.manifests.addListener(notifyListeners);
    _backend.engine.addListener(notifyListeners);
    _backend.mode.addListener(_onModeChanged);
  }

  final AppsBackend _backend = AppsBackend.instance;
  final int pageSize;

  AppsBackend get backend => _backend;
  AppsCatalogApi get api => _backend.api;
  FlipperClient get client => _backend.client;
  InstallEngine get engine => _backend.engine;
  ManifestRegistry get manifests => _backend.manifests;
  bool get isReady => _backend.isReady;

  List<AppCategory> _categories = const [];
  List<AppCategory> get categories => _categories;

  AppCategory? _currentCategory;
  AppCategory? get currentCategory => _currentCategory;

  AppsSort _sort = AppsSort.newUpdates;
  AppsSort get sort => _sort;

  String _query = '';
  String get query => _query;

  final List<AppCard> _apps = [];
  List<AppCard> get apps => List.unmodifiable(_apps);

  bool _categoriesLoading = false;
  bool get categoriesLoading => _categoriesLoading;

  bool _appsLoading = false;
  bool get appsLoading => _appsLoading;

  bool _reachedEnd = false;
  bool get reachedEnd => _reachedEnd;

  int _offset = 0;
  Object? _lastError;
  Object? get lastError => _lastError;

  CatalogAppState stateFor(AppCard app) => catalogAppState(
        card: app,
        manifest: app.id.isNotEmpty
            ? manifests.byUid(app.id)
            : manifests.byAlias(app.alias),
        targetSdk: _backend.targetSdk,
        ignoreSdkMismatch: _backend.ignoreSdkMismatch,
      );

  ValueListenable<CatalogMode> get mode => _backend.mode;
  bool get apiFallbackEnabled => _backend.apiFallbackEnabled;
  String? get deviceApi => _backend.deviceApi;
  String? get serverApi => _backend.serverApi;
  String? get compatApi => _backend.compatApi;
  ApiVerdict? get incompatibility => _backend.incompatibility;

  void chooseCompatibility() => _backend.chooseCompatibility();
  Future<void> refreshMode() => _backend.resolveMode(force: true);

  AppCategory? categoryById(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> initialize() async {
    unawaited(manifests.ensureFresh());
    await _backend.resolveMode();
    await _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    final m = _backend.mode.value;
    if (m != CatalogMode.normal && m != CatalogMode.compatibility) return;
    if (_categories.isEmpty) await loadCategories();
    if (_apps.isEmpty) await refresh();
  }

  void _onModeChanged() {
    notifyListeners();
    final m = _backend.mode.value;
    if (m == CatalogMode.normal || m == CatalogMode.compatibility) {
      unawaited(_maybeLoad());
    }
  }

  Future<void> loadCategories() async {
    _categoriesLoading = true;
    notifyListeners();
    try {
      _categories = await api.fetchCategories();
      _lastError = null;
    } catch (e) {
      _lastError = e;
    } finally {
      _categoriesLoading = false;
      notifyListeners();
    }
  }

  void selectCategory(AppCategory? category) {
    if (_currentCategory?.id == category?.id) return;
    _currentCategory = category;
    refresh();
  }

  void selectSort(AppsSort sort) {
    if (_sort == sort) return;
    _sort = sort;
    refresh();
  }

  void setQuery(String query) {
    final trimmed = query.trim();
    if (_query == trimmed) return;
    _query = trimmed;
    refresh();
  }

  static const Duration _loadErrorCooldown = Duration(seconds: 3);
  final Stopwatch _sinceLoadError = Stopwatch();

  Future<void> refresh() async {
    _apps.clear();
    _offset = 0;
    _reachedEnd = false;
    _lastError = null;
    _sinceLoadError
      ..stop()
      ..reset();
    notifyListeners();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_appsLoading || _reachedEnd) return;
    if (_sinceLoadError.isRunning &&
        _sinceLoadError.elapsed < _loadErrorCooldown) {
      return;
    }
    _appsLoading = true;
    notifyListeners();
    try {
      final page = await api.fetchApps(
        offset: _offset,
        limit: pageSize,
        sortBy: _sort,
        categoryId: _currentCategory?.id,
        query: _query.isEmpty ? null : _query,
      );
      _apps.addAll(page.items);
      _offset = page.nextOffset;
      if (!page.hasMore) _reachedEnd = true;
      IconResolver.instance.warmFromCatalog(page.items);
      _lastError = null;
      _sinceLoadError
        ..stop()
        ..reset();
    } catch (e) {
      _lastError = e;
      _sinceLoadError
        ..reset()
        ..start();
    } finally {
      _appsLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _backend.manifests.removeListener(notifyListeners);
    _backend.engine.removeListener(notifyListeners);
    _backend.mode.removeListener(_onModeChanged);
    super.dispose();
  }
}
