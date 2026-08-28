import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../../services/logging.dart';
import 'catalog_api.dart';
import 'models/category.dart';

const String kCategoriesAsset = 'assets/atp/categories.json';
const String kCategoryIconFolder = 'assets/ic/appcat';

class CategoryRegistry {
  CategoryRegistry._();

  static final CategoryRegistry instance = CategoryRegistry._();

  List<AppCategory> _bundled = const [];
  List<AppCategory> _all = const [];
  final Map<String, String> _assetsById = {};

  Future<List<AppCategory>> ensureBundled() async {
    if (_bundled.isNotEmpty) return _all;
    try {
      final raw = jsonDecode(await rootBundle.loadString(kCategoriesAsset));
      final out = <AppCategory>[];
      for (final item in (raw as List)) {
        final entry = item as Map<String, dynamic>;
        final id = (entry['id'] ?? '') as String;
        final icon = (entry['icon'] ?? '') as String;
        if (icon.isNotEmpty) _assetsById[id] = '$kCategoryIconFolder/$icon.svg';
        out.add(
          AppCategory(
            id: id,
            name: (entry['name'] ?? '') as String,
            color: (entry['color'] ?? '') as String,
            iconAsset: _assetsById[id],
            priority: (entry['priority'] as num?)?.toInt(),
          ),
        );
      }
      _bundled = out;
      if (_all.isEmpty) _all = out;
    } catch (e) {
      LogService.log('[Categories] bundled list failed: $e');
    }
    return _all;
  }

  /// Resolves a category name by id, going to the catalog only when the id is
  /// not in the list already loaded.
  Future<String?> nameFor(AppsCatalogApi api, String id) async {
    if (id.isEmpty) return null;
    String? pick(List<AppCategory> list) {
      for (final category in list) {
        if (category.id == id && category.name.isNotEmpty) return category.name;
      }
      return null;
    }

    return pick(_all) ?? pick(await refreshFromCatalog(api));
  }

  Future<List<AppCategory>> refreshFromCatalog(AppsCatalogApi api) async {
    await ensureBundled();
    final fetched = await api.fetchCategories();
    if (fetched.isEmpty) return _all;
    final byId = {for (final c in _bundled) c.id: c};
    final out = <AppCategory>[];
    for (final category in fetched) {
      final bundled = byId.remove(category.id);
      out.add(category.withIconAsset(_assetsById[category.id]));
      if (bundled == null) {
        LogService.log('[Categories] new category "${category.name}"');
      }
    }
    out.addAll(byId.values);
    out.sort((a, b) => (a.priority ?? 0).compareTo(b.priority ?? 0));
    _all = out;
    return _all;
  }
}
