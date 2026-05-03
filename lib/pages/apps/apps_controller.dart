import 'package:flutter/foundation.dart';

import 'apps_catalog_api.dart';
import 'models/app_card.dart';
import 'models/app_category.dart';

class AppsCatalogController extends ChangeNotifier {
  AppsCatalogController({AppsCatalogApi? api, this.pageSize = 48})
      : _api = api ?? AppsCatalogApi(),
        _ownsApi = api == null;

  final AppsCatalogApi _api;
  final bool _ownsApi;
  final int pageSize;

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

  AppsCatalogApi get api => _api;

  Future<void> initialize() async {
    if (_categories.isEmpty) {
      await loadCategories();
    }
    if (_apps.isEmpty) {
      await refresh();
    }
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

  Future<void> refresh() async {
    _apps.clear();
    _offset = 0;
    _reachedEnd = false;
    _lastError = null;
    notifyListeners();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_appsLoading || _reachedEnd) return;
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
    } catch (e) {
      _lastError = e;
      _reachedEnd = true;
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
    if (_ownsApi) _api.close();
    super.dispose();
  }
}
