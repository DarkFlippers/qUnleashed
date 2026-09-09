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
    final res = await get(
      uri,
      headers: {io.HttpHeaders.acceptHeader: 'application/json', ...headers},
    );
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppHttpException(res.statusCode, uri.toString(), text);
    }
    return _decodeText(text);
  }

  static Future<dynamic> postJson(
    Uri uri,
    Object body, {
    Map<String, String> headers = const {},
  }) async {
    final req = await client.postUrl(uri);
    req.headers
      ..set(io.HttpHeaders.acceptHeader, 'application/json')
      ..set(io.HttpHeaders.contentTypeHeader, 'application/json');
    for (final entry in headers.entries) {
      req.headers.set(entry.key, entry.value);
    }
    req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppHttpException(res.statusCode, uri.toString(), text);
    }
    return _decodeText(text);
  }

  static io.Directory? _jsonCacheDir;

  /// The on-disk JSON HTTP cache directory (inside the app support container).
  /// Exposed so the Storage settings can report its size and clear it.
  static Future<io.Directory> httpCacheDirectory() => _ensureJsonCacheDir();

  /// Points the cache at a directory of the caller's choosing.
  ///
  /// For tests only: the real path comes from the platform's app-support
  /// container, which a unit test has no plugin to resolve, and without this
  /// none of the caching behaviour - the TTL, revalidation, the stale copy
  /// that makes screens work offline - can be exercised at all.
  @visibleForTesting
  static set jsonCacheDirectory(io.Directory? dir) => _jsonCacheDir = dir;

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
    _CachePaths? paths;
    _JsonCacheEntry? cached;
    try {
      final dir = await _ensureJsonCacheDir();
      final key = sha256.convert(utf8.encode(uri.toString())).toString();
      paths = _CachePaths(dir, key);
      cached = await _JsonCacheEntry.read(paths);
    } catch (_) {}

    if (cached != null && DateTime.now().difference(cached.fetchedAt) < ttl) {
      final hit = await _tryDecodeBodyFile(cached.bodyFile);
      if (hit.ok) return hit.value;
      // Unusable, so fall through to the fetch below rather than serve it.
      cached = null;
    }

    // Only the fetch is guarded, and the body is decoded after it: falling back
    // to a stale copy is the answer to a network failure, not to a response
    // that arrived and will not parse. Returning a decode from inside the try
    // would put it back under the catch, which answers failure with the same
    // stale copy - spawning a second isolate to redo the work that just failed.
    //
    // Exactly one of these is set below: a 304 leaves the body already on disk
    // current, anything else produces a fresh one.
    String? fresh;
    String? freshEtag;
    io.File? unchanged;
    try {
      final etag = cached?.etag ?? '';
      final res = await get(
        uri,
        headers: {
          io.HttpHeaders.acceptHeader: 'application/json',
          if (etag.isNotEmpty) io.HttpHeaders.ifNoneMatchHeader: etag,
          ...headers,
        },
      );
      if (res.statusCode == io.HttpStatus.notModified && cached != null) {
        await res.drain<void>();
        // Only the timestamp moves, and it now lives in its own file - a 304
        // used to rewrite the entire body to disk to re-stamp the TTL.
        // A 304 should carry an ETag and servers do rotate weak validators, so
        // re-stamping with the old one would keep revalidating against a
        // validator the server has already moved past.
        final rotated = res.headers.value(io.HttpHeaders.etagHeader);
        if (paths != null) {
          await _JsonCacheEntry.stamp(paths, rotated ?? cached.etag);
        }
        unchanged = cached.bodyFile;
      } else {
        final text = await res.transform(utf8.decoder).join();
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw AppHttpException(res.statusCode, uri.toString(), text);
        }
        fresh = text;
        freshEtag = res.headers.value(io.HttpHeaders.etagHeader) ?? '';
      }
    } catch (_) {
      // The stale copy is the answer to a network failure - but only if it
      // reads. If it does not, the caller needs the network error that sent us
      // here, not a parse error about the fallback.
      if (cached != null) {
        final stale = await _tryDecodeBodyFile(cached.bodyFile);
        if (stale.ok) return stale.value;
      }
      rethrow;
    }
    // Freshly fetched, so the text is already in this isolate: hand it over
    // rather than making the isolate read back what we just wrote.
    final body = fresh;
    if (body != null) {
      // Decoded before it is stored, and outside the try so a parse failure is
      // not answered with the stale copy. A captive portal replies 200 with an
      // HTML login page; caching that would overwrite a good entry with
      // something that can never be served, taking the offline copy with it.
      final decoded = await _decodeText(body);
      // An empty response is not cached either: a zero-length body on disk is
      // exactly what damage looks like, and it must stay unambiguous.
      if (paths != null && body.isNotEmpty) {
        try {
          await _JsonCacheEntry.store(paths, etag: freshEtag ?? '', body: body);
        } catch (_) {}
      }
      return decoded;
    }
    final file = unchanged;
    if (file != null) {
      final revalidated = await _tryDecodeBodyFile(file);
      if (revalidated.ok) return revalidated.value;
      // The server says our copy is current and it will not parse. There is
      // nothing to serve now; the next open reads the same file, treats it as
      // a miss and refetches, so this heals itself rather than sticking.
      throw const FormatException('cached body unreadable after revalidation');
    }
    throw StateError('revalidation produced neither a body nor a cache hit');
  }

  /// Parses a body that is already in this isolate, off the calling isolate.
  ///
  /// An empty *response* decodes to null, which is a legitimate answer from a
  /// server. That is the opposite of [_readAndDecodeJson], where an empty
  /// *file* is damage - and the difference is why an empty response is never
  /// written to the cache in the first place.
  static Future<dynamic> _decodeText(String text) {
    if (text.isEmpty) return Future.value();
    return compute(jsonDecode, text);
  }

  /// Parses a cached body without touching it on the calling isolate: the
  /// isolate is given the path and does the read, the UTF-8 decode and the
  /// parse. This is the whole point of splitting the body out of the entry.
  static Future<dynamic> _decodeBodyFile(io.File file) =>
      compute(_readAndDecodeJson, file.path);

  /// Decodes a cached body, reporting a bad file rather than throwing.
  ///
  /// Every caller answers an unusable cache entry the same way - treat it as
  /// absent - and two of them must not let a parse error stand in for the
  /// reason they were reached: the offline path would report a truncated file
  /// instead of the connection failure that sent it there.
  ///
  /// Only these two exceptions mean the file itself is unusable. Anything else
  /// - an isolate that will not spawn under memory pressure, most of all - is
  /// not a cache fault and must propagate, or every open silently refetches
  /// with no way to tell the two apart.
  static Future<({bool ok, dynamic value})> _tryDecodeBodyFile(
    io.File file,
  ) async {
    try {
      return (ok: true, value: await _decodeBodyFile(file));
    } on FormatException {
      return (ok: false, value: null);
    } on io.FileSystemException {
      return (ok: false, value: null);
    }
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

/// Reads and parses a JSON file. Runs inside a [compute] isolate, so it must
/// stay top-level and take nothing but the path.
Future<dynamic> _readAndDecodeJson(String path) async {
  final text = await io.File(path).readAsString();
  // An empty cache file is damage, never a value: an empty response is not
  // stored in the first place. Throwing is what lets the callers treat it as a
  // miss - returning null here made a destroyed entry look like a successful
  // hit that decoded to nothing, and no guard could tell the difference.
  if (text.isEmpty) throw const FormatException('empty cache body');
  return jsonDecode(text);
}

/// The three files one cache key can occupy: the metadata, the raw body, and
/// the single pre-split file an older build may have left behind.
class _CachePaths {
  _CachePaths(io.Directory dir, String key)
    : meta = io.File('${dir.path}${io.Platform.pathSeparator}$key.meta'),
      body = io.File('${dir.path}${io.Platform.pathSeparator}$key.body'),
      legacy = io.File('${dir.path}${io.Platform.pathSeparator}$key.json');

  final io.File meta;
  final io.File body;
  final io.File legacy;
}

/// A cache entry's metadata, plus where its body is. The body deliberately is
/// not a field: holding it here is what forced the whole payload through the
/// calling isolate, since reading the entry meant unescaping the body out of
/// the same JSON object.
class _JsonCacheEntry {
  _JsonCacheEntry({
    required this.etag,
    required this.fetchedAt,
    required this.bodyFile,
  });

  final String etag;
  final DateTime fetchedAt;
  final io.File bodyFile;

  static Future<_JsonCacheEntry?> read(_CachePaths paths) async {
    try {
      if (await paths.meta.exists() && await paths.body.exists()) {
        // Tens of bytes, so decoding it here costs nothing measurable.
        final data = jsonDecode(await paths.meta.readAsString());
        if (data is! Map<String, dynamic>) return null;
        final fetchedAtMs = (data['fetched_at'] as num?)?.toInt();
        if (fetchedAtMs == null) return null;
        return _JsonCacheEntry(
          etag: (data['etag'] as String?) ?? '',
          fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAtMs),
          bodyFile: paths.body,
        );
      }
    } catch (_) {
      return null;
    }
    return _migrate(paths);
  }

  /// Splits a pre-split-format entry into the pair and returns it.
  ///
  /// Here only so an upgrade does not throw away a cache an offline user is
  /// relying on - the stale copy is what makes cached screens work with no
  /// network. The decode runs in an isolate because it is exactly the
  /// whole-body unescape the new format exists to keep off the UI isolate, and
  /// the old file is deleted once split, so this runs at most once per entry.
  static Future<_JsonCacheEntry?> _migrate(_CachePaths paths) async {
    try {
      if (!await paths.legacy.exists()) return null;
      final data = await compute(_readAndDecodeJson, paths.legacy.path);
      if (data is! Map) return null;
      final fetchedAtMs = (data['fetched_at'] as num?)?.toInt();
      final body = data['body'] as String?;
      if (fetchedAtMs == null || body == null) return null;
      final etag = (data['etag'] as String?) ?? '';
      // store throws if either half failed, so reaching the delete means the
      // new pair is on disk. The legacy file is the only copy until then, and
      // removing it on a half-completed write is how an offline user loses
      // their cache for good.
      await store(paths, etag: etag, body: body, fetchedAtMs: fetchedAtMs);
      // Cleanup, so its failure - including losing the race with a concurrent
      // call that already deleted it - must not discard the migrated entry.
      try {
        await paths.legacy.delete();
      } catch (_) {}
      return _JsonCacheEntry(
        etag: etag,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAtMs),
        bodyFile: paths.body,
      );
    } catch (_) {
      return null;
    }
  }

  /// Writes the body beside its target and renames it into place, then the
  /// metadata.
  ///
  /// The rename is what makes an overwrite safe. Writing in place truncates
  /// first, so a crash or a full disk mid-write used to leave a zero-length
  /// body next to metadata that was still intact and still inside its TTL -
  /// a cache hit that decoded to null, healed its own timestamp on the next
  /// 304, and never refetched. A rename is atomic, so a reader sees either the
  /// previous complete body or the new one.
  ///
  /// Metadata goes last. On a first write a crash between the two leaves no
  /// metadata, which reads as a miss. On an overwrite it leaves the previous
  /// metadata against the new body: an older timestamp and a stale validator,
  /// so the next read revalidates and corrects itself.
  ///
  /// Throws if either write fails. Callers that delete another copy of the
  /// body depend on hearing about it.
  static Future<void> store(
    _CachePaths paths, {
    required String etag,
    required String body,
    int? fetchedAtMs,
  }) async {
    final tmp = io.File('${paths.body.path}.tmp');
    try {
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(paths.body.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
    await _writeMeta(paths, etag, fetchedAtMs);
  }

  /// Not flushed, deliberately. The body above is fsynced before its rename
  /// because that is what makes the swap atomic; this is ~46 bytes whose loss
  /// costs one revalidation round trip, and fsyncing it measured 1.8ms - most
  /// of the cost of a 304, which is the most frequent write there is. The
  /// ordering [store] documents comes from the await and the rename, not from
  /// this flush: a crash preserves page-cache order, and a power loss leaves
  /// no metadata, which reads as a miss.
  static Future<void> _writeMeta(
    _CachePaths paths,
    String etag,
    int? fetchedAtMs,
  ) => paths.meta.writeAsString(
    jsonEncode({
      'etag': etag,
      'fetched_at': fetchedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    }),
  );

  /// Re-stamps the metadata after a 304, best-effort on purpose: the body on
  /// disk is valid either way, so failing here costs one revalidation round
  /// trip rather than correctness.
  static Future<void> stamp(_CachePaths paths, String etag) async {
    try {
      await _writeMeta(paths, etag, null);
    } catch (_) {}
  }
}
