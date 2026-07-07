import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppHttpException implements Exception {
  AppHttpException(this.statusCode, this.url, [this.body]);

  final int statusCode;
  final String url;
  final String? body;

  @override
  String toString() =>
      'AppHttpException($statusCode, $url${body == null ? '' : ', $body'})';
}

/// Single shared HTTP client for the whole app: connections are kept alive
/// between requests instead of paying TCP+TLS setup per call. Never close it
/// from feature code — page-level `close()` methods must only stop issuing
/// new requests.
class AppHttp {
  AppHttp._();

  static const String userAgent = 'qunleashed-app';

  static final io.HttpClient client = io.HttpClient()
    ..connectionTimeout = const Duration(seconds: 25)
    ..userAgent = userAgent;

  static Future<io.HttpClientResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final req = await client.getUrl(uri);
    for (final entry in headers.entries) {
      req.headers.set(entry.key, entry.value);
    }
    return req.close();
  }

  static Future<dynamic> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final res = await get(uri, headers: {
      io.HttpHeaders.acceptHeader: 'application/json',
      ...headers,
    });
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppHttpException(res.statusCode, uri.toString(), text);
    }
    if (text.isEmpty) return null;
    return compute(jsonDecode, text);
  }

  static io.Directory? _jsonCacheDir;

  static Future<io.Directory> _ensureJsonCacheDir() async {
    final existing = _jsonCacheDir;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final dir = io.Directory(
      '${support.path}${io.Platform.pathSeparator}http_cache',
    );
    await dir.create(recursive: true);
    return _jsonCacheDir = dir;
  }

  /// GET JSON through a disk cache. An entry younger than [ttl] is served
  /// without touching the network; a stale entry is revalidated with
  /// If-None-Match (a 304 costs no body transfer); when the network fails the
  /// stale copy is returned if one exists, so cached screens work offline.
  static Future<dynamic> getJsonCached(
    Uri uri, {
    Duration ttl = const Duration(minutes: 5),
    Map<String, String> headers = const {},
  }) async {
    io.File? file;
    _JsonCacheEntry? cached;
    try {
      final dir = await _ensureJsonCacheDir();
      final key = sha256.convert(utf8.encode(uri.toString())).toString();
      file = io.File('${dir.path}${io.Platform.pathSeparator}$key.json');
      cached = await _JsonCacheEntry.read(file);
    } catch (_) {}

    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < ttl) {
      return _decodeCachedBody(cached.body);
    }

    try {
      final etag = cached?.etag ?? '';
      final res = await get(uri, headers: {
        io.HttpHeaders.acceptHeader: 'application/json',
        if (etag.isNotEmpty) io.HttpHeaders.ifNoneMatchHeader: etag,
        ...headers,
      });
      if (res.statusCode == io.HttpStatus.notModified && cached != null) {
        await res.drain<void>();
        if (file != null) await cached.refresh(file);
        return _decodeCachedBody(cached.body);
      }
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AppHttpException(res.statusCode, uri.toString(), text);
      }
      if (file != null) {
        final entry = _JsonCacheEntry(
          etag: res.headers.value(io.HttpHeaders.etagHeader) ?? '',
          fetchedAt: DateTime.now(),
          body: text,
        );
        try {
          await entry.write(file);
        } catch (_) {}
      }
      return _decodeCachedBody(text);
    } catch (_) {
      if (cached != null) return _decodeCachedBody(cached.body);
      rethrow;
    }
  }

  static Future<dynamic> _decodeCachedBody(String text) {
    if (text.isEmpty) return Future.value();
    return compute(jsonDecode, text);
  }

  static Future<Uint8List> getBytes(
    Uri uri, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
  }) async {
    final res = await get(uri, headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final text = await res.transform(utf8.decoder).join();
      throw AppHttpException(res.statusCode, uri.toString(), text);
    }
    final total = res.contentLength > 0 ? res.contentLength : null;
    final out = BytesBuilder(copy: false);
    onProgress?.call(0, total);
    await for (final chunk in res) {
      out.add(chunk);
      onProgress?.call(out.length, total);
    }
    return out.takeBytes();
  }

  static Future<void> downloadToFile(
    Uri uri,
    String savePath, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
  }) async {
    final res = await get(uri, headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppHttpException(res.statusCode, uri.toString());
    }
    final total = res.contentLength > 0 ? res.contentLength : null;
    final sink = io.File(savePath).openWrite();
    var received = 0;
    try {
      onProgress?.call(0, total);
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}

class _JsonCacheEntry {
  _JsonCacheEntry({
    required this.etag,
    required this.fetchedAt,
    required this.body,
  });

  final String etag;
  final DateTime fetchedAt;
  final String body;

  static Future<_JsonCacheEntry?> read(io.File file) async {
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return null;
      final fetchedAtMs = (data['fetched_at'] as num?)?.toInt();
      final body = data['body'] as String?;
      if (fetchedAtMs == null || body == null) return null;
      return _JsonCacheEntry(
        etag: (data['etag'] as String?) ?? '',
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAtMs),
        body: body,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(io.File file) => file.writeAsString(
    jsonEncode({
      'etag': etag,
      'fetched_at': fetchedAt.millisecondsSinceEpoch,
      'body': body,
    }),
    flush: true,
  );

  /// Re-stamps the entry after a 304 so the TTL window restarts.
  Future<void> refresh(io.File file) async {
    try {
      await _JsonCacheEntry(
        etag: etag,
        fetchedAt: DateTime.now(),
        body: body,
      ).write(file);
    } catch (_) {}
  }
}
