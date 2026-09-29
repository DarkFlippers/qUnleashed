import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/http/app_http.dart';
import 'package:qunleashed/services/logging.dart';

/// What the JSON cache says when it cannot do its job.
///
/// The cache is what makes the apps and firmware screens work offline, and
/// three of its failures used to be `catch (_) {}`. None of them breaks the
/// call they happen in — the read falls through to the network, the store
/// happens after the answer is already on its way — which is exactly why they
/// were invisible: the cost lands on the *next* launch, offline, with nothing
/// on disk and no record of why.
///
/// ADR 0008: nothing is waiting on any of these, so the answer is a kept log
/// rather than a surface.
class FakeServer {
  FakeServer(this._server)
    : uri = Uri.parse('http://127.0.0.1:${_server.port}/catalog.json') {
    _server.listen((req) async {
      requests += 1;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': true}));
      await req.response.close();
    });
  }

  static Future<FakeServer> start() async =>
      FakeServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final Uri uri;
  int requests = 0;

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late Directory cacheDir;
  late FakeServer server;
  late int logBase;

  setUp(() async {
    cacheDir = Directory.systemTemp.createTempSync('http_cache_failures');
    AppHttp.jsonCacheDirectory = cacheDir;
    server = await FakeServer.start();
    LogService.clearHistory();
    logBase = LogService.history.length;
  });

  tearDown(() async {
    AppHttp.jsonCacheDirectory = null;
    await server.stop();
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  });

  bool said(String fragment) =>
      LogService.history.skip(logBase).any((l) => l.contains(fragment));

  /// The cache file names for [uri], which are keyed by its digest.
  String keyOf(Uri uri) =>
      sha256.convert(utf8.encode(uri.toString())).toString();

  group('a cache that works', () {
    test('says nothing', () async {
      await AppHttp.getJsonCached(server.uri);

      expect(said('[Http]'), isFalse);
    });

    test('serves the second call from disk', () async {
      await AppHttp.getJsonCached(server.uri);
      await AppHttp.getJsonCached(server.uri);

      expect(server.requests, 1);
    });
  });

  group('an entry that will not parse', () {
    // Both halves on disk and the metadata truncated - a process that died
    // mid-write, or a format this version no longer understands. The entry is
    // treated as absent, which is right, and it will fail the same way on
    // every launch until something overwrites it.
    setUp(() {
      final sep = Platform.pathSeparator;
      final key = keyOf(server.uri);
      File('${cacheDir.path}$sep$key.meta').writeAsStringSync('{"etag":');
      File('${cacheDir.path}$sep$key.body').writeAsStringSync('{}');
    });

    test('still answers from the network', () async {
      final body = await AppHttp.getJsonCached(server.uri);

      expect(body, isNotNull);
      expect(server.requests, 1);
    });

    test('says the entry could not be read', () async {
      await AppHttp.getJsonCached(server.uri);

      expect(said('cache entry unreadable'), isTrue);
    });

    // It is read inside `_JsonCacheEntry.read`, which returns null rather
    // than throwing - so the catch around the whole cache lookup never sees
    // it, and neither did anyone else.
    test('is not reported twice', () async {
      await AppHttp.getJsonCached(server.uri);

      expect(
        LogService.history.skip(logBase).where((l) => l.contains('unreadable')),
        hasLength(1),
      );
    });
  });

  group('a cache that cannot be written', () {
    // The whole directory replaced by a file. This is also the only way to
    // reach the catch around the lookup itself: a bad *entry* is handled a
    // level down, so what is left for the outer one is the cache directory
    // being unusable.
    setUp(() async {
      cacheDir.deleteSync(recursive: true);
      File(cacheDir.path).writeAsStringSync('in the way');
    });

    test('still answers the caller', () async {
      final body = await AppHttp.getJsonCached(server.uri);

      expect(body, isNotNull);
    });

    test('says the answer was not kept', () async {
      await AppHttp.getJsonCached(server.uri);

      expect(said('could not cache'), isTrue);
    });

    test('does not throw out of the call', () async {
      await expectLater(AppHttp.getJsonCached(server.uri), completes);
    });
  });
}
