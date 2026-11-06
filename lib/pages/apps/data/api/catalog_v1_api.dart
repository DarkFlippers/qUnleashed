part of '../catalog_api.dart';

/// The v1 families, authors and search, as the server serves them.
class CatalogV1Api extends _CatalogProtocol {
  CatalogV1Api({
    required super.server,
    required super.userAgent,
    super.api,
    super.target,
    super.unfiltered,
  });
  @override
  String get version => 'v1';

  static Duration? _ttlFor(String? query) =>
      query != null && query.isNotEmpty ? null : const Duration(minutes: 5);

  Future<List<T>> _list<T>(
    Uri uri,
    T Function(Map<String, dynamic>) read,
    String what, {
    Duration? ttl,
  }) async {
    final body = await _getJson(uri, ttl: ttl);
    if (body is! List) {
      throw AppsCatalogException(0, uri.toString(), 'expected list');
    }
    return readEach(body, read, what);
  }

  Future<Map<String, dynamic>> _object(Uri uri, {Duration? ttl}) async {
    final body = await _getJson(uri, ttl: ttl);
    if (body is! Map<String, dynamic>) {
      throw AppsCatalogException(0, uri.toString(), 'expected object');
    }
    return body;
  }

  Future<Map<String, dynamic>> _status() =>
      _object(_uri('/status', const {}), ttl: const Duration(hours: 6));

  Future<bool> fetchDevCatalog() async {
    final flag = (await _status())['dev_catalog'];
    return flag is bool ? flag : true;
  }

  Future<List<AppSdk>> fetchSdks() async {
    final uri = _uri('/status', const {});
    final body = await _status();
    final sdks = body['sdk'];
    if (sdks is! List) {
      throw AppsCatalogException(0, uri.toString(), 'expected sdk list');
    }
    return readEach(sdks, AppSdk.fromStatusJson, 'SDKs');
  }

  Future<List<AppCategory>> fetchCategories({required CatalogFamily family}) =>
      _list(
        _uri('/${family.v1Root}/category', {
          if (family.usesDevice) ..._apiParams(),
        }),
        AppCategory.fromJson,
        'categories',
        ttl: const Duration(hours: 1),
      );

  Future<AppsPage> fetchApps({
    int offset = 0,
    int limit = 48,
    AppsSort sortBy = AppsSort.newUpdates,
    String? categoryId,
    String? query,
    required CatalogFamily family,
    String? authorId,
  }) async {
    final uri = _uri('/${family.v1Root}', {
      'offset': '$offset',
      'limit': '$limit',
      'sort_by': sortBy.v1Field ?? sortBy.field,
      'sort_order': '${sortBy.v1Field != null ? sortBy.v1Order : sortBy.order}',
      if (categoryId != null && categoryId.isNotEmpty)
        'category_id': categoryId,
      if (query != null && query.isNotEmpty) 'query': query,
      'author_id': ?authorId,
      if (family.usesDevice) ..._apiParams(),
    });
    return AppsPage(
      items: await _list(uri, AppCard.fromJson, 'apps', ttl: _ttlFor(query)),
      offset: offset,
      limit: limit,
    );
  }

  Future<List<AppCard>> fetchAppsByUids(
    List<String> uids, {
    CatalogFamily family = CatalogFamily.apps,
  }) async {
    final ids = uids.where((id) => id.isNotEmpty).toSet().toList();
    final out = <AppCard>[];
    for (var i = 0; i < ids.length; i += 500) {
      final uri = _uri('/${family.v1Root}/lookup', const {});
      final body = await AppHttp.postJson(
        uri,
        {'ids': ids.sublist(i, math.min(i + 500, ids.length)), ..._apiParams()},
        headers: {io.HttpHeaders.userAgentHeader: userAgent},
      );
      if (body is! List) {
        throw AppsCatalogException(0, uri.toString(), 'expected list');
      }
      out.addAll(readEach(body, AppCard.fromJson, 'apps'));
    }
    return out;
  }

  Future<AppDetail> fetchApp(
    String idOrAlias, {
    required CatalogFamily family,
    String? app,
  }) async => AppDetail.fromJson(
    await _object(
      _uri('/${family.v1Root}/${Uri.encodeComponent(idOrAlias)}', {
        if (family.usesDevice) ..._apiParams(),
        'app': ?app,
      }),
      ttl: const Duration(minutes: 5),
    ),
  );

  Future<CatalogSearch> search(String query, {int limit = 36}) async {
    final body = await _object(
      _uri('/search', {'query': query, 'limit': '$limit', ..._apiParams()}),
    );
    final totals = <CatalogFamily, int>{};
    final rawTotals = body['totals'];
    if (rawTotals is Map) {
      for (final entry in rawTotals.entries) {
        final family = CatalogFamily.byServerName(
          entry.key is String ? entry.key as String : null,
        );
        if (family != null && entry.value is num) {
          totals[family] = (entry.value as num).toInt();
        }
      }
    }
    return CatalogSearch(
      query: query,
      items: body['items'] is List
          ? readEach(body['items'] as List, AppCard.fromJson, 'search items')
          : const [],
      totals: Map.unmodifiable(totals),
      authors: body['authors'] is List
          ? readEach(
              body['authors'] as List,
              AuthorSummary.fromJson,
              'search authors',
            )
          : const [],
    );
  }

  Future<CatalogSearch> fetchNewFeed({int limit = 36}) async => CatalogSearch(
    query: '',
    items: await _list(
      _uri('/feed/new', {'since': '0', 'limit': '$limit'}),
      AppCard.fromJson,
      'new feed',
      ttl: const Duration(minutes: 5),
    ),
    totals: const {},
    authors: const [],
  );

  Future<List<AuthorSummary>> fetchAuthors({
    String? query,
    int offset = 0,
    int limit = 48,
  }) => _list(
    _uri('/authors', {
      'sort_by': 'items',
      'offset': '$offset',
      'limit': '$limit',
      if (query != null && query.isNotEmpty) 'query': query,
    }),
    AuthorSummary.fromJson,
    'authors',
    ttl: _ttlFor(query),
  );

  Future<AuthorSummary> fetchAuthor(String id) async => AuthorSummary.fromJson(
    await _object(
      _uri('/authors/${Uri.encodeComponent(id)}', const {}),
      ttl: const Duration(minutes: 5),
    ),
  );

  Uri buildDownloadUri(
    String versionId, {
    required String api,
    String target = 'f7',
    CatalogFamily family = CatalogFamily.apps,
  }) => _uri(
    '/${family.v1Root}/version/${Uri.encodeComponent(versionId)}/build/compatible',
    {'target': target, 'api': api},
  );

  Future<Uint8List> fetchBuild(
    String versionId, {
    CatalogFamily family = CatalogFamily.apps,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    String? apiOverride,
    void Function(String api)? onBuildApi,
  }) {
    final t = target, a = apiOverride ?? api;
    if (t == null || a == null) {
      throw StateError('Set target and api before fetching builds');
    }
    return _signedBytes(
      buildDownloadUri(versionId, api: a, target: t, family: family),
      onProgress: onProgress,
      onBuildApi: onBuildApi,
    );
  }

  Future<InstallPlan> fetchAnimationPlan(String versionId) async =>
      InstallPlan.fromJson(
        await _object(
          _uri(
            '/animations/version/${Uri.encodeComponent(versionId)}/plan',
            const {},
          ),
        ),
      );

  Future<Uint8List> fetchAnimationFile(
    String versionId,
    String name,
  ) => _signedBytes(
    _uri(
      '/animations/version/${Uri.encodeComponent(versionId)}/file/${Uri.encodeComponent(name)}',
      const {},
    ),
  );

  Uri sourceBundleUri(
    String versionId, {
    CatalogFamily family = CatalogFamily.apps,
  }) => _uri(
    '/${family.v1Root}/version/${Uri.encodeComponent(versionId)}/bundle',
    const {},
  );
}
