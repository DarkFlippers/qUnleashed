import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/assembler/controller.dart';
import '../data/apps_backend.dart';
import '../data/catalog_api.dart';
import '../data/catalog_mode.dart';
import '../data/categories.dart';
import '../data/catalog_state.dart';
import '../data/catalog_feed.dart';
import '../data/install_engine.dart';
import '../data/manifest_registry.dart';
import '../data/models/card.dart';
import '../data/models/category.dart';
import '../data/sort.dart';
import '../icons/icon_resolver.dart';

export '../data/catalog_mode.dart' show CatalogMode;
export '../data/catalog_state.dart' show CatalogAppState;
export '../data/install_engine.dart'
    show AppAction, AppActionType, AppActionStage;

class AppsCatalogController extends ChangeNotifier {
  AppsCatalogController({this.pageSize = 48}) {
    _backend.manifests.addListener(notifyListeners);
    _backend.engine.addListener(notifyListeners);
    _backend.mode.addListener(_onModeChanged);
    // Switching between the local and the server builder changes what the
    // install buttons do, so the grid has to hear about it.
    AssemblerController.instance.addListener(notifyListeners);
  }

  final AppsBackend _backend = AppsBackend.instance;
  final int pageSize;

  AppsCatalogApi get api => _backend.api;
  InstallEngine get engine => _backend.engine;
  ManifestRegistry get manifests => _backend.manifests;

  late final CatalogFeed _catalogFeed = CatalogFeed(api);

  final List<AppCard> _catalogCards = [];
  final Set<String> _catalogAliases = {};

  List<AppCategory> _categories = const [];
  List<AppCategory> get categories => _categories;

  AppCategory? _currentCategory;
  AppCategory? get currentCategory => _currentCategory;

  AppsSort _sort = AppsSort.newUpdates;
  AppsSort get sort => _sort;

  String _query = '';

  final List<AppCard> _apps = [];
  List<AppCard> get apps => List.unmodifiable(_apps);

  bool _categoriesLoading = false;
  bool get categoriesLoading => _categoriesLoading;

  bool _appsLoading = false;
  bool get appsLoading => _appsLoading;

  bool _reachedEnd = false;
  bool get reachedEnd => _reachedEnd;

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
  String? get deviceApi => _backend.deviceApi;
  String? get serverApi => _backend.serverApi;
  String? get compatApi => _backend.compatApi;

  AppCategory? categoryById(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  AppCategory? categoryFor(AppCard app) => categoryById(app.categoryId);

  Future<void> initialize() async {
    unawaited(manifests.ensureFresh());
    await _backend.resolveMode();
    await _maybeLoad();
  }

  static bool showsCatalog(CatalogMode mode) =>
      mode == CatalogMode.normal ||
      mode == CatalogMode.nearestApi ||
      mode == CatalogMode.sourceBuild;

  Future<void> _maybeLoad() async {
    if (!showsCatalog(_backend.mode.value)) return;
    if (_categories.isEmpty) await loadCategories();
    if (_apps.isEmpty) await refresh();
  }

  void _onModeChanged() {
    unawaited(refresh());
    if (showsCatalog(_backend.mode.value)) unawaited(_maybeLoad());
  }

  Future<void> loadCategories() async {
    _categoriesLoading = true;
    _categories = await CategoryRegistry.instance.ensureBundled();
    notifyListeners();
    try {
      _categories = await CategoryRegistry.instance.refreshFromCatalog(api);
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
    _catalogCards.clear();
    _catalogAliases.clear();
    _reachedEnd = false;
    _lastError = null;
    _catalogFeed.reset();
    _sinceLoadError
      ..stop()
      ..reset();
    _rebuild();
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
      final items = await _catalogFeed.next(
        limit: pageSize,
        sort: _sort,
        category: _currentCategory,
        query: _query,
      );
      for (final card in items) {
        if (!_catalogAliases.add(card.alias)) continue;
        _catalogCards.add(card);
      }
      if (!_catalogFeed.hasMore) _reachedEnd = true;
      IconResolver.instance.warmFromCatalog(items);
      _rebuild();
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

  void _rebuild() {
    _apps
      ..clear()
      ..addAll(sortAppCards(_catalogCards, _sort));
  }

  @override
  void dispose() {
    _backend.manifests.removeListener(notifyListeners);
    _backend.engine.removeListener(notifyListeners);
    _backend.mode.removeListener(_onModeChanged);
    AssemblerController.instance.removeListener(notifyListeners);
    super.dispose();
  }
}
