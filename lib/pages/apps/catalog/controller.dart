import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/guarded.dart';
import '../../../services/assembler/controller.dart';
import '../data/animation_files.dart';
import '../data/apps_backend.dart';
import '../data/catalog_api.dart';
import '../data/catalog_mode.dart';
import '../data/categories.dart';
import '../data/catalog_state.dart';
import '../data/catalog_feed.dart';
import '../data/install_engine.dart';
import '../data/manifest_registry.dart';
import '../data/models/author.dart';
import '../data/models/card.dart';
import '../data/models/category.dart';
import '../data/sort.dart';
import '../icons/icon_resolver.dart';

export '../data/catalog_mode.dart' show CatalogMode;
export '../data/catalog_state.dart' show CatalogAppState;
export '../data/install_engine.dart'
    show AppAction, AppActionType, AppActionStage;

enum CatalogSearchView { everything, authors }

class AppsCatalogController extends ChangeNotifier {
  AppsCatalogController({
    this.pageSize = 48,
    this.authorId,
    this._family = CatalogFamily.apps,
  }) {
    _endpoint = api.endpoint;
    _backend.manifests.addListener(notifyListeners);
    _backend.engine.addListener(notifyListeners);
    _backend.dolphin.addListener(notifyListeners);
    _backend.styleManifests.addListener(notifyListeners);
    _backend.mode.addListener(_onModeChanged);
    // Switching between the local and the server builder changes what the
    // install buttons do, so the grid has to hear about it.
    AssemblerController.instance.addListener(notifyListeners);
  }

  final AppsBackend _backend = AppsBackend.instance;
  final int pageSize;
  final String? authorId;

  AppsCatalogApi get api => _backend.api;
  InstallEngine get engine => _backend.engine;
  ManifestRegistry get manifests => _backend.manifests;
  AnimationFiles get animationFiles => _backend.animationFiles;

  late CatalogFeed _catalogFeed = CatalogFeed(api);
  int _generation = 0;
  bool _disposed = false;
  String? _endpoint;
  int _categoryGeneration = 0;
  Future<void>? _inFlight;

  final List<AppCard> _catalogCards = [];
  final Set<String> _catalogAliases = {};

  List<AppCategory> _categories = const [];
  List<AppCategory> get categories => _categories;

  AppCategory? _currentCategory;
  AppCategory? get currentCategory => _currentCategory;

  AppsSort _sort = AppsSort.newUpdates;
  AppsSort get sort => _sort;

  CatalogFamily _family;
  CatalogFamily get family => _family;
  bool get showsAnimations => _family == CatalogFamily.animations;
  bool get showsMenuStyles => _family == CatalogFamily.menuStyles;

  CatalogFamily familyOf(AppCard app) =>
      CatalogFamily.byServerName(app.family) ?? _family;

  CatalogSearchView? _searchView;
  CatalogSearchView? get searchView => _searchView;

  CatalogSearch? _search;
  CatalogSearch? get searchResult => _search;

  final List<AuthorSummary> _authors = [];
  List<AuthorSummary> get authors => List.unmodifiable(_authors);

  String _query = '';
  String get query => _query;

  static const Duration _queryDelay = Duration(milliseconds: 300);
  Timer? _queryDebounce;

  final List<AppCard> _apps = [];
  List<AppCard> get apps => List.unmodifiable(_apps);

  bool _categoriesLoading = false;
  bool get categoriesLoading => _categoriesLoading;

  bool _appsLoading = false;
  bool get appsLoading => _appsLoading;

  bool _reachedEnd = false;
  bool get reachedEnd => _reachedEnd;

  Object? _feedError;
  Object? _categoriesError;
  Object? get lastError => _feedError ?? _categoriesError;

  CatalogAppState stateFor(AppCard app) {
    final family = familyOf(app);
    if (family == CatalogFamily.animations) {
      return _backend.dolphin.contains(app.alias)
          ? CatalogAppState.update
          : CatalogAppState.install;
    }
    final registry = family == CatalogFamily.menuStyles
        ? _backend.styleManifests
        : manifests;
    // Variants of one item share its uid; a card made for one of them asks
    // about that app's own file.
    return catalogAppState(
      card: app,
      manifest: app.id.isNotEmpty && app.selectedAppId == null
          ? registry.byUid(app.id)
          : registry.byAlias(app.alias),
      targetSdk: _backend.targetSdk,
      ignoreSdkMismatch: _backend.ignoreSdkMismatch,
    );
  }

  ValueListenable<CatalogMode> get mode => _backend.mode;

  // Keep the console accessible when source builds were explicitly selected,
  // including before a device is connected or a build server is reachable.
  bool get showsBuilder =>
      _backend.preference == CatalogModePreference.sourceBuild ||
      _backend.mode.value == CatalogMode.sourceBuild;
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
    unawaited(
      guarded('[AppsCatalog] refresh manifests', manifests.ensureFresh),
    );
    _watchFamily(_family);
    await _backend.resolveMode();
    await _maybeLoad();
  }

  static bool showsCatalog(CatalogMode mode) =>
      mode == CatalogMode.normal ||
      mode == CatalogMode.nearestApi ||
      mode == CatalogMode.sourceBuild;

  Future<void> _maybeLoad() async {
    if (_disposed || !showsCatalog(_backend.mode.value)) return;
    if (_categories.isEmpty) await loadCategories();
    if (_apps.isEmpty) await refresh();
  }

  void _onModeChanged() {
    if (_disposed) return;
    if (!showsCatalog(_backend.mode.value)) {
      _generation++;
      _categoryGeneration++;
      return;
    }
    if (_endpoint != api.endpoint) {
      _endpoint = api.endpoint;
      _categories = const [];
      _currentCategory = null;
      _searchView = null;
      _family = CatalogFamily.apps;
      _sort = AppsSort.newUpdates;
      CategoryRegistry.instance.useEndpoint(api.endpoint);
    }
    unawaited(guarded('[AppsCatalog] refresh on mode change', refresh));
    if (showsCatalog(_backend.mode.value)) {
      unawaited(guarded('[AppsCatalog] load on mode change', _maybeLoad));
    }
  }

  Future<void> loadCategories() async {
    final generation = ++_categoryGeneration;
    final endpoint = api.endpoint;
    final family = _family;
    bool stale() =>
        _disposed ||
        generation != _categoryGeneration ||
        family != _family ||
        endpoint != api.endpoint;
    _categoriesLoading = true;
    if (family == CatalogFamily.apps) {
      CategoryRegistry.instance.useEndpoint(api.endpoint);
      final bundled = await CategoryRegistry.instance.ensureBundled();
      if (stale()) return;
      _categories = bundled;
    }
    notifyListeners();
    try {
      final fetched = family == CatalogFamily.apps
          ? await CategoryRegistry.instance.refreshFromCatalog(api)
          : nestCategories(
              await CategoryRegistry.instance.withBundledIcons(
                await api.fetchCategories(family: family),
              ),
            );
      if (stale()) return;
      _categories = fetched;
      _categoriesError = null;
    } catch (e) {
      if (stale()) return;
      _categoriesError = e;
    } finally {
      if (!stale()) {
        _categoriesLoading = false;
        notifyListeners();
      }
    }
  }

  void selectCategory(AppCategory? category) {
    if (_currentCategory?.id == category?.id) return;
    _currentCategory = category;
    refresh();
  }

  Future<void> selectFamily(CatalogFamily family) async {
    final leavesSearchView = _searchView != null;
    _searchView = null;
    if (_family == family) {
      if (leavesSearchView) await refresh();
      return;
    }
    _family = family;
    _currentCategory = null;
    _categories = const [];
    _categoriesError = null;
    _watchFamily(family);
    unawaited(guarded('[AppsCatalog] load categories', loadCategories));
    await refresh();
  }

  void selectSearchView(CatalogSearchView view) {
    if (_searchView == view) return;
    _searchView = view;
    if (view == CatalogSearchView.everything) {
      _watchFamily(CatalogFamily.animations);
      _watchFamily(CatalogFamily.menuStyles);
    }
    refresh();
  }

  void closeSearch() {
    _queryDebounce?.cancel();
    if (_query.isEmpty) return;
    _query = '';
    refresh();
  }

  void _watchFamily(CatalogFamily family) {
    if (family == CatalogFamily.animations) {
      unawaited(
        guarded(
          '[AppsCatalog] read animation manifest',
          _backend.dolphin.ensureFresh,
        ),
      );
    }
    if (family == CatalogFamily.menuStyles) {
      unawaited(
        guarded(
          '[AppsCatalog] read menu style manifests',
          _backend.watchMenuStyles,
        ),
      );
    }
  }

  void selectSort(AppsSort sort) {
    if (_sort == sort) return;
    _sort = sort;
    refresh();
  }

  void setQuery(String query) {
    final trimmed = query.trim();
    _queryDebounce?.cancel();
    if (_query == trimmed) return;
    _queryDebounce = Timer(_queryDelay, () {
      _query = trimmed;
      refresh();
    });
  }

  static const Duration _loadErrorCooldown = Duration(seconds: 3);
  final Stopwatch _sinceLoadError = Stopwatch();

  Future<void> refresh() async {
    if (_disposed) return;
    _catalogCards.clear();
    _catalogAliases.clear();
    _search = null;
    _authors.clear();
    _reachedEnd = false;
    _feedError = null;
    _generation++;
    _catalogFeed = CatalogFeed(api);
    _appsLoading = false;
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
    final generation = _generation;
    final feed = _catalogFeed;
    final view = _searchView;
    final query = _query;
    _appsLoading = true;
    notifyListeners();
    final previous = _inFlight;
    final done = Completer<void>();
    _inFlight = done.future;
    try {
      if (previous != null) await previous;
      if (_disposed || generation != _generation) return;
      switch (view) {
        case CatalogSearchView.everything:
          final result = query.isEmpty
              ? await api.fetchNewFeed()
              : await api.search(query);
          if (_disposed || generation != _generation) return;
          _search = result;
          IconResolver.instance.warmFromCatalog(result.items);
          _reachedEnd = true;
        case CatalogSearchView.authors:
          final page = await api.fetchAuthors(
            query: query,
            offset: _authors.length,
            limit: pageSize,
          );
          if (_disposed || generation != _generation) return;
          _authors.addAll(page);
          if (page.length < pageSize) _reachedEnd = true;
        case null:
          final items = await feed.next(
            limit: pageSize,
            sort: _sort,
            category: _currentCategory,
            query: query,
            family: _family,
            authorId: authorId,
          );
          if (_disposed || generation != _generation) return;
          for (final card in items) {
            if (!_catalogAliases.add(card.alias)) continue;
            _catalogCards.add(card);
          }
          if (!feed.hasMore) _reachedEnd = true;
          IconResolver.instance.warmFromCatalog(items);
          _rebuild();
      }
      _feedError = null;
      _sinceLoadError
        ..stop()
        ..reset();
    } catch (e) {
      if (_disposed || generation != _generation) return;
      _feedError = e;
      _sinceLoadError
        ..reset()
        ..start();
    } finally {
      done.complete();
      if (!_disposed && generation == _generation) {
        _appsLoading = false;
        notifyListeners();
      }
    }
  }

  void _rebuild() {
    _apps
      ..clear()
      ..addAll(
        api.ranksOnServer(_sort, _family)
            ? _catalogCards
            : sortAppCards(_catalogCards, _sort),
      );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _categoryGeneration++;
    _queryDebounce?.cancel();
    _backend.manifests.removeListener(notifyListeners);
    _backend.engine.removeListener(notifyListeners);
    _backend.dolphin.removeListener(notifyListeners);
    _backend.styleManifests.removeListener(notifyListeners);
    _backend.mode.removeListener(_onModeChanged);
    AssemblerController.instance.removeListener(notifyListeners);
    super.dispose();
  }
}
