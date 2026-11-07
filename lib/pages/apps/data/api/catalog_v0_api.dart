part of '../catalog_api.dart';

/// Archivarius v0; its paths and request bodies stay independent of v1.
class CatalogV0Api extends _CatalogProtocol {
  CatalogV0Api({
    required super.server,
    required super.userAgent,
    super.api,
    super.target,
    super.unfiltered,
  });
  @override
  String get version => 'v0';

  bool _isSdkNotExists(AppHttpException e) =>
      e.statusCode == 400 && (e.body?.contains('is not exists') ?? false);

  Future<T> _withApiFallback<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AppHttpException catch (e) {
      if (!unfiltered && _isSdkNotExists(e)) {
        unfiltered = true;
        return run();
      }
      rethrow;
    }
  }

  Future<List<AppSdk>> fetchSdks() async {
    final uri = _uri('/sdk', const {});
    final body = await _getJson(uri, ttl: const Duration(hours: 6));
    if (body is! List) {
      throw AppsCatalogException(0, uri.toString(), 'expected list');
    }
    return readEach(body, AppSdk.fromJson, 'SDKs');
  }

  Future<List<AppCategory>> fetchCategories({int limit = 500}) {
    return _withApiFallback(() async {
      final uri = _uri('/0/category', {'limit': '$limit', ..._apiParams()});
      final body = await _getJson(uri, ttl: const Duration(hours: 1));
      if (body is! List) {
        throw AppsCatalogException(0, uri.toString(), 'expected list');
      }
      return readEach(body, AppCategory.fromJson, 'categories');
    });
  }

  Future<AppsPage> fetchApps({
    int offset = 0,
    int limit = 48,
    AppsSort sortBy = AppsSort.newUpdates,
    String? categoryId,
    String? query,
    bool? isLatestReleaseVersion,
    bool? hasVersion,
  }) {
    return _withApiFallback(() async {
      final uri = _uri('/0/application', {
        'limit': '$limit',
        'offset': '$offset',
        'sort_by': sortBy.field,
        'sort_order': '${sortBy.order}',
        if (categoryId != null && categoryId.isNotEmpty)
          'category_id': categoryId,
        if (query != null && query.isNotEmpty) 'query': query,
        if (isLatestReleaseVersion != null)
          'is_latest_release_version': '$isLatestReleaseVersion',
        if (hasVersion != null) 'has_version': '$hasVersion',
        ..._apiParams(),
      });
      final body = await _getJson(
        uri,
        ttl: query != null && query.isNotEmpty
            ? null
            : const Duration(minutes: 5),
      );
      if (body is! List) {
        throw AppsCatalogException(0, uri.toString(), 'expected list');
      }
      final items = readEach(body, AppCard.fromJson, 'apps');
      return AppsPage(items: items, offset: offset, limit: limit);
    });
  }

  static const int _maxUidBatch = 500;

  Future<List<AppCard>> fetchAppsByUids(
    List<String> uids, {
    AppsSort sortBy = AppsSort.newUpdates,
  }) {
    return _withApiFallback(() async {
      final clean = uids
          .where((e) => RegExp(r'^[0-9a-f]{24}$').hasMatch(e))
          .toList(growable: false);
      if (clean.isEmpty) return const <AppCard>[];
      final out = <AppCard>[];
      for (var i = 0; i < clean.length; i += _maxUidBatch) {
        final chunk = clean.sublist(
          i,
          math.min(i + _maxUidBatch, clean.length),
        );
        final uri = _uri('/1/application', const {});
        final body = await AppHttp.postJson(
          uri,
          <String, dynamic>{
            'limit': chunk.length,
            'offset': 0,
            'sort_by': sortBy.field,
            'sort_order': sortBy.order,
            'applications': chunk,
            ..._apiParams(),
          },
          headers: {io.HttpHeaders.userAgentHeader: userAgent},
        );
        if (body is! List) {
          throw AppsCatalogException(0, uri.toString(), 'expected list');
        }
        out.addAll(readEach(body, AppCard.fromJson, 'apps'));
      }
      return out;
    });
  }

  Future<AppDetail> fetchApp(String idOrAlias, {bool? isLatestReleaseVersion}) {
    return _withApiFallback(() async {
      final uri = _uri('/0/application/$idOrAlias', {
        if (isLatestReleaseVersion != null)
          'is_latest_release_version': '$isLatestReleaseVersion',
        ..._apiParams(),
      });
      final body = await _getJson(uri, ttl: const Duration(minutes: 5));
      if (body is! Map<String, dynamic>) {
        throw AppsCatalogException(0, uri.toString(), 'expected object');
      }
      return AppDetail.fromJson(body);
    });
  }

  /// Where a version's file for [target] and [api] is, as the official app
  /// asks for it.
  Uri buildDownloadUri(
    String versionId, {
    required String target,
    required String api,
  }) => _uri(
    '/0/application/version/${Uri.encodeComponent(versionId)}/build/compatible',
    {'target': target, 'api': api},
  );

  Future<List<int>> fetchFapBuild(
    String versionId, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    String? apiOverride,
  }) async {
    final t = target;
    final a = apiOverride ?? api;
    if (t == null || a == null) {
      throw StateError(
        'AppsCatalogApi.target / .api must be set before fetching builds',
      );
    }
    return AppHttp.getBytes(
      buildDownloadUri(versionId, target: t, api: a),
      headers: {io.HttpHeaders.userAgentHeader: userAgent},
      onProgress: onProgress,
    );
  }

  Uri sourceBundleUri(String versionId) =>
      _uri('/application/version/$versionId/bundle', const {});

  Future<List<int>> fetchSourceBundle(
    String versionId, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final uri = sourceBundleUri(versionId);
    return AppHttp.getBytes(
      uri,
      headers: {io.HttpHeaders.userAgentHeader: userAgent},
      onProgress: onProgress,
    );
  }
}
