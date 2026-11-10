import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../../services/logging.dart';
import 'catalog_api.dart';
import 'models/category.dart';

const String kCategoriesAsset = 'assets/catalog/categories.json';
const String kCategoryIconFolder = 'assets/ic/appcat';

class CategoryRegistry {
  CategoryRegistry._();

  static final CategoryRegistry instance = CategoryRegistry._();

  List<AppCategory> _bundled = const [];
  List<AppCategory> _all = const [];
  String? _endpoint;

  /// The catalog the list is for (AppsCatalogApi.endpoint): another one
  /// starts again from the bundled list.
  void useEndpoint(String endpoint) {
    if (_endpoint == endpoint) return;
    _endpoint = endpoint;
    _all = _bundled;
  }

  final Map<String, String> _assetsById = {};

  /// Other families name the same categories with their own ids - CLI sends
  /// `games` where apps send the ObjectId - so the name finds the icon too.
  final Map<String, String> _assetsByName = {};

  String? _assetFor(AppCategory category) =>
      _assetsById[category.id] ??
      _assetsByName[category.name.trim().toLowerCase()];

  /// [categories] with the bundled icons wherever one matches, for the
  /// families that do not go through [refreshFromCatalog].
  Future<List<AppCategory>> withBundledIcons(
    List<AppCategory> categories,
  ) async {
    await ensureBundled();
    return [for (final c in categories) c.withIconAsset(_assetFor(c))];
  }

  Future<List<AppCategory>> ensureBundled() async {
    if (_bundled.isNotEmpty) return _all;
    try {
      final raw = jsonDecode(await rootBundle.loadString(kCategoriesAsset));
      final out = <AppCategory>[];
      for (final item in (raw as List)) {
        final entry = item as Map<String, dynamic>;
        final id = (entry['id'] ?? '') as String;
        final icon = (entry['icon'] ?? '') as String;
        final name = (entry['name'] ?? '') as String;
        if (icon.isNotEmpty) {
          final asset = '$kCategoryIconFolder/$icon.svg';
          _assetsById[id] = asset;
          _assetsByName[name.trim().toLowerCase()] = asset;
        }
        out.add(
          AppCategory(
            id: id,
            name: name,
            color: (entry['color'] ?? '') as String,
            iconAsset: _assetsById[id],
            priority: (entry['priority'] as num?)?.toInt(),
          ),
        );
      }
      _bundled = out;
      if (_all.isEmpty) _all = out;
    } catch (e) {
      // A bundled asset, so a packaging fault rather than a network one, and
      // there is no user action that helps - which is why #112 gave this no
      // failed state while its three siblings got one.
      //
      // It leaves _assetsById empty and _bundled with it, so the guard at the
      // top of this method lets the next call try again and the icons come
      // back the moment the asset parses. What does not recover is a build
      // that shipped a broken asset, and nothing on screen could fix that.
      LogService.warn('[Categories] bundled list failed: $e');
    }
    return _all;
  }

  /// Resolves a category name by id, going to the catalog only when the id is
  /// not in the list already loaded.
  Future<String?> nameFor(AppsCatalogApi api, String id) async {
    useEndpoint(api.endpoint);
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
    final endpoint = api.endpoint;
    useEndpoint(endpoint);
    await ensureBundled();
    final fetched = await api.fetchCategories();
    if (endpoint != api.endpoint) return _all;
    if (fetched.isEmpty) return _all;
    final byId = {for (final c in _bundled) c.id: c};
    final out = <AppCategory>[];
    for (final category in fetched) {
      final bundled = byId.remove(category.id);
      out.add(category.withIconAsset(_assetFor(category)));
      if (bundled == null) {
        LogService.info('[Categories] new category "${category.name}"');
      }
    }
    out.addAll(byId.values);
    _all = nestCategories(out);
    return _all;
  }
}
