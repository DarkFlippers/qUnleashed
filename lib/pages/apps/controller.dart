import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';

import 'catalog_api.dart';
import 'install_service.dart';
import 'models/card.dart';
import 'models/category.dart';

export 'install_service.dart' show AppButtonState;

enum AppsCatalogFilter { all, installed, updates }

class AppsCatalogController extends ChangeNotifier {
  AppsCatalogController({this.pageSize = 48})
    : install = AppsInstallService.shared() {
    _api = install.api;
    _client = install.client;
    install.addListener(notifyListeners);
  }

  late final AppsCatalogApi _api;
  late final FlipperClient _client;
  final int pageSize;
  final AppsInstallService install;

  FlipperClient get client => _client;

  List<AppCategory> _categories = const [];
  List<AppCategory> get categories => _categories;

  AppCategory? _currentCategory;
  AppCategory? get currentCategory => _currentCategory;

  AppsSort _sort = AppsSort.newUpdates;
  AppsSort get sort => _sort;

  String _query = '';
  String get query => _query;

  AppsCatalogFilter _filter = AppsCatalogFilter.all;
  AppsCatalogFilter get filter => _filter;

  final List<AppCard> _apps = [];
  List<AppCard> get apps => List.unmodifiable(_apps);

  List<AppCard> get displayedApps {
    switch (_filter) {
      case AppsCatalogFilter.all:
        return List.unmodifiable(_apps);
      case AppsCatalogFilter.installed:
        return _apps
            .where(
              (app) =>
                  install.isInstalled(app) ||
                  install.buttonState(app) == AppButtonState.update,
            )
            .toList(growable: false);
      case AppsCatalogFilter.updates:
        return _apps.where((app) {
          if (install.buttonState(app) == AppButtonState.update) return true;
          final action = install.actionFor(app);
          return action != null && action.type == AppActionType.update;
        }).toList(growable: false);
    }
  }

  List<AppCard> get updatableApps => _apps
      .where((app) => install.buttonState(app) == AppButtonState.update)
      .toList(growable: false);

  void updateAll() {
    for (final app in updatableApps) {
      unawaited(
        install.installOrUpdate(app, category: categoryById(app.categoryId)),
      );
    }
  }

  bool _categoriesLoading = false;
  bool get categoriesLoading => _categoriesLoading;

  bool _appsLoading = false;
  bool get appsLoading => _appsLoading;

  bool _reachedEnd = false;
  bool get reachedEnd => _reachedEnd;

  int _offset = 0;
  Object? _lastError;
  Object? get lastError => _lastError;

  AppsCatalogApi get api => _api;

  Future<void> initialize() async {
    if (_categories.isEmpty) await loadCategories();
    if (_apps.isEmpty) await refresh();
  }

  Future<void> loadCategories() async {
    _categoriesLoading = true;
    notifyListeners();
    try {
      _categories = await _api.fetchCategories();
      _lastError = null;
    } catch (e) {
      _lastError = e;
    } finally {
      _categoriesLoading = false;
      notifyListeners();
    }
  }

  void selectCategory(AppCategory? category) {
    if (identical(_currentCategory, category)) return;
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

  void setFilter(AppsCatalogFilter value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  static const Duration _loadErrorCooldown = Duration(seconds: 3);
  // Stopwatch, not DateTime: the flipperlib protobuf exports shadow
  // dart:core's DateTime in this file.
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
    // A transient network error no longer ends the pagination; the cooldown
    // keeps the scroll listener from hammering the API in a retry loop.
    if (_sinceLoadError.isRunning &&
        _sinceLoadError.elapsed < _loadErrorCooldown) {
      return;
    }
    _appsLoading = true;
    notifyListeners();
    try {
      final page = await _api.fetchApps(
        offset: _offset,
        limit: pageSize,
        sortBy: _sort,
        categoryId: _currentCategory?.id,
        query: _query.isEmpty ? null : _query,
      );
      _apps.addAll(page.items);
      _offset = page.nextOffset;
      if (!page.hasMore) _reachedEnd = true;
      _lastError = null;
      _sinceLoadError
        ..stop()
        ..reset();
      install.cacheCatalogIcons(page.items);
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

  AppCategory? categoryById(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  void dispose() {
    install.removeListener(notifyListeners);
    super.dispose();
  }
}
