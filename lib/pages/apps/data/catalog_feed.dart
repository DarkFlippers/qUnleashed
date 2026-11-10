import 'catalog_api.dart';
import 'models/card.dart';
import 'models/category.dart';

class CatalogFeed {
  CatalogFeed(this.api);

  final AppsCatalogApi api;

  int _offset = 0;
  bool _hasMore = true;

  bool get hasMore => _hasMore;

  Future<List<AppCard>> next({
    required int limit,
    required AppsSort sort,
    AppCategory? category,
    String query = '',
    CatalogFamily family = CatalogFamily.apps,
    String? authorId,
  }) async {
    if (!_hasMore) return const [];
    final page = await api.fetchApps(
      offset: _offset,
      limit: limit,
      sortBy: sort,
      categoryId: category?.id,
      query: query.isEmpty ? null : query,
      family: family,
      authorId: authorId,
    );
    _offset = page.nextOffset;
    _hasMore = page.hasMore;
    return page.items;
  }
}
