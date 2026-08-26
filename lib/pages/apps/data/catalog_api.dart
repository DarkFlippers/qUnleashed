import 'dart:io' as io;
import 'dart:math' as math;

import '../../../services/http/app_http.dart';
import 'models/card.dart';
import 'models/category.dart';
import 'models/detail.dart';

enum AppsSort {
  newUpdates(field: 'updated_at', order: -1),
  oldUpdates(field: 'updated_at', order: 1),
  newReleases(field: 'created_at', order: -1),
  oldReleases(field: 'created_at', order: 1),
  alphabetical(field: 'updated_at', order: -1);

  final String field;
  final int order;
  const AppsSort({required this.field, required this.order});
}

class AppsPage {
  final List<AppCard> items;
  final int offset;
  final int limit;

  const AppsPage({
    required this.items,
    required this.offset,
    required this.limit,
  });

  bool get hasMore => items.length >= limit;
  int get nextOffset => offset + items.length;
}

class AppsCatalogException implements Exception {
  final int statusCode;
  final String url;
  final String? body;

  AppsCatalogException(this.statusCode, this.url, [this.body]);

  @override
  String toString() =>
      'AppsCatalogException($statusCode, $url${body == null ? '' : ', $body'})';
}

class AppsCatalogApi {
  static const String defaultBaseUrl =
      'https://catalog.flipperzero.one/api/v0';

  final String baseUrl;
  final String userAgent;

  String? api;
  String? target;

  bool _closed = false;

  AppsCatalogApi({
    this.baseUrl = defaultBaseUrl,
    this.userAgent = AppHttp.userAgent,
    this.api,
    this.target,
  });

  void close() {
    _closed = true;
  }

  bool unfiltered = false;

  Map<String, String> _apiParams() {
    if (unfiltered) return const {};
    final a = api, t = target;
    if (a != null && a.isNotEmpty && t != null && t.isNotEmpty) {
      return {'api': a, 'target': t};
    }
    return const {};
  }

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
    return body
        .whereType<Map<String, dynamic>>()
        .map(AppSdk.fromJson)
        .toList(growable: false);
  }

  Future<List<AppCategory>> fetchCategories({int limit = 500}) {
    return _withApiFallback(() async {
      final uri = _uri('/category', {
        'limit': '$limit',
        ..._apiParams(),
      });
      final body = await _getJson(uri, ttl: const Duration(hours: 1));
      if (body is! List) {
        throw AppsCatalogException(0, uri.toString(), 'expected list');
      }
      return body
          .whereType<Map<String, dynamic>>()
          .map(AppCategory.fromJson)
          .toList(growable: false);
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
      final items = body
          .whereType<Map<String, dynamic>>()
          .map(AppCard.fromJson)
          .toList(growable: false);
      return AppsPage(items: items, offset: offset, limit: limit);
    });
  }

  static const int _maxUidBatch = 500;

  Future<List<AppCard>> fetchAppsByUids(
    List<String> uids, {
    AppsSort sortBy = AppsSort.newUpdates,
  }) {
    return _withApiFallback(() async {
      final clean = uids.where((e) => e.isNotEmpty).toList(growable: false);
      if (clean.isEmpty) return const <AppCard>[];
      final out = <AppCard>[];
      for (var i = 0; i < clean.length; i += _maxUidBatch) {
        final chunk = clean.sublist(i, math.min(i + _maxUidBatch, clean.length));
        final uri = _uri('/1/application', const {});
        if (_closed) throw StateError('AppsCatalogApi has been closed');
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
        out.addAll(
          body.whereType<Map<String, dynamic>>().map(AppCard.fromJson),
        );
      }
      return out;
    });
  }

  Future<AppCard> fetchAppCard(String idOrAlias) {
    return _withApiFallback(() async {
      final uri = _uri('/application/$idOrAlias', {
        ..._apiParams(),
      });
      final body = await _getJson(uri, ttl: const Duration(minutes: 30));
      if (body is! Map<String, dynamic>) {
        throw AppsCatalogException(0, uri.toString(), 'expected object');
      }
      return AppCard.fromJson(body);
    });
  }

  Future<AppDetail> fetchApp(
    String idOrAlias, {
    bool? isLatestReleaseVersion,
  }) {
    return _withApiFallback(() async {
      final uri = _uri('/application/$idOrAlias', {
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

  Future<List<int>> fetchFapBuild(
    String versionId, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    String? apiOverride,
  }) async {
    final t = target;
    final a = apiOverride ?? api;
    if (t == null || a == null) {
      throw StateError(
          'AppsCatalogApi.target / .api must be set before fetching builds');
    }
    final uri = _uri(
      '/application/version/$versionId/build/compatible',
      {'target': t, 'api': a},
    );
    if (_closed) throw StateError('AppsCatalogApi has been closed');
    return AppHttp.getBytes(
      uri,
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
    if (_closed) throw StateError('AppsCatalogApi has been closed');
    return AppHttp.getBytes(
      uri,
      headers: {io.HttpHeaders.userAgentHeader: userAgent},
      onProgress: onProgress,
    );
  }

  Uri _uri(String path, Map<String, String> query) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '${base.path}$path',
      queryParameters: query.isEmpty ? null : query,
    );
  }

  Future<dynamic> _getJson(Uri uri, {Duration? ttl}) async {
    if (_closed) {
      throw StateError('AppsCatalogApi has been closed');
    }
    final headers = {io.HttpHeaders.userAgentHeader: userAgent};
    if (ttl == null) return AppHttp.getJson(uri, headers: headers);
    return AppHttp.getJsonCached(uri, ttl: ttl, headers: headers);
  }
}
