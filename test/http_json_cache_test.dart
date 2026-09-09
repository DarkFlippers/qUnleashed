import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/http/app_http.dart';

/// A payload big enough that the split matters, small enough to stay quick.
final Map<String, Object?> payload = {
  'data': [
    for (var i = 0; i < 40; i++) {'id': 'app_$i', 'name': 'Application $i'},
  ],
  'total': 40,
};

/// A server that answers one JSON document, counts requests, and honours
/// If-None-Match so revalidation can be observed rather than assumed.
class FakeCatalog {
  FakeCatalog(this._server)
    : uri = Uri.parse('http://127.0.0.1:${_server.port}/catalog.json') {
    _server.listen((req) async {
      requests += 1;
      ifNoneMatch.add(req.headers.value(HttpHeaders.ifNoneMatchHeader));
      if (status != 200) {
        req.response.statusCode = status;
        req.response.write('upstream said no');
        await req.response.close();
        return;
      }
      if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
        req.response.statusCode = HttpStatus.notModified;
        await req.response.close();
        return;
      }
      req.response.headers.set(HttpHeaders.etagHeader, etag);
      req.response.write(jsonEncode(body));
      await req.response.close();
    });
  }

  static Future<FakeCatalog> start() async =>
      FakeCatalog(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  /// Captured up front: reading `port` off a closed server throws, and the
  /// offline tests need the address after shutting it down.
  final Uri uri;
  bool _stopped = false;
  int requests = 0;
  int status = 200;
  String etag = 'W/"v1"';
  Object? body = payload;
  final List<String?> ifNoneMatch = [];

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _server.close(force: true);
  }
}

void main() {
  late Directory cacheDir;
  late FakeCatalog server;

  setUp(() async {
    cacheDir = Directory.systemTemp.createTempSync('http_json_cache');
    AppHttp.jsonCacheDirectory = cacheDir;
    server = await FakeCatalog.start();
  });

  tearDown(() async {
    await server.stop();
    AppHttp.jsonCacheDirectory = null;
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  });

  String keyFor(Uri uri) =>
      sha256.convert(utf8.encode(uri.toString())).toString();

  File cacheFile(Uri uri, String ext) =>
      File('${cacheDir.path}${Platform.pathSeparator}${keyFor(uri)}.$ext');

  /// Backdates an entry's timestamp so staleness can be tested without waiting.
  void ageEntry(Uri uri, Duration by) {
    final meta = cacheFile(uri, 'meta');
    final data = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
    data['fetched_at'] = DateTime.fromMillisecondsSinceEpoch(
      data['fetched_at'] as int,
    ).subtract(by).millisecondsSinceEpoch;
    meta.writeAsStringSync(jsonEncode(data));
  }

  group('getJsonCached', () {
    test('fetches and returns the document', () async {
      final got = await AppHttp.getJsonCached(server.uri);

      expect((got as Map)['total'], 40);
      expect(server.requests, 1);
    });

    test('serves a fresh entry without touching the network', () async {
      await AppHttp.getJsonCached(server.uri);
      final again = await AppHttp.getJsonCached(server.uri);

      expect((again as Map)['total'], 40);
      expect(server.requests, 1, reason: 'the second read came from disk');
    });

    // The point of the change: the body is stored raw, so reading an entry
    // never means unescaping the whole payload out of a wrapper object on the
    // calling isolate.
    test('stores the body raw, not embedded in the metadata', () async {
      await AppHttp.getJsonCached(server.uri);

      final body = cacheFile(server.uri, 'body');
      final meta = cacheFile(server.uri, 'meta');

      expect(body.existsSync(), isTrue);
      expect(meta.existsSync(), isTrue);
      expect(jsonDecode(body.readAsStringSync()), payload);
      expect(meta.lengthSync(), lessThan(200), reason: 'metadata only');
      expect(meta.readAsStringSync(), isNot(contains('app_0')));
    });

    test(
      'revalidates a stale entry and serves the cached body on 304',
      () async {
        await AppHttp.getJsonCached(server.uri);
        final again = await AppHttp.getJsonCached(
          server.uri,
          ttl: Duration.zero,
        );

        expect(server.requests, 2);
        expect(server.ifNoneMatch.last, 'W/"v1"');
        expect(
          (again as Map)['total'],
          40,
          reason: 'served from the cached body',
        );
      },
    );

    test('a 304 restarts the freshness window', () async {
      const window = Duration(minutes: 10);
      await AppHttp.getJsonCached(server.uri);
      // Aged past the window rather than slept past it, so the difference
      // between re-stamping and not is deterministic instead of a race.
      ageEntry(server.uri, const Duration(hours: 1));

      await AppHttp.getJsonCached(server.uri, ttl: window);
      expect(server.requests, 2, reason: 'the stale entry was revalidated');

      await AppHttp.getJsonCached(server.uri, ttl: window);
      expect(server.requests, 2, reason: 'the 304 made it fresh again');
    });

    test('picks up a changed document when the etag moves', () async {
      await AppHttp.getJsonCached(server.uri);
      server
        ..etag = 'W/"v2"'
        ..body = {'total': 7};

      final got = await AppHttp.getJsonCached(server.uri, ttl: Duration.zero);

      expect((got as Map)['total'], 7);
    });

    // What makes cached screens work with no network.
    test('falls back to the stale copy when the network fails', () async {
      await AppHttp.getJsonCached(server.uri);
      await server.stop();

      final got = await AppHttp.getJsonCached(server.uri, ttl: Duration.zero);

      expect((got as Map)['total'], 40);
    });

    test('rethrows when the network fails and nothing is cached', () async {
      final uri = server.uri;
      await server.stop();

      expect(() => AppHttp.getJsonCached(uri), throwsA(isA<Exception>()));
    });

    test('throws on a non-2xx response and caches nothing', () async {
      server.status = 500;

      await expectLater(
        AppHttp.getJsonCached(server.uri),
        throwsA(isA<AppHttpException>()),
      );
      expect(cacheFile(server.uri, 'body').existsSync(), isFalse);
    });

    // An upgrade must not throw away a cache an offline user is relying on.
    test('migrates a pre-split entry and still serves it offline', () async {
      final uri = server.uri;
      cacheFile(uri, 'json').writeAsStringSync(
        jsonEncode({
          'etag': 'W/"old"',
          'fetched_at': DateTime.now().millisecondsSinceEpoch,
          'body': jsonEncode({'total': 99}),
        }),
      );
      await server.stop();

      final got = await AppHttp.getJsonCached(uri);

      expect((got as Map)['total'], 99);
      expect(cacheFile(uri, 'json').existsSync(), isFalse, reason: 'consumed');
      expect(cacheFile(uri, 'body').existsSync(), isTrue);
      expect(jsonDecode(cacheFile(uri, 'body').readAsStringSync()), {
        'total': 99,
      });
    });

    test('ignores metadata whose body file is gone', () async {
      await AppHttp.getJsonCached(server.uri);
      cacheFile(server.uri, 'body').deleteSync();

      final got = await AppHttp.getJsonCached(server.uri);

      expect((got as Map)['total'], 40);
      expect(server.requests, 2, reason: 'a half-written entry is a miss');
    });
  });
}
