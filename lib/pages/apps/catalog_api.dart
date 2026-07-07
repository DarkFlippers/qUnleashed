import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';

import '../../services/http/app_http.dart';
import 'models/card.dart';
import 'models/category.dart';
import 'models/detail.dart';

enum AppsSort {
  newUpdates(field: 'updated_at', order: -1),
  oldUpdates(field: 'updated_at', order: 1),
  newReleases(field: 'created_at', order: -1),
  oldReleases(field: 'created_at', order: 1);

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

  Future<List<AppCategory>> fetchCategories({int limit = 500}) async {
    final uri = _uri('/category', {
      'limit': '$limit',
      'api': ?api,
      'target': ?target,
    });
    final body = await _getJson(uri);
    if (body is! List) {
      throw AppsCatalogException(0, uri.toString(), 'expected list');
    }
    return body
        .whereType<Map<String, dynamic>>()
        .map(AppCategory.fromJson)
        .toList(growable: false);
  }

  Future<AppsPage> fetchApps({
    int offset = 0,
    int limit = 48,
    AppsSort sortBy = AppsSort.newUpdates,
    String? categoryId,
    String? query,
    bool? isLatestReleaseVersion,
    bool? hasVersion,
  }) async {
    final uri = _uri('/0/application', {
      'limit': '$limit',
      'offset': '$offset',
      'sort_by': sortBy.field,
      'sort_order': '${sortBy.order}',
      if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
      if (query != null && query.isNotEmpty) 'query': query,
      if (isLatestReleaseVersion != null)
        'is_latest_release_version': '$isLatestReleaseVersion',
      if (hasVersion != null) 'has_version': '$hasVersion',
      'api': ?api,
      'target': ?target,
    });
    final body = await _getJson(uri);
    if (body is! List) {
      throw AppsCatalogException(0, uri.toString(), 'expected list');
    }
    final items = body
        .whereType<Map<String, dynamic>>()
        .map(AppCard.fromJson)
        .toList(growable: false);
    return AppsPage(items: items, offset: offset, limit: limit);
  }

  Future<AppDetail> fetchApp(
    String idOrAlias, {
    bool? isLatestReleaseVersion,
  }) async {
    final uri = _uri('/application/$idOrAlias', {
      if (isLatestReleaseVersion != null)
        'is_latest_release_version': '$isLatestReleaseVersion',
      'api': ?api,
      'target': ?target,
    });
    final body = await _getJson(uri);
    if (body is! Map<String, dynamic>) {
      throw AppsCatalogException(0, uri.toString(), 'expected object');
    }
    return AppDetail.fromJson(body);
  }

  Future<List<int>> fetchFapBuild(
    String versionId, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final t = target;
    final a = api;
    if (t == null || a == null) {
      throw StateError(
          'AppsCatalogApi.target / .api must be set before fetching builds');
    }
    final uri = _uri(
      '/application/version/$versionId/build/compatible',
      {'target': t, 'api': a},
    );
    return _getBytes(uri, onProgress: onProgress);
  }

  Uri _uri(String path, Map<String, String> query) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '${base.path}$path',
      queryParameters: query.isEmpty ? null : query,
    );
  }

  Future<dynamic> _getJson(Uri uri) async {
    final res = await _send(uri);
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppsCatalogException(res.statusCode, uri.toString(), text);
    }
    if (text.isEmpty) return null;
    return compute(jsonDecode, text);
  }

  Future<List<int>> _getBytes(
    Uri uri, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final res = await _send(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final text = await res.transform(utf8.decoder).join();
      throw AppsCatalogException(res.statusCode, uri.toString(), text);
    }
    final totalBytes = res.contentLength > 0 ? res.contentLength : null;
    final out = <int>[];
    var receivedBytes = 0;
    onProgress?.call(0, totalBytes);
    await for (final chunk in res) {
      out.addAll(chunk);
      receivedBytes += chunk.length;
      onProgress?.call(receivedBytes, totalBytes);
    }
    return out;
  }

  Future<io.HttpClientResponse> _send(Uri uri) async {
    if (_closed) {
      throw StateError('AppsCatalogApi has been closed');
    }
    return AppHttp.get(uri, headers: {
      io.HttpHeaders.userAgentHeader: userAgent,
      io.HttpHeaders.acceptHeader: 'application/json',
    });
  }
}
